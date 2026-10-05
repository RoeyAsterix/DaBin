DaBin configurable action shortcuts — 2026-10-05

Settings → Quick access now records, clears and resets shortcuts for Full screen and Recording on/off. Defaults are Control + Option + F and Control + Option + R. Full screen reuses header safe-area expansion/restoration. Recording pauses/resumes selected capture sources; unconfigured recording opens setup after draft, modal and native text-composition checks. Existing Search/Save Clipboard shortcuts remain available.

All eight focused native App Store Release suites pass on the exact unchanged source. The native recorder checks real focus, event-queue key handling, repeated keys, matching release, Escape/Delete/Tab/Shift-Tab, focus loss and teardown. Tests also cover persistence, disabled bindings, duplicate/standard/macOS reservations, registration rollback and stale callbacks. Window fixtures cover hidden opening, restoration, invalid drafts, native marked text and recording channels/exclusions. Shared Search native keyboard coverage passes. The compact Settings render was visually inspected.

Unsigned Release compilation and packaging preflight pass for 0.4.33 (88). verification.json records the release/input fingerprints and evidence hashes. Automated action dispatch uses a fake registrar; hardware/global activation from another application and sandbox runtime are not claimed. No archive, installation or upload is performed by this verification.

The previous full run remains historical evidence: 120/121 suites passed, strict zoom performance budgets and native framework table warnings remain open. This change has eight focused suites, not a new full registered run. Signing remains the existing human authentication boundary.
