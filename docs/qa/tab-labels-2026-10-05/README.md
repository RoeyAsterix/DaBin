DaBin main tab labels — 2026-10-05

The main tabs read Projects, Tasks, Captions from left to right. Projects was already first. The former Today and Inbox labels are updated in the header, Tasks heading, tutorial, keyboard shortcut label and capture destination messages. Date-specific Today labels remain. Unplanned task copy describes planning state accurately rather than promising a move between tabs. Stable accessibility identifiers, routes, task/project assignments and stored keys are preserved.

All three existing focused App Store Release suites pass: HeaderInteractionTests, NavigationHistoryTests and LocalFileLocationTests. The source inputs stayed unchanged throughout. The existing native menu test expectation was updated for Return to Captions; no new tests were added. The current 380-point synthetic fixture render was inspected and shows all three labels fitting in the requested order.

The updated unsigned App Store Release compiles and passes packaging preflight. This does not establish a signed distribution archive, installation, upload or Apple approval. The previous full121-suite run belongs to E038 source and is historical; it reported120passed with the strict zoom failure and native table warnings still open.

The prior stalled archive was stopped by the agent because these user-requested labels superseded its source before upload. Its stop must not be represented as a natural signing failure. Current publication and exact-source human signing handoff are tracked in ../testflight-internal-0.4.33-2026-10-05/status.json. The unrelated local-update QA folder was preserved.
