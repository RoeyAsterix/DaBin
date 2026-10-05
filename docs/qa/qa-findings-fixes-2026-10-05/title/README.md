The candidate replaces only the editable task-title field with a public AppKit wrapping NSTextField. The existing draft binding, native NavigationEditorRegion, title AX identifier/help, native field editor and max two-line header remain. Other capture titles are unchanged.

The verified title production source and cleaned relevant regression test were promoted into the writable clone after exact baseline SHA guards. The actual repository is untouched and the author has launched no GUI. See closure.json for accepted runtime hashes and final promoted hashes. The snapshot in `fixture/native` is compiled with App Store Release/no extra definitions and warnings-as-errors. Exact copied-source/test/resource/command hashes are in candidate-manifest.json.

Root native verification (serial, own-process fictional fixture) from `/Users/roeylibfeld/Documents/ChatGPT/DaBin/capture-fix/docs/qa/qa-findings-fixes-2026-10-05/title/fixture/native`:

```sh
DABIN_TASK_PLAN_QA_OUTPUT='/Users/roeylibfeld/Documents/ChatGPT/DaBin/capture-fix/docs/qa/qa-findings-fixes-2026-10-05/title/renders' DYLD_LIBRARY_PATH='/Users/roeylibfeld/Documents/ChatGPT/DaBin/capture-fix/docs/qa/qa-findings-fixes-2026-10-05/title/build' '/Users/roeylibfeld/Documents/ChatGPT/DaBin/capture-fix/docs/qa/qa-findings-fixes-2026-10-05/title/apps/TaskPlanTitleCandidate.app/Contents/MacOS/TaskPlanInteractionTests'
```

Then verify the actual full-Board raster with the existing defective baseline:

```sh
/Users/roeylibfeld/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3 '/Users/roeylibfeld/Documents/ChatGPT/DaBin/capture-fix/docs/qa/qa-findings-fixes-2026-10-05/title/verify_title_renders.py' --renders '/Users/roeylibfeld/Documents/ChatGPT/DaBin/capture-fix/docs/qa/qa-findings-fixes-2026-10-05/title/renders' --baseline-probe-output '/Users/roeylibfeld/Documents/ChatGPT/DaBin/capture-fix/docs/qa/full-certification-2026-10-05/native-title-probe/output' --report '/Users/roeylibfeld/Documents/ChatGPT/DaBin/capture-fix/docs/qa/qa-findings-fixes-2026-10-05/title/candidate-raster-proof.json'
```

Required result: native TaskPlan actions pass; both 100% and 200% full-Board title rasters contain real foreground glyphs in each line band; 100% no longer has a blank reserved second line. The title stays within its actual content width and no more than two native line heights plus cell padding. The old matched title raster must still fail its second-line band (baseline measured6920 first-line foreground pixels and0 second-line pixels).

Interaction checks require explicit title focus, original native field/editor identity and UTF16 selection through380→600→1200→380 resize, complete pending multilingual text, focused Return as multiline input without an implicit save, and explicit Save through existing validation. Existing CaptureDetailNavigationTests, NavigationGestureTests and WorkspaceWindowTests must be rerun after integration for native history/focus/draft/navigation compatibility.

For physical corroboration, rebuild the separately named visible native title probe against this candidate module (root-only launch) and inspect the unfocused380×680/100% header. Its last title line should truncate visibly with an ellipsis when more than two lines are needed. Full stored/native/AX text must remain intact; clicking and typing must use the real native field editor.

Public API basis: [NSTextField maximumNumberOfLines](https://developer.apple.com/documentation/appkit/nstextfield/maximumnumberoflines), [preferredMaxLayoutWidth](https://developer.apple.com/documentation/appkit/nstextfield/preferredmaxlayoutwidth) and NSCell.truncatesLastVisibleLine in the local current SDK. Do not accept the previous rejected fixedSize modifier as a fix.

The candidate native diagnostics isolated a four-point alignment transform: standard borderless NSTextField reports left/right alignmentRectInsets2, field bounds312×50, alignment rect308×50 and preferred width308. The visual raster already showed two lines, but the strict actual-width contract failed. The final candidate overrides only the custom field’s public alignmentRectInsets to zero, so its SwiftUI proposed width and complete native frame use the same wrapping width. The strict width/height guard remains unchanged. The native insets, drawing rect, full text, fit/intrinsic sizes and exact title geometry are retained in title-geometry-zoom100.json; the pre-override evidence is in attempts/native-alignment-diagnostic.

AppKit’s SDK NSLayoutConstraint.h291–302 explicitly documents the default frame/alignment transform via alignmentRectInsets and permits overriding the property. This avoids replacing the cell, altering title draft semantics or relaxing containment tests.

Targeted root native runtime passed379checks. The read-only raster proof passed: baseline100%first/second foreground pixels6920/0; candidate100%6920/7041 in308×50pt, candidate200%7082/7236 in276×58pt. Both remain within two native line heights, visibly truncate the final line and retain complete title text. Continuous380→600→1200→380 editing preserved field/editor identity and UTF16 selection; Return and explicit Save passed. The root final whole-suite campaign must revalidate the promoted cleaned test against all current integrated sources.

The final unchanged-input current campaign completed at 2026-10-05T03:53:14.521439Z: 120 of 121 suites passed; only WorkspaceZoomPerformanceTests failed its unchanged p95 budget. TaskPlan 379, readability 599, Detail navigation 995, gestures 72 and seeded graphics 108535 passed. Current source fingerprint 206badd60f8e8639b925fb4f0f4f69168c23245e91b46364d51bf57757d9e293; sourceChangedDuringRun=false. closure.json joins the exact completed report and fresh current title raster proof. This closes the title finding and does not claim all global QA findings are fixed.
