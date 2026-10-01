#!/usr/bin/env python3
"""Legacy entry point: create a guarded standalone ZIP on Desktop, without sources."""
from pathlib import Path
import subprocess
import sys

if __name__ == '__main__':
    helper = Path(__file__).resolve().parent / 'package_standalone.py'
    destination = Path.home() / 'Desktop/DaBin-macOS-Build.zip'
    raise SystemExit(subprocess.call([sys.executable, str(helper), '--output', str(destination), *sys.argv[1:]]))
