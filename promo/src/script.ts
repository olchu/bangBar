import { FPS } from "./theme";

const s = (seconds: number) => Math.round(seconds * FPS);

// Every beat of the video, in frames. Scenes read from here so the edit can be re-timed in one place.
export const T = {
  openHover: s(3.0),
  collapseToCompact: s(5.8),
  expandFromCompact: s(7.9),
  nextTrackClick: s(9.6),
  clockFocus: s(11.2),
  minuteTick: s(12.6),
  clipboardSwipe: s(14.6),
  clipboardOpen: s(15.0),
  clipboardScroll: s(16.2),
  clipboardCopy: s(17.9),
  clipboardClose: s(19.8),
  pageSwipe: s(20.6),
  pageTwo: s(21.0),
  habitClick: s(23.2),
  pageBack: s(26.0),
  mirrorClick: s(27.0),
  shutter: s(29.2),
  hide: s(31.0),
  endCard: s(34.8),
};

export const PAGE1_W = 766;
export const PAGE2_W = 803;
export const HIDDEN_W = 240;
