import React from "react";
import { useCurrentFrame } from "remotion";
import { Backward, Forward, Pause, Repeat, Shuffle } from "../Icons";
import { T } from "../script";
import { ACCENT, FONT, FPS, MONO, fade } from "../theme";
import { TRACKS } from "./Artwork";

export const currentTrackIndex = (frame: number) => (frame >= T.nextTrackClick + 3 ? 1 : 0);

const formatTime = (seconds: number) => {
  const s = Math.floor(seconds);
  return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, "0")}`;
};

export const trackPosition = (frame: number) => {
  const index = currentTrackIndex(frame);
  const startFrame = index === 0 ? 0 : T.nextTrackClick + 3;
  return TRACKS[index].start + (frame - startFrame) / FPS;
};

export const NowPlayingWidget: React.FC = () => {
  const frame = useCurrentFrame();
  const index = currentTrackIndex(frame);
  const track = TRACKS[index];
  const position = trackPosition(frame);
  const textIn = index === 1 ? fade(frame, T.nextTrackClick + 3, Infinity, 7) : 1;
  const forwardPress = frame >= T.nextTrackClick && frame < T.nextTrackClick + 5 ? 0.8 : 1;

  return (
    <div style={{ width: 300, height: 110, display: "flex", gap: 12, fontFamily: FONT }}>
      <div style={{ width: 110, height: 110, flexShrink: 0 }} />
      <div style={{ flex: 1, paddingTop: 14, display: "flex", flexDirection: "column" }}>
        <div style={{ opacity: textIn, transform: `translateY(${(1 - textIn) * 4}px)` }}>
          <div style={{ fontSize: 15, fontWeight: 600, color: "white", whiteSpace: "nowrap" }}>{track.title}</div>
          <div style={{ fontSize: 12, color: "rgba(255,255,255,0.5)", marginTop: 3 }}>{track.artist}</div>
        </div>
        <div style={{ flex: 1 }} />
        <div style={{ height: 3, borderRadius: 2, background: "rgba(255,255,255,0.15)", position: "relative" }}>
          <div
            style={{
              position: "absolute",
              left: 0,
              top: 0,
              bottom: 0,
              width: `${Math.min(position / track.duration, 1) * 100}%`,
              borderRadius: 2,
              background: ACCENT,
            }}
          />
        </div>
        <div
          style={{
            display: "flex",
            justifyContent: "space-between",
            fontFamily: MONO,
            fontSize: 10,
            color: "rgba(255,255,255,0.4)",
            marginTop: 3,
            marginBottom: 6,
          }}
        >
          <span>{formatTime(position)}</span>
          <span>{formatTime(track.duration)}</span>
        </div>
        <div style={{ display: "flex", alignItems: "center", gap: 20, color: "white", height: 18 }}>
          <Backward size={15} />
          <Pause size={18} />
          <Forward size={15} style={{ transform: `scale(${forwardPress})` }} />
          <Shuffle size={15} color="rgba(255,255,255,0.35)" />
          <Repeat size={15} color="rgba(255,255,255,0.35)" />
        </div>
      </div>
    </div>
  );
};

export const PlayingIndicator: React.FC<{ frame: number }> = ({ frame }) => (
  <div style={{ display: "flex", alignItems: "center", gap: 2.5, height: 14 }}>
    {[0, 1, 2, 3].map((i) => {
      const h = 4 + 9 * (0.5 + 0.5 * Math.sin(frame * 0.33 + i * 1.7) * Math.cos(frame * 0.11 + i));
      return <div key={i} style={{ width: 2.5, height: h, borderRadius: 2, background: ACCENT, opacity: 0.85 }} />;
    })}
  </div>
);
