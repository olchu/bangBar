import React from "react";
import { useCurrentFrame } from "remotion";
import { ClipboardIcon, Gear, Trash } from "./Icons";
import { HIDDEN_W, PAGE1_W, PAGE2_W, T } from "./script";
import {
  ACCENT,
  MENU_BAR_H,
  MONO,
  NOTCH_W,
  PANEL,
  PANEL_COMPACT_W,
  PANEL_EXPANDED_H,
  SCREEN_W,
  fade,
  springTrack,
  track,
} from "./theme";
import { Artwork } from "./widgets/Artwork";
import { ClipboardFilters, ClipboardSurface } from "./widgets/Clipboard";
import { ClockWidget } from "./widgets/Clock";
import { MirrorWidget } from "./widgets/Mirror";
import { NowPlayingWidget, PlayingIndicator } from "./widgets/NowPlaying";
import { HabitsWidget, MoonWidget, PomodoroWidget, SystemWidget } from "./widgets/PageTwo";

// Port of NotchPanelShape.swift.
export const notchPath = (w: number, h: number) => {
  const top = Math.min(PANEL.topRadius, Math.min(w, h) / 2);
  const bottom = Math.min(PANEL.bottomRadius, Math.min(w, h) / 2);
  const ear = Math.min(PANEL.earInset, w / 4);
  const minX = ear;
  const maxX = w - ear;
  return [
    `M ${minX} 0`,
    `Q ${minX + top} 0 ${minX + top} ${top}`,
    `L ${minX + top} ${h - bottom}`,
    `Q ${minX + top} ${h} ${minX + top + bottom} ${h}`,
    `L ${maxX - top - bottom} ${h}`,
    `Q ${maxX - top} ${h} ${maxX - top} ${h - bottom}`,
    `L ${maxX - top} ${top}`,
    `Q ${maxX - top} 0 ${maxX} 0`,
    "Z",
  ].join(" ");
};

const panelConfig = { damping: 19, stiffness: 150, mass: 0.85 };

export const panelGeometry = (frame: number) => {
  const w = springTrack(
    frame,
    [
      [0, HIDDEN_W],
      [T.openHover, PAGE1_W],
      [T.collapseToCompact, PANEL_COMPACT_W],
      [T.expandFromCompact, PAGE1_W],
      [T.pageTwo, PAGE2_W],
      [T.pageBack, PAGE1_W],
      [T.hide, PANEL_COMPACT_W],
      [T.hide + 9, HIDDEN_W],
    ],
    panelConfig,
  );
  const h = springTrack(
    frame,
    [
      [0, MENU_BAR_H],
      [T.openHover, PANEL_EXPANDED_H],
      [T.collapseToCompact, MENU_BAR_H],
      [T.expandFromCompact, PANEL_EXPANDED_H],
      [T.hide, MENU_BAR_H],
    ],
    panelConfig,
  );
  const visible = Math.min(fade(frame, T.openHover, Infinity, 3), 1 - fade(frame, T.hide + 16, Infinity, 6));
  const expansion = Math.max(0, Math.min(1, (h - MENU_BAR_H) / (PANEL_EXPANDED_H - MENU_BAR_H)));
  return { w, h, visible, expansion };
};

const Divider: React.FC = () => <div style={{ width: 1, height: 60, background: "rgba(255,255,255,0.2)", flexShrink: 0 }} />;

const Row: React.FC<{ children: React.ReactNode }> = ({ children }) => (
  <div style={{ display: "flex", alignItems: "center", gap: PANEL.spacing, height: PANEL.contentHeight }}>{children}</div>
);

const lerp = (a: number, b: number, t: number) => a + (b - a) * t;

