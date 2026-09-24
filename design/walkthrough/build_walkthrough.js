const WIDTH = 1920;
const HEIGHT = 1080;
const FPS = 30;

const COLORS = {
  background: "#F8F4FA",
  bubble: "#FFFFFF",
  bubbleLine: "#72508E",
  ink: "#342A40",
};

const scenes = [
  {
    start: 0,
    duration: 5.5,
    side: "left",
    copy: "Hi, I'm DaBin.\nI remember what you worked on.",
  },
  {
    start: 5.5,
    duration: 6.5,
    side: "right",
    copy: "Drop or paste text, links, images,\nPDFs, docs, videos, or other files.",
  },
  {
    start: 12,
    duration: 6.5,
    side: "left",
    copy: "I save each capture under today\non your private Daily board.",
  },
  {
    start: 18.5,
    duration: 6.5,
    side: "right",
    copy: "Browse Daily or Weekly.\nFilter by content type or tasks.\nWeekly hides empty days.",
  },
  {
    start: 25,
    duration: 7.5,
    side: "left",
    copy: "Search a day or week - even words\ninside screenshots, images, PDFs,\nand documents.",
  },
  {
    start: 32.5,
    duration: 7.5,
    side: "right",
    copy: "Copy, comment, or set a reminder.\nMinimize or remove it.\nTurn any capture into a task.",
  },
  {
    start: 40,
    duration: 7,
    side: "left",
    copy: "Auto Capture is optional.\nIt starts OFF, and can save future\ncopies and screenshots.",
  },
  {
    start: 47,
    duration: 6.5,
    side: "right",
    copy: "Your captures and searchable text\nstay in my local archive on your Mac.\nExport a day or week whenever you want.",
  },
  {
    start: 53.5,
    duration: 5,
    side: "left",
    copy: "Feed me your day.\nI'll keep it tidy.",
  },
];

function robotAnimations(duration, side, index) {
  const direction = side === "left" ? -1 : 1;
  const sway = index % 2 === 0 ? 1 : -1;
  return [
    {
      property: "opacity",
      keyframes: [
        { at: 0, value: 0, easing: "ease-out" },
        { at: 0.35, value: 1 },
        { at: duration - 0.35, value: 1, easing: "ease-in" },
        { at: duration, value: 0 },
      ],
    },
    {
      property: "offsetX",
      keyframes: [
        { at: 0, value: direction * 110, easing: "house" },
        { at: 0.58, value: 0 },
        { at: duration - 0.42, value: 0, easing: "ease-in" },
        { at: duration, value: direction * 62 },
      ],
    },
    {
      property: "offsetY",
      keyframes: [
        { at: 0, value: 46, easing: "house" },
        { at: 0.48, value: -18, easing: "ease-out" },
        { at: 0.92, value: 0, easing: "smooth" },
        { at: duration * 0.52, value: -10, easing: "ease-in-out" },
        { at: duration * 0.63, value: 0 },
        { at: duration - 0.42, value: 0, easing: "ease-in" },
        { at: duration, value: 28 },
      ],
    },
    {
      property: "scale",
      keyframes: [
        { at: 0, value: 0.82, easing: "house" },
        { at: 0.42, value: 1.07, easing: "ease-out" },
        { at: 0.82, value: 1 },
        { at: duration - 0.35, value: 1, easing: "ease-in" },
        { at: duration, value: 0.94 },
      ],
    },
    {
      property: "rotation",
      keyframes: [
        { at: 0, value: direction * 5, easing: "house" },
        { at: 0.55, value: -direction * 2.8, easing: "ease-out" },
        { at: 1.05, value: 0, easing: "smooth" },
        { at: duration * 0.42, value: sway * 2.2, easing: "ease-in-out" },
        { at: duration * 0.58, value: -sway * 1.4, easing: "ease-in-out" },
        { at: duration * 0.72, value: 0 },
        { at: duration, value: -direction * 3 },
      ],
    },
  ];
}

