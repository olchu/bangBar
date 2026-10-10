import React from "react";
import { useCurrentFrame } from "remotion";
import { T } from "./script";
import { track } from "./theme";

type Key = [frame: number, x: number, y: number];

// Screen-point positions; panel content starts at x=437, y=41 on page 1.
const PATH: Key[] = [
  [0, 1180, 600],
  [12, 1180, 600],
  [78, 762, 24],
  [T.openHover + 40, 735, 90],
  [T.collapseToCompact - 14, 705, 118],
  [T.collapseToCompact + 6, 690, 300],
  [T.expandFromCompact - 26, 672, 280],
  [T.expandFromCompact - 2, 640, 20],
  [T.nextTrackClick - 16, 640, 143],
  [T.nextTrackClick + 14, 640, 143],
  [T.clockFocus + 6, 832, 104],
  [T.clipboardSwipe - 6, 800, 112],
  [T.clipboardCopy - 14, 772, 124],
  [T.clipboardCopy + 26, 772, 124],
  [T.clipboardClose - 10, 780, 112],
  [T.habitClick - 22, 760, 110],
  [T.habitClick - 4, 565, 98],
  [T.pageBack - 10, 640, 110],
  [T.mirrorClick - 4, 1028, 96],
  [T.shutter - 14, 1028, 96],
  [T.shutter - 2, 1028, 125],
  [T.hide - 18, 1028, 125],
  [T.hide + 2, 1150, 470],
  [T.endCard, 1180, 520],
];

const CLICKS = [T.nextTrackClick, T.clipboardCopy, T.habitClick, T.mirrorClick, T.shutter];

export type Swipe = { at: number; dx: number; dy: number };

export const SWIPES: Swipe[] = [
  { at: T.clipboardSwipe, dx: 0, dy: 1 },
  { at: T.clipboardClose - 6, dx: 0, dy: -1 },
  { at: T.pageSwipe, dx: -1, dy: 0 },
  { at: T.pageBack - 6, dx: 1, dy: 0 },
];

export const cursorPosition = (frame: number) => {
  const frames = PATH.map((k) => k[0]);
  let i = frames.findIndex((f) => f > frame);
  if (i === -1) i = PATH.length - 1;
  const a = PATH[Math.max(i - 1, 0)];
  const b = PATH[i];
  const stops = (v: 1 | 2): [number, number][] => [
    [a[0], a[v]],
    [b[0], b[v]],
  ];
  return { x: track(frame, stops(1)), y: track(frame, stops(2)) };
};

const SwipeHint: React.FC<{ swipe: Swipe; frame: number }> = ({ swipe, frame }) => {
  const local = frame - swipe.at;
  if (local < -4 || local > 22) return null;
  const travel = track(local, [
    [0, 0],
    [14, 1],
  ]);
  const opacity = Math.min(track(local, [[-4, 0], [2, 1]]), track(local, [[14, 1], [22, 0]]));
  const offset = (travel - 0.5) * 26;
  return (
    <div style={{ position: "absolute", left: 22, top: 18, opacity }}>
      <div
        style={{
          position: "relative",
          width: 44,
          height: 44,
          borderRadius: 12,
          background: "rgba(20,20,24,0.72)",
          border: "1px solid rgba(255,255,255,0.18)",
          backdropFilter: "blur(10px)",
        }}
      >
        {[-1, 1].map((side) => (
          <div
            key={side}
            style={{
              position: "absolute",
              left: 22 - 4 + (swipe.dy !== 0 ? side * 6 : swipe.dx * offset),
              top: 22 - 4 + (swipe.dx !== 0 ? side * 6 : swipe.dy * offset),
              width: 8,
              height: 8,
              borderRadius: "50%",
              background: "white",
              boxShadow: "0 0 6px rgba(255,255,255,0.8)",
            }}
          />
        ))}
      </div>
    </div>
  );
};

export const Cursor: React.FC = () => {
  const frame = useCurrentFrame();
  const { x, y } = cursorPosition(frame);
  const click = CLICKS.find((c) => frame >= c && frame < c + 14);
  const local = click === undefined ? 99 : frame - click;
  const press = local < 4 ? 0.82 : 1;
  const ring = track(local, [
    [0, 0],
    [14, 1],
  ]);
  const opacity = track(frame, [
    [T.endCard - 6, 1],
    [T.endCard + 4, 0],
  ]);

  return (
    <div style={{ position: "absolute", left: x, top: y, opacity, pointerEvents: "none" }}>
      {click !== undefined && (
        <div
          style={{
            position: "absolute",
            left: -16 * ring,
            top: -16 * ring,
            width: 32 * ring,
            height: 32 * ring,
            borderRadius: "50%",
            border: "2px solid rgba(255,255,255,0.85)",
            opacity: 1 - ring,
          }}
        />
      )}
      {SWIPES.map((s) => (
        <SwipeHint key={s.at} swipe={s} frame={frame} />
      ))}
      <svg
        width={22}
        height={32}
        viewBox="0 0 22 32"
        style={{ position: "absolute", left: -3, top: -2, transform: `scale(${press})`, transformOrigin: "3px 2px", filter: "drop-shadow(0 2px 3px rgba(0,0,0,0.45))" }}
      >
        <path d="M3 2 L3 25 L8.5 19.8 L12.3 28.6 L16 27 L12.3 18.4 L19.6 18.4 Z" fill="black" stroke="white" strokeWidth="1.6" strokeLinejoin="round" />
      </svg>
    </div>
  );
};
