#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
exec python3 "$project_root/scripts/run_qa.py" "$@"
