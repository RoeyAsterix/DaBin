#!/usr/bin/env python3
"""Package visually verified local review assets without publishing them."""
import argparse
import hashlib
import json
import shutil
import zipfile
from pathlib import Path

from pypdf import PdfReader
from release_inputs import ROOT, add_release_arguments, digest, read_release, verify_asset_manifest, verify_unchanged

HERE = Path(__file__).resolve().parent


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    add_release_arguments(parser)
    parser.add_argument('--package', action='store_true', required=True)
    parser.add_argument('--pack-dir', type=Path)
    parser.add_argument('--screenshots-dir', type=Path)
    parser.add_argument('--guide', type=Path, default=ROOT / 'docs/DaBin-Quick-Guide.pdf')
    parser.add_argument('--guide-assets', type=Path, default=ROOT / 'design/onepager/assets')
    parser.add_argument('--guide-qa', type=Path)
    parser.add_argument('--document-qa', type=Path)
    parser.add_argument('--friendly-copy', type=Path, default=ROOT / 'docs/DaBin-Friendly-Copy.txt')
    parser.add_argument('--output-zip', type=Path)
    parser.add_argument('--replace-draft', action='store_true', help='Replace only this candidate draft ZIP after repair')
    args = parser.parse_args()
    release = read_release(args)
    version, build = release['version'], release['build']
    pack = (args.pack_dir or ROOT / f'docs/app-store/submission-pack-{version}-{build}').resolve()
    if pack.name.startswith('submission-pack-') and pack.name != f'submission-pack-{version}-{build}':
        raise SystemExit('Do not overwrite the historical pack.')
    shots = (args.screenshots_dir or ROOT / f'docs/app-store/screenshots/{version}-{build}').resolve()
    document_qa = args.document_qa or HERE / f'qa/{version}-{build}/document-verification.json'
    receipt = json.loads(document_qa.read_text())
    document = pack / 'DaBin-App-Store-Content.docx'
    if ((receipt.get('version'), receipt.get('build')) != (version, build)
            or receipt.get('documentSHA256') != digest(document)
            or not str(receipt.get('visualReview', '')).startswith('PASS')
            or not str(receipt.get('sourceCopyParity', '')).startswith('PASS')):
        raise SystemExit('Current document source-parity and all-page visual PASS receipt required.')
    authoring = json.loads((pack / 'authoring-inputs.json').read_text())
    if ((authoring['version'], authoring['build']) != (version, build)
            or authoring['policySHA256'] != digest(release['native'] / 'Resources/PrivacyPolicy.md')):
        raise SystemExit('Document authoring inputs do not match the selected release.')
    metadata = json.loads((pack / 'Copy/metadata-en-US.json').read_text())
    if digest(pack / 'Copy/metadata-en-US.json') != authoring['metadataSHA256']:
        raise SystemExit('Pack metadata differs from the exact document authoring source.')
    if (metadata['candidate']['version'], metadata['candidate']['build']) != (version, build):
        raise SystemExit('Pack metadata version/build mismatch.')
    if digest(pack / 'Copy/PrivacyPolicy.md') != authoring['policySHA256']:
        raise SystemExit('Pack policy differs from the selected bundled policy.')
    screenshot_manifest = json.loads((shots / 'manifest.json').read_text())
    verify_asset_manifest(screenshot_manifest, release)
    if not str(screenshot_manifest.get('visualReview', '')).startswith('PASS'):
        raise SystemExit('Screenshot visual PASS required.')
    for shot in screenshot_manifest['screenshots']:
        if digest(shots / shot['file']) != shot['sha256'] or digest(pack / 'Screenshots' / shot['file']) != shot['sha256']:
            raise SystemExit(f'Screenshot changed after review: {shot["file"]}')
    guide_manifest = json.loads((args.guide_assets / 'guide-native-source-manifest.json').read_text())
    verify_asset_manifest(guide_manifest, release)
    guide_qa_path = args.guide_qa or ROOT / f'design/onepager/qa/robot-guide-{version}-{build}.json'
    guide_qa = json.loads(guide_qa_path.read_text())
    guide_hash = guide_qa.get('pdf_sha256') or guide_qa.get('outputs', {}).get('docs/DaBin-Quick-Guide.pdf')
    if ((guide_qa.get('version'), str(guide_qa.get('build'))) != (version, build)
            or guide_qa.get('result') != 'PASS' or guide_hash != digest(args.guide)):
        raise SystemExit('Current guide source/hash and all-page visual PASS receipt required.')
    reader = PdfReader(args.guide)
    text = '\n'.join(page.extract_text() for page in reader.pages)
    if version not in text or 'Export Selected' not in text or len(reader.pages) != 2:
        raise SystemExit('Current two-page guide with selected-export instructions required.')
    if f'Version {version} ({build})' not in args.friendly_copy.read_text():
        raise SystemExit('Friendly copy must match the selected release.')
    archive_name = f'DaBin-App-Store-Pack-{version}-{build}'
    output = args.output_zip or ROOT / f'output/{archive_name}.zip'
    if output.name.startswith('DaBin-App-Store-Pack-') and output.name != archive_name + '.zip':
        raise SystemExit('Output ZIP name refers to a different historical release.')
    if output.exists() and not args.replace_draft:
        raise SystemExit('Preserve the existing ZIP or explicitly replace this candidate draft after repair.')
    verify_unchanged(release)
    shutil.copy2(args.guide, pack / 'DaBin-Quick-Guide.pdf')
    shutil.copy2(args.friendly_copy, pack / 'Copy/DaBin-Friendly-Copy.txt')
    (pack / 'README.txt').write_text(f"""DABIN APP STORE CONTENT PACK
Version {version} ({build}) - English US

Open DaBin-App-Store-Content.docx for listing fields, review instructions,
screenshot pages, privacy declarations, owner fields and support copy.
DaBin-Quick-Guide.pdf is the updated two-page customer guide.

Screenshots/ contains original 1440 x 900 opaque RGB PNGs in upload order:
01 Captions, 02 Projects, 03 Focus. Compare them with the exact final signed
app and confirm artwork rights before upload. Do not extract them from Word.

Copy/ contains individual public listing fields, private review notes,
support-page copy, metadata, bundled policy and friendly guide text.
Fill real owner/contact fields; keep private review contacts out of a public
repository or website. What's New is for a subsequent App Store version.

Assets/ contains the current 1024-pixel icon and bundled ICNS for reference.
The Mac icon is delivered in the app build. No preview video or signed
application package is included.

Native QA status: {authoring.get('qaStatus', 'pending')}.
Performance status: {authoring.get('performanceStatus', 'pending')}.
Known issues and remaining gates are recorded in authoring-inputs.json and
the submission document. This pack is not ready for submission while any
quality, performance, owner or release gate remains open.

This is a local preparation pack. Owner declarations, public policy/support
parity, distribution signing/validation, signed-app acceptance and screenshot
comparison remain separate release gates. No upload or submission performed.
manifest.json records files and checksums and excludes itself.
""")
    manifest = {'product': 'DaBin', 'version': version, 'build': build, 'locale': 'en-US',
        'status': 'CONTENT_PREPARED_OWNER_FIELDS_AND_RELEASE_GATES_PENDING',
        'submissionReady': False, 'qaStatus': authoring.get('qaStatus', 'pending'),
        'performanceStatus': authoring.get('performanceStatus', 'pending'),
        'knownIssues': authoring.get('knownIssues', []),
        'pendingReleaseGates': authoring.get('pendingReleaseGates', []),
        'docxPages': receipt['documentPages'], 'quickGuidePages': len(reader.pages),
        'documentVerificationSHA256': digest(document_qa), 'guideVerificationSHA256': digest(guide_qa_path),
        'screenshots': {'dimensions': [1440, 900], 'format': 'PNG', 'mode': 'RGB', 'alpha': False,
                        'order': ['Captions', 'Projects', 'Focus'], 'source': 'Native Store views with fictional records',
                        'finalSignedAppComparison': 'pending'},
        'sourceScreenshotHashes': {s['file']: s['sha256'] for s in screenshot_manifest['screenshots']},
        'files': []}
    for path in sorted(pack.rglob('*')):
        if path.is_file() and path.name != 'manifest.json':
            manifest['files'].append({'file': str(path.relative_to(pack)), 'bytes': path.stat().st_size, 'sha256': digest(path)})
    (pack / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    output.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(output, 'w', zipfile.ZIP_DEFLATED) as zipped:
        for path in sorted(pack.rglob('*')):
            if path.is_file():
                zipped.write(path, Path(archive_name) / path.relative_to(pack))
    with zipfile.ZipFile(output) as zipped:
        if zipped.testzip() is not None:
            raise SystemExit('ZIP integrity failure.')
        for entry in manifest['files']:
            if hashlib.sha256(zipped.read(archive_name + '/' + entry['file'])).hexdigest() != entry['sha256']:
                raise SystemExit('ZIP checksum mismatch.')
    print(json.dumps({'zip': str(output), 'bytes': output.stat().st_size, 'files': len(manifest['files']) + 1}, indent=2))


if __name__ == '__main__':
    main()
