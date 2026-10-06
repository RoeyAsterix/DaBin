# DaBin 0.4.45 (100) local update — 6 October 2026

Installed and reopened the latest working source from an isolated production snapshot. This is a local ad-hoc signed Release build for the GitHub distribution channel; it is not a signed Store archive, TestFlight upload or complete QA campaign.

The snapshot contained 206 canonical production inputs and fingerprint `d638f6564a9b85ec0769df847f56f45b8675c771c090ffa9c8e5f0291ff29a89`. Source, snapshot and built receipt matched before and after installation. The exact installed executable path was confirmed running. Strict deep signature verification, ARM64, main/updater executable hashes and source entitlements passed.

The existing 0.4.44 (99) app was backed up by the guarded installer to `/Users/roeylibfeld/Applications/.DaBinBackups/20261006-181259-bc62a696.app`. Normal Command-Q saved the draft; after opening the exact installed app path, the draft matched exactly, Auto Capture remained paused and Settings displayed DaBin 0.4.45 (100). Captions was restored as the final view. No capture text was saved in this evidence.

Validation here is scoped to compilation, packaging/signature/provenance, guarded replacement and a small launch/UI smoke check. Full functional, stability and performance QA for build 100 remains separate and must not be inferred from this local installation. The newer TestFlight campaign is in `../testflight-upgrade-0.4.45-100-2026-10-06/`; all build-88 signing helpers are superseded and must not be used for the latest source.
