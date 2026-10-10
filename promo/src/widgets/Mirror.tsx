import React from "react";
import { useCurrentFrame } from "remotion";
import { Video } from "../Icons";
import { T } from "../script";
import { springTrack, track } from "../theme";

// A stylised stand-in for the camera feed: soft room light and a head-and-shoulders silhouette.
const CameraFeed: React.FC<{ frame: number }> = ({ frame }) => {
  const sway = Math.sin(frame * 0.05) * 2;
  return (
    <div style={{ position: "absolute", inset: 0, background: "linear-gradient(160deg, #3a3f55 0%, #20232f 55%, #15161d 100%)" }}>
      <div style={{ position: "absolute", left: -20, top: -10, width: 80, height: 80, borderRadius: "50%", background: "radial-gradient(circle, rgba(255,214,150,0.55), rgba(255,214,150,0))" }} />
      <div
        style={{
          position: "absolute",
          left: 47 - 21 + sway,
          top: 22,
          width: 42,
          height: 50,
          borderRadius: "50% 50% 46% 46%",
          background: "radial-gradient(circle at 40% 35%, #e9b896, #b77b5c 70%, #8a5843)",
        }}
      />
      <div style={{ position: "absolute", left: 47 - 25 + sway, top: 14, width: 50, height: 26, borderRadius: "50% 50% 30% 30%", background: "#2a1d18" }} />
      <div
        style={{
          position: "absolute",
          left: 47 - 46 + sway * 0.6,
          top: 70,
          width: 92,
          height: 60,
          borderRadius: "46px 46px 0 0",
          background: "linear-gradient(180deg, #5b6b8c, #3c4763)",
        }}
      />
    </div>
  );
};

export const MirrorWidget: React.FC = () => {
  const frame = useCurrentFrame();
  const running = springTrack(frame, [
    [0, 0],
    [T.mirrorClick + 2, 1],
    [T.hide, 0],
  ]);
  const press = frame >= T.mirrorClick && frame < T.mirrorClick + 4 ? 0.9 : 1;
  const flash = track(frame, [
    [T.shutter + 1, 0],
    [T.shutter + 2, 1],
    [T.shutter + 12, 0],
  ]);
  const shutterPress = frame >= T.shutter && frame < T.shutter + 4 ? 0.82 : 1;

  return (
    <div style={{ width: 94, height: 110, display: "flex", alignItems: "center", justifyContent: "center", position: "relative" }}>
      <div
        style={{
          position: "absolute",
          width: 94,
          height: 94,
          borderRadius: 16,
          overflow: "hidden",
          opacity: running,
          transform: `scale(${0.6 + 0.4 * running})`,
          border: "1px solid rgba(255,255,255,0.22)",
          boxShadow: "0 0 10px rgba(255,255,255,0.10)",
        }}
      >
        <CameraFeed frame={frame} />
        <div style={{ position: "absolute", inset: 0, background: "white", opacity: flash }} />
        <div
          style={{
            position: "absolute",
            left: "50%",
            bottom: 7,
            width: 20,
            height: 20,
            marginLeft: -10,
            borderRadius: "50%",
            border: "2px solid rgba(255,255,255,0.9)",
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
            transform: `scale(${shutterPress})`,
          }}
        >
          <div style={{ width: 13, height: 13, borderRadius: "50%", background: "white" }} />
        </div>
        <div
          style={{
            position: "absolute",
            right: 6,
            top: 6,
            width: 19,
            height: 19,
            borderRadius: "50%",
            background: "rgba(0,0,0,0.55)",
            border: "1px solid rgba(255,255,255,0.16)",
            color: "white",
            fontSize: 9,
            fontWeight: 700,
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
          }}
        >
          ✕
        </div>
      </div>
      <div
        style={{
          width: 52,
          height: 52,
          borderRadius: "50%",
          background: "linear-gradient(180deg, rgba(255,255,255,0.18), rgba(255,255,255,0.045))",
          border: "1px solid rgba(255,255,255,0.16)",
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
          color: "rgba(255,255,255,0.85)",
          opacity: 1 - running,
          transform: `scale(${press * (1 - 0.3 * running)})`,
        }}
      >
        <Video size={22} />
      </div>
    </div>
  );
};
