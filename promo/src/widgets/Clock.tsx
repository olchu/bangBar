import React from "react";
import { useCurrentFrame } from "remotion";
import { T } from "../script";
import { ACCENT, FONT, ROUNDED, track } from "../theme";

const EVENT_TINT = "#FF9F0A";

export const ClockWidget: React.FC = () => {
  const frame = useCurrentFrame();
  const ticked = frame >= T.minuteTick;
  const tickPop = track(frame, [
    [T.minuteTick, 1.12],
    [T.minuteTick + 10, 1],
  ]);
  const highlight = track(frame, [
    [T.clockFocus + 6, 0],
    [T.clockFocus + 16, 1],
    [T.clipboardSwipe - 6, 1],
    [T.clipboardSwipe + 4, 0],
  ]);
  const colonOpacity = 0.42;

  return (
    <div style={{ width: 194, height: 110, fontFamily: FONT, display: "flex", flexDirection: "column", gap: 6 }}>
      <div style={{ height: 43, display: "flex", alignItems: "baseline", gap: 8 }}>
        <div
          style={{
            fontFamily: ROUNDED,
            fontSize: 34,
            fontWeight: 700,
            color: "rgba(255,255,255,0.94)",
            fontVariantNumeric: "tabular-nums",
            display: "flex",
            alignItems: "baseline",
            gap: 2,
            paddingRight: 4,
            lineHeight: 1.15,
          }}
        >
          <span>09</span>
          <span style={{ color: `rgba(255,255,255,${colonOpacity})`, transform: "translateY(-1px)" }}>:</span>
          <span style={{ display: "inline-block", transform: `scale(${tickPop})`, transformOrigin: "50% 80%" }}>
            {ticked ? "42" : "41"}
          </span>
        </div>
        <div style={{ fontFamily: ROUNDED, display: "flex", alignItems: "baseline", gap: 4 }}>
          <span style={{ fontSize: 11, fontWeight: 600, color: "rgba(255,255,255,0.48)" }}>THU</span>
          <span style={{ fontSize: 14, fontWeight: 700, color: ACCENT }}>8</span>
          <span style={{ fontSize: 11, fontWeight: 600, color: "rgba(255,255,255,0.48)" }}>OCT</span>
        </div>
      </div>

      <div style={{ display: "flex", flexDirection: "column", gap: 4, position: "relative" }}>
        <div
          style={{
            position: "absolute",
            inset: "-5px -8px -4px -8px",
            borderRadius: 10,
            background: `rgba(255,159,10,${0.12 * highlight})`,
            boxShadow: `0 0 0 1px rgba(255,159,10,${0.35 * highlight})`,
          }}
        />
        <EventRow time="10:00" title="Design review" status={ticked ? "in 18 min · Zoom" : "in 19 min · Zoom"} />
        <EventRow time="11:30" title="1:1 with Alex" status="in 1 h 48 min" compact />
      </div>
    </div>
  );
};

const EventRow: React.FC<{ time: string; title: string; status: string; compact?: boolean }> = ({
  time,
  title,
  status,
  compact,
}) => (
  <div style={{ position: "relative", paddingLeft: 8, display: "flex", flexDirection: "column", gap: compact ? 2 : 3 }}>
    <div
      style={{
        position: "absolute",
        left: 0,
        top: 1,
        bottom: 1,
        width: 2.5,
        borderRadius: 2,
        background: EVENT_TINT,
        opacity: compact ? 0.75 : 1,
      }}
    />
    <div style={{ display: "flex", alignItems: "baseline", gap: 5, opacity: compact ? 0.5 : 1 }}>
      <span style={{ fontFamily: ROUNDED, fontSize: compact ? 10 : 11, fontWeight: 700, color: EVENT_TINT }}>{time}</span>
      <span style={{ fontSize: compact ? 10 : 11, fontWeight: 600, color: EVENT_TINT, whiteSpace: "nowrap" }}>{title}</span>
    </div>
    <span style={{ fontSize: compact ? 8 : 9, fontWeight: 500, color: `rgba(255,255,255,${compact ? 0.28 : 0.42})` }}>
      {status}
    </span>
  </div>
);
