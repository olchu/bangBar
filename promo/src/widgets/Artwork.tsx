import React from "react";

export const TRACKS = [
  { title: "Midnight Drive", artist: "Neon Coast", duration: 214, start: 71 },
  { title: "Glass Garden", artist: "Mira Vale", duration: 187, start: 0 },
];

const Synthwave: React.FC = () => (
  <div style={{ position: "absolute", inset: 0, background: "linear-gradient(180deg, #1b0b3a 0%, #4a1460 45%, #d9385e 75%, #ff9a5a 100%)" }}>
    <div
      style={{
        position: "absolute",
        left: "22%",
        top: "26%",
        width: "56%",
        height: "56%",
        borderRadius: "50%",
        background: "linear-gradient(180deg, #ffd46b 0%, #ff6a5b 60%, #e83a7c 100%)",
        boxShadow: "0 0 40px rgba(255,120,90,0.6)",
        WebkitMaskImage:
          "repeating-linear-gradient(180deg, #000 0px, #000 7%, transparent 7%, transparent 9%)",
      }}
    />
    <div
      style={{
        position: "absolute",
        left: 0,
        right: 0,
        bottom: 0,
        height: "30%",
        background:
          "linear-gradient(180deg, rgba(20,6,40,0.9), #0d0420), repeating-linear-gradient(90deg, rgba(255,80,160,0.5) 0 1px, transparent 1px 12%)",
        backgroundBlendMode: "screen",
      }}
    />
  </div>
);

const Garden: React.FC = () => (
  <div style={{ position: "absolute", inset: 0, background: "radial-gradient(circle at 30% 25%, #9ff3e0 0%, #2bb3a3 30%, #0c4e66 65%, #071a2e 100%)" }}>
    <div style={{ position: "absolute", left: "48%", top: "40%", width: "44%", height: "44%", borderRadius: "50%", background: "radial-gradient(circle at 35% 35%, #fff6d8, #f6b8ff 55%, rgba(120,80,255,0))", opacity: 0.85 }} />
    <div style={{ position: "absolute", left: "10%", top: "58%", width: "30%", height: "30%", borderRadius: "50%", border: "2px solid rgba(255,255,255,0.55)" }} />
  </div>
);

export const Artwork: React.FC<{ index: number; radius: number }> = ({ index, radius }) => (
  <div style={{ position: "absolute", inset: 0, borderRadius: radius, overflow: "hidden" }}>
    {index === 0 ? <Synthwave /> : <Garden />}
  </div>
);
