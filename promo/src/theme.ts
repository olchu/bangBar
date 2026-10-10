import { Easing, interpolate, spring } from "remotion";

export const FPS = 30;
export const WIDTH = 1920;
export const HEIGHT = 1080;
export const DURATION = 40 * FPS;

export const ACCENT = "#FF383C";
export const PIN = "#FF9F0A";

export const FONT = "'SF Pro', -apple-system, system-ui, sans-serif";
export const ROUNDED = "'SF Rounded', 'SF Pro', -apple-system, sans-serif";
export const MONO = "'SF Mono', Menlo, monospace";

// Logical MacBook Pro 14" screen, in points.
export const SCREEN_W = 1512;
export const SCREEN_H = 982;
export const MENU_BAR_H = 37;
export const NOTCH_W = 185;

export const PANEL = {
  topRadius: 22,
  earInset: 22,
  bottomRadius: 26,
  topSafeInset: 41,
  contentHeight: 110,
  edgePadding: 20,
  horizontalPadding: 64,
  spacing: 12,
};

export const PANEL_EXPANDED_H = PANEL.topSafeInset + PANEL.contentHeight + PANEL.edgePadding;
export const PANEL_COMPACT_W = 340;

export const ease = Easing.bezier(0.22, 1, 0.36, 1);

export type Stop = [frame: number, value: number];

export const track = (frame: number, stops: Stop[], easing = ease) =>
  interpolate(
    frame,
    stops.map((s) => s[0]),
    stops.map((s) => s[1]),
    { extrapolateLeft: "clamp", extrapolateRight: "clamp", easing },
  );

export const springTrack = (
  frame: number,
  stops: Stop[],
  config: Parameters<typeof spring>[0]["config"] = { damping: 17, stiffness: 140, mass: 0.9 },
) => {
  let value = stops[0][1];
  for (let i = 1; i < stops.length; i++) {
    const [at, target] = stops[i];
    if (frame < at) break;
    const progress = spring({ frame: frame - at, fps: FPS, config });
    value = value + (target - value) * progress;
  }
  return value;
};

export const fade = (frame: number, inAt: number, outAt = Infinity, length = 8) =>
  Math.min(
    track(frame, [
      [inAt, 0],
      [inAt + length, 1],
    ]),
    outAt === Infinity
      ? 1
      : track(frame, [
          [outAt, 1],
          [outAt + length, 0],
        ]),
  );
