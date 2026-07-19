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
  - `ClipboardHistoryView.swift`: clipboard history surface, item cards, image-group cards, and group detail view;
  - `CompactClipboardGroupWidget.swift`: compact image-collection status shown while a group is active;
  - `PanelTopBar.swift`: panel navigation, clipboard filters and image-group collection controls;
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
  - `MoonWidget`: 110×110, with an 87.3×87.3 moon image
  - `PomodoroWidget` (displayed as **Focus Timer**): 110×110
  - `CountdownWidget`: 150×110
  - `MirrorWidget`: 94×94
  - divider: 1×60
  - visible edge padding: 20 pt from the shaped side wall and bottom edge
  - raw SwiftUI horizontal padding: `panelTopEarInset + panelTopRadius + visible padding`
  - compact width: `min(max(notchWidth + compactNotchSidePadding * 2, 320), 360)`, with `compactNotchSidePadding = 100`
  - compact horizontal padding: `min(max(height + 18, 50), 50)`
  - widget spacing: 20
- Current expanded width formula:
  - `padding * 2 + sum(widget widths) + spacing * (widget count - 1)`
- Future widgets should add their fixed width to `PanelLayout.expandedWidgetWidths` so the panel grows automatically.

### Clipboard History — Implemented

**Status:** ✅ Implemented, including separate `All`, `Text`, and `Images` views and image grouping.

- Clipboard history is a panel-level surface, not an item in the reorderable widget row.
- The clipboard button in `PanelTopBar` switches the expanded panel between widgets and history.
- History has `All`, `Text`, and `Images` filters. Image groups appear in `All` and `Images`, but not in `Text`.
- The top bar retains the Settings button and, while history is open, also provides Clear History and image-group collection controls.
- Text and image cards are shown in a horizontally scrolling row. Clicking a card writes it back to the system pasteboard; hover and context-menu actions allow individual deletion.
- Image-group cards show a stacked preview and item count, open into a group detail view, and support copy, rename, and delete actions.
- Copying a group writes its persisted image file URLs as separate pasteboard items so Finder and destination editors receive a real multi-file paste.

**Capture and persistence:**

- `ClipboardHistoryService` polls `NSPasteboard.general` every 0.6 seconds and captures non-empty text, PNG/TIFF images, and image file URLs.
- Image file URLs are read and normalized to PNG before storage. Re-copying a stored single image writes the image back to the pasteboard; copying a group uses file URLs.
- Content is fingerprinted with SHA-256. An identical text or image payload is deduplicated and moved to the newest position instead of retaining duplicate history entries.
- History is stored under Application Support in `BangBar/ClipboardHistory/`:
  - `index.json` stores item metadata and text payloads;
  - `groups.json` stores image-group metadata;
  - `Images/` stores normalized PNG payloads.
- The legacy `clipboard-history.json` format is migrated on load.
- History is limited to 200 items and 20 MB per item. A user-selectable total storage limit of 50, 100, 250, or 500 MB defaults to 100 MB; oldest entries and their image files are removed when a limit is exceeded.
- Current storage usage is published for Settings. Clear History removes unpinned items, image files, and groups while preserving pinned cards.

**Temporary clipboard protection:**

- Optional transient-change filtering waits 0.5–2.0 seconds before accepting a changed pasteboard, defaulting to 1 second. If the pasteboard returns to the previous stable content during that window, the temporary value is not saved.
- An optional recorded transcription shortcut suppresses capture while the shortcut is held and for a configurable 0.5–3.0 second grace period after release, defaulting to 1.5 seconds.
- Shortcut recording supports normal modifier/key combinations and a standalone `fn` key. `Esc` clears the recorded shortcut.

**Image groups:**

- `New Image Group` starts a collection session and assigns subsequently captured images to that group; text remains outside the group.
- Collection stops manually or automatically after 2 minutes without a new image, 15 minutes total, or 30 collected images.
- While collection is active, clipboard content takes priority over Focus Timer and Now Playing in compact mode. The compact surface shows previews, group name, image count, and the remaining inactivity time.
- Expanding the panel during collection opens Clipboard History with the Images filter selected.
- An active collection keeps the panel available in compact mode even when music and Focus Timer are inactive. Compact width receives additional room for the collection status.

**Pinned cards — Implemented:**

- ✅ Text cards, image cards, and image-group cards can be pinned and unpinned from their context menu or card action.
- Pin actions use a warm orange `#FF9F0A` pin icon that complements the default red accent while remaining visually distinct.
- Pinned cards always appear before unpinned cards in the history row. Within each section, newest items remain first.
- Pin state is persisted with the card metadata and restored after relaunch.
- `Clear All` / Clear History removes only unpinned cards. Pinned cards and their persisted image files remain intact.
- A pinned card can still be removed explicitly with its individual Delete action; pinning protects it only from bulk clearing and automatic storage eviction.
- When a pinned card is copied again, it remains pinned and moves to the newest position within the pinned section.
- Filters continue to apply normally: pinned text appears in `All` and `Text`; pinned images and image groups appear in `All` and `Images`.

### ClockWidget

- Combines the clock and calendar-event surface in one 190×110 widget.
- Header shows current time in `HH:mm` format:
  - hours and minutes are large, bold, rounded, and monospaced;
  - the colon is dimmer than the digits.
