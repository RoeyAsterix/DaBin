# Final signed-app acceptance — pending

Use fictional content in a fresh macOS test account. Do not mark a row passed from source inspection, an unsigned build, or a different-channel installed app. Record the exact exported app hash, signature, OS, device and date. App Store Connect processing/review remains a separate gate.

| Workflow | Required observation | Status |
|---|---|---|
| Install / first launch | Signed installer works; board/menu/robot open; no crash or unsolicited capture/access prompt | Pending |
| Capture consent | Capture starts off; declining consent keeps manual capture working; explicit opt-in shows persistent recording state | Pending |
| Clipboard / screenshot folder | Save fictional clipboard content/new image only; existing screenshot files remain unimported; Pause stops new captures | Pending |
| Scoped bookmark | Native folder grant survives quit/relaunch; revoked access is reported; clipboard-only monitoring still visibly records | Pending |
| Import / export / backup | Native picker-selected sources/destinations work outside container; cancel changes nothing; backup restore checks integrity | Pending |
| Search and tasks | Typing, Cmd-V, context paste, date-grouped results, new task, priority tags and focus timer operate correctly | Pending |
| External drag | Text/card/file drops in a native editor, browser text field and file destination yield correct text/bytes; source preserved | Pending physical drops |
| Deletion / recovery | Recently Deleted, restore and permanent delete match policy, without changing original source files | Pending signed app |
| Notifications | Permission asked only when needed; refusal leaves other features usable; generic reminder content | Pending |
| Quit / relaunch | Quit stops capture/timers/watchers; no background helper; archived records reopen without duplication/loss | Pending |
| Upgrade | Restore a fictional previous-version archive into test account; update signed app; verify records, settings and grants | Pending |
| Platforms | Apple Silicon macOS 14 and current shipping macOS; monitor move/reconnect/full-screen | Pending physical OS/display matrix |
| Accessibility | Keyboard-only and VoiceOver traversal, focus, labels, contrast, Reduce Motion, dark/light mode | Pending manual VoiceOver pass; native automated coverage recorded separately |
| Resources / network | Observe idle and active capture energy/memory; offline use; optional previews on IPv6-only network | Pending physical profiling/network setup |
| Submission materials | Exact UI matches screenshots; live policy matches bundled text; real support contact and owner declarations complete | Pending owner / final binary |

These are acceptance gates for this release, not a claim that every item is a separately mandated Apple questionnaire field. They close observed test-scope gaps and the app-completeness risk for this particular app.
