# BangBar — Feature Spec

## Current Widgets

### ClockWidget
- Shows current time in `HH:mm` format
- Font: 32pt thin monospaced
- Updates every second via shared timer

### NowPlayingWidget
- Shows artwork (110×110, rounded), title, artist, progress bar, playback controls
- Supports Spotify and Apple Music via AppleScript
- Falls back to CalendarWidget when no music is playing
- Click on artwork opens the player app
- Title truncates with `…` if too long
- Progress bar updates every second via local tick timer (no extra AppleScript calls)

---

## Planned Widgets

### WeatherWidget

**Goal:** Show current temperature and weather condition.

**Data source:** [Open-Meteo](https://open-meteo.com/) — free, no API key required.
- Endpoint: `https://api.open-meteo.com/v1/forecast?latitude=LAT&longitude=LON&current=temperature_2m,weathercode`
- Location: obtained once via `CLLocationManager` (one-shot, no continuous tracking)
- Fallback: if location denied, use hardcoded default coords (configurable in code)

**Update interval:** Every 30 minutes.

**Display:**
```
[SF Symbol icon]  +18°
                  Partly cloudy
```
- Temperature: 20pt semibold, white
- Condition: 12pt, white 50% opacity
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
- Stores `temperature: Double`, `weatherCode: Int`

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
