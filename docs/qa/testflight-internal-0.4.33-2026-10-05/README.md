DaBin 0.4.33 (88) — current internal TestFlight publication

The latest user-requested tabs are Projects, Tasks, Captions, from left to right. The updated source and focused QA are pushed to origin/main at 5796852360bf11cb28f780e55839390a5f99e957. Current canonical release fingerprint is a85333395e0a982230f3a8246db0d671e050b595f04a954f559dc29912caef09.

All 3 existing focused native App Store Release suites pass with unchanged inputs: HeaderInteractionTests, NavigationHistoryTests and LocalFileLocationTests. The current compact 380-point fixture render was inspected and shows all three labels fitting. Updated unsigned App Store Release compilation and packaging preflight pass. ../tab-labels-2026-10-05/verification.json contains the receipts and evidence hashes. No current signed archive, installation, upload, internal readiness or Apple approval is claimed.

The previous E038 full 121-suite run is historical evidence:120 passed, strict zoom performance failed, and framework table warnings remain open. No new full registered run or performance fix is claimed for this visible-label update.

The old source's first signed archive failed with errSecInternalComponent; its second stalled codesign was stopped by the agent. Its third normal PTY retry also stalled at CodeSign and was stopped by the agent because the human requested new labels before upload. The third exit65 records an agent stop, not a natural new signing failure. All final logs and receipts are preserved. Old archives and old frozen helper are superseded and must not be uploaded for the latest source.

App Store Connect was last verified with old 0.4.31 (86) uploaded and Personal Testing containing one accepted owner tester who had installed it. The current source has not been uploaded. Once the current signed archive is verified, normal Xcode Organizer upload, Apple processing and adding current 0.4.33 (88) to the existing internal group remain authorized. Adding an internal build emails the selected group's testers: https://developer.apple.com/help/app-store-connect/test-a-beta-version/add-internal-testers/. Record Apple email request separately from actual inbox delivery; do not remove/readd the accepted tester or email an old build as if current.

The new frozen exact-source human signing command is:

/opt/homebrew/opt/python@3.14/bin/python3.14 /private/tmp/dabin-testflight-tabs-20261005.py

It must be run from the signed-in Mac Terminal and uses the existing normal archive helper and installed signing assets. status.json records its hash, current fingerprint and exact new receipt pattern. The old helper command is superseded. Computer Use refused native Terminal control, and automatic approval review rejected protected Keychain/SecurityAgent control because it crosses an authentication boundary. No protected authentication UI is inspected, controlled or bypassed, and no security settings or private signing material are accessed.

The 30-minute follow-up remains active and quiet for the same human handoff. It verifies only exact current-source receipts before upload. The unrelated local-update QA folder is preserved.
