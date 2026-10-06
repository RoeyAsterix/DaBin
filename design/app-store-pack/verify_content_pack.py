#!/usr/bin/env python3
"""Verify submission-document source parity; record visual approval only after inspection."""
import argparse
import json
import zipfile
from pathlib import Path
from xml.etree import ElementTree

from PIL import Image
from pypdf import PdfReader
from release_inputs import ROOT, add_release_arguments, digest, read_release, verify_asset_manifest

HERE = Path(__file__).resolve().parent
W = '{http://schemas.openxmlformats.org/wordprocessingml/2006/main}'


def normalized(value):
    return ' '.join(value.split())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    add_release_arguments(parser)
    parser.add_argument('--pack-dir', type=Path)
    parser.add_argument('--render-dir', type=Path, required=True)
    parser.add_argument('--screenshots-dir', type=Path)
    parser.add_argument('--inspected-pages', help='Comma-separated page numbers, supplied only after opening every rendered page')
    parser.add_argument('--write-receipt', action='store_true')
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    release = read_release(args)
    version, build = release['version'], release['build']
    pack = args.pack_dir or ROOT / f'docs/app-store/submission-pack-{version}-{build}'
    shots = args.screenshots_dir or ROOT / f'docs/app-store/screenshots/{version}-{build}'
    metadata = json.loads((pack / 'Copy/metadata-en-US.json').read_text())
    if (metadata['candidate']['version'], metadata['candidate']['build']) != (version, build):
        raise SystemExit('Pack metadata candidate mismatch.')
    manifest = json.loads((shots / 'manifest.json').read_text())
    verify_asset_manifest(manifest, release)
    document = pack / 'DaBin-App-Store-Content.docx'
    with zipfile.ZipFile(document) as zipped:
        xml = ElementTree.fromstring(zipped.read('word/document.xml'))
        paragraphs = [normalized(''.join(node.text or '' for node in paragraph.iter(W + 't')))
                      for paragraph in xml.iter(W + 'p')]
        # Formatting splits a sentence into Word runs without adding spaces.
        # Preserve the displayed paragraph text before comparing complete copy.
        text = normalized(' '.join(paragraphs))
        import hashlib
        embedded = {hashlib.sha256(zipped.read(name)).hexdigest()
                    for name in zipped.namelist() if name.startswith('word/media/')}
    for key, filename in [('name', 'name.txt'), ('subtitle', 'subtitle.txt'),
                          ('promotionalText', 'promotional-text.txt'), ('description', 'description.txt'),
                          ('keywords', 'keywords.txt')]:
        value = metadata['productPage'][key]
        if (pack / 'Copy' / filename).read_text() != value + '\n':
            raise SystemExit(f'Plain copy parity failed: {key}')
        # The description's section titles and paragraphs are separate native Word elements.
        for line in value.splitlines():
            if line.strip() and normalized(line) not in text:
                raise SystemExit(f'Document public-field parity failed: {key}')
    for block in metadata['review']['notes'].split('\n\n'):
        if normalized(block) not in text:
            raise SystemExit('Document review-note parity failed.')
    if (pack / 'Copy/review-notes.txt').read_text() != metadata['review']['notes'] + '\n':
        raise SystemExit('Plain review-note parity failed.')
    policy = release['native'] / 'Resources/PrivacyPolicy.md'
    if digest(pack / 'Copy/PrivacyPolicy.md') != digest(policy):
        raise SystemExit('Policy copy differs from selected release.')
    for block in policy.read_text().split('\n\n'):
        if block.strip() and not block.startswith('#'):
            if normalized(block.replace('**', '')) not in text:
                raise SystemExit('Document policy-body parity failed.')
    for shot in manifest['screenshots']:
        if (digest(shots / shot['file']) != shot['sha256']
                or digest(pack / 'Screenshots' / shot['file']) != shot['sha256']
                or shot['sha256'] not in embedded):
            raise SystemExit(f'Document screenshot hash parity failed: {shot["file"]}')
    if not paragraphs or paragraphs[0] != 'DaBin App Store Content':
        raise SystemExit('Document title changed or missing.')
    rendered_pdf = args.render_dir / 'DaBin-App-Store-Content.pdf'
    pages = len(PdfReader(rendered_pdf).pages)
    pngs = list(args.render_dir.glob('page-*.png'))
    if len(pngs) != pages:
        raise SystemExit('Every PDF page must have one rendered PNG.')
    for index in range(1, pages + 1):
        image = args.render_dir / f'page-{index}.png'
        with Image.open(image) as opened:
            opened.verify()
    inspected = {int(part) for part in args.inspected_pages.split(',')} if args.inspected_pages else set()
    approved = inspected == set(range(1, pages + 1))
    if args.write_receipt and not approved:
        raise SystemExit('Open all rendered pages before supplying --inspected-pages and writing visual PASS.')
    counts = {key: len(metadata['productPage'][key]) for key in ['name', 'subtitle', 'promotionalText', 'description']}
    limits = {'name': 30, 'subtitle': 30, 'promotionalText': 170, 'description': 4000}
    if any(counts[key] > limit for key, limit in limits.items()):
        raise SystemExit('Public field exceeds its prepared limit.')
    keywords = len(metadata['productPage']['keywords'].encode('utf-8'))
    review = len(metadata['review']['notes'].encode('utf-8'))
    if keywords > 100 or review > 4000:
        raise SystemExit('Keyword/review byte limits exceeded.')
    receipt = {'version': version, 'build': build, 'documentPages': pages,
        'documentSHA256': digest(document), 'renderedPDFSHA256': digest(rendered_pdf),
        'visualReview': 'PASS: every rendered page opened and inspected; no clipping, overlap, broken tables or image overflow.' if approved else 'Pending all-page inspection.',
        'inspectedPages': sorted(inspected),
        'sourceCopyParity': 'PASS: exact public fields, review notes, complete bundled policy body and all three source PNGs verified.',
        'fieldCounts': counts, 'keywordUTF8Bytes': keywords, 'reviewNotesUTF8Bytes': review,
        'pending': 'Owner declarations, public policy/support parity, distribution signing, signed-app acceptance and Apple review; no upload or submission.'}
    if args.write_receipt:
        output = args.output or HERE / f'qa/{version}-{build}/document-verification.json'
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(json.dumps(receipt, indent=2) + '\n')
        authoring_path = pack / 'authoring-inputs.json'
        authoring = json.loads(authoring_path.read_text())
        authoring['visualReview'] = receipt['visualReview']
        authoring['visualReviewReceipt'] = str(output.resolve())
        authoring['renderedPDFSHA256'] = receipt['renderedPDFSHA256']
        authoring_path.write_text(json.dumps(authoring, indent=2) + '\n')
    print(json.dumps(receipt, indent=2))


if __name__ == '__main__':
    main()
