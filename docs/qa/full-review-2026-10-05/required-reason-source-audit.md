# File timestamp required-reason source audit

Checked UTC: **2026-10-05T22:06:18.489211+00:00**. Candidate **0.4.41 (96)**, production fingerprint `d6a7dd7fd2e2de4f167476ba91d8be232917024ecf745679bc4a5f3c83fab5fa`. Every file hash below matches the locked candidate. [Machine-readable evidence](required-reason-source-audit.json).

**Result: no concrete missing timestamp reason found; no native/reason change recommended.** No native process, test, build, UI action or source modification was performed.

Apple defines C617.1 for metadata within app/group/CloudKit containers, and 3B52.1 for files or directories the user specifically granted access to. The timestamp API list includes date properties/keys and POSIX stat/fstat/lstat/getattrlist families; generic `attributesOfItem` and `.fileSizeKey` are not named there. A user-selected external path alone does not establish use of a listed timestamp API. [Official Apple definitions](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype). The official documentation search content was readable; direct HTML required JavaScript and its Markdown link was unsupported by the web reader. No third-party source was used.

| Source site | Origin and actual use |
|---|---|
| `CapturePreviews.swift:82–88` | Reads creation/modification dates for decoded-image cache invalidation. References are validated managed originals/thumbnails, rooted at `store.root` through `DailyArchive.safeURL`; original external source paths are not used. |
| `OutgoingFileSnapshot.swift:51,59,103,106–107` | `fstat` checks managed source size/modification time before and after copy; `lstat` checks the default app temporary outgoing root. Shipping callers in `ExplorerTransfer.swift:44–115` supply managed originals or generated daily Markdown. `ExplorerScreen.swift:362` and `ExplorerQuery.swift:68–75` trace daily files to `store.root`. |
| `CaptureStore.swift:144–157`, `OriginalFileStorage.swift:60–67` | Incoming external files are checked for type/symlink/alias status and copied/hashed. No external timestamp read. |
| `ScreenshotFolderMonitor.swift:213–231` | Chosen external screenshot-folder enumeration reads type/symlink flags and size; no timestamp key or listed POSIX timestamp API. |
| `ArchiveBackup.swift:66,131,336–422` | Selected backup and export paths use entry existence, type, device and inode metadata. No timestamps are consumed and no listed POSIX timestamp API is invoked. Manifest `createdAt` is generated `Date()`, not filesystem creation time. |
| Other inspected metadata sites | `DailyArchive`, `DraftArchive`, `CaptureRepository`, `WorkspaceStore`, `ContentIndexService`, `UpdateHandoff` and `SoftwareUpdateService` inspect type, size, identity, owner or permissions; no further date consumption found. |

The shipping default archive is Application Support/DaBin (`CaptureStore.swift:32–35`); production startup constructs it without an external root (`ApplicationCoordinator.swift:40`). **Actual Store container and temporary-root resolution remains a sandbox-runtime gate.** The ordinary native test executables do not enforce it. C617.1 must not be described as blanket coverage for any app-owned external file or arbitrary temporary directory. Explicit custom archive/staging roots are isolated test injections, and no shipping caller supplies a custom external outgoing staging root.

This audit is not binary dependency analysis or Apple approval. Reaudit if external timestamp/stat calls are added. The coordinator separately reported no release-source matches for AppleKeyboard/AppleInterface/global CFPreferences/UserDefaults external-suite access; that report is attributed and was not independently rerun here.

