#!/bin/zsh
# Archive the exact tested build; complete macOS signing authentication yourself.
# No app data is changed, no security settings are changed, and no upload occurs.
'/opt/homebrew/Cellar/python@3.14/3.14.5/Frameworks/Python.framework/Versions/3.14/bin/python3.14' '/Users/roeylibfeld/Documents/KARI Creatives/DaBin/docs/qa/testflight-upgrade-0.4.42-97-2026-10-06/prepare_archive.py'
archive_result=$?
printf "\nArchive preparation finished (exit %s).\n" "$archive_result"
printf "Keep this window open for the receipt path above. Press Return to close.\n"
read -r
exit "$archive_result"