- Date appears on the same row as the time, aligned to the right side of the clock widget:
  - format is `EEE d MMM`, e.g. `TUE 19 MAY`;
  - weekday and month are small and dim;
  - day number is slightly larger, bolder, and rendered in the user's accent color;
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
  - calendar filtering is controlled by `BangBarSettings.Key.selectedCalendarIds`;
  - an empty calendar filter setting means all calendars are shown;
  - an explicit empty selected calendar list means no calendar events are shown;
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
  - each event shows relative status below the title using compact duration text, e.g. `starts in 2h 30min`, `starts in 45min`, or `ends in 1h`.
- Empty authorized state:
  - shown when calendar access is authorized and there are no more non-all-day events today;
  - displays a left-aligned looping `man.mp4` illustration at 55×55;
  - text block to the right is centered in the remaining space;
  - text is `No plans` and `walking free`;
  - MP4 playback uses `AVQueuePlayer` + `AVPlayerLooper`, muted, with no controls;
  - playback uses a video-only composition and trims the final frame to reduce visible loop hesitation;
  - when "Tint walking figure" is enabled in settings, `.colorMultiply(accentColor)` is applied to the video view.

### NowPlayingWidget

- Always shows the player widget in expanded mode; it does not fall back to a calendar widget when no player is open.
- Shows artwork (110×110, rounded), title, artist, progress bar, playback controls, shuffle, and repeat controls.
- When no player is open:
  - title is `No player open`;
  - subtitle is `Ready when music starts`;
  - artwork area shows `ArtworkPlaceholder`: dark background, accent-colored music note with a soft radial glow;
  - controls are disabled/dimmed.
- Supports Spotify and Apple Music via AppleScript.
- Shuffle and repeat state are polled with now-playing metadata.
- Shuffle button toggles shuffle for Spotify and Music.
- Repeat button cycles Music through `off → all → one → off`; Spotify toggles repeat as `off/all`.
- Click on artwork opens the player app.
- For Apple Music, a favorited track shows a red top-right artwork corner with a white heart. For an unfavorited track, the corner appears on artwork hover and can be clicked to favorite the track.
- Spotify does not show the favorite corner because its AppleScript API does not expose library favorite state or mutation.
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

**Photo capture:**

- While the preview is running, a small circular shutter button sits at the bottom-center of the preview, alongside the existing stop button at the top-trailing corner. It is only visible in the `.running` state.
- Tapping the shutter captures a single still frame from the live `AVCaptureSession` through an `AVCapturePhotoOutput` (JPEG).
- The saved image is mirrored horizontally so it matches the on-screen preview (Photo Booth–style selfie). Preferred approach: set the photo connection's `isVideoMirrored = true` (with `automaticallyAdjustsVideoMirroring = false`); fall back to a manual horizontal flip of the captured `CGImage` if mirroring is unsupported.
- Photos are written to `~/Pictures/BangBar/` (folder created on first use) as `BangBar-yyyy-MM-dd-HHmmss.jpg`. No sandbox or extra entitlement is required (`ENABLE_APP_SANDBOX = NO`).
- Feedback: on success the widget plays a brief white flash and momentarily shows a checkmark; on failure the shutter shows a short red flash. The capture button is disabled while a capture is in flight.
- `MirrorCameraService` additions:
  - `AVCapturePhotoOutput` created and added to the session during configuration (reset together with the session).
  - `capturePhoto()` method, guarded to `.running`, that builds `AVCapturePhotoSettings` and triggers capture on the session queue.
  - An `AVCapturePhotoCaptureDelegate` that decodes, mirrors, and writes the file, then publishes results on the main queue.
  - `@Published` flags for UI feedback: `isCapturing`, `didCapturePhoto` (brief flash), `captureDidFail`, and `lastPhotoURL`.
- Out of scope for the first version (possible follow-ups): choosing the save folder in Settings, a "Reveal in Finder" action, capturing without the mirror flip, and countdown/burst modes.

**Development plan — Mirror photo capture:**

