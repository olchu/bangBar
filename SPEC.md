# BangBar — Feature Spec

## Panel Behavior

BangBar is a top-pinned notch panel with three visible modes:

- Hidden: the panel is ordered out, unless music is playing.
- Compact: shown at menu-bar/notch height while music is playing.
- Expanded: full widget panel opened by hover.

The panel background is pure sRGB black (`0,0,0`) inside the clipped notch shape. The `NSPanel` itself remains transparent so the clipped shape does not render as a rectangle.

### Hidden → Expanded

- Triggered by hovering the stable notch trigger zone.
- Panel appears pinned to the top edge.
- Expanded panel width is calculated from `PanelLayout`: horizontal padding, fixed widget widths, divider width, and spacing.
- Expanded panel width must not be maintained as a separate hardcoded window width.
- The panel must not visually detach from the top edge during frame animation.
- Expanded content fades in after the frame animation begins.

### Hidden → Compact

- If music starts while the panel is hidden, the compact panel appears instead of staying fully hidden.
- Initial frame is `concealedCompactFrame`, centered behind the notch with menu-bar height.
- It expands to `compactFrame` by width while staying pinned to the top.
- Artwork and the playing indicator are hidden until the compact frame has enough space.
- Artwork and indicator reveal after a short delay; current delay is ~60 ms.
- Compact artwork reveals with scale/opacity only for first appearance from hidden/music-start.

### Compact → Expanded

- Triggered by hovering the compact panel, its visible frame plus a 10 px perimeter activation buffer, or the stable notch trigger zone.
- The transition animates from the current compact frame to the expanded frame.
- A short grace period prevents immediate re-closing while the mouse is on the boundary.
- Compact hover hit testing must not depend only on the clipped shape, because artwork and indicator can be visually inside areas that shape hit testing treats as edge cases.

### Expanded → Compact

- If music is playing and the mouse leaves the expanded panel, the panel collapses to compact instead of hiding.
- The collapse uses the current expanded frame as the animation start.
- The top edge stays pinned during the whole animation.
- Compact artwork must be restored without the initial music-start reveal animation.

### Compact → Hidden

- When music stops, compact mode hides by reversing the compact appearance:
  - artwork and indicator collapse/disappear first;
  - then the panel width shrinks toward `concealedCompactFrame`;
  - the window is ordered out only after it reaches the concealed width.
- The window position must not jump down or right during this hide animation.

### Hover Stability

- Closing logic uses a small buffer around the panel and trigger zone to avoid boundary flicker.
- `HoverHostingView` forwards `mouseEntered` and `mouseMoved` from inside the panel to the same hover handler used by global tracking. This keeps hover behavior stable over interactive SwiftUI content such as album artwork.
- `syncCompactVisibility` must not repeatedly call `enterCompactMode()` while the panel is already compact; now-playing updates happen frequently and should not restart compact animations.

## Now Playing Transitions

### Hero Artwork

Album artwork should read visually as one continuous element between compact and expanded modes.

- During `compact → expanded`, a temporary `ArtworkHeroView` is drawn above the normal widgets.
- Compact artwork and expanded artwork are hidden as needed while the hero layer is active.
- Hero progress is driven by the AppKit frame animation, not by an independent SwiftUI timer.
- The hero interpolates:
  - position;
  - size;
  - corner radius.
- At the end of `compact → expanded`, expanded artwork becomes visible underneath the hero before the hero layer is removed. This overlap prevents a one-frame blink.
- At `expanded → compact`, the hero animation runs in reverse (`1 → 0`) and compact artwork is restored without the initial reveal scale animation.
- Any delayed hero cleanup work must be cancelled when a new transition starts.

### Compact Now Playing

- Compact mode shows album artwork on the left and a subtle animated playing indicator on the right.
- The indicator uses thin low-opacity vertical bars so it does not distract from the menu bar.
- Compact content uses `PanelLayout.compactHorizontalPadding(for:)` so artwork and the indicator sit clear of the rounded side corners while remaining visible at menu-bar height.
- Artwork size is smaller than the bar height and clipped with a small rounded rectangle.
- Clicking artwork opens the active player.
- Compact mode remains available only while music is playing.

## Current Widgets

### Component Structure

