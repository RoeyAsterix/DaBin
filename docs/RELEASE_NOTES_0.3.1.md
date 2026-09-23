# DaBin 0.3.1

DaBin's little purple robot has a new home option and a friendlier personality.

## Choose where the robot waits

Open **… → Settings → Your quiet corner** and choose:

- **Screen corners** — the familiar default. Move the pointer into any corner to reveal DaBin.
- **Below camera island** — on a compatible MacBook, move the pointer to the built-in camera island and the robot peeks out underneath it.

DaBin uses the screen safe-area information supplied by macOS to find the real camera cutout. If a display has no camera island, that display continues using its corners. Your choice stays ready if you later connect or return to a compatible display.

The choice is a local app preference. It does not change captures, move the Daily board or require Camera, Screen Recording or Accessibility permission.

## A more expressive robot

The transient robot is now a native macOS character with independently animated eyes, face, lid, arms and body. It can:

- peek in from the nearest edge and give a small greeting;
- follow the pointer while you hover;
- open its lid when a supported drag arrives;
- chew while DaBin saves the capture;
- celebrate a successful save, shrug at a partial save, or look puzzled after a failure;
- blink, glance around and occasionally shrug while waiting.

Animation work stops when the robot hides. With **Reduce Motion** enabled in macOS, DaBin keeps clear expression changes while removing positional, repeated and keyframed movement.

## Everything else stays familiar

Drop or paste content onto the robot, then double-click it to open Daily. Captures remain in the same private local archive, the Daily board keeps its saved position, and displays without a camera island retain the corner interaction.

The direct build can install this release from **Settings → Software updates**. The current personal package is ARM64 and locally signed for the owner's Mac; distribution to other Macs still requires Developer ID signing and Apple notarization.
