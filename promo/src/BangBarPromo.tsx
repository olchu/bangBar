import React from "react";
import { AbsoluteFill, Audio, Img, getStaticFiles, spring, staticFile, useCurrentFrame } from "remotion";
import { Captions } from "./Captions";
import { Cursor } from "./Cursor";
import { MenuBar, Notch, ScreenFrame, Wallpaper } from "./Desktop";
import { Panel } from "./Panel";
import { T } from "./script";
import { ACCENT, DURATION, FONT, FPS, SCREEN_W, WIDTH, ease, track } from "./theme";

const FontFaces: React.FC = () => (
  <style>{`
    @font-face { font-family: 'SF Pro'; src: url(${staticFile("fonts/SFNS.ttf")}); font-weight: 100 900; }
    @font-face { font-family: 'SF Rounded'; src: url(${staticFile("fonts/SFNSRounded.ttf")}); font-weight: 100 900; }
    @font-face { font-family: 'SF Mono'; src: url(${staticFile("fonts/SFNSMono.ttf")}); font-weight: 100 900; }
  `}</style>
);

const Camera: React.FC<{ children: React.ReactNode }> = ({ children }) => {
  const frame = useCurrentFrame();
  const zoom = track(
    frame,
    [
      [0, 1.27],
      [80, 1.74],
      [T.clipboardOpen, 1.74],
      [T.clipboardOpen + 30, 1.8],
      [T.pageTwo, 1.8],
      [T.pageTwo + 30, 1.7],
      [T.mirrorClick, 1.7],
      [T.mirrorClick + 40, 1.82],
      [T.hide, 1.82],
      [T.endCard, 1.6],
      [T.endCard + 50, 1.3],
    ],
    ease,
  );
  return (
    <div
      style={{
        position: "absolute",
        left: WIDTH / 2 - (SCREEN_W / 2) * zoom,
        top: 0,
        transform: `scale(${zoom})`,
        transformOrigin: "0 0",
      }}
    >
      {children}
    </div>
  );
};

const EndCard: React.FC = () => {
  const frame = useCurrentFrame();
  const local = frame - T.endCard;
  if (local < 0) return null;
  const dim = track(local, [
    [0, 0],
    [20, 1],
  ]);
  const icon = spring({ frame: local - 8, fps: FPS, config: { damping: 13, stiffness: 120 } });
  const title = spring({ frame: local - 16, fps: FPS, config: { damping: 18, stiffness: 140 } });
  const tagline = spring({ frame: local - 24, fps: FPS, config: { damping: 18, stiffness: 140 } });
  const glow = 0.6 + 0.4 * Math.sin(local * 0.12);

  return (
    <AbsoluteFill style={{ alignItems: "center", justifyContent: "center", fontFamily: FONT }}>
      <AbsoluteFill style={{ background: "radial-gradient(ellipse at 50% 45%, rgba(18,10,14,0.88), rgba(4,4,6,0.98))", opacity: dim }} />
      <div
        style={{
          position: "absolute",
          width: 520,
          height: 520,
          top: 160,
          borderRadius: "50%",
          background: `radial-gradient(circle, rgba(255,56,60,${0.28 * glow * icon}), rgba(255,56,60,0) 65%)`,
        }}
      />
      <div style={{ display: "flex", flexDirection: "column", alignItems: "center", gap: 18, marginTop: -40 }}>
        <Img
          src={staticFile("appicon.png")}
          style={{
            width: 220,
            height: 220,
            opacity: icon,
            transform: `scale(${0.6 + 0.4 * icon}) translateY(${(1 - icon) * 40}px)`,
            filter: "drop-shadow(0 20px 50px rgba(0,0,0,0.6))",
          }}
        />
        <div
          style={{
            fontSize: 120,
            fontWeight: 800,
            letterSpacing: -4,
            color: "white",
            opacity: title,
            transform: `translateY(${(1 - title) * 30}px)`,
          }}
        >
          Bang<span style={{ color: ACCENT }}>Bar</span>
        </div>
        <div
          style={{
            fontSize: 42,
            fontWeight: 500,
            letterSpacing: -0.6,
            color: "rgba(255,255,255,0.62)",
            opacity: tagline,
            transform: `translateY(${(1 - tagline) * 20}px)`,
          }}
        >
          Your notch, finally useful.
        </div>
      </div>
    </AbsoluteFill>
  );
};

const hasMusic = () => getStaticFiles().some((f) => f.name === "music.mp3");

export const BangBarPromo: React.FC = () => {
  const frame = useCurrentFrame();
  const fadeOut = track(frame, [
    [DURATION - 12, 0],
    [DURATION, 1],
  ]);

  return (
    <AbsoluteFill style={{ background: "#000" }}>
      <FontFaces />
      <Camera>
        <ScreenFrame>
          <Wallpaper />
          <MenuBar />
          <Notch />
          <Panel />
          <Cursor />
        </ScreenFrame>
      </Camera>
      <AbsoluteFill
        style={{ background: "radial-gradient(ellipse 80% 70% at 50% 35%, rgba(0,0,0,0) 55%, rgba(0,0,0,0.55) 100%)" }}
      />
      <Captions />
      <EndCard />
      <AbsoluteFill style={{ background: "#000", opacity: fadeOut }} />
      {hasMusic() && (
        <Audio
          src={staticFile("music.mp3")}
          volume={(f) => track(f, [[0, 0], [10, 1], [DURATION - 30, 1], [DURATION, 0]])}
        />
      )}
    </AbsoluteFill>
  );
};