- `PanelContentView` is the thin composition root for the visible panel:
  - owns shared runtime state used by the panel surface (`MirrorCameraService`, `CalendarEventService`, current time timer);
  - chooses compact vs expanded content;
  - wires panel-level animation, clipping, opacity, and hover-driven lifecycle hooks.
- Panel constants and observable panel animation state live in `PanelLayout.swift`.
- Widget implementations are split by responsibility:
  - `NowPlayingWidgets.swift`: expanded now-playing widget, compact now-playing widget, artwork placeholder, artwork hero transition, and playing indicator;
  - `ClockWidget.swift`: clock header, calendar event rendering, empty calendar state, and looping no-plans MP4 view;
  - `MirrorWidget.swift`: mirror button, camera preview SwiftUI wrapper, and AppKit preview container;
  - `NotchPanelShape.swift`: custom panel clipping shape.
- Legacy/standalone widgets live outside `PanelContentView`:
  - `CalendarWidget.swift`;
  - `SystemWidget.swift`.
- New widget UI should be added as a separate file instead of growing `PanelContentView.swift`.

### Layout Constants

- Expanded layout is configured by `PanelLayout`.
- Widget sizes are fixed, not inferred from flexible SwiftUI content:
  - `NowPlayingWidget`: 300×110
  - `ClockWidget`: 190×110
  - `MirrorWidget`: 94×94
  - divider: 1×70
  - visible edge padding: 20 pt from the shaped side wall and bottom edge
  - raw SwiftUI horizontal padding: `panelTopEarInset + panelTopRadius + visible padding`
  - compact width: `min(max(notchWidth + compactNotchSidePadding * 2, 320), 360)`, with `compactNotchSidePadding = 100`
  - compact horizontal padding: `min(max(height + 18, 50), 50)`
  - widget spacing: 20
- Current expanded width formula:
  - `padding * 2 + sum(widget widths) + spacing * (widget count - 1)`
- Future widgets should add their fixed width to `PanelLayout.expandedWidgetWidths` so the panel grows automatically.

### ClockWidget

- Combines the clock and calendar-event surface in one 190×110 widget.
- Header shows current time in `HH:mm` format:
  - hours and minutes are large, bold, rounded, and monospaced;
  - the colon is dimmer than the digits.
- Date appears on the same row as the time, aligned to the right side of the clock widget:
  - format is `EEE d MMM`, e.g. `TUE 19 MAY`;
  - weekday and month are small and dim;
  - day number is slightly larger, bolder, and brighter;
  - month and weekday use the user's current system locale.
- The widget updates every second via the shared timer.
- Calendar event data refreshes at most once per minute while authorized.

### Calendar Events In ClockWidget

- Calendar events are provided by `CalendarEventService` using EventKit.
- The app requires calendar permission and uses `NSCalendarsFullAccessUsageDescription`.
- The app entitlement includes `com.apple.security.personal-information.calendars`.
- Passive startup checks the current calendar authorization status but does not request access automatically.
- Clicking the calendar area is the user action that:
  - requests full calendar access when status is not determined;
  - opens macOS Calendar privacy settings when access is denied or restricted.
- Calendar access states:
  - `unknown`: show access prompt text;
  - `requesting`: show access prompt text while request is in flight;
  - `authorized`: show events or empty state;
  - `denied`: show settings prompt;
  - `failed`: show failure prompt and log the failure.
- The service fetches up to two upcoming events for today:
  - all-day events are ignored;
  - events that already ended are ignored;
  - events are sorted by start date;
  - title whitespace is trimmed;
  - each event carries its calendar color.
- Event rendering:
  - the first event is the primary row;
  - the second event, when present, is rendered as a compact secondary row;
  - each event has its own vertical left marker in that event's calendar color;
  - the event start time and title use the event calendar color;
  - the end time is not shown;
  - no timeline/progress line is shown;
  - calendar icons are not shown, to preserve title space;
  - each event shows relative status below the title: `starts in N min` or `ends in N min`.
- Empty authorized state:
  - shown when calendar access is authorized and there are no more non-all-day events today;
  - displays a left-aligned looping `man.mp4` illustration at 55×55;
  - text block to the right is centered in the remaining space;
  - text is `No plans` and `walking free`;
  - MP4 playback uses `AVQueuePlayer` + `AVPlayerLooper`, muted, with no controls;
  - playback uses a video-only composition and trims the final frame to reduce visible loop hesitation.