function bubbleAnimations(duration, side) {
  const direction = side === "left" ? 1 : -1;
  return [
    {
      property: "opacity",
      keyframes: [
        { at: 0.12, value: 0, easing: "ease-out" },
        { at: 0.52, value: 1 },
        { at: duration - 0.42, value: 1, easing: "ease-in" },
        { at: duration, value: 0 },
      ],
    },
    {
      property: "offsetX",
      keyframes: [
        { at: 0.12, value: direction * 72, easing: "house" },
        { at: 0.62, value: 0 },
        { at: duration - 0.42, value: 0, easing: "ease-in" },
        { at: duration, value: direction * 34 },
      ],
    },
    {
      property: "scale",
      keyframes: [
        { at: 0.12, value: 0.92, easing: "house" },
        { at: 0.52, value: 1.025, easing: "ease-out" },
        { at: 0.82, value: 1 },
        { at: duration - 0.42, value: 1, easing: "ease-in" },
        { at: duration, value: 0.97 },
      ],
    },
  ];
}

export default async ({ project, frame, media, path, rect, text }) => {
  const projectDir = process.env.DABIN_VIDEO_PROJECT_DIR || "build/DaBinRobotWalkthrough";
  const robotPath = process.env.DABIN_ROBOT_ASSET ||
    "../../native/Resources/Assets.xcassets/AppIcon.appiconset/icon_512x512@2x.png";

  const p = await project({
    dir: projectDir,
    size: `${WIDTH}x${HEIGHT}`,
    fps: FPS,
    background: COLORS.background,
  });
  const robot = await p.add(robotPath);

  scenes.forEach((scene, index) => {
    const robotLeft = scene.side === "left";
    const robotX = robotLeft ? 70 : 1370;
    const bubbleX = robotLeft ? 640 : 150;
    const bubbleY = 310;
    const bubbleWidth = 1130;
    const bubbleHeight = scene.copy.split("\n").length === 3 ? 330 : 290;
    const bubbleFontSize = scene.copy.length > 94 ? 47 : scene.copy.length > 72 ? 51 : 57;

    const tail = robotLeft
      ? path({
          d: "M 54 0 L 0 27 L 54 54 Z",
          x: -46,
          y: bubbleHeight * 0.55,
          width: 54,
          height: 54,
          fill: COLORS.bubble,
          stroke: { width: 4, color: COLORS.bubbleLine, cap: "round" },
        })
      : path({
          d: "M 0 0 L 54 27 L 0 54 Z",
          x: bubbleWidth - 8,
          y: bubbleHeight * 0.55,
          width: 54,
          height: 54,
          fill: COLORS.bubble,
          stroke: { width: 4, color: COLORS.bubbleLine, cap: "round" },
        });

    const robotNode = frame(
      {
        name: `Robot ${index + 1}`,
        x: robotX,
        y: 320,
        width: 500,
        height: 500,
        layout: "none",
        origin: "center",
        animate: robotAnimations(scene.duration, scene.side, index),
        motionBlur: { samples: 6, shutter: 0.42 },
      },
      [
        media({
          file: robot,
          x: 0,
          y: 0,
          width: 500,
          height: 500,
          fit: "contain",
          shadow: { x: 0, y: 18, blur: 32, color: "#35254333" },
        }),
      ],
    );

    const bubbleNode = frame(
      {
        name: `Speech bubble ${index + 1}`,
        x: bubbleX,
        y: bubbleY,
        width: bubbleWidth,
        height: bubbleHeight,
        layout: "none",
        origin: "center",
        animate: bubbleAnimations(scene.duration, scene.side),
      },
      [
        tail,
        rect({
          x: 0,
          y: 0,
          width: bubbleWidth,
          height: bubbleHeight,
          fill: COLORS.bubble,
          radius: 54,
          strokeColor: COLORS.bubbleLine,
          strokeWidth: 4,
          shadow: { x: 0, y: 18, blur: 46, color: "#35254324" },
        }),
        text(scene.copy, {
          x: 68,
          y: scene.copy.split("\n").length === 3 ? 56 : 61,
          width: bubbleWidth - 136,
          height: bubbleHeight - 108,
          fontFamily: "DM Sans",
          fontSize: bubbleFontSize,
          fontWeight: 700,
          lineHeight: 1.18,
          align: "left",
          color: COLORS.ink,
          motion: {
            by: "line",
            from: { opacity: 0, y: 18, scale: 0.985 },
            at: 0.5,
            duration: 0.72,
            overlap: 0.2,
            easing: "house",
          },
        }),
      ],
    );

    const root = frame(
      { width: WIDTH, height: HEIGHT, layout: "none" },
      [robotNode, bubbleNode],
    );

    p.compose(root, {
      at: scene.start,
      dur: scene.duration,
      name: `DaBin walkthrough ${index + 1}`,
    });
  });
};
