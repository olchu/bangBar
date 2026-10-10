import React from "react";
import { Img, staticFile, useCurrentFrame } from "remotion";
import { Battery, Checklist, Checkmark, Drive, Flame, Network, Pause, Reset } from "../Icons";
import { T } from "../script";
import { ACCENT, FONT, FPS, MONO, ROUNDED, springTrack } from "../theme";

const TICKS = 60;

export const PomodoroWidget: React.FC = () => {
  const frame = useCurrentFrame();
  const remaining = 25 * 60 - 47 - Math.floor(frame / FPS);
  const progress = 1 - remaining / (25 * 60);
  const time = `${Math.floor(remaining / 60)}:${String(remaining % 60).padStart(2, "0")}`;

  return (
    <div style={{ width: 110, height: 110, position: "relative", fontFamily: ROUNDED }}>
      {Array.from({ length: TICKS }, (_, i) => {
        const active = i / TICKS < progress;
        const angle = (i / TICKS) * 360;
        return (
          <div
            key={i}
            style={{
              position: "absolute",
              left: 54,
              top: 55 - 51,
              width: 2,
              height: active ? 7 : 5,
              borderRadius: 1,
              background: ACCENT,
              opacity: active ? 1 : 0.18,
              transformOrigin: "1px 51px",
              transform: `rotate(${angle}deg)`,
            }}
          />
        );
      })}
      <div style={{ position: "absolute", inset: 0, display: "flex", flexDirection: "column", alignItems: "center", justifyContent: "center", gap: 3 }}>
        <div style={{ display: "flex", alignItems: "center", gap: 4, color: ACCENT, fontSize: 9, fontWeight: 600 }}>
          <div style={{ width: 5, height: 5, borderRadius: "50%", background: ACCENT }} />
          FOCUS
        </div>
        <div style={{ fontSize: 26, fontWeight: 700, color: "rgba(255,255,255,0.94)", fontVariantNumeric: "tabular-nums", lineHeight: 1 }}>
          {time}
        </div>
        <div
          style={{
            fontSize: 9,
            fontWeight: 500,
            color: "rgba(255,255,255,0.5)",
            padding: "1px 7px",
            borderRadius: 10,
            border: "1px solid rgba(255,255,255,0.2)",
            marginTop: 2,
          }}
        >
          2 / 4
        </div>
      </div>
      <div style={{ position: "absolute", left: -8, bottom: 6, color: "rgba(255,255,255,0.45)" }}>
        <Reset size={13} />
      </div>
      <div style={{ position: "absolute", right: -8, bottom: 6, color: "rgba(255,255,255,0.45)" }}>
        <Pause size={13} />
      </div>
    </div>
  );
};

const HABITS = [
  { name: "Morning run", history: [1, 1, 0, 1, 1, 1], done: true, streak: 3 },
  { name: "Read 20 pages", history: [1, 1, 1, 1, 1, 1], done: false, streak: 6 },
  { name: "No sugar", history: [0, 1, 1, 0, 1, 1], done: true, streak: 2 },
  { name: "Meditate", history: [1, 0, 0, 1, 0, 1], done: false, streak: 1 },
];

