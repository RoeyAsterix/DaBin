# DaBin 0.3.0 QA evidence

- `full-run/report.json` is the machine-readable Release run for all 22 registered suites. Adjacent compile and execution logs preserve each outcome.
- `media-integration-v0.3.0.log` covers synthetic PDF, RTF and H.264 previews and fitted PDF geometry.
- `release-ui-renders.json` inventories 28 production-view renders. PNGs are generated artifacts and are not stored in Git history.
- `app-store-preflight-static-v0.3.0.log` records 20 passing source/package checks.
- `app-store-preflight-release-v0.3.0.log` records the two remaining release-environment blockers: Apple Developer Team ID and full Xcode.

All fixtures are synthetic and isolated. These logs contain no captures, clipboard contents, account tokens, or personal paths.
