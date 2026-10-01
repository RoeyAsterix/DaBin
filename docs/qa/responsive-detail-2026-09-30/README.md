# Responsive capture details

DaBin 0.4.2 (54) makes capture details use the available window size.

## Changes

- Removed the 860-point detail content ceiling.
- Media preview height responds to the visible viewport and preserves aspect ratio. Short windows reserve room for the heading/actions and fixed Save bar.
- Titles, body text, comment editors and attachment tiles grow within readable bounds.
- Wide task workspaces place planning beside attachments. `AnyLayout` retains the same editors when returning to a narrow column.
- The save footer remains outside scrolling. No storage or capture semantics changed.

## Verification

- Final focused native QA: **3/3 suites, 522 checks** — WorkspaceWindow 193, CaptureTaskConversion 173, DailyCapture 156. [Source-fingerprinted report](focused-qa-report.json).
- New native resize checks use the same hosting tree at 380×680, 1200×900 and 1200×430, then return to compact. They verify real preview/content growth, visible Save, retained draft identity, comment/reminder/checklist input, editor focus where available, and no silent saves.
- **24 native responsive renders** cover image, task and comment at 380×430, 760×680, 1200×900 and 1200×430, in light and dark. [Manifest](responsive-detail-renders.json).
- An initial fit check caught short-window clipping. The viewport budget was corrected. The final **24 preview-fit renders** pass: all four colored markers remain visible in 16 image/document samples. Eight PDF renders are layout evidence only; AppKit bitmap capture omits PDFKit tiles. [Manifest](preview-fit-renders.json).
- `generate_project.py --check` and `git diff --check` pass. Release compilation uses warnings as errors; no separate Swift lint task is configured.
- An independent source review found no concrete regression in the three production UI changes.

These are focused regression checks, not a rerun of all 50 suites or distribution approval. Live video playback and PDF page navigation during resizing were not exercised in this cycle; their existing native view identity and fit implementation were preserved.

## Visual evidence

Screens use fictional records in isolated archives. They are production-view renders, not screenshots of the owner's capture archive.

[Compact image](image-compact-light.png) · [Expanded image](image-expanded-light.png) · [Expanded task](task-expanded-dark.png) · [Expanded comment](comment-expanded-light.png) · [Wide short window](image-wide-short-dark.png)

## Local installation

The final ARM64 Release build and strict code-signature verification passed. The guarded installer preserved build 53 in its application backup folder and left the capture archive untouched. The installed executable matches the verified build hash. DaBin was relaunched, Settings showed **0.4.2 (54)**, and the previously open capture was reopened and expanded. Auto Capture remained paused. [Installation verification](local-install-verification.json).
