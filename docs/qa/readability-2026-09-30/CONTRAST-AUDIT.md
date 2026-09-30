# DaBin readability audit — 30 September 2026

## Scope and method

This is an engineering/expert review, not a usability study with recruited participants or an accessibility certification. The review inspected the current compact-header native renders in light and dark appearances, the minimum-width Workspace render, semantic palette values, typography, selected/focused states, and the user-controlled opacity behavior.

The calculation uses the sRGB design colors, linearized relative luminance, and alpha composition. Text is assessed against 4.5:1; recognizable active icons against 3:1. These are useful design targets from the [W3C text contrast explanation](https://www.w3.org/WAI/WCAG22/Understanding/contrast-minimum.html) and [non-text contrast explanation](https://www.w3.org/WAI/WCAG22/Understanding/non-text-contrast.html). Pixel antialiasing is intentionally excluded from the color calculation. Actual readability also depends on font size/weight, display, vision, and ambient lighting.

Repeat the measurements with:

```sh
python3 docs/qa/readability-2026-09-30/measure_contrast.py
```

The JSON records unrounded ratios and source hashes. Pass/fail decisions use unrounded values; the table below rounds only for reading.

## Findings and implemented correction

Primary, secondary, task, and completed text colors already pass on the three solid board/card/soft surfaces. The smallest ratios before changes were:

| Semantic color | Minimum across both themes and solid surfaces |
| --- | ---: |
| Primary | 11.80:1 |
| Secondary | 5.89:1 |
| Task | 5.07:1 |
| Completed | 5.09:1 |

The accent resolver only checked an untinted surface. A chosen accent that barely passed that check could lose readability once used for text on its own selected background. Eighteen of the 28 preset/custom-color and appearance cases tested fell below 4.5:1 on the actual 13% selected-board fill. The default purple selected navigation passed; the failure was not universal.

`ThemeSettings.resolvedAccentColor` now accounts for a 16% focus/selection tint over the least favorable solid surface, with a 4.6:1 target. It mixes only as much black or white as needed. Stored user choices and the default light purple remain unchanged; the rendered default dark purple becomes `B9A4CF`.

| Appearance and choice | Selected board before | Selected board after | Conservative focus fill after |
| --- | ---: | ---: | ---: |
| Light purple | 5.27 | 5.27 | 4.63 |
| Light amber | 4.18 | 5.24 | 4.60 |
| Light custom gray | 4.20 | 5.23 | 4.60 |
| Dark purple | 5.01 | 5.90 | 4.60 |
| Dark blue | 4.47 | 5.89 | 4.60 |
| Dark amber | 4.47 | 5.89 | 4.60 |

The minimum corrected conservative ratio is **4.600000018:1** across the measured colors. Automated Swift checks were extended to cover 10%, 13%, 14%, and 16% selection/focus fills; stronger pressed icon fill plus group fading; the semantic solid palette; and dynamic appearance resolution. This audit agent did not execute the test runner; the main QA report records actual execution.

## Transparency

User-selected transparency cannot guarantee contrast against arbitrary desktop content. At 75% board opacity, secondary text falls to 3.53:1 on a black desktop in light mode or 3.10:1 on a white desktop in dark mode. At 35%, it can approach 1:1. Opaque capture cards still provide their own stable background.

Keep the user preference, explain this tradeoff, provide a direct return to solid opacity, and keep navigation/status chrome readable. macOS Reduce Transparency already requests a solid board. The parent implementation handles header/footer protection and the Settings recovery control; see its final screenshots and verification report for those changes. This document does not claim arbitrary reduced-opacity body content passes contrast requirements.

## Typography and visual observations

- The compact light Inbox render has a clear hierarchy: 13 pt capture prompt, 15 pt card titles, and supporting metadata. The compact header leaves substantially more visible content without removing the labeled primary routes.
- The minimum dark Workspace render preserves full primary-route labels and an intact first card. The scroll continuation is visible.
- The most fragile text is 10 pt project/date/effort metadata. Recommend increasing important metadata to at least 11 pt where layout allows, with wrapping rather than truncation for long project names. Root owns typography/layout changes and their rendering verification.
- The default light/dark palette needs no wholesale color replacement. The low-opacity drag-grip symbol is decorative, with the actual draggable region separate from icon navigation.
- Card borders are decorative grouping boundaries, not the sole indication of a button or state. This audit did not assert that every faint divider must reach 3:1.

## Limits

This bounded review did not operate the personal archive, alter user preferences, launch app/test processes, test VoiceOver, or inspect every possible custom color and background image. Fourteen representative colors were measured in each appearance; the binary-search correction handles arbitrary valid sRGB choices. The main QA cycle supplies final native renders, interaction checks, compiler/build results, and test reports.
