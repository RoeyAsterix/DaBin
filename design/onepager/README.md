# DaBin one-page quick guide

Final PDF: `../../output/pdf/DaBin-Quick-Guide.pdf`

A4 portrait, one page. Uses the existing native `DaBinLogo.swift` logo, exported with `ExportLogo.swift`, and the existing app robot icon. No product asset was redesigned. The generator uses standard PDF fonts and has no machine-specific font dependency.

Content checked against the current native README and implementation. Describes implemented capture, Daily/Week, search, comments, reminders, tasks, placement, theme, local storage, and the user-initiated GitHub update control. No AI/project-detection, silent-update, or automatic-monitoring claims.

Built with ReportLab; pypdf confirmed one A4 page and expected text. Poppler rendering was inspected at 1684px height for legibility, clipping, alignment and spacing. The PDF is self-contained.

To regenerate, run `build_guide.py` with Python, ReportLab and pypdf. It uses the existing native app icon and writes a layout diagnostic into `../../tmp/pdfs/`.
