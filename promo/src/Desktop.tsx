import React from "react";
import { Apple, ControlCenter, Search, Wifi } from "./Icons";
import { FONT, MENU_BAR_H, NOTCH_W, SCREEN_H, SCREEN_W } from "./theme";

export const Wallpaper: React.FC = () => (
  <div
    style={{
      position: "absolute",
      inset: 0,
      background: `
        radial-gradient(ellipse 60% 50% at 22% 78%, rgba(255,56,60,0.38), rgba(255,56,60,0) 70%),
        radial-gradient(ellipse 55% 45% at 82% 70%, rgba(94,92,230,0.42), rgba(94,92,230,0) 70%),
        radial-gradient(ellipse 70% 40% at 50% 8%, rgba(255,140,90,0.18), rgba(255,140,90,0) 70%),
        linear-gradient(180deg, #120d18 0%, #0b0a12 60%, #07070b 100%)`,
    }}
  />
);

const MenuItem: React.FC<{ children: React.ReactNode; bold?: boolean }> = ({ children, bold }) => (
  <span style={{ fontWeight: bold ? 700 : 500 }}>{children}</span>
);

export const MenuBar: React.FC = () => (
  <div
    style={{
      position: "absolute",
      left: 0,
      top: 0,
      width: SCREEN_W,
      height: MENU_BAR_H,
      background: "rgba(20,14,24,0.35)",
      backdropFilter: "blur(20px)",
      color: "rgba(255,255,255,0.92)",
      fontFamily: FONT,
      fontSize: 13.5,
      display: "flex",
      alignItems: "center",
      padding: "0 18px",
      boxSizing: "border-box",
    }}
  >
    <div style={{ display: "flex", alignItems: "center", gap: 22 }}>
      <Apple size={15} color="white" />
      <MenuItem bold>Finder</MenuItem>
      <MenuItem>File</MenuItem>
      <MenuItem>Edit</MenuItem>
      <MenuItem>View</MenuItem>
      <MenuItem>Go</MenuItem>
      <MenuItem>Window</MenuItem>
      <MenuItem>Help</MenuItem>
    </div>
    <div style={{ flex: 1 }} />
    <div style={{ display: "flex", alignItems: "center", gap: 18 }}>
      <BangBarStatusIcon />
      <Wifi size={16} color="white" />
      <Search size={15} color="white" />
      <ControlCenter size={16} color="white" />
      <MenuItem>Thu Oct 8  9:41</MenuItem>
    </div>
  </div>
);

const BangBarStatusIcon: React.FC = () => (
  <div style={{ width: 20, height: 14, borderRadius: 3.5, border: "1.6px solid white", position: "relative", boxSizing: "border-box" }}>
    <div style={{ position: "absolute", left: 3, right: 3, top: -1.6, height: 5, borderRadius: "0 0 3px 3px", background: "white" }} />
  </div>
);

export const Notch: React.FC = () => (
  <svg
    width={NOTCH_W + 16}
    height={MENU_BAR_H}
    style={{ position: "absolute", left: SCREEN_W / 2 - NOTCH_W / 2 - 8, top: 0 }}
  >
    <path
      d={`M0 0 Q8 0 8 8 L8 ${MENU_BAR_H - 10} Q8 ${MENU_BAR_H} 18 ${MENU_BAR_H} L${NOTCH_W - 2} ${MENU_BAR_H} Q${NOTCH_W + 8} ${MENU_BAR_H} ${NOTCH_W + 8} ${MENU_BAR_H - 10} L${NOTCH_W + 8} 8 Q${NOTCH_W + 8} 0 ${NOTCH_W + 16} 0 Z`}
      fill="#000"
    />
    <circle cx={(NOTCH_W + 16) / 2 + 22} cy={MENU_BAR_H / 2} r={3.2} fill="#0d0f1a" />
    <circle cx={(NOTCH_W + 16) / 2 + 22} cy={MENU_BAR_H / 2} r={1.4} fill="#1d2440" />
  </svg>
);

export const ScreenFrame: React.FC<{ children: React.ReactNode }> = ({ children }) => (
  <div style={{ position: "absolute", left: 0, top: 0, width: SCREEN_W, height: SCREEN_H, overflow: "hidden" }}>
    {children}
  </div>
);
