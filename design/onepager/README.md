# DaBin one-page quick guide

Final PDF: `../../output/pdf/DaBin-Quick-Guide.pdf`

A4 portrait, one page. Uses the existing native `DaBinLogo.swift` logo, exported with `ExportLogo.swift`, and the existing app robot icon. No product asset was redesigned. The generator uses standard PDF fonts and has no machine-specific font dependency.

Content checked against the current native implementation. It covers manual drag and paste, Daily/Weekly, search, comments, reminders, tasks, placement, appearance controls, and the opt-in Auto Capture flow. The Auto Capture section explains that it starts off, watches future clipboard changes and the selected screenshot folder, stores content locally, supports pausing and default exclusions, and groups four or more actions from one clock hour into an expandable summary.

Built with ReportLab; pypdf confirmed one A4 page and expected text. Poppler rendering was inspected at 2807px height for legibility, clipping, alignment and spacing. The PDF is self-contained.

To regenerate, run `build_guide.py` with Python, ReportLab and pypdf. It uses the existing native app icon and writes a layout diagnostic into `../../tmp/pdfs/`.