### NowPlayingWidget

- Always shows the player widget in expanded mode; it does not fall back to a calendar widget when no player is open.
- Shows artwork (110×110, rounded), title, artist, progress bar, playback controls, shuffle, and repeat controls.
- When no player is open:
  - title is `No player open`;
  - subtitle is `Ready when music starts`;
  - artwork area shows the placeholder artwork instead of stale artwork;
  - controls are disabled/dimmed.
- Supports Spotify and Apple Music via AppleScript.
- Shuffle and repeat state are polled with now-playing metadata.
- Shuffle button toggles shuffle for Spotify and Music.
- Repeat button cycles Music through `off → all → one → off`; Spotify toggles repeat as `off/all`.
- Click on artwork opens the player app.
- Title truncates with `…` if too long.
- Progress bar updates every second via local tick timer (no extra AppleScript calls).
- Expanded artwork participates in the hero artwork transition from compact mode.
- When the active player closes or no track can be read, `NowPlayingService` clears the entire `NowPlayingInfo`, including artwork, so stale artwork is not displayed.

### MirrorWidget

- Mirror widget is shown on the right side of the expanded panel.
- Default state is a circular video button.
- Clicking starts the camera preview when permission is available.
- Running state shows a mirrored camera preview clipped to a rounded rectangle.
- The mirror stops when compact mode is entered, when the expanded panel disappears, or when explicitly toggled off.

---

## Planned Widgets

### Near-Term Plan

1. Add `PomodoroWidget` as the next widget.
2. Add settings entry buttons that open a settings panel.
3. Keep new implementation split into separate component/service files instead of growing `PanelContentView.swift`.

### MoonWidget

**Goal:** Show current moon phase and days until next full moon.

**Data source:** Calculated locally — no network required.
- Use standard astronomical formula (synodic period = 29.53059 days)
- Reference new moon: Jan 6, 2000 18:14 UTC (known epoch)

**Display:**
```
🌕  Full moon
    in 3 days
```
or if today is full moon:
```
🌕  Full moon
    today
```
- Phase icon: Unicode moon emoji or SF Symbol (`moon.full`, `moon.circle`, etc.)
- Phase name: current phase name
- Days to next full moon shown when > 0

**Phases (8):** New → Waxing Crescent → First Quarter → Waxing Gibbous → Full → Waning Gibbous → Last Quarter → Waning Crescent

**No service needed** — pure computed properties on a struct `MoonPhase`.

---

### PomodoroWidget

**Priority:** Next planned widget.

**Goal:** Pomodoro timer — 25 min work / 5 min break cycles.

**Display:**
```
[play/pause]  25:00
              Work
```
- Timer: 24pt thin monospaced, white
- Label: "Work" or "Break", 11pt, white 50% opacity
- Single play/pause button (SF Symbol `play.fill` / `pause.fill`)
- On work session end: brief visual flash + auto-start break
- On break end: auto-start next work session

**State machine:**
```
idle → work(running) → work(paused) → break(running) → break(paused) → work...
```

**Durations:**
- Work: 25 min
- Break: 5 min
- Long break after 4 pomodoros: 15 min

**Service:** `PomodoroService: ObservableObject`
- Uses `Timer` on `.main` run loop
- Persists completed pomodoro count in `UserDefaults`
- Does NOT send notifications (requires entitlement) — panel visual feedback only

---

## Planned Settings Panel

**Goal:** Provide buttons that open a dedicated settings panel from the main UI.

- Add compact, low-noise settings buttons where they are discoverable but do not compete with primary widget content.
- Clicking a settings button opens the app settings panel/window.
- Settings panel should be implemented separately from `PanelContentView`.
- Initial settings surface should be enough to configure planned widgets and panel behavior without editing code.
- Candidate settings:
  - enable/disable optional widgets;
  - Pomodoro work/break/long-break durations;
  - calendar visibility/options;
  - now-playing player preferences if needed.

---

## Layout Plan (after new widgets)

```
[NowPlayingWidget] | Divider | [ClockWidget] | Divider | [MoonWidget] | [PomodoroWidget] | Divider | [MirrorWidget]
```

Panel width may need to increase to accommodate all widgets.
Each widget separated by `Divider` at 70pt height.
