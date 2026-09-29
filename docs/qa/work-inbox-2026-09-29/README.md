# DaBin 0.4.0 build 47 — local candidate

Implemented the approved save/find/resume changes in the native app. This candidate is built and reviewed locally, but has **not been installed or published**. The previous running app and user archive were preserved.

## Verified

- Optimized ARM64 standalone build succeeds with warnings treated as errors. The build script verifies the strict signature on a clean copy; the candidate remains locally ad-hoc signed.
- Xcode Release build succeeds with `CODE_SIGNING_ALLOWED=NO`, using a separate `native/build/WorkInboxXcode` directory. This does not establish App Store signing, notarization or acceptance.
- Final regression run: **36/40 suites passed**, with unchanged source inputs. All **33 non-focus suites pass**. WeeklyWindowTests, FilterResizeTests and RobotDropTests also pass.
- New checks cover global-shortcut registration/rollback, global search and receipt-only Today, pins/projects, drafts surviving follow-up actions, delayed promised-file busy state, channel independence, legacy schema decoding and recoverable deletion.
- Archive recovery includes 61 assertions for backup round trips, original bytes, notes/local edits, organization, trash, corruption/conflict rejection, atomic metadata commit and rollback that preserves replaced or edited files.
- **26 native production-view renders** cover Today, Library/project resume, Follow-ups, Search/context, notes, project detail, Recently Deleted and Settings in light/dark appearance. Renders use fictional isolated data. Compact and wider layouts were reviewed; one-result Search was enlarged so its Copy action is initially visible.
- Generated Xcode project and whitespace checks pass. Build source/resource hashes match the corresponding final QA inputs.

Environment: Apple Silicon, macOS 26.6.2 (25G83), macOS SDK 27.0; minimum deployment target remains macOS 14. Older supported systems were not run.

## Unresolved live checks

The Mac remained locked throughout live-access attempts. The following failures remain recorded; **the full suite is not green**:

| Suite | Observed result |
| --- | --- |
| WindowTests | 140 of 142 assertions pass; hover keyboard focus and return-to-robot focus fail. |
| DailyCaptureTests | The test panel does not become key for native Edit routing. |
| RobotWindowTransitionTests | The settled test frame does not report as actually visible after staging cleanup. |
| HeaderInteractionTests | The in-process harness sees AppKit controls but cannot enumerate SwiftUI virtual accessibility identifiers/labels. An unlocked accessibility inspection is needed; the lock is not proven to be the only cause. |

These results must not be represented as successful live verification. Global shortcuts and normal interactions with the installed app still need an unlocked-session pass.

`install_app.py` correctly refused installation because another DaBin process was running. No force-quit or app replacement was performed. After unlocking, inspect/save any existing drafts, quit normally, make a local pre-migration archive backup, rerun the unresolved checks, and install with the existing guarded installer. Verify the new version and actual user flows before calling the update installed.

## Evidence

- [Complete final regression report](regression-report.json)
- [Final build receipt and hashes](build-receipt.json)
- [Xcode build log](xcode-build.log)
- [Native-render manifest](screenshots/simpler-ui-renders.json)
- [Today](screenshots/native-view-simpler-today-light-380x560.png)
- [Project resume](screenshots/native-view-simpler-project-resume-light-380x560.png)
- [Search](screenshots/native-view-simpler-search-matches-light-380x480.png)
- [Follow-ups](screenshots/native-view-simpler-follow-ups-light-380x450.png)
- [Dark Library](screenshots/native-view-simpler-library-dark-380x560.png)
- [Recently Deleted](screenshots/native-view-simpler-recently-deleted-light-380x500.png)

The source and scope are described in [0.4.0 release notes](../../RELEASE_NOTES_0.4.0.md). Semantic search, cloud sync, pricing changes and public distribution are outside this candidate.
