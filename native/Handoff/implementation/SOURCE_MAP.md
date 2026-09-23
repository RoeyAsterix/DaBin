# Sources, precedence and provenance

## Precedence

1. Current user instruction: create a Codex handoff to build DaBin as a macOS app; preserve the explicit **“Without a sidebar”** decision.
2. Selected v2 design and its product invariants, consolidated in this package's `PRODUCT_AND_DESIGN.md`.
3. Current source brief, `reference/product/OPEN_DESIGN_HANDOFF.md`, for required capture, per-card actions and contextual search.
4. `reference/product/PRODUCT_PLAN.md` for the underlying date-based capture model.
5. New native defaults in `NATIVE_BUILD.md` fill implementation gaps; they do not imply prior native validation.

The older `source/DaBin/CODEX_DESIGN_HANDOFF.md` was inspected but is historical. Its request to design a prototype, older dimensions, and optional/P1 treatment of search must not override this implementation assignment. It is intentionally excluded to avoid handing Codex a conflicting task.

## Copied references

| Package path | Original project-relative path | Treatment |
| --- | --- | --- |
| `reference/prototype/` | `DaBin/open-design-v2/` | Entire selected prototype, unchanged |
| `reference/product/OPEN_DESIGN_HANDOFF.md` | `source/DaBin/OPEN_DESIGN_HANDOFF.md` | Current pre-v2 source brief, unchanged |
| `reference/product/PRODUCT_PLAN.md` | `source/DaBin/PRODUCT_PLAN.md` | Product model, unchanged |
| `reference/brand-spec.md` | `brand-spec.md` | Extracted direction/tokens, unchanged |
| `reference/tools/qa_dabin.cjs` | `tools/qa_dabin.cjs` | Historical browser harness source, unchanged; paths assume original workspace |

Links inside copied historical product briefs may name older files outside this package. They are provenance, not the implementation reading route. Use the curated relative links in `START_HERE.md`. Do not reopen visual exploration or implement both concepts because a historical brief requested comparison.

The review gallery contains **21 live HTML states**, not screenshot evidence. Its narrow state is browser adaptation evidence, not a request for an iOS app. The original browser QA records **14 logic/DOM-neutral smoke checks** and explicitly excludes rendered/browser and native verification. The historical QA harness is not a native test suite.

The prototype includes fictional sample entries and sample assets. Some PDF/video/AI originals are intentionally absent and show fallback behavior. Do not promote those entries into real user storage or claim they demonstrate working native import. The robot source is `reference/prototype/assets/robot.svg` and is preserved byte-for-byte. The Apple system fonts are referenced by name; no font binaries are supplied.

At handoff time, no existing native implementation was supplied to integrate or validate. Work only within the selected DaBin repository.

`design-tokens.json` preserves selected light/dark OKLCH values and provides mechanically converted, rounded sRGB hex values for native asset colors. The JSON is a convenience, not a rebrand. `search-cases.json` is newly authored fixture data checked against the current pure search model. Native porting and native tests remain to be done.

## Apple API references

Consult the linked official documentation and the installed SDK for availability. API choices below were checked against Apple documentation on 22 September 2026; this is API evidence, not runtime QA.

| Area | Official reference |
| --- | --- |
| Panel activation | [nonactivatingPanel](https://developer.apple.com/documentation/appkit/nswindow/stylemask-swift.struct/nonactivatingpanel) |
| Spaces policy | [canJoinAllSpaces](https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct/canjoinallspaces) |
| Click timing | [doubleClickInterval](https://developer.apple.com/documentation/appkit/nsevent/doubleclickinterval) |
| Menu recovery | [NSStatusItem](https://developer.apple.com/documentation/appkit/nsstatusitem) |
| File promises | [NSFilePromiseReceiver](https://developer.apple.com/documentation/appkit/nsfilepromisereceiver) |
| Temporary file access | [startAccessingSecurityScopedResource](https://developer.apple.com/documentation/foundation/nsurl/startaccessingsecurityscopedresource()) |
| Persistence/migration | [ModelContainer](https://developer.apple.com/documentation/swiftdata/modelcontainer), [ModelActor](https://developer.apple.com/documentation/swiftdata/modelactor) |
| Web metadata | [LPMetadataProvider](https://developer.apple.com/documentation/linkpresentation/lpmetadataprovider) |
| File thumbnails | [QLThumbnailGenerator](https://developer.apple.com/documentation/quicklookthumbnailing/qlthumbnailgenerator) |
| Notifications | [Schedule local notifications](https://developer.apple.com/documentation/usernotifications/scheduling-a-notification-locally-from-your-app), [Request permission](https://developer.apple.com/documentation/usernotifications/asking-permission-to-use-notifications) |
| Permissions | [Configure App Sandbox](https://developer.apple.com/documentation/xcode/configuring-the-macos-app-sandbox) |
| Optional login item | [SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice) |

No Apple documentation is redistributed in full in this package.