export const HabitsWidget: React.FC = () => {
  const frame = useCurrentFrame();
  const clicked = springTrack(frame, [
    [0, 0],
    [T.habitClick + 2, 1],
  ], { damping: 12, stiffness: 180 });
  const doneCount = HABITS.filter((h) => h.done).length + (clicked > 0.5 ? 1 : 0);

  return (
    <div style={{ width: 220, height: 110, fontFamily: FONT, display: "flex", flexDirection: "column", gap: 6 }}>
      <div style={{ height: 16, display: "flex", alignItems: "center", gap: 6 }}>
        <Checklist size={12} color={ACCENT} />
        <span style={{ fontFamily: ROUNDED, fontSize: 11, fontWeight: 700, color: "rgba(255,255,255,0.85)" }}>
          {doneCount}/{HABITS.length}
        </span>
        <div style={{ flex: 1, display: "flex", gap: 3 }}>
          {HABITS.map((_, i) => (
            <div key={i} style={{ flex: 1, height: 4, borderRadius: 2, background: i < doneCount ? ACCENT : "rgba(255,255,255,0.14)" }} />
          ))}
        </div>
      </div>
      {HABITS.map((habit, i) => {
        const isTarget = i === 1;
        const done = habit.done || (isTarget && clicked > 0.5);
        const fill = isTarget ? clicked : habit.done ? 1 : 0;
        return (
          <div
            key={habit.name}
            style={{
              height: 19,
              display: "flex",
              alignItems: "center",
              gap: 7,
              padding: "0 4px",
              borderRadius: 6,
              background: isTarget && frame > T.habitClick - 12 && frame < T.pageBack ? "rgba(255,255,255,0.06)" : "transparent",
            }}
          >
            <div
              style={{
                width: 13,
                height: 13,
                borderRadius: "50%",
                border: `1.5px solid ${ACCENT}`,
                background: `rgba(255,56,60,${fill})`,
                display: "flex",
                alignItems: "center",
                justifyContent: "center",
                transform: isTarget ? `scale(${1 + 0.25 * Math.sin(Math.PI * Math.min(clicked, 1))})` : undefined,
              }}
            >
              {fill > 0.3 && <Checkmark size={9} color="black" style={{ opacity: fill }} />}
            </div>
            <span
              style={{
                flex: 1,
                fontSize: 11,
                fontWeight: 600,
                color: done ? "rgba(255,255,255,0.45)" : "rgba(255,255,255,0.92)",
                whiteSpace: "nowrap",
              }}
            >
              {habit.name}
            </span>
            <div style={{ display: "flex", gap: 2 }}>
              {[...habit.history, done ? 1 : 0].map((d, day) => (
                <div
                  key={day}
                  style={{
                    width: 6,
                    height: 6,
                    borderRadius: 1.5,
                    background: d ? ACCENT : "rgba(255,255,255,0.14)",
                    boxShadow: day === 6 && !d ? `inset 0 0 0 1px ${ACCENT}` : undefined,
                  }}
                />
              ))}
            </div>
            <div style={{ width: 22, display: "flex", alignItems: "center", gap: 1, justifyContent: "flex-end" }}>
              <Flame size={9} color={done ? ACCENT : "rgba(255,255,255,0.35)"} filled={done} />
              <span style={{ fontFamily: ROUNDED, fontSize: 9, fontWeight: 700, color: done ? ACCENT : "rgba(255,255,255,0.35)" }}>
                {isTarget && done ? habit.streak + 1 : habit.streak}
              </span>
            </div>
          </div>
        );
      })}
    </div>
  );
};

const Sparkline: React.FC<{ seed: number; frame: number }> = ({ seed, frame }) => {
  const points = Array.from({ length: 24 }, (_, i) => {
    const t = (i + frame / 6) * 0.55 + seed;
    const v = 0.5 + 0.28 * Math.sin(t) + 0.15 * Math.sin(t * 2.3 + seed);
    return [i * (60 / 23), 20 - v * 18] as const;
  });
  const d = points.map(([x, y], i) => `${i ? "L" : "M"}${x.toFixed(1)},${y.toFixed(1)}`).join(" ");
  return (
    <svg width={60} height={20} style={{ display: "block" }}>
      <path d={`${d} L60,20 L0,20 Z`} fill="rgba(255,56,60,0.18)" />
      <path d={d} fill="none" stroke={ACCENT} strokeWidth={1.4} />
    </svg>
  );
};

