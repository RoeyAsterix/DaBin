# DaBin package for Open Design

Start with [OPEN_DESIGN_HANDOFF.md](./OPEN_DESIGN_HANDOFF.md). It contains the current assignment, the user's latest feedback, required behavior, deliverables, and a ready-to-send prompt.

The current interaction is **hidden at rest → cursor enters any screen corner → purple robot peeks inward → direct drop or explicit paste into the robot → brief digest animation → safe retraction after cursor exit**. There is no separate drop/paste area, composer, capture text box, or add button. Hover alone does not capture clipboard content.

Double-clicking the robot opens a compact Daily board with no sidebar or desktop background. Every capture has Comment and Reminder buttons. Keep All / Links / Files / Media filters and required contextual search: only dates with matches, with the capture immediately before and after each match from that same day, deduplicating overlap. An opened Daily board stays interactable until dismissed; moving from the corner into the board must not close it. This dismissal behavior is a design assumption supporting the user's requested flow.

Use [PRODUCT_PLAN.md](./PRODUCT_PLAN.md) for the product model. `opendesign-redesign/` is the most recent functional prototype and a **rejected historical visual reference**; `design/` and `references/` are earlier rejected concepts. Their persistent robot, separate capture controls, dimensions, and layouts do not describe the corrected design. `CODEX_DESIGN_HANDOFF.md` is historical; the Open Design handoff is authoritative wherever files differ.

All files in this package concern DaBin. The requested new design should be placed in a separate `DaBin/open-design-v2/` folder so it can be compared with the included references.
