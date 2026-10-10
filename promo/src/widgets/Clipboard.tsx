import React from "react";
import { useCurrentFrame } from "remotion";
import { Checkmark, Pin } from "../Icons";
import { T } from "../script";
import { ACCENT, FONT, MONO, PIN, ROUNDED, springTrack, track } from "../theme";

type Card =
  | { kind: "text"; text: string; meta: string; mono?: boolean; pinned?: boolean }
  | { kind: "image"; gradient: string; meta: string }
  | { kind: "group"; name: string; count: number };

const CARDS: Card[] = [
  { kind: "text", text: "git commit -m \"ship notch panel\"", meta: "Terminal · now", mono: true, pinned: true },
  { kind: "image", gradient: "linear-gradient(135deg, #ff9a8b 0%, #ff6a88 45%, #6a5cff 100%)", meta: "PNG · 2 min" },
  { kind: "text", text: "https://developer.apple.com/design/human-interface-guidelines", meta: "Safari · 4 min" },
  { kind: "group", name: "Moodboard", count: 6 },
  { kind: "text", text: "Meet at 7, the place on Rue Oberkampf 🍷", meta: "Messages · 12 min" },
  { kind: "image", gradient: "linear-gradient(160deg, #0f2027 0%, #2c5364 60%, #6dd5ed 100%)", meta: "Screenshot · 20 min" },
  { kind: "text", text: "func animateFrame(to target: NSRect)", meta: "Xcode · 31 min", mono: true },
];

const CARD_W = 118;
const CARD_H = 100;
const GAP = 10;
const COPY_INDEX = 4;

const CardView: React.FC<{ card: Card; copied: number; pressed: boolean }> = ({ card, copied, pressed }) => (
  <div
    style={{
      width: CARD_W,
      height: CARD_H,
      flexShrink: 0,
      borderRadius: 12,
      background: "rgba(255,255,255,0.07)",
      border: `1px solid rgba(255,255,255,${0.1 + 0.5 * copied})`,
      position: "relative",
      overflow: "hidden",
      transform: `scale(${pressed ? 0.94 : 1})`,
      fontFamily: FONT,
    }}
  >
    {card.kind === "text" && (
      <div style={{ padding: "9px 10px", display: "flex", flexDirection: "column", height: "100%", boxSizing: "border-box" }}>
        <div
          style={{
            fontFamily: card.mono ? MONO : FONT,
            fontSize: card.mono ? 10 : 11,
            lineHeight: 1.35,
            color: "rgba(255,255,255,0.88)",
            overflow: "hidden",
            flex: 1,
            wordBreak: "break-word",
          }}
        >
          {card.text}
        </div>
        <div style={{ fontSize: 8.5, color: "rgba(255,255,255,0.38)", fontWeight: 500 }}>{card.meta}</div>
      </div>
    )}
    {card.kind === "image" && (
      <>
        <div style={{ position: "absolute", inset: 5, bottom: 22, borderRadius: 8, background: card.gradient }} />
        <div style={{ position: "absolute", left: 10, bottom: 7, fontSize: 8.5, color: "rgba(255,255,255,0.38)", fontWeight: 500 }}>
          {card.meta}
        </div>
      </>
    )}
    {card.kind === "group" && (
      <>
        {[2, 1, 0].map((i) => (
          <div
            key={i}
            style={{
              position: "absolute",
              left: 22 + i * 6,
              top: 12 - i * 3,
              width: 62,
              height: 48,
              borderRadius: 7,
              border: "1.5px solid rgba(0,0,0,0.6)",
              background: ["#ffb86b", "#ff6a88", "#7b6cff"][i],
              transform: `rotate(${(i - 1) * 7}deg)`,
            }}
          />
        ))}
        <div style={{ position: "absolute", left: 10, bottom: 8, right: 10, display: "flex", justifyContent: "space-between", alignItems: "baseline" }}>
          <span style={{ fontSize: 10, fontWeight: 600, color: "rgba(255,255,255,0.88)" }}>{card.name}</span>
          <span style={{ fontFamily: ROUNDED, fontSize: 9, fontWeight: 700, color: ACCENT }}>{card.count}</span>
        </div>
      </>
    )}
    {card.kind === "text" && card.pinned && (
      <div style={{ position: "absolute", right: 7, top: 7, color: PIN }}>
        <Pin size={11} />
      </div>
    )}
    <div
      style={{
        position: "absolute",
        inset: 0,
        background: `rgba(0,0,0,${0.62 * copied})`,
        display: "flex",
        flexDirection: "column",
        alignItems: "center",
        justifyContent: "center",
        gap: 4,
        opacity: copied,
      }}
    >
      <div style={{ width: 26, height: 26, borderRadius: "50%", background: ACCENT, display: "flex", alignItems: "center", justifyContent: "center", transform: `scale(${0.6 + 0.4 * copied})` }}>
        <Checkmark size={15} color="white" />
      </div>
      <span style={{ fontSize: 10, fontWeight: 700, color: "white" }}>Copied</span>
    </div>
  </div>
);

export const CLIPBOARD_SCROLL = 2 * (CARD_W + GAP);
export const COPY_CARD_CENTER_X = COPY_INDEX * (CARD_W + GAP) + CARD_W / 2 - CLIPBOARD_SCROLL;
export const CARDS_TOP = 4;
export const CARD_HEIGHT = CARD_H;

export const ClipboardSurface: React.FC<{ width: number }> = ({ width }) => {
  const frame = useCurrentFrame();
  const scroll = track(frame, [
    [T.clipboardScroll, 0],
    [T.clipboardScroll + 24, CLIPBOARD_SCROLL],
  ]);
  const copied = springTrack(frame, [
    [0, 0],
    [T.clipboardCopy + 3, 1],
    [T.clipboardCopy + 40, 0],
  ]);
  const pressed = frame >= T.clipboardCopy && frame < T.clipboardCopy + 4;

  return (
    <div style={{ width, height: 110, overflow: "hidden", position: "relative" }}>
      <div style={{ display: "flex", gap: GAP, paddingTop: CARDS_TOP, transform: `translateX(${-scroll}px)` }}>
        {CARDS.map((card, i) => (
          <CardView key={i} card={card} copied={i === COPY_INDEX ? copied : 0} pressed={i === COPY_INDEX && pressed} />
        ))}
      </div>
      <div style={{ position: "absolute", right: 0, top: 0, bottom: 0, width: 30, background: "linear-gradient(90deg, rgba(0,0,0,0), #000)" }} />
    </div>
  );
};

export const ClipboardFilters: React.FC = () => (
  <div style={{ display: "flex", gap: 2, fontFamily: MONO, fontSize: 10, fontWeight: 600 }}>
    {["All", "Text", "Images"].map((label, i) => (
      <div
        key={label}
        style={{
          padding: "3px 8px",
          borderRadius: 6,
          background: i === 0 ? "rgba(255,56,60,0.18)" : "transparent",
          color: i === 0 ? ACCENT : "rgba(255,255,255,0.5)",
        }}
      >
        {label}
      </div>
    ))}
  </div>
);
