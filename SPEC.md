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

### Layout Constants

- Expanded layout is configured by `PanelLayout`.
- Widget sizes are fixed, not inferred from flexible SwiftUI content:
  - `NowPlayingWidget`: 300×110
  - `ClockWidget`: 120 pt wide
  - divider: 1×70
  - visible edge padding: 20 pt from the shaped side wall and bottom edge
  - raw SwiftUI horizontal padding: `panelTopEarInset + panelTopRadius + visible padding`
  - compact width: `min(max(notchWidth + compactNotchSidePadding * 2, 340), 440)`, with `compactNotchSidePadding = 105`
  - compact horizontal padding: `min(max(height + 18, 50), 60)`
  - widget spacing: 20
- Current expanded width formula:
  - `padding * 2 + sum(widget widths) + spacing * (widget count - 1)`
- Future widgets should add their fixed width to `PanelLayout.expandedWidgetWidths` so the panel grows automatically.

### ClockWidget
- Shows current time in `HH:mm` format, plus day number, short month, and weekday
- Date is the primary top block: large bold day number with month and weekday
- Month and weekday use the user's current system locale.
- Time is secondary below the date, smaller, gray, and monospaced
- Shows compact weather under the time when local weather is available: SF Symbol, temperature, and locality/condition
- Weather uses `WeatherService`, Open-Meteo, and one-shot Core Location. There is no fallback location; if macOS does not provide a coordinate or the request fails, the weather row is hidden.
- Date uses a compact two-column layout so Russian weekday names fit within the fixed widget width
- Updates every second via shared timer

### NowPlayingWidget
- Shows artwork (110×110, rounded), title, artist, progress bar, playback controls, shuffle, and repeat controls
- Supports Spotify and Apple Music via AppleScript
- Shuffle and repeat state are polled with now-playing metadata.
- Shuffle button toggles shuffle for Spotify and Music.
- Repeat button cycles Music through `off → all → one → off`; Spotify toggles repeat as `off/all`.
- Falls back to CalendarWidget when no music is playing
- Click on artwork opens the player app
- Title truncates with `…` if too long
- Progress bar updates every second via local tick timer (no extra AppleScript calls)
- Expanded artwork participates in the hero artwork transition from compact mode.

---

## Planned Widgets

### WeatherWidget

**Status:** Folded into `ClockWidget` for the current compact right-side layout.

**Goal:** Show current temperature and weather condition.

**Data source:** [Open-Meteo](https://open-meteo.com/) — free, no API key required.
- Endpoint: `https://api.open-meteo.com/v1/forecast?latitude=LAT&longitude=LON&current=temperature_2m,weather_code&temperature_unit=celsius`
- Location: obtained via `CLLocationManager` request-location calls, without continuous tracking
- Locality: resolved via `MKReverseGeocodingRequest` and shown when available
- Fallback: none. If location permission, location lookup, geocoding, or weather loading fails, hide the weather row instead of showing default-city weather.

**Update interval:** Every 30 minutes.

**Display:**
```
[SF Symbol icon]  +18°
                  Locality
```
- Temperature: 11pt semibold monospaced, white 48% opacity
- Locality/condition: 10pt medium, white 48% opacity
- Icon: SF Symbol mapped from WMO weather code (see mapping table below)
- No label header

**WMO → SF Symbol mapping (key codes):**
| WMO | Condition | SF Symbol |
|-----|-----------|-----------|
| 0 | Clear sky | `sun.max.fill` |
| 1–3 | Partly cloudy | `cloud.sun.fill` |
| 45–48 | Fog | `cloud.fog.fill` |
| 51–67 | Rain/drizzle | `cloud.rain.fill` |
| 71–77 | Snow | `cloud.snow.fill` |
| 80–82 | Rain showers | `cloud.heavyrain.fill` |
| 95–99 | Thunderstorm | `cloud.bolt.rain.fill` |

**Service:** `WeatherService: ObservableObject`
- Polls Open-Meteo via `URLSession.shared.dataTask`
- Parses JSON with `JSONDecoder`
- Stores `temperature: Double`, `weatherCode: Int`, and optional `locationTitle`
- Clears weather state when Core Location cannot provide a usable coordinate

---

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

## Layout Plan (after new widgets)

```
[NowPlayingWidget] | Divider | [WeatherWidget] | [MoonWidget] | [PomodoroWidget] | [ClockWidget]
```

Panel width may need to increase to accommodate all widgets.
Each widget separated by `Divider` at 70pt height.
