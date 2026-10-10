import React from "react";
import { spring, useCurrentFrame } from "remotion";
import { T } from "./script";
import { ACCENT, FONT, FPS, track } from "./theme";

type Caption = { from: number; to: number; text: string; accent?: string; sub?: string };

const s = (seconds: number) => Math.round(seconds * FPS);

export const CAPTIONS: Caption[] = [
  { from: s(0.3), to: s(2.8), text: "Your notch does nothing.", accent: "nothing." },
  { from: T.openHover + 4, to: s(5.6), text: "Until now.", accent: "now." },
  { from: T.collapseToCompact + 6, to: T.expandFromCompact - 2, text: "Music lives in the notch.", accent: "notch." },
  { from: T.expandFromCompact + 8, to: s(11.0), text: "Now Playing, always in reach.", accent: "Playing," },
  { from: T.clockFocus + 4, to: s(14.4), text: "Your next meeting, at a glance.", accent: "meeting," },
  { from: T.clipboardSwipe + 6, to: s(19.6), text: "Everything you copied.", sub: "Clipboard history, one swipe away", accent: "copied." },
  { from: T.pageSwipe + 8, to: s(25.8), text: "Swipe for more.", sub: "Focus timer · Habits · System · Moon", accent: "more." },
  { from: T.mirrorClick, to: s(30.8), text: "A mirror before every call.", accent: "mirror" },
  { from: T.hide + 4, to: T.endCard - 4, text: "Gone when you don't need it.", accent: "Gone" },
];

const CaptionView: React.FC<{ caption: Caption; frame: number }> = ({ caption, frame }) => {
  const local = frame - caption.from;
  const out = track(frame, [
    [caption.to - 8, 0],
    [caption.to, 1],
  ]);
  const words = caption.text.split(" ");

  return (
    <div
      style={{
        position: "absolute",
        left: 0,
        right: 0,
        top: 590,
        display: "flex",
        flexDirection: "column",
        alignItems: "center",
        gap: 22,
        opacity: 1 - out,
        transform: `translateY(${-14 * out}px)`,
        filter: `blur(${out * 8}px)`,
      }}
    >
      <div style={{ display: "flex", gap: 22, fontFamily: FONT, fontSize: 84, fontWeight: 700, letterSpacing: -2.5, color: "white" }}>
        {words.map((word, i) => {
          const p = spring({ frame: local - i * 3, fps: FPS, config: { damping: 16, stiffness: 160 } });
          return (
            <span
              key={i}
              style={{
                display: "inline-block",
                opacity: p,
                transform: `translateY(${(1 - p) * 34}px)`,
                filter: `blur(${(1 - p) * 10}px)`,
                color: word === caption.accent ? ACCENT : "white",
                textShadow: word === caption.accent ? "0 0 40px rgba(255,56,60,0.45)" : "0 4px 30px rgba(0,0,0,0.5)",
              }}
            >
              {word}
            </span>
          );
        })}
      </div>
      {caption.sub && (
        <div
          style={{
            fontFamily: FONT,
            fontSize: 34,
            fontWeight: 500,
            color: "rgba(255,255,255,0.6)",
            letterSpacing: -0.4,
            opacity: track(local, [
              [words.length * 3 + 4, 0],
              [words.length * 3 + 14, 1],
            ]),
          }}
        >
          {caption.sub}
        </div>
      )}
    </div>
  );
};

export const Captions: React.FC = () => {
  const frame = useCurrentFrame();
  return (
    <>
      {CAPTIONS.filter((c) => frame >= c.from - 2 && frame <= c.to + 1).map((c) => (
        <CaptionView key={c.from} caption={c} frame={frame} />
      ))}
    </>
  );
};