export const SystemWidget: React.FC = () => {
  const frame = useCurrentFrame();
  const cpu = Math.round(18 + 9 * Math.sin(frame * 0.09) + 4 * Math.sin(frame * 0.31));
  const pulse = 0.5 + 0.5 * Math.sin(frame * 0.2);

  const card = (title: string, value: string, seed: number) => (
    <div style={{ flex: 1, display: "flex", flexDirection: "column", gap: 3 }}>
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "baseline" }}>
        <span style={{ fontFamily: MONO, fontSize: 10, fontWeight: 500, color: "rgba(255,255,255,0.5)" }}>{title}</span>
        <span style={{ fontFamily: MONO, fontSize: 11, fontWeight: 600, color: "rgba(255,255,255,0.9)" }}>{value}</span>
      </div>
      <Sparkline seed={seed} frame={frame} />
    </div>
  );

  return (
    <div style={{ width: 160, height: 110, fontFamily: FONT, display: "flex", flexDirection: "column", gap: 6 }}>
      <div style={{ height: 18, display: "flex", alignItems: "center", gap: 6 }}>
        <Battery size={14} color={ACCENT} />
        <span style={{ fontFamily: MONO, fontSize: 11, fontWeight: 600, color: "rgba(255,255,255,0.72)" }}>84%</span>
        <div style={{ flex: 1 }} />
        <div style={{ width: 14, height: 14, position: "relative", display: "flex", alignItems: "center", justifyContent: "center" }}>
          <div style={{ position: "absolute", width: 6 + 7 * pulse, height: 6 + 7 * pulse, borderRadius: "50%", background: ACCENT, opacity: 0.25 * (1 - pulse) }} />
          <div style={{ width: 6, height: 6, borderRadius: "50%", background: ACCENT }} />
        </div>
        <span style={{ fontFamily: MONO, fontSize: 11, fontWeight: 600, color: ACCENT }}>OK</span>
      </div>
      <div style={{ height: 57, display: "flex", alignItems: "center", gap: 7 }}>
        {card("CPU", `${cpu}%`, 0)}
        <div style={{ width: 1, height: 38, background: "rgba(255,255,255,0.14)" }} />
        {card("RAM", "11.2G", 2.4)}
      </div>
      <div style={{ height: 17, display: "flex", alignItems: "center", gap: 5, color: "rgba(255,255,255,0.72)" }}>
        <Drive size={12} color={ACCENT} />
        <span style={{ fontFamily: MONO, fontSize: 9, fontWeight: 500 }}>312 GB</span>
        <div style={{ flex: 1 }} />
        <Network size={10} color={ACCENT} />
        <span style={{ fontFamily: MONO, fontSize: 8, fontWeight: 500 }}>192.168.1.24</span>
      </div>
    </div>
  );
};

export const MoonWidget: React.FC = () => {
  const label = (top: string, bottom: string, align: "left" | "right") => (
    <div style={{ textAlign: align, lineHeight: 1.15 }}>
      <div style={{ fontFamily: ROUNDED, fontSize: 12, fontWeight: 700, color: "rgba(255,255,255,0.9)" }}>{top}</div>
      <div style={{ fontFamily: ROUNDED, fontSize: 8, fontWeight: 600, color: "rgba(255,255,255,0.42)", letterSpacing: 0.4 }}>{bottom}</div>
    </div>
  );
  return (
    <div style={{ width: 110, height: 110, position: "relative" }}>
      <div style={{ position: "absolute", left: 25, top: 25, width: 60, height: 60, borderRadius: "50%", overflow: "hidden" }}>
        <Img src={staticFile("moon.png")} style={{ width: "100%", height: "100%", objectFit: "cover" }} />
        <div
          style={{
            position: "absolute",
            inset: 0,
            borderRadius: "50%",
            background: "radial-gradient(circle at 72% 50%, rgba(0,0,0,0.94) 52%, rgba(0,0,0,0) 60%)",
          }}
        />
      </div>
      <div style={{ position: "absolute", left: 0, top: 0 }}>{label("8%", "ILLUM.", "left")}</div>
      <div style={{ position: "absolute", right: 0, top: 0 }}>{label("Waning", "PHASE", "right")}</div>
      <div style={{ position: "absolute", left: 0, bottom: 0 }}>{label("Oct 10", "NEW", "left")}</div>
      <div style={{ position: "absolute", right: 0, bottom: 0 }}>{label("Oct 26", "FULL", "right")}</div>
    </div>
  );
};