| Checked source/resource | SHA-256 |
|---|---|
| `native/Resources/PrivacyInfo.xcprivacy` | `a9863c850f76e33c454b61aea834e1a9980db80a6d1d659b0d7a68ae835ee014` |
| `native/Sources/DaBin/ApplicationCoordinator.swift` | `4943fc63baeb82ffa76875b6e7a681a92304578e09088b0e4a8f6fbdde566cb4` |
| `native/Sources/DaBin/CaptureStore.swift` | `0ade3d0b992dcc5d284f70b13fc477995e82934f07f1dac59c2ccdb7c9f40098` |
| `native/Sources/DaBin/CapturePreviews.swift` | `83946800de9b22ad7209c3e188045839501b712bb5c2a178826603b83219abba` |
| `native/Sources/DaBin/OutgoingFileSnapshot.swift` | `fc37977b95e3a79cb2af295d3ee6e9159ec27a4ada7d84e9a96f7fdbc1e27048` |
| `native/Sources/DaBin/ExplorerTransfer.swift` | `578b24a46a5001b99eb3cde729a0f8bf593c9b5e847b47dcc29ed2aa00caafa0` |
| `native/Sources/DaBin/ExplorerScreen.swift` | `a55f44e37454b493479a50cbab794a6c0ecaf511cab17f339583e423de850777` |
| `native/Sources/DaBin/ExplorerQuery.swift` | `491d1ca752db038c2e877df94b15cc1242c64a1d472bd80d04d581a31f019e96` |
| `native/Sources/DaBin/OriginalFileStorage.swift` | `0374224915bf5ec6997ed692ec8b43288f70bc7455d54a78a2ac72237ed0df73` |
| `native/Sources/DaBin/ScreenshotFolderMonitor.swift` | `7057f0aff481db96009f0ba9a7ec06262fc3c987744c59d00646e208be0b48df` |
| `native/Sources/DaBin/ArchiveBackup.swift` | `f551d5b1710ec375902f32fa4cab14752a8bf9c7b1683e715f96da93c4555e69` |
| `native/Sources/DaBin/DailyArchive.swift` | `f9097332732a44e2a705c02eda1df9628cde45b8c16a80ecd3d43c7b1ef7fafa` |
| `native/Sources/DaBin/DraftArchive.swift` | `0a5601ec9dc987ced2c3cf42cd37bd5ac6e9175fdf7e69e32da600b0f9d85a49` |
| `native/Sources/DaBin/CaptureRepository.swift` | `51e0bf85feb85c01c498f2403479ac33fa0bf6cb41f265860d2ffaa533d4b318` |
| `native/Sources/DaBin/WorkspaceStore.swift` | `7063676747d0ee49945833e767631ce8245151395a6a56c8e1259e594abf3e3d` |
| `native/Sources/DaBin/ContentIndexService.swift` | `c1d27d28092c9e97b5fac1ebe8bdac511701b55eb1027eb4ab80b860a3ec6f6b` |
| `native/Sources/DaBin/InputService.swift` | `f461a08ffc71034d53e63d582e1ad0d6e020fde643cdb0a79d6af344ddd27239` |
| `native/Sources/DaBin/AppState.swift` | `c689b1cddc8335138bce51e78e788b7ea4a8fdc532147bf306fa7588c03c34ae` |
| `native/Sources/DaBin/UpdateHandoff.swift` | `aa8fadb66cc79ea16080dae270b1748b2b002ad36e3466e0bdb47b681654602a` |
| `native/Sources/DaBin/SoftwareUpdateService.swift` | `3b088ea8deff38bf5085370c06e4c32e02d2d7933622eb0f0f9eae18f1dd6623` |
| `native/Sources/DaBin/AutoCaptureService.swift` | `4fc07bf2adf559ea6bc814cc1f4fd58475ddccb2a1e47846580b4aaad59cede7` |
| `native/Sources/DaBin/AutoCaptureSettings.swift` | `f5e53774d1bf9421261feef5852e51a6954ba6a831172c46481c539c8cb2b2d0` |
| `native/Sources/DaBin/ShelfExport.swift` | `67589f74ba21c927ca0358ea37110e802ddd7fa16a1bba29faf4ca0c01b0b8b3` |
| `native/Sources/DaBin/DayExport.swift` | `604f447a16ac6a67bd1e170d9779fe35c929e686a67dd6ea70e6ca363cd2a2a9` |
| `native/Sources/DaBin/ProjectWorkspaceExport.swift` | `5126852a7222ebfd20252034202e2fd1aebe690c163cd2e8c520a268e323a11a` |
