# DaBin — build 53 source-bound redesign

Source: supplied native/BoardComponents.swift Palette; ThemeSettings.swift; DaBinLogo.swift; RobotAppFrameView.swift; current-build53 synthetic screenshots.

```css
:root {
--bg: oklch(99.239% 0.00283 308.429); /* #FDFCFE */
--surface: oklch(100.000% 0.00000 89.876); /* #FFFFFF */
--fg: oklch(28.126% 0.01892 303.380); /* #2B2731 */
--muted: oklch(47.957% 0.02523 306.469); /* #615A69 */
--border: oklch(91.077% 0.00867 308.355); /* #E3E0E6 */
--accent: oklch(49.050% 0.08612 306.445); /* #6D5387 */
--font-display: "SF Pro Rounded", "Avenir Next", -apple-system, sans-serif;
--font-body: "SF Pro Text", -apple-system, BlinkMacSystemFont, sans-serif;
--font-mono: "SF Mono", ui-monospace, Menlo, monospace;
}
```

- No permanent sidebar; four labeled destinations and contextual controls.
- Retain 10pt side, 32pt head, 18pt feet reservations. Robot metal gradients only on the frame.
- Cards use 1px borders and 12px radius; depth reserved for menus.
- Purple denotes selected destination and primary action; status uses text and shape too.
- 14px body and 12px metadata; 32px desktop targets, 44px on touch.
- Dark source tokens: #1D1C21 canvas, #252328 surface, #EBEAED text, #A9A6AE metadata, #3C3940 border, #AB92C6 readable accent.
