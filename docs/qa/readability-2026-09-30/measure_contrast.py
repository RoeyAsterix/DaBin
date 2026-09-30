#!/usr/bin/env python3
"""Repeatable sRGB design-color audit, independent of SwiftUI rendering/tests."""
import hashlib
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
SOURCE = ROOT / "native/Sources/DaBin"


def rgb(value):
    return tuple(int(value[index:index + 2], 16) / 255 for index in (0, 2, 4))


def luminance(color):
    linear = [value / 12.92 if value <= .04045 else ((value + .055) / 1.055) ** 2.4 for value in color]
    return sum(value * weight for value, weight in zip(linear, (.2126, .7152, .0722)))


def contrast(first, second):
    values = (luminance(first), luminance(second))
    return (max(values) + .05) / (min(values) + .05)


def mix(first, second, fraction):
    return tuple(a + (b - a) * fraction for a, b in zip(first, second))


def adjusted(value, dark, selected_fill):
    color = rgb("AB92C6" if value == "6D5387" and dark else value)
    surface = rgb("2D2A30" if dark else "F3F1F5")
    target = rgb("FFFFFF" if dark else "000000")
    threshold = 4.6 if selected_fill else 4.5
    if not selected_fill and value == "6D5387":
        return color

    def readable(candidate):
        return contrast(candidate, mix(surface, candidate, selected_fill)) >= threshold

    if readable(color):
        return color
    low, high = 0.0, 1.0
    for _ in range(24):
        middle = (low + high) / 2
        if readable(mix(color, target, middle)):
            high = middle
        else:
            low = middle
    return mix(color, target, high)


def hex_color(color):
    return "".join(f"{round(value * 255):02X}" for value in color)


palette_source = (SOURCE / "BoardComponents.swift").read_text()
palette = {
    name: {"light": rgb(light), "dark": rgb(dark)}
    for name, light, dark in re.findall(r"static let (\w+) = adaptive\(light: 0x([0-9A-F]{6}), dark: 0x([0-9A-F]{6})\)", palette_source)
}
theme_source = (SOURCE / "ThemeSettings.swift").read_text()
presets = dict(re.findall(r'case \.(\w+): return "([0-9A-F]{6})"', theme_source))
presets["purple"] = "6D5387"
presets.update({f"custom-{value}": value for value in ["000000", "FFFFFF", "FF0000", "00FF00", "0000FF", "FFFF00", "888888", "F0F0FA"]})
report = {
    "method": "WCAG relative sRGB luminance, source design colors; no pixel-antialiasing sampling, no formal compliance claim",
    "sourceHashes": {name: hashlib.sha256((SOURCE / name).read_bytes()).hexdigest() for name in ["ThemeSettings.swift", "BoardComponents.swift"]},
    "solidPalette": [], "accentStates": [], "transparencyStress": [],
}
for mode in ["light", "dark"]:
    for name in ["foreground", "muted", "task", "completed"]:
        report["solidPalette"].append({"mode": mode, "color": name, "ratios": {
            surface: contrast(palette[name][mode], palette[surface][mode]) for surface in ["background", "surface", "soft"]
        }})
    for name, value in presets.items():
        before = adjusted(value, mode == "dark", 0)
        after = adjusted(value, mode == "dark", .16)
        board = palette["background"][mode]
        soft = palette["soft"][mode]
        report["accentStates"].append({
            "mode": mode, "choice": name, "storedHex": value,
            "beforeHex": hex_color(before), "afterHex": hex_color(after),
            "beforeSelectedBoard13Percent": contrast(before, mix(board, before, .13)),
            "afterSelectedBoard13Percent": contrast(after, mix(board, after, .13)),
            "beforeConservativeFocusSoft16Percent": contrast(before, mix(soft, before, .16)),
            "afterConservativeFocusSoft16Percent": contrast(after, mix(soft, after, .16)),
        })
    for opacity in [.35, .75, 1]:
        adverse_desktop = rgb("000000" if mode == "light" else "FFFFFF")
        background = mix(adverse_desktop, palette["background"][mode], opacity)
        report["transparencyStress"].append({"mode": mode, "boardOpacity": opacity,
            "desktop": "black" if mode == "light" else "white",
            "mutedContrast": contrast(palette["muted"][mode], background),
            "primaryContrast": contrast(palette["foreground"][mode], background),
        })
destination = Path(__file__).with_name("contrast-measurements.json")
destination.write_text(json.dumps(report, indent=2) + "\n")
print(destination)
print("Smallest solid foreground/secondary/status ratio:", min(r for entry in report["solidPalette"] for r in entry["ratios"].values()))
print("Smallest revised selected/focus ratio:", min(entry["afterConservativeFocusSoft16Percent"] for entry in report["accentStates"]))
print("Before: custom/preset selection failures:", sum(entry["beforeSelectedBoard13Percent"] < 4.5 for entry in report["accentStates"]), "/", len(report["accentStates"]))
