# Quiet Orbit provenance

Source: user-supplied `DABIN_ROBOT_CODEX_HANDOFF.zip`.
SHA-256: `9e690af76e24dee92f54f5f9c7cd3ab2f423c63c823752bd0c583d418bd29eb4`.

The supplied geometry and gradients were translated into the native Core Animation renderer. The SVG fragment and composed scene remain editable references. The captured content is never used as an animation preview.

`QuietOrbitGeometry.swift` maps seven perches from the reference coordinate system to measured macOS camera geometry. `RobotView` owns manual entry, relocation, hardware exclusion, and native input. `AutoCaptureRobotPresenter` keeps the existing successful-save and burst-count lifecycle. The shared `RobotCharacterView` draws and animates the character; no animation dependency was introduced.

Existing corner placement, capture formats, app-window behavior, and hover-paste commands remain supported. The robot does not perform a periodic idle routine. Reduce Motion uses short opacity transitions.
