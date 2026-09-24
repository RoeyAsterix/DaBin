# DaBin one-page feature guide

Final PDF: `../../output/pdf/DaBin-Quick-Guide.pdf`

The guide is one A4 landscape page. It uses the existing DaBin logo, the native robot icon, standard PDF fonts, and vector-drawn feature icons. The landscape grid keeps the complete feature inventory readable while preserving DaBin's compact purple visual language.

Content is checked against the current native implementation. The page covers manual capture, Daily and Weekly, filters, contextual local search, per-card actions, tasks, reminders, day and week export, Auto Capture, hourly grouping, robot behavior, appearance, menu bar controls, updates, shortcuts, storage, and privacy.

Run `build_guide.py` with Python, ReportLab, and pypdf. The generator writes the delivery copy to `../../output/pdf/DaBin-Quick-Guide.pdf`, syncs the identical repository copy to `../../docs/DaBin-Quick-Guide.pdf`, and writes structural and content checks to `../../tmp/pdfs/layout-check.json`.

Before publishing, render the PDF with Poppler and inspect the page at print resolution for clipping, alignment, spacing, and legibility.
