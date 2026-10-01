# DaBin robot walkthrough

This source builds a silent 58.5-second 1920 x 1080 DaBin walkthrough. The existing native robot is the only character; every explanation appears inside an animated speech bubble.

The video uses nine short beats covering manual capture, Daily, Weekly, filters, local search, card actions, tasks, reminders, optional Auto Capture, privacy, and day/week export.

Build with the native Higgsedit CLI:

```sh
DABIN_ROBOT_ASSET=../../native/Resources/Assets.xcassets/AppIcon.appiconset/icon_512x512@2x.png \
DABIN_VIDEO_PROJECT_DIR=build/DaBinRobotWalkthrough \
higgsedit build design/walkthrough/build_walkthrough.js

higgsedit check build/DaBinRobotWalkthrough
higgsedit sheet build/DaBinRobotWalkthrough \
  --times 1.5,7.5,14,20.5,27,34.5,41.5,48.5,55 \
  --cols 3 \
  --out build/DaBinRobotWalkthrough/renders/contact-sheet.png

higgsedit render build/DaBinRobotWalkthrough \
  --quality final \
  --depth 8 \
  --bitrate 12M \
  --out build/DaBinRobotWalkthrough/renders/DaBin-Robot-Walkthrough.mp4
```

The delivery file belongs under `output/video/` and generated Higgsedit project files remain untracked.
