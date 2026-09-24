# DaBin 0.3.9

## Weekly shows the days that matter

- Weekly now omits dates that contain no captures, cards, or tasks.
- Tasks carried into later dates and tasks shown on their reminder date count as activity, so they keep that date visible.
- Content filters change the cards inside an active date without rearranging the date columns.
- The seven-day calendar range and previous/next week navigation are unchanged.

## A smaller Weekly window

- The Weekly panel now grows to match the number of active dates instead of always opening at seven-column width.
- A range with no activity remains at the compact 380 × 290 point size and shows one bored-robot message instead of seven empty columns.
- Sparse weeks keep their dates in chronological order and center the remaining columns.
- The left/right opening direction, movable panel, narrow-display scrolling, themes, transparency, filters, and Reduce Motion behavior remain available.

## Verification

Automated state coverage checks empty, sparse, nonconsecutive, carried-task, reminder-day, and filter-stability cases. Native window coverage checks content-sized widths from zero through seven active dates, both opening directions, compact empty ranges, screen clamping, navigation, and restoration. Fresh light and dark native renders cover compact empty weeks and a two-day sparse week.