export const Panel: React.FC = () => {
  const frame = useCurrentFrame();
  const { w, h, visible, expansion } = panelGeometry(frame);
  const content = track(expansion, [
    [0.55, 0],
    [1, 1],
  ]);
  const compactContent = track(expansion, [
    [0, 1],
    [0.3, 0],
  ]);
  const compactReveal = fade(frame, T.collapseToCompact + 8, T.hide + 6, 6);

  const page = springTrack(frame, [
    [0, 0],
    [T.pageTwo, 1],
    [T.pageBack, 0],
  ], panelConfig);
  const clipboard = springTrack(frame, [
    [0, 0],
    [T.clipboardOpen, 1],
    [T.clipboardClose, 0],
  ], panelConfig);

  const inner = PANEL.horizontalPadding;
  const page1Left = w / 2 - PAGE1_W / 2 + inner - page * PAGE1_W;
  const page2Left = w / 2 - PAGE2_W / 2 + inner + (1 - page) * PAGE2_W;
  const page1Top = PANEL.topSafeInset - clipboard * 70;
  const clipboardTop = PANEL.topSafeInset + (1 - clipboard) * 70;

  const compactArt = { x: PANEL.earInset + PANEL.topRadius + 10, y: (MENU_BAR_H - 24) / 2, size: 24, radius: 6 };
  const art = {
    x: lerp(compactArt.x, page1Left, expansion),
    y: lerp(compactArt.y, page1Top, expansion),
    size: lerp(compactArt.size, 110, expansion),
    radius: lerp(compactArt.radius, 12, expansion),
  };
  const artOpacity = expansion > 0.05 ? 1 - clipboard : compactReveal;
  const nextTrack = fade(frame, T.nextTrackClick + 3, Infinity, 8);
  const trackBounce = track(frame, [
    [T.nextTrackClick + 2, 0.93],
    [T.nextTrackClick + 14, 1],
  ]);

  const leftZone = Math.max((w - NOTCH_W) / 2 - 8, 20);

  return (
    <div
      style={{
        position: "absolute",
        left: SCREEN_W / 2 - w / 2,
        top: 0,
        width: w,
        height: h,
        opacity: visible,
        clipPath: `path('${notchPath(w, h)}')`,
        background: "#000",
      }}
    >
      <div style={{ position: "absolute", left: 0, right: 0, top: 0, height: PANEL.topSafeInset, opacity: content }}>
        <div
          style={{
            position: "absolute",
            right: w - leftZone,
            top: 13,
            display: "flex",
            alignItems: "center",
            gap: 9,
            color: clipboard > 0.5 ? ACCENT : "rgba(255,255,255,0.55)",
          }}
        >
          <div style={{ opacity: clipboard, display: "flex", alignItems: "center", gap: 9 }}>
            <ClipboardFilters />
            <div style={{ width: 1, height: 12, background: "rgba(255,255,255,0.2)" }} />
          </div>
          <ClipboardIcon size={15} />
        </div>
        <div style={{ position: "absolute", right: 52, top: 13, display: "flex", alignItems: "center", gap: 10 }}>
          <div
            style={{
              opacity: clipboard,
              display: "flex",
              alignItems: "center",
              gap: 4,
              color: ACCENT,
              fontFamily: MONO,
              fontSize: 10,
              fontWeight: 600,
            }}
          >
            <Trash size={11} color={ACCENT} />
            Clear
          </div>
          <Gear size={15} color="rgba(255,255,255,0.55)" />
        </div>
      </div>

      <div style={{ position: "absolute", left: page1Left, top: page1Top, opacity: content * (1 - clipboard) }}>
        <Row>
          <NowPlayingWidget />
          <Divider />
          <ClockWidget />
          <Divider />
          <MirrorWidget />
        </Row>
      </div>

      <div style={{ position: "absolute", left: page2Left, top: PANEL.topSafeInset, opacity: content * page }}>
        <Row>
          <PomodoroWidget />
          <Divider />
          <HabitsWidget />
          <Divider />
          <SystemWidget />
          <Divider />
          <MoonWidget />
        </Row>
      </div>

      <div style={{ position: "absolute", left: w / 2 - PAGE1_W / 2 + inner, top: clipboardTop, opacity: content * clipboard }}>
        <ClipboardSurface width={PAGE1_W - inner * 2} />
      </div>

      <div
        style={{
          position: "absolute",
          left: art.x,
          top: art.y,
          width: art.size,
          height: art.size,
          opacity: artOpacity,
          transform: `scale(${trackBounce})`,
        }}
      >
        <Artwork index={0} radius={art.radius} />
        <div style={{ position: "absolute", inset: 0, opacity: nextTrack }}>
          <Artwork index={1} radius={art.radius} />
        </div>
      </div>

      <div
        style={{
          position: "absolute",
          right: PANEL.earInset + PANEL.topRadius + 12,
          top: (MENU_BAR_H - 14) / 2,
          opacity: compactContent * compactReveal,
        }}
      >
        <PlayingIndicator frame={frame} />
      </div>
    </div>
  );
};