1. **Session output.** In `MirrorCameraService.configureSessionIfNeeded()`, create a `photoOutput` property and `session.addOutput(photoOutput)` when `canAddOutput` is true (inside the existing `beginConfiguration`/`commitConfiguration` block). Clear it in `resetSession()`.
2. **Mirroring.** After adding the output, configure its video connection: if `isVideoMirroringSupported`, set `automaticallyAdjustsVideoMirroring = false` and `isVideoMirrored = true` so captures match the preview.
3. **Capture API.** Add `capturePhoto()`: guard `state == .running` and not already capturing, set `isCapturing = true`, then on `sessionQueue` call `photoOutput.capturePhoto(with: AVCapturePhotoSettings, delegate:)`. Keep the delegate retained for the duration of the capture.
4. **Delegate + save.** Implement `photoOutput(_:didFinishProcessingPhoto:error:)`: on success take `fileDataRepresentation()`, ensure `~/Pictures/BangBar/` exists, write `BangBar-<timestamp>.jpg`; publish `lastPhotoURL`, pulse `didCapturePhoto`, clear `isCapturing`. On error set `captureDidFail` and clear `isCapturing`. (If step 2's mirroring is unsupported, flip the `CGImage` here before writing.)
5. **Shutter button.** In `MirrorWidget`, in the `.running` branch add a bottom-center shutter button (white ring, ~26pt) calling `service.capturePhoto()`, disabled while `service.isCapturing`.
6. **Feedback.** Overlay a white flash whose opacity animates off `didCapturePhoto`, plus a transient checkmark; drive a short red flash off `captureDidFail`.
7. **Verify.** Build, run, open the panel, start the mirror, capture, and confirm the flash feedback and a new file in `~/Pictures/BangBar/`. Confirm capture is ignored when the camera is off/denied.

---

## Planned Widgets

### Near-Term Plan

1. ✅ Focus Timer (`PomodoroWidget` internally) is implemented and wired into the expanded panel, compact mode, and Settings.
2. ✅ Settings entry points are implemented through the app menu and expanded-panel chrome button.
3. ✅ `MoonWidget` is implemented as a local, no-permission widget and wired into Settings and widget ordering.
4. ✅ `RemindersWidget` and `ReminderService` are implemented and wired into Settings and widget ordering.
5. ✅ Clipboard History is implemented as a panel-level surface with `All`, `Text`, and `Images` filters, persistent text/image items, and image-group collection and management.
6. ⬜ Implement Mirror photo capture according to the development plan above.
7. ⬜ Fix task hover tooltip positioning: when hovering a task/reminder row, the tooltip must appear near the hovered row inside or immediately adjacent to the panel/widget, not far away on the desktop. Audit coordinate-space conversion between SwiftUI/AppKit/window/screen coordinates and clamp the tooltip to the panel bounds when possible.
8. ⬜ Add `CountdownWidget` as a local, user-configured date countdown widget.
9. ⬜ Consider `NotionWidget` after the local widgets and interaction fixes.
10. ✅ Pinned Clipboard History cards stay first and survive Clear History.
11. ⬜ Build the Companion state engine and MVP with a temporary original placeholder; add the final character design later.
12. Keep new implementation split into separate component/service files instead of growing `PanelContentView.swift`.

### MoonWidget

**Goal:** Show current moon phase, illuminated percentage, and next full moon date.

**Data source:** Calculated locally — no network required.
- Compute approximate solar and lunar ecliptic longitudes from J2000.
- Current illumination uses lunar elongation: `(1 - cos(elongation)) / 2`.
- Next full moon date is found by sampling forward from the current date and refining the illumination peak.

**Display:**
```
100%                 21D
ILLUM.           TO FULL
       [MoonTexture]
PHASE              FULL
Last             Jun 30
```
- Moon image: `MoonTexture` asset clipped to a circle.
- No moon-cycle progress arc is drawn.
- Phase shadow: render a darkened full `MoonTexture` base, then render the bright texture above it through a calculated illumination mask. The mask area matches the calculated illumination percentage; everything outside it stays under shadow.
- Moon disk is slightly smaller than the original 90×90 design and vertically positioned to balance the text overlay.
- Shadow side uses a darker overlay than the default texture shadow.
- Top-left: rounded illuminated fraction, shown as a percent without a leading dot.
- Top-right: days until the next full moon, formatted as `XD`, labelled `TO FULL`.
- Bottom-left: `PHASE` label with the current phase short name below it, title-cased, white, medium weight.
- Bottom-right: `FULL` label with the next calculated full moon date below it, white, medium weight; date is never in the past.
- Accent-colored moon values use `BangBarSettings.Key.accentColorHex`; non-accent values remain white.

**Phases (8):** New → Waxing Crescent → First Quarter → Waxing Gibbous → Full → Waning Gibbous → Last Quarter → Waning Crescent

**No service needed** — pure computed properties on a struct `MoonPhase`.

**Settings:** Enabled/disabled via "Moon" toggle in Settings.

---

### Focus Timer (`PomodoroWidget`)

**Goal:** Focus timer with configurable work / break cycles (defaults: 25 min work / 5 min break).

**Naming:** The product-facing name is **Focus Timer**. Existing `Pomodoro…` Swift types and `UserDefaults` keys remain unchanged for source and saved-settings compatibility.

**Layout:** Square 110×110, implemented in `PomodoroWidget.swift` + `PomodoroService.swift`.

**Visual design:**
- Circular tick ring: 72 evenly-spaced dashes around the perimeter; elapsed ticks colored in accent color, remaining ticks at 18% opacity
- Center: colored dot + session label (9pt semibold rounded, uppercased); dot and label dim when paused
- Timer: 26pt bold rounded + `.monospacedDigit()`, white 94% opacity
- Cycle counter: `"N / rounds"` in a capsule outline (9pt, white 50%), where `rounds` is the configured focus sessions before a long break
- Bottom-left: `arrow.counterclockwise` reset button (13pt bold, white 45%)
- Bottom-right: `play.fill` / `pause.fill` button (13pt bold, white 45%)
- Tapping anywhere on the widget also toggles play/pause
- Accent color is shared with the rest of the panel via `@AppStorage`

**State machine:**
```
idle → work(running) → work(paused) → break(running) → break(paused) → work...
```

**Durations:** all configurable in Settings → Widgets → FOCUS TIMER (persisted in `UserDefaults`, read live by `PomodoroService`):
- Work / Focus: default 25 min (`pomodoroWorkMinutes`, range 5–90, step 5)
- Short break: default 5 min (`pomodoroShortBreakMinutes`, range 1–30, step 1)
- Long break: default 15 min (`pomodoroLongBreakMinutes`, range 5–45, step 5)
- Rounds before long break: default 4 (`pomodoroRounds`, range 2–8)

Changing a setting while the timer is idle updates the displayed time immediately (via `UserDefaults.didChangeNotification`); a running timer is left untouched until its next session.

**Cycle counter** shows which focus session is active in the current set of `rounds`:
- During work: `(completedPomodoros % rounds) + 1`
- During break: completed count in cycle (shows `rounds` after the last)

**Service:** `PomodoroService: ObservableObject`
- `@Published` properties: `sessionType`, `isRunning`, `secondsRemaining`, `completedPomodoros`, `didJustComplete`
- Uses `Timer` on `.main` run loop
- `completedPomodoros` persisted in `UserDefaults`
- `reset()` stops timer and returns to work session at the configured focus duration
- Auto-advances to next session on completion; `didJustComplete` briefly set true for flash feedback
- Does NOT send notifications (requires entitlement) — panel visual feedback only
- Enabled/disabled via "Focus Timer" toggle in Settings

---

### RemindersWidget

**Goal:** Show a small list or count of incomplete Apple Reminders that matter now.

**Data source:** Apple Reminders via EventKit.

- Use `EKEventStore` with reminder entity type (`.reminder`).
- Requires `NSRemindersFullAccessUsageDescription`.
- Sandboxed macOS app must include `com.apple.security.personal-information.reminders`.
- Request access from an explicit user action, not passively on launch.
- Use `requestFullAccessToReminders` on modern macOS.
- Fetch reminders with EventKit reminder predicates, for example incomplete reminders due today or overdue.
- Ignore completed reminders by default.

**Possible display modes:**
```
3 tasks
2 overdue
```
or:
```
09:00  Pay invoice
Today  Buy milk
```

**Service:** `ReminderService: ObservableObject`

- Tracks authorization state separately from calendar authorization.
- Fetches incomplete reminders asynchronously through EventKit callbacks.
- Normalizes reminders into app-owned value types before rendering.
- Refreshes periodically while the panel is expanded and when reminder access changes.

---

### CountdownWidget

**Goal:** Show a user-created countdown to a chosen future date.

**Data source:** Local app state only — no network or system permission required.

**Layout:** Fixed 150×110 widget, implemented in `CountdownWidget.swift` plus a small persistence/service type if needed.

**Empty state:**
- If no countdown exists, show a quiet empty state with:
  - title text such as `No countdown`;
  - secondary text such as `pick a date`;
  - a small `plus` button.
- The plus button opens a modal creation window.

**Create/edit flow:**
- Plus button opens a modal window similar in spirit to the add-reminder window.
- Modal fields:
  - countdown title;
  - target date;
  - optional target time.
- Actions:
  - `Cancel` closes without saving;
  - `Create` saves the countdown and updates the widget immediately.
- The create action is disabled until title and target date are valid.
- Target date should normally be in the future. If a past date is selected, the UI should either reject it or clearly mark it as elapsed.

**Display:**
```
[+] 
Trip to Tokyo
1y 2m 14d 6h
```
- Shows the countdown title on the first line, truncated with `…` if needed.
- Shows remaining time below the title.
- Remaining time is calculated from `Date()` to the target date and updates at least once per minute while the panel is expanded.
- If the target time includes hours/minutes, the countdown should include hours when useful.
- Suggested compact format:
  - `2y 3m 4d` for long ranges;
  - `14d 6h` for ranges under one month;
  - `6h 20m` for ranges under one day;
  - `now` or `done` when the target date has arrived.
- Use `.monospacedDigit()` for the numeric countdown so it does not visually jump.
- Use the shared accent color for the most important number or small status mark.

**Persistence:**
- Store countdown data in `UserDefaults` via `BangBarSettings` or a small `CountdownService`.
- Persist:
  - title;
  - target date/time;
  - creation/update timestamp if useful for future editing.
- V1 supports one active countdown in the widget. Multiple countdowns can be considered later if there is a clear UI need.

**Interactions:**
- Clicking the plus button creates a countdown when empty.
- When a countdown already exists, clicking the widget or a small edit affordance can reopen the modal to edit/replace it.
- A delete/reset action should be available in the modal or a contextual control so the widget can return to empty state.

**Settings:** Enabled/disabled via a "Countdown" toggle in Settings and included in widget ordering.

---

### Companion Widget

**Status:** ⬜ Planned. The behavior and technical direction are defined below; character identity, name, sprites, and final visual design are TBD.

**Product name:** **Companion**. `Calm Care` is the name of its low-pressure care philosophy, not the user-facing widget name.

**Goal:** Add a calm desktop companion inspired by classic virtual pets without reproducing Tamagotchi characters, branding, artwork, or exact punitive pacing. The pet should reward occasional care without interrupting focused work or punishing the user for closing the Mac, sleeping, travelling, or spending time away from the computer.

**Product principles:**

- The pet is a quiet companion, not a responsibility simulator.
- Needs change slowly and primarily during meaningful Mac use rather than raw wall-clock time.
- The user never returns to accumulated emergencies caused solely by sleep, screen lock, app termination, or time away from the computer.
- Missing an ordinary request does not immediately count as a care mistake.
- Poor care can influence mood, personality, and evolution, but absence alone must not kill the pet.
- System notifications are out of scope for the first version. Important states may use the compact panel only when doing so remains rare and unobtrusive.
- Interactions should take a few seconds. Longer activities and mini-games remain optional.

**Character and visual design — TBD:**

- The character will be an original BangBar creature, not an existing Tamagotchi character or a close visual copy.
- Character name, silhouette, sprite style, color palette, animation frames, sounds, and evolution appearances will be designed later.
- The first implementation may use a temporary neutral placeholder while the state engine is developed, but placeholder art must not become the final identity by accident.

**Active-time clock:**

- Pet needs advance according to accumulated `activeUseSeconds`, not continuously from wall-clock time.
- Active use counts only while all of the following are true:
  - the Mac is awake;
  - the user session is unlocked;
  - the display is active;
  - user input idle time is less than approximately 10 minutes.
- Sleep, display sleep, lock screen, logout, app termination, and idle time beyond the threshold pause need decay.
- On wake or relaunch, the service resumes from the last saved state without applying full offline decay.
- A small capped amount of passive progression may be considered later for growth, but it must never create care mistakes, sickness, mess, or death while the user is absent.
- Use system workspace/session notifications and idle-time checks where available; avoid private frameworks and special entitlements.

**Suggested calm pacing:**

- Hunger loses one step after roughly 3 hours of accumulated active use.
- Happiness loses one step after roughly 4 hours of accumulated active use.
- Cleanliness may require attention roughly once per 6 hours of accumulated active use.
- A request for attention occurs no more than once every 2–3 hours of active use.
- Sickness is possible only after multiple unresolved needs across several active-use days, never from one missed interaction.
- Growth stages take multiple real days with minimum active-use requirements:
  - egg / arrival;
  - baby;
  - child;
  - teen;
  - adult.
- A complete lifecycle should last approximately 4–6 weeks rather than several days.
- All timing values should live in one configuration type so they can be tuned after real-world testing.

**Core state:**

```swift
struct CompanionState: Codable {
    var id: UUID
    var createdAt: Date
    var lastUpdatedAt: Date
    var activeUseSeconds: TimeInterval
    var stage: CompanionStage
    var hunger: Int
    var happiness: Int
    var cleanliness: Int
    var discipline: Int
    var consecutiveUnresolvedNeeds: Int
    var careMistakes: Int
    var currentNeed: CompanionNeed?
    var currentNeedStartedAt: Date?
    var isSleeping: Bool
}
```

- Suggested meters use a small fixed range such as `0...4` for a classic, readable feel.
- Values are clamped on every mutation.
- Runtime-only animation state must not be mixed into the persisted pet model.
- The service publishes normalized UI state on the main actor.

**Needs and care mistakes:**

- Initial needs: hungry, wants attention, dirty, tired, and unwell.
- Ordinary requests remain available for a generous active-time window and do not interrupt Focus Timer.
- Ignoring one ordinary request clears or defers it without an immediate care mistake.
- A care mistake is recorded only after repeated unresolved needs or deliberately inappropriate care.
- Consecutive successful care gradually restores the pet's condition and can reduce the impact of earlier mistakes.
- False/selfish calls and discipline may be added after the core loop is proven; they are not required for MVP.
- Critical condition should produce a recoverable resting state. Permanent death is not part of MVP.
- A completed adult lifecycle may later end with the pet peacefully leaving to explore, followed by an optional new egg.

**Focus Timer integration:**

- While Focus Timer is running, the pet does not surface requests, play attention animations, or take over compact mode.
- Need decay may either pause completely during a focus session or continue without starting a response deadline; MVP should pause it for the least distracting behavior.
- After a completed focus session, the pet may show one quiet positive reaction or offer a short interaction.
- Focus completion must not guarantee a request every time; apply cooldowns so the reaction stays pleasant.
- Clipboard image collection keeps its existing highest compact-mode priority.

**Interactions:**

- Feed: restores hunger with one click.
- Pet: gives a small happiness increase with a short cursor/click interaction.
- Clean: restores cleanliness when needed.
- Rest: allows or encourages sleep when tired.
- Status: shows the current meters and a concise hint without opening a large management screen.
- Initial interactions should complete in a few seconds and should not open separate windows.
- A 10–15 second optional mini-game may be added after MVP to improve happiness; declining it has no penalty.

**Panel behavior:**

- Expanded mode contains the full fixed-width pet widget and its direct interactions.
- The pet does not need to be visible in compact mode during normal idle behavior.
- Compact mode may be used for a rare unresolved important need only after the cooldown and priority rules are satisfied.
- Compact priority remains:
  1. active clipboard image collection;
  2. running Focus Timer;
  3. currently playing music;
  4. rare important pet state, if compact pet presentation is enabled.
- The pet must not repeatedly reopen or restart compact animations during state ticks.

**Persistence:**

- Persist one active pet as versioned JSON under Application Support, for example `BangBar/Companion/companion.json`.
- Store a schema version so future state fields and evolution systems can be migrated safely.
- Save after user interactions, stage transitions, important need changes, and periodically while active time accumulates.
- Use atomic writes.
- On corrupted state, preserve the unreadable file for diagnostics when practical and create a fresh pet instead of crashing.
- Resetting the pet must require explicit confirmation in Settings.

**Architecture:**

- `CompanionService`: owns the simulation clock, persisted state, interactions, lifecycle, and Focus Timer coordination.
- `CompanionState`: persisted value model.
- `CompanionRules`: centralized tunable durations, thresholds, meter ranges, and growth requirements.
- `CompanionWidget`: expanded SwiftUI surface.
- `CompactCompanionWidget`: optional later compact surface for rare important needs.
- Character sprites and animation definitions should remain separate from simulation rules so the final character can be added without rewriting the engine.
- Add the widget as a new `BangBarWidget` case, Settings toggle, ordering option, and fixed `PanelLayout` width only when the first usable UI exists.

**Evolution:**

- Evolution is deterministic from accumulated care patterns plus a small seeded variation, not from aggressive random punishment.
- Candidate inputs include care mistakes, average happiness, cleanliness, completed Focus Timer sessions, optional play frequency, and response consistency.
- The same pet `id` should seed any random branch so relaunching cannot reroll an outcome.
- Exact branches and adult forms remain TBD until the character family is designed.

**MVP implementation plan:**

1. Define `CompanionState`, `CompanionRules`, versioned persistence, and migration boundaries.
2. Implement active-use detection and verify that sleep, lock, long idle, and app termination do not create decay.
3. Implement slow hunger, happiness, and cleanliness progression plus feed, pet, and clean actions.
4. Integrate Focus Timer so simulation and attention requests pause while focus is running.
5. Build the expanded widget with a temporary original placeholder, meters, concise status, and direct actions.
6. Add Settings enable/disable and widget ordering support.
7. Run a multi-day pacing test and tune all intervals before adding more mechanics.
8. Replace the placeholder with the final original character and animations when the design is ready.
9. Add growth stages and care-based evolution.
10. Consider optional compact important-need presentation and a short mini-game only after the quiet core loop feels right.

**MVP acceptance criteria:**

- Closing the lid overnight does not reduce meters or create a care mistake.
- Leaving the Mac idle or locked for a workday does not create accumulated emergencies.
- A continuous active work session produces no more than one optional attention request within 2–3 hours.
- Focus Timer runs without pet interruptions.
- `Feed`, `Pet`, and `Clean` update and persist immediately.
- Relaunch restores the same pet and meters.
- Several ignored ordinary requests do not cause sudden death.
- Widget enablement and ordering behave like the existing optional widgets.

**Out of scope for MVP:**

- copied Tamagotchi names, characters, sprites, sounds, or branding;
- permanent death caused by neglect;
- system push/local notifications;
- network accounts, cloud sync, multiplayer, breeding, trading, or social features;
- multiple simultaneous pets;
- monetization or collectible purchases;
- elaborate mini-games;
- final evolution tree before character design is complete.

---

### NotionWidget

**Goal:** Show tasks from a single column of a user's Notion database (board), e.g. all tasks whose Status is `In progress`. Which column is shown is chosen in Settings.

**Data source:** Notion REST API over HTTPS (`api.notion.com`) via `URLSession`. No private frameworks, no entitlements — a plain network request, consistent with the no-Developer-ID constraint.

**Authentication:**
- Uses a user-provided **internal integration token** (created by the user at notion.so/my-integrations).
- The token is stored in the macOS **Keychain**, never in `UserDefaults` and never committed to the repo.
- All requests send headers:
  - `Authorization: Bearer <token>`
  - `Notion-Version: 2022-06-28`
  - `Content-Type: application/json`
- The user must share the target database with the integration (Notion page `•••` → Connections → add integration), otherwise the API returns 404. Settings surfaces this as a hint on connection failure.

**Concept mapping:**
- A Board view's columns are the option values of one database property of type `status` (or `select`). BangBar does not model columns separately — showing a column means filtering the database query by that property value.

**Configuration (stored keys):**
- Keychain: integration token.
- `UserDefaults` via `BangBarSettings.Key`:
  - `notionDatabaseId` — 32-char database id.
  - `notionStatusProperty` — the property name used for grouping/filter (e.g. `Status`).
  - `notionStatusPropertyType` — `status` or `select`, needed to build the correct filter shape.
  - `notionSelectedStatus` — the chosen column value (e.g. `In progress`).
  - `showNotionWidget` — enable/disable toggle.

**Database id parsing:**
- Settings accepts either a raw id or a full Notion URL. The id is the last 32 hex characters of the URL path (dashes optional, ignore any `?v=` view query). Store the normalized 32-char id.

**Schema fetch (Settings only):**
- `GET /v1/databases/{id}` retrieves the database.
- From `properties`, collect every property whose type is `status` or `select`; these are candidate grouping properties. Each candidate exposes its `options[].name` as the selectable columns.
- Settings uses this to populate the "Status property" and "Show column" dropdowns with the user's real values instead of free text.

**Task query:**
- `POST /v1/databases/{id}/query` with body:
  ```json
  {
    "filter": { "property": "<notionStatusProperty>", "<type>": { "equals": "<notionSelectedStatus>" } },
    "page_size": 10
  }
  ```
  where `<type>` is `status` or `select` per `notionStatusPropertyType`.
- Task title is read from the database's `title`-type property (`properties[titleProp].title[].plain_text`, joined).
- Each result page carries its `id` and public `url` for opening in Notion.

**Data model:**
```swift
struct NotionTask: Identifiable {
    let id: String        // page id
    let title: String
    let url: URL?         // page url, for click-to-open
}
```

**Service:** `NotionService: ObservableObject` (mirrors `ReminderService` structure)
- `@Published private(set) var items: [NotionTask]`
- `@Published private(set) var state: State` where
  ```swift
  enum State { case notConfigured, loading, ready, error(String) }
  ```
- `notConfigured` when token or database id is missing.
- Polls on a background queue on a timer (~60 s while relevant) and publishes on `DispatchQueue.main`; refresh is also triggered when relevant settings change (`UserDefaults.didChangeNotification`).
- `refresh()` runs the query; network/decoupling failures set `.error` with a short message; non-200 responses (401/404) map to concise text ("Check token", "Share DB with integration").
- `fetchSchema(completion:)` used only by Settings to load candidate properties and their options.
- Results capped (e.g. first 10; widget shows first ~4 with a "+N more").

**Display (mirrors RemindersWidget):**
- Fixed size, proposed 190×110 (same as `ClockWidget`), added to `PanelLayout.expandedWidgetWidths` as `notionWidgetWidth` so the panel grows automatically.
- Header row: small SF Symbol + selected column name + task count on the left.
- Up to `maxVisible` (~4) task rows; each row is title (truncated with `…`) with a leading circular marker; overflow shows `+N more`.
- Clicking a row opens the page `url` in the browser / Notion app.
- Hover tooltip shows the full title, reusing the tooltip tracking pattern from `RemindersWidget`.
- States:
  - `notConfigured`: quiet prompt "Set up in Settings".
  - `loading`: subtle placeholder on first load only.
  - `ready` + empty: empty state ("Nothing here").
  - `error`: concise error text.

**Complete action (phase 2 — checkbox):**
- Phase 1 is read-only. Phase 2 adds a circular checkbox per row (like `ReminderRow`) that marks a task done.
- Notion `status` properties have grouped options (typically To-do / In Progress / Complete groups). Completing a task means `PATCH /v1/pages/{id}` setting the status property to the first option in the "Complete" group (resolved from the schema's `status.groups`). For a plain `select` property, Settings must let the user pick which value represents "done".
- On success, optimistically remove the row and `refresh()`.

**Settings section (NOTION):**
- Integration token field (secure), stored to Keychain.
- Database URL / ID field with a `Connect` action that runs `fetchSchema`.
- After a successful connect:
  - "Status property" dropdown (shown when more than one candidate exists).
  - "Show column" dropdown listing that property's option values.
- Connection errors show concise guidance (invalid token, database not shared).

**Constraints:**
- Public Notion API only; the only secret is the user's own token, held in Keychain, never committed.
- No third-party dependencies; `URLSession` + `Codable` only.
- Enabled/disabled via a "Notion" toggle in Settings and included in widget ordering (`BangBarWidget.notion`).

---

## Settings Panel

Implemented as a custom dark macOS settings window (`SettingsView`), opened from the app menu or expanded-panel chrome button.

**Window chrome:**
- Initial size: 1180×700, minimum size 960×600.
- Opening the settings window, including first creation, uses an initially centered content rect and keeps the new window transparent until its final centered frame is applied, so it does not visibly jump into place.
- Uses a transparent/full-size titlebar so the Apple window controls sit over the black settings surface.
- Titlebar separator/material backgrounds are removed or forced black from `AppDelegate`.
- Window background dragging is disabled so it does not conflict with widget drag/drop inside settings.
- Settings content uses compact in-window spacing: a shorter titlebar and reduced top/leading/bottom padding compared with the original roomy layout.
- The settings window does not draw internal divider lines under the titlebar or between the sidebar and main content.

**Sidebar tabs:**
- `WIDGETS`
- `PERMISSIONS`
- `APPEARANCE`
- `CLIPBOARD`
- `ABOUT`
- Tabs are centered in the left sidebar and highlight with the current accent color.
- Sidebar illustration uses the `settingsIllustration` asset from the asset catalog, is bottom-aligned inside its frame, and is grouped near the footer logo without a divider line below it.
- Sidebar footer is rendered in SwiftUI as a small left-aligned `OLCHU_ STUDIO` text logo with a plain accent dot, not as an image asset; the current app version from `CFBundleShortVersionString` is shown opposite it, right-aligned.

**About section:**
- Displays the app icon, app name, and current version (`CFBundleShortVersionString`).
- Contains a "Check for Updates" button that triggers `UpdateService.checkForUpdates()`.
- Shows update status text below the button: `Up to date`, `Version X.Y.Z available`, download progress percentage, or an error message.
- When an update is available, a second "Update & Restart" button appears; tapping it calls `UpdateService.downloadAndInstall()`.
- The check button is disabled while a check or download is in progress.
- See **Auto-Update** section for the full implementation spec.

**Widgets section:**
- Shows helper text explaining that widgets can be enabled, disabled, and reordered.
- Top tray shows currently enabled widgets in saved order; top tray chips do not show toggles and are sized proportionally to their real panel widget widths.
- Top tray uses native SwiftUI `onDrag`/`onDrop` reordering for enabled widgets, with a solid black drag preview for each chip.
- Available widgets list shows every widget with icon, title, description, and toggle.
- Calendar selection is shown as a separate Calendar setting with each EventKit calendar name on the left and a right-aligned switch toggle, plus quick All/None actions.
- Settings toggles use a custom dark-theme switch style: on state is accent-filled, off state has a dark track with a visible light outline.
- Reminders list selection is shown as a separate Reminders setting, not inline inside the available widgets list.
- Drag/drop on either the top tray or available list updates `BangBarSettings.Key.widgetOrder`.
- `PanelContentView` reads the saved widget order and renders enabled widgets in that order.
- Toggle: Music — show/hide `NowPlayingWidget`
- Toggle: Calendar — show/hide `ClockWidget`
- Toggle: Moon — show/hide `MoonWidget`
- Toggle: Focus Timer — show/hide `PomodoroWidget`
- Toggle: Countdown — show/hide `CountdownWidget`
- Toggle: Notion — show/hide `NotionWidget`
- Toggle: Mirror — show/hide `MirrorWidget`

**Permissions section:**
- Toggle: Open BangBar at login (via `SMAppService`)
- Camera: shows authorization status, requests access or opens System Settings
- Calendar: shows authorization status, requests full access or opens System Settings
- Automation: opens System Settings › Privacy › Automation (required for Spotify/Music AppleScript control)

**Appearance section:**
- Accent color picker is shown as a wide swatch button with the current hex value; clicking it opens the system color panel, stores the value as a hex string in `UserDefaults`, and defaults to `#FF383C`. Reset button disables itself when the current value equals the default.
- Toggle: Tint walking figure — applies accent color to the no-plans MP4 animation.

**Clipboard section:**
- Storage card selects the total history limit, shows current disk usage and the fixed item limits, and provides Clear History.
- Temporary Changes card enables delayed stable-content capture and selects the wait duration.
- Transcription card enables shortcut-based suppression, records the shortcut (including `fn`), and selects the post-release protection duration.

**Accent color** is read via `@AppStorage` in `ClockWidget` (day number), `ArtworkPlaceholder` (glow + icon), `PomodoroWidget`, `MoonWidget`, and `SettingsView`. The `Color(hex:)` / `hexString` helpers live in `BangBarSettings.swift`.

---

## Auto-Update

### Goal

Allow the user to check for updates and install them without leaving the app, without Developer ID, and without any third-party framework.

### Distribution

- Releases are published on GitHub Releases, tagged with semver (`v1.2.3`).
- Each release contains a single asset named `BangBar.zip` — a zip archive with `BangBar.app` at its root.
- The GitHub repo owner and name are stored as compile-time constants in `UpdateService.swift`.

### UpdateService

`final class UpdateService: ObservableObject`, lives in `UpdateService.swift`.

**State machine:**
```
idle → checking → upToDate
                → available(latestVersion: String, downloadURL: URL)
                → error(String)

available → downloading(progress: Double)
          → error(String)

downloading → installing
            → error(String)
```

**Published property:** `@Published var state: UpdateState`

**Methods:**
- `func checkForUpdates() async` — hits GitHub API, compares versions, transitions to `upToDate` or `available`.
- `func downloadAndInstall() async` — downloads the zip, unzips, writes the updater script, launches it, terminates the app.

### Version Check

- GET `https://api.github.com/repos/<owner>/<repo>/releases/latest` using `URLSession.shared`.
- Parse `tag_name` (strip leading `v`) and compare against `Bundle.main.infoDictionary["CFBundleShortVersionString"]` using semver component comparison (`Int` comparison per dot-segment, not string lexicographic).
- Store `browser_download_url` of the asset named `BangBar.zip` for later download.
- No GitHub auth token — public repo API only.

### Download

- `URLSession.shared.downloadTask(with:delegate:)` with a delegate that reports `fractionCompleted` to update `state` to `.downloading(progress)` on the main queue.
- Save the downloaded zip to `FileManager.default.temporaryDirectory`.

### Install

1. Unzip via `Process`: `unzip -o <zip_path> -d <temp_dir>/BangBar_update/`
2. Determine install destination: `Bundle.main.bundleURL` (replaces the running copy in-place).
3. Write a shell script to `/tmp/bangbar_updater.sh`:
   ```bash
   #!/bin/bash
   sleep 1.5
   cp -R "<temp_dir>/BangBar_update/BangBar.app" "<install_destination>"
   open "<install_destination>"
   rm -rf "<temp_dir>/BangBar_update" /tmp/bangbar_updater.sh
   ```
4. `chmod +x /tmp/bangbar_updater.sh`
5. Launch the script via `Process` with `launchPath = "/bin/bash"`, `arguments = ["/tmp/bangbar_updater.sh"]`, no pipe — fully detached.
6. Call `NSApp.terminate(nil)`.

The app quits; the script runs in the background, waits 1.5 s for the process to exit, copies the new app over itself, and reopens it.

### Error Handling

- Network failure or non-200 response → `.error("Could not reach update server")`
- Zip not found in release assets → `.error("Update package not found")`
- Unzip failure (non-zero exit) → `.error("Failed to unpack update")`
- All errors are displayed as status text in the ABOUT tab; no alerts.

### Constraints

- No Sparkle, no third-party dependencies.
- No sandbox, no hardened runtime — direct `cp -R` works without privilege escalation.
- No background polling — update check is user-initiated only (button in ABOUT tab).
- No delta updates — always downloads the full zip.

---

## Layout Plan (after new widgets)

```
[NowPlayingWidget] | Divider | [ClockWidget] | Divider | [RemindersWidget] | Divider | [NotionWidget] | Divider | [MoonWidget] | [PomodoroWidget] | [CountdownWidget] | Divider | [MirrorWidget]
```

Panel width may need to increase to accommodate all widgets.
Each widget separated by `Divider` at 35pt height.

`RemindersWidget` and `CountdownWidget` can be added as optional widgets once the settings panel can enable/disable optional surfaces.

---

## Potential Widget Backlog

These are not immediate commitments, but useful directions to consider after Focus Timer (`PomodoroWidget`), settings, and `RemindersWidget`.

### FocusWidget

- Shows current macOS Focus / Do Not Disturb state.
- Offers a compact toggle if the system API allows it.
- Should stay visually quiet; focus status is useful only if it does not become another distraction.

### WeatherWidget

- Shows current temperature and short condition text, e.g. `12° Rain`.
- Requires choosing a data source such as WeatherKit or another provider.
- Should avoid heavy decorative weather art; this panel needs concise glanceable data.

### BatteryWidget

- Shows MacBook battery level and charging state.
- Could later include connected accessory battery levels if available.
- Best display is likely a percentage plus tiny charging/status icon.

### QuickLauncherWidget

- Provides 2-4 icon buttons for frequent actions or apps.
- Candidate actions: open Calendar, Reminders, Music, app settings.
- Should use SF Symbols / familiar icons and avoid text-heavy buttons.

### NetworkWidget

- Shows Wi-Fi / VPN / online status.
- Useful when switching between networks or debugging connectivity.
- Should avoid noisy live throughput unless there is a clear need.

### SystemLoadWidget

- Shows a compact health indicator for CPU/RAM/thermal pressure.
- Should avoid becoming a dense monitoring dashboard.
- Prefer one small status summary over multiple always-changing numbers.

### NextAlarmWidget

- Shows the next alarm or timer if a reliable macOS data source is available.
- Feasibility needs investigation; this should not be built until the API path is clear.
