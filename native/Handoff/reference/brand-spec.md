# DaBin — spatial redesign

Source: `source/DaBin/OPEN_DESIGN_HANDOFF.md` (current brief). The prior prototype is functional evidence and a rejected layout, not a seed to shrink.

## Palette
Extracted source colors: panel #fdfcfe, surface #ffffff, foreground #292631, muted #77717e, border #eae7ed, accent #6c548c. The new panel uses these neutral families with darker secondary text for legibility.

```css
--bg: oklch(99.3% 0.003 310);
--surface: oklch(100% 0 0);
--fg: oklch(28% 0.020 302);
--muted: oklch(48% 0.024 305);
--border: oklch(91% 0.009 308);
--accent: oklch(49% 0.087 307);
--font-display: 'SF Pro Display', -apple-system, BlinkMacSystemFont, sans-serif;
--font-body: 'SF Pro Text', -apple-system, BlinkMacSystemFont, sans-serif;
--font-mono: 'SF Mono', ui-monospace, Menlo, monospace;
```

## Posture
- Transparent desktop, content-sized floating surfaces, no simulated wallpaper.
- A tucked metallic-purple bin is the only resting element.
- Neutral open surfaces; color mostly comes from captures and the robot.
- Hairline boundaries; one restrained popover shadow; no nested card boxes.
- Readable 14–16px type and 32–44px controls instead of scaling down the rejected UI.

## Selected spatial model
Edge tab: 32 × 43px SVG bounds at rest; a 52 × 56px pointer target; 84 × 92px transient drop receiver; 420 × up to 640px Daily content sheet. The larger on-demand sheet trades temporary area for readable capture content.

Alternative: a 38 × 36px bottom-docked bin opening a 740 × 322px horizontal tray. This reads more content at once but collides with the macOS Dock zone and covers more horizontal working area.
