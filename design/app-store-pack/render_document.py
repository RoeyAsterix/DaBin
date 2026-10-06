#!/usr/bin/env python3
"""Use the Documents skill renderer with the explicit bundled headless LibreOffice."""
import importlib.util
import os
from pathlib import Path

BUNDLE = Path('/Users/roeylibfeld/.cache/codex-runtimes/codex-primary-runtime/dependencies')
SOFFICE = BUNDLE / 'native/libreoffice-headless/libreoffice/LibreOfficeDev.app/Contents/MacOS/soffice'
RENDERER = Path('/Users/roeylibfeld/.codex/plugins/cache/openai-primary-runtime/documents/26.915.20218/skills/documents/render_docx.py')


def main():
    if not SOFFICE.is_file():
        raise SystemExit(f'Bundled LibreOffice unavailable: {SOFFICE}; desktop LibreOffice will not be used.')
    spec = importlib.util.spec_from_file_location('review_pack_document_renderer', RENDERER)
    renderer = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(renderer)
    # Do not allow PATH discovery to choose the user's desktop installation.
    renderer._resolve_soffice = lambda: str(SOFFICE)
    os.environ['PATH'] = os.pathsep.join([str(BUNDLE / 'python/bin'),
        str(BUNDLE / 'native/poppler/poppler/bin'), str(BUNDLE / 'bin/override'),
        os.environ.get('PATH', '')])
    renderer.main()


if __name__ == '__main__':
    main()
