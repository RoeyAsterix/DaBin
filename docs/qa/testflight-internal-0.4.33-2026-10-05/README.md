DaBin 0.4.33 (88) — current internal TestFlight publication

Card deletion and recovery are pushed to origin/main at 3735e8d331db18cafe9e5e77847550f47871a048. Required release fingerprint: 6b013ca1385c4aaf1d837e924e12eaa9bbeeba5ad3544fea2ede31b88f83d909. The current source retains Projects → Tasks → Captions, configurable Full screen/Recording shortcuts, compact cards and Projects recovery/navigation fixes.

Every saved content card has Delete through its Trash control or visible More menu. Live notes have persistent Recently Deleted and safe Restore/Undo. Saved comments delete by exact ID with additive Undo, retaining composer drafts and later replies. Hour/action/batch confirmations freeze visible IDs so hidden items and new arrivals survive. Permanent deletion is separately confirmed. ../card-deletion-2026-10-05/README.md, verification.json and action-coverage.json contain the exact scope and evidence.

The affected campaign and scoped rechecks validate 24 distinct suites across the campaign; 10 suites passed on final production, including 152 native deletion checks and explicit cleanup. The earlier broad campaign differs in two accessibility-only source refinements; its raw failures and rechecks remain preserved. This is not a full run of all 124 registered suites. The previous Projects 123-suite campaign consolidated 122 passing suites on its older source. Its strict zoom latency failure (62.884ms input p95 against 50ms, 70.973ms timer p95 against 33ms) and native framework table warnings remain open; not retested or claimed fixed here.

Fresh unsigned arm64 App Store Release compilation, packaging, actual embedded metadata/binary verification, deterministic project checking and 32 packaging unit tests pass. Signing, sandbox runtime, installation, archive, upload, internal readiness and current email delivery remain unverified.

Current exact-source human signing command:

```sh
/opt/homebrew/opt/python@3.14/bin/python3.14 /private/tmp/dabin-testflight-card-delete-20261005.py
```

Run this from the signed-in Mac Terminal and complete normal macOS signing authentication. status.json records helper SHA, source/code/configuration guards, shared lock and exact receipt pattern. archive-card-delete-human-handoff.py is an identical recovery copy; archive-card-delete-handoff-preparation.json proves preparation only. All earlier helpers and archives are superseded for latest publication; historical evidence is retained.

Computer Use refused native Terminal control. Automatic approval review rejected protected Keychain/SecurityAgent control because it crosses authentication. Protected authentication UI is never inspected, controlled or bypassed; private signing material and security settings are not accessed.

After verifying the current receipt, unchanged source/configuration/code ancestry, actual archived 0.4.33 (88), log/hash, signature and strict archive preflight, use Xcode Organizer normal App Store Connect Upload with Internal Only and manage version/build disabled. Revalidate Apple session and server builds, verify upload/processing, and add only this current build to Personal Testing group 88bf737b-ecd4-48ed-b084-73cee2f3a93c in app 6815956446 with current What to Test notes. The last recorded Apple check is historical and showed old 0.4.31 (86) with one accepted owner tester. Never remove/readd that tester or email an old build as current. Record Apple's email request separately from actual inbox delivery. Upload, processing, internal readiness, beta review and customer Store approval are separate; do not publish a customer-facing Store release.

The 30-minute follow-up remains active and quiet for an unchanged human handoff, checking only exact current receipts. The unrelated local-update QA folder remains untouched.
