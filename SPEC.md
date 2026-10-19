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
- Expanded panel width is calculated from `PanelLayout`: horizontal padding, intrinsic widget widths, divider widths, and spacing.
- Expanded panel width must not be maintained as a separate hardcoded window width.
- The panel grows and shrinks to the enabled widgets that fit the current width budget; widgets must never overlap or be covered by a wider neighbor.
- The maximum expanded width is the smaller of the original full-widget budget (`1468 pt`) and the current screen's visible width minus `8 pt` on each side.
- This is a width budget, not a hardcoded widget-count limit. A future narrow widget may still fit where a wider one does not.
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

- The panel activation threshold is configurable from `−20...+40 px` and defaults to `0`.
- At `0`, the hidden panel opens exactly at the built-in notch bounds; in compact mode it opens at the visible `NotchPanelShape` contour. Transparent margins of the compact window never trigger expansion.
- Positive values expand the activation rect and negative values inset it.
- Because both hidden and compact activation areas are pinned to the physical top edge, the threshold moves their reachable bottom edge once. A negative threshold must not also inset the unreachable top edge and collapse the compact area's height.
- Closing logic uses a small buffer around the panel and trigger zone to avoid boundary flicker.
- `HoverHostingView` forwards `mouseEntered` and `mouseMoved` from inside the panel to the same hover handler used by global tracking. This keeps hover behavior stable over interactive SwiftUI content such as album artwork.
- `syncCompactVisibility` must not repeatedly call `enterCompactMode()` while the panel is already compact; now-playing updates happen frequently and should not restart compact animations.
- Hover and status-menu opening interrupt an in-flight transition instead of dropping the request. The requested expanded state survives a Space/display transition even before the opening animation finishes.
- Deferred opening, hiding, artwork cleanup, and Space retries belong to a transition identifier; superseded callbacks must not change the panel.
- The panel does not hide automatically when the application deactivates. Hidden and visible windows both check active-Space membership on presentation; off-Space windows temporarily use `moveToActiveSpace`, then restore the all-Spaces policy. Presentation checks membership after a delay and permits at most two retries.
- Sleep/wake and Space/display changes cancel pending transitions and rebuild the requested mode. Hidden panels stay ordered out rather than being flashed onscreen at zero opacity.
- Playback-position ticks must not trigger compact-window animations; unchanged frame targets complete immediately.

Manual regression coverage for panel lifecycle: open from hover and the status menu on two desktops and a full-screen Space; switch Spaces while expanding/collapsing; open during a page animation; start/stop music while compact; sleep/wake in hidden and expanded modes; repeat on another display. Confirm that stale callbacks never reopen a dismissed panel and that the log contains no exhausted Space-presentation retries.

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

### Widget Settings

- The Widgets settings screen has a centered secondary tab bar: General, Calendar, Moon, Reminders, Focus Timer, GitHub, and Habits. Calendar selection and meeting-alert configuration live together in the Calendar tab; there is no separate Calendar sidebar destination.
- Widgets without additional settings do not get an empty secondary tab.
- General owns widget enable/disable controls and drag-and-drop ordering.
- Calendar owns calendar selection, Moon owns location selection, Reminders owns reminder-list selection, Focus Timer owns session-duration and round settings, GitHub owns the public username, and Habits owns habit management and statistics.
- Widget-specific settings must not be added back to General.

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
- `SystemWidget.swift` provides live CPU, memory, power/disk, thermal status, and local IPv4 information.
- `SystemWidget.swift` lives outside `PanelContentView`.
- New widget UI should be added as a separate file instead of growing `PanelContentView.swift`.

### Layout Constants

- Expanded layout is configured by `PanelLayout`.
- Each widget declares its layout width in `BangBarWidget.layoutWidth`; the panel itself derives its width from the enabled content:
  - `NowPlayingWidget`: 300×110
  - `ClockWidget`: 210×110
  - `MoonWidget`: 110×110, with a 78×78 moon image
  - `PomodoroWidget` (displayed as **Focus Timer**): 110×110
  - `CountdownWidget`: 150×110
  - `MirrorWidget`: 94×94
  - `SystemWidget`: 160×110
  - `GitHubWidget`: 150×110
  - `AIUsageWidget`: 140×110
  - `HabitsWidget`: 220×110
  - `TranslatorWidget`: 150×110
  - divider: 1×60
  - visible edge padding: 20 pt from the shaped side wall and bottom edge
  - raw SwiftUI horizontal padding: `panelTopEarInset + panelTopRadius + visible padding`
  - compact width: `min(max(notchWidth + compactNotchSidePadding * 2, 320), 360)`, with `compactNotchSidePadding = 100`
  - compact horizontal padding: `min(max(height + 18, 50), 50)`
  - widget spacing: 12
- Current expanded width formula:
  - `padding * 2 + sum(widget.layoutWidth) + dividerWidth * (widget count - 1) + spacing * 2 * (widget count - 1)`
- Settings evaluates the proposed enabled-widget set before enabling another widget. If it exceeds `PanelLayout.maximumExpandedWidth(on:)`, that toggle is disabled and its subtitle explains that another widget must be turned off.
- Runtime rendering also calls `widgetsThatFit(_:maximumWidth:)` in saved order as a safety boundary, so older preferences and smaller screens cannot produce overlapping widgets.
- Widgets use their declared frames directly without compensating negative offsets or negative horizontal padding. Calendar received a wider declared frame and GitHub a narrower one so neighboring widgets are pushed normally instead of being overdrawn.
- Future widgets must provide `BangBarWidget.layoutWidth`; no separate panel/window-width constant should be added.

### Clipboard History — Implemented

**Status:** ✅ Implemented, including separate `All`, `Text`, and `Images` views and image grouping.

- Clipboard history is a panel-level surface, not an item in the reorderable widget row.
- The clipboard button in `PanelTopBar` switches the expanded panel between widgets and history.
- Optional two-finger trackpad swipe navigation can be configured in Settings → Clipboard → Gestures. By default, a downward swipe over non-scrollable expanded-panel content opens Clipboard History and an upward swipe returns to the normal widget surface; an inversion toggle swaps those directions. When disabled, scroll events are not intercepted. The entire Habits widget is an explicit navigation-swipe exclusion region, so its header and vertical list never switch panel surfaces. Gesture routing happens at the panel-window level so vertical navigation continues to work while the pointer is directly over Clipboard cards; horizontal deltas still pass through to the card scroller.
- History has `All`, `Text`, and `Images` filters. Image groups appear in `All` and `Images`, but not in `Text`.
- The top bar retains the Settings button and, while history is open, also provides Clear History and image-group collection controls.
- Text and image cards are shown in a horizontally scrolling row. Clicking a card writes it back to the system pasteboard; hover and context-menu actions allow individual deletion.
- Image cards (including those inside a group) show an open button in the top-left corner on hover, plus an `Open Image` context-menu item; both open the persisted full-size image in BangBar's own preview window, centered on the screen under the pointer and fitted to 80% of its visible area (never upscaled). `Esc` or the close button dismisses it. If the file is missing, an alert is shown.
- Image-group cards show a stacked preview and item count, open into a group detail view, and support copy, rename, and delete actions.
- Copying a group writes its persisted image file URLs as separate pasteboard items so Finder and destination editors receive a real multi-file paste.

**Capture and persistence:**

- `ClipboardHistoryService` polls `NSPasteboard.general` every 0.6 seconds and captures non-empty text, PNG/TIFF images, and image file URLs.
- Image file URLs are read and normalized to PNG before storage. Re-copying a stored single image writes the image back to the pasteboard; copying a group uses file URLs.
- Content is fingerprinted with SHA-256. An identical text or image payload is deduplicated and moved to the newest position instead of retaining duplicate history entries.
- Image payloads are read from the pasteboard on main (NSPasteboard is not documented as thread-safe, and reading at poll time keeps the text fallback and never loses a copy). Fingerprint hashing, PNG normalization and the file write run on `imageProcessingQueue`; a payload matching the last stable fingerprint is dropped there before any encoding. Adopting the current content as already seen (launch, after suspension, suppressed changes) also hashes images off main.
- `index.json` and `groups.json` are written together on a background serial queue, debounced by 300 ms, from a snapshot taken on main; the last snapshot wins. A pending write is flushed synchronously on app termination.
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
  - each event shows relative status below the title using compact duration text: durations below 24 hours use hours and minutes (for example `starts in 2h 30min`), while durations of 24 hours or more use days and remaining hours (for example `ends in 5d 2h`). Zero-value trailing units are omitted.
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
- Shuffle and repeat state are read with now-playing metadata.
- Shuffle button toggles shuffle for Spotify and Music.
- Repeat button cycles Music through `off → all → one → off`; Spotify toggles repeat as `off/all`.
- Click on artwork opens the player app.
- For Apple Music, a favorited track shows an accent-colored top-right artwork corner with a white heart. For an unfavorited track, the corner appears on artwork hover and can be clicked to favorite the track.
- Spotify does not show the favorite corner because its AppleScript API does not expose library favorite state or mutation.
- Title truncates with `…` if too long.
- Progress bar updates every second via local tick timer (no extra AppleScript calls).
- All AppleScript runs through `AppleScriptRunner` (`/usr/bin/osascript` via `Process`, off the main thread), never `NSAppleScript`.
- Refreshes are event-driven: `com.apple.Music.playerInfo` / `com.spotify.client.PlaybackStateChanged` distributed notifications (observed with `.deliverImmediately`, because AppKit suspends them for an inactive menu bar app) and player launch/quit trigger a refresh, coalesced over 200 ms because players post bursts. Polling is only a fallback: every 10 s while the expanded widget is visible, every 30 s otherwise. The last active player is queried first.
- Each refresh runs a cheap state script (track ID, title, artist, state, position, duration, shuffle, repeat). The details script (favorite lookup through the library and Music artwork export to `/tmp/bangbar_artwork.png`) runs only when the track changes or after a favorite command. Right after a track change the player may not have the artwork yet: an empty artwork result is not cached, and details are re-fetched after 1 s, up to 3 times per track (sharing the coalesced notification poll). The iTunes Search fallback runs only on the last attempt.
- Player commands update controls optimistically and request an immediate refresh without a fixed delay. Each command bumps a generation counter; a refresh that started before the command, or while any command is still running, is discarded so it cannot flip an optimistic toggle back. Commands run on one serial queue, in the order they were issued.
- Metadata refreshes are coalesced so a slow one cannot create overlapping AppleScript requests.
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
3. ✅ `MoonWidget` is implemented with local astronomical calculations, optional Core Location access, manual-city fallback, and widget ordering.
4. ✅ `RemindersWidget` and `ReminderService` are implemented and wired into Settings and widget ordering.
5. ✅ Clipboard History is implemented as a panel-level surface with `All`, `Text`, and `Images` filters, persistent text/image items, and image-group collection and management.
6. ⬜ Implement Mirror photo capture according to the development plan above.
7. ✅ Task hover tooltip appears next to the hovered row, clamped to the panel bounds.
8. ✅ `CountdownWidget` is implemented as a local, user-configured date countdown widget with a create/edit window, Settings toggle and widget ordering.
9. ⬜ Consider `NotionWidget` after the local widgets and interaction fixes.
10. ✅ Pinned Clipboard History cards stay first and survive Clear History.
11. ❌ Companion is dropped and not planned. Its code stays in the project, hidden from the interface, with the runtime service not started.
12. ✅ `HabitsWidget` is implemented with daily completion, local history/statistics, and Settings management according to the plan below.
13. Keep new implementation split into separate component/service files instead of growing `PanelContentView.swift`.
14. ✅ Swipeable widget pages/surfaces are implemented — see "Planned: Widget Pages (Swipe Between Surfaces)" below.
15. ✅ Keyboard Layout Switcher, Phase 1 (manual conversion by hotkey) — see "Keyboard Layout Switcher" below.
16. ✅ Keyboard Layout Switcher, Phase 2 (automatic conversion).
17. ⬜ Work through the Refactoring Backlog (P1 items first) — see "Refactoring Backlog" below.

### MoonWidget

**Goal:** Show current moon phase, illuminated percentage, and the next new and full moon dates.

**Data source:** Astronomical values are calculated locally — no network is required after coordinates are known.
- Compute approximate solar and lunar ecliptic longitudes from J2000.
- Current illumination uses lunar elongation: `(1 - cos(elongation)) / 2`.
- Next new and full moon dates are found by sampling forward from the current date and refining the illumination minimum or peak.
- The observing coordinates come from Core Location when automatic location is enabled, otherwise from the city saved in Settings. Resolving a newly entered city may use the system geocoder and network.

**Display:**
```
100%                 Last
ILLUM.              PHASE
       [MoonTexture]
NEW                 FULL
Jun 15            Jun 30
```
- Moon image: `MoonTexture` asset clipped to a circle.
- No moon-cycle progress arc is drawn.
- Phase shadow: render a darkened full `MoonTexture` base, then render the bright texture above it through a calculated illumination mask. The mask area matches the calculated illumination percentage; everything outside it stays under shadow.
- The illumination mask is rotated to match the bright limb as seen relative to the observer's local horizon; it is not kept permanently vertical.
- Moon disk is slightly smaller than the original 90×90 design and vertically positioned to balance the text overlay.
- Shadow side uses a darker overlay than the default texture shadow.
- Top-left: rounded illuminated fraction, shown as a percent without a leading dot.
- Top-right: `PHASE` label with the current phase short name above it, title-cased, white, medium weight.
- Bottom-left: `NEW` label with the next calculated new moon date below it, white, medium weight; date is never in the past.
- Bottom-right: `FULL` label with the next calculated full moon date below it, white, medium weight; date is never in the past.
- Accent-colored moon values use `BangBarSettings.Key.accentColorHex`; non-accent values remain white.

**Phases (8):** New → Waxing Crescent → First Quarter → Waxing Gibbous → Full → Waning Gibbous → Last Quarter → Waning Crescent

**Shadow orientation:**

1. Convert the approximate ecliptic positions of the Sun and Moon to apparent equatorial right ascension and declination using the obliquity of the ecliptic. Let these be `(αs, δs)` and `(αm, δm)`.
2. Calculate the position angle of the Moon's bright limb, measured eastward from celestial north:
   ```
   χ = atan2(
       cos(δs) · sin(αs − αm),
       sin(δs) · cos(δm) − cos(δs) · sin(δm) · cos(αs − αm)
   )
   ```
3. Calculate local apparent sidereal time from J2000 days and observer longitude, then the Moon's hour angle `H = LST − αm`.
4. Calculate the Moon's parallactic angle for observer latitude `φ`:
   ```
   q = atan2(
       sin(H) · cos(φ),
       sin(φ) · cos(δm) − cos(φ) · sin(δm) · cos(H)
   )
   ```
5. The bright-limb angle relative to the local zenith is `χ − q`. `MoonIlluminationMask` is authored with its illuminated side pointing right rather than up, so add `90°`. SwiftUI screen coordinates have Y increasing downward, so mirror the final angle:
   ```
   screenRotation = −(degrees(χ − q) + 90°)
   ```
6. Recalculate from the live panel date. This makes the shadow orientation change with time, observer latitude, and longitude while the illumination fraction continues to determine the mask shape.

The mask is always authored with its illuminated limb on the right, for both waxing and waning phases. Its terminator is `x = (1 − 2 · illumination) · sqrt(radius² − y²)`. Never mirror it based on phase: the bright-limb angle already points toward the Sun. Screen right is not celestial east; looking at the sky, positive eastward angles run counterclockwise from up. Orientation regression checks run with `bash scripts/test_moon_geometry.sh` and compare the rotated mask against an independent 3D projection of sunlight.

The approximation is intended for a small visual widget rather than telescope pointing. The calculation lives in `MoonOrientation.swift`; `MoonPhase` continues to own phase, illumination, and full-moon timing. `MoonLocationService` owns permission requests, current coordinates, and manual-city resolution.

**Settings:**
- Enabled/disabled via the Moon toggle in General widget settings.
- Settings → Widgets → Moon contains an automatic-location toggle and manual city field.
- Automatic and manual coordinates are persisted separately, so a Core Location refresh never overwrites the selected fallback city.
- When automatic location is denied, disabled, or has not produced coordinates yet, the saved manual city is used. Automatic coordinates have no hardcoded default.
- The rows use text labels without decorative leading icons.

---

### GitHubWidget

**Goal:** Show a compact GitHub-style public contribution calendar using the user's accent color.

**Data source and loading:**
- The username is stored in `BangBarSettings.Key.githubUsername`; no token or GitHub authentication is required.
- `GitHubContributionsService` requests the user's public GitHub contribution HTML for each calendar year intersecting the trailing-year range and merges days by `data-date`.
- While the widget is active, contribution data refreshes every 30 minutes. A successful response is cached for the same interval.
- Requests identify the app with a `BangBar` user agent. Invalid usernames, parsing failures, and unavailable responses produce compact empty/error states.
- Successful results for the same username are cached in memory for three hours.
- `PanelContentView` owns `GitHubContributionsService`; `GitHubWidget` observes the injected service. Switching to Clipboard removes the widget view but must not destroy its loaded contribution state or visibly reinitialize it when returning.
- The service loads approximately 53 weeks so the footer can report the total for the trailing 365 days, even though only the latest 13 weeks are rendered.

**Display:**
- The widget is a static 150×110 surface; it does not scroll horizontally.
- It shows the latest 13 calendar weeks, approximately the last three months.
- Month labels appear above the grid. Labels too close to the following month are suppressed to avoid overlap.
- Only `Mon`, `Wed`, and `Fri` weekday labels are printed on the left.
- Empty past/today cells remain subtly visible; future dates are rendered as clear space with no square.
- Contribution levels 1–4 use increasing opacity of the current accent color. Level 0 uses a faint neutral square.
- Hovering a day opens the shared adaptive-width tooltip with either `No contributions on …` or the exact contribution count and date.
- The footer is centered below the grid and reads `N contributions in the last year` using the full trailing-year total.
- The GitHub name/header and decorative icon are not shown inside the widget, preserving room for the grid.

**Settings:**
- Enabled/disabled via the GitHub toggle in General widget settings.
- Settings → Widgets → GitHub contains the public username field and no decorative leading icon.
- An empty username shows `Add username in Settings` in the widget.

### SystemWidget visual details

- CPU and RAM charts use the same sparkline implementation and both include an accent-colored area gradient beneath the line.
- The gradient runs from accent color at `34%` opacity near the line to `2%` at the bottom.
- Sparkline grid dots use `8 pt` spacing, `1.25 pt` diameter, and white at `24%` opacity: denser but quieter than the original grid.
- The sparkline endpoint remains a 4×4 accent dot with glow.
- The filled center of the separate pulsing status indicator is 6×6; its outer ring remains 19×19.

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

### HabitsWidget

**Status:** ✅ Implemented.

**Goal:** Let the user define actions they intend to perform every day, mark each one complete directly in the expanded panel, and review enough history to understand consistency over time.

**Scope and states:**
- Every configured habit is daily; custom weekdays, frequencies, reminders, quantities, notes, and partial progress are out of scope for the first version.
- A habit has exactly two states for the current local day: incomplete and complete.
- Incomplete is the default. Clicking a row's status control or title toggles today to complete; clicking again returns it to incomplete.
- Past days can be corrected: clicking a day in a habit's history strip (widget or Settings) toggles that day. Marking a day before the habit's creation day backfills it by moving the creation day back to that date.
- Completed habits remain in their configured position. They are never hidden, moved to the bottom, or removed from the day's list.
- A newly created habit is incomplete for the current day. Renaming or reordering a habit preserves its identity and history.

**Layout and interaction:**
- Fixed `220×110` expanded widget, implemented in `HabitsWidget.swift`.
- Header is a single 16pt line matching other widget headers: an accent `checklist` icon, today's value such as `3/5`, and a segmented progress bar with one segment per habit. When every habit is done, the icon becomes `checkmark.seal.fill` and the value reads `All done`.
- The header reserves only the height required by its visible content so four rows fit before scrolling.
- Each habit row shows a seven-day history strip of small rounded squares for the trailing seven local calendar days (today last, outlined in the accent color while incomplete) and the current streak. Accent squares mean complete, neutral squares mean incomplete, and very faint squares mean the habit did not exist yet. Hovering a square shows its date and state; clicking toggles that day.
- The streak shows an accent `flame.fill` when today is done, an outlined dim `flame` when a streak exists but today is not done yet, and `–` without a streak.
- The habit list occupies the remaining height and scrolls vertically when it does not fit. The scroll view must not show a permanent scrollbar and must retain comfortable row hit targets.
- Whenever the panel closes, the habit list is reset to its first row without animation while hidden. The next opening must already be at the top; no visible reverse scrolling or opening jitter is allowed.
- Habit row buttons must not trigger AppKit focus-preserving auto-scroll. The ScrollView uses a native top default anchor and its identity is reset only after panel content becomes hidden; no programmatic `scrollTo` is allowed during view appearance.
- An incomplete row uses an accent-outlined status circle and near-white text.
- A complete row fills the status circle with the accent color and a black checkmark, and dims the title. Completed rows remain readable but visibly recede behind incomplete work.
- State changes animate with a short spring without changing row order. Rows highlight on hover.
- Long names truncate to one line in the widget; the full title is available through the shared tooltip behavior.
- Empty state reads `Add habits in Settings` with a small accent-colored status mark.
- The widget has no add, delete, rename, or reorder controls; configuration belongs to Settings.

**Daily rollover:**
- Day boundaries use `Calendar.autoupdatingCurrent.startOfDay(for:)`, so reset follows the user's current locale, calendar, time zone, and daylight-saving changes.
- Completion is stored against a local day identifier rather than being destructively cleared at midnight. When the observed day changes, the service publishes a fresh incomplete state for the new day and preserves previous records as history.
- The service checks the day when it starts, when the panel becomes active, after settings changes, and when the system reports a significant time or calendar-day change. The app does not need to remain running at midnight.
- Moving the clock or time zone backward must reveal the records belonging to the resulting local date rather than overwriting them.

**Data model and persistence:**
- `HabitDefinition`: stable UUID, title, sort order, and creation-day identifier.
- `HabitDayRecord`: local day identifier plus the set of completed habit UUIDs for that day.
- A small `HabitService` owns CRUD, ordering, completion toggles, rollover observation, statistics, serialization, and change publication.
- Persist definitions and day records as versioned `Codable` JSON in `UserDefaults` under dedicated `BangBarSettings.Key` values. Malformed data falls back safely to an empty collection without crashing the panel.
- Keep a rolling 365 days of records. Pruning never removes habit definitions.
- Deleting a habit requires confirmation and removes that habit plus its associated history. Renaming and reordering never rewrite history.
- No network, account, notification, calendar, or health permission is required.

**History and statistics:**
- Statistics count only dates on or after a habit's creation date; days before the habit existed are excluded from denominators.
- Settings → Widgets → Habits shows:
  - a summary strip: today's completed count, aggregate completion rates for the last 7 and 30 days, and the best streak with its habit;
  - a tracker with one row per habit: in-place name editing (saved on Return or focus loss), a clickable strip of the trailing 7–21 days sized to the available width, current streak, and 30-day completion rate; the drag handle and delete button appear on hover, and delete is also in the context menu;
  - a GitHub-style weekly activity heatmap filling the available width (up to 53 weeks) with month and weekday labels, a Less→More legend, and per-day completed versus available counts on hover.
- A streak is a run of consecutive eligible local days with that habit completed. Today's incomplete state does not break the current streak until the day has ended.
- Aggregate daily completion is `completed eligible habits / eligible habits`. Days with no eligible habits are excluded.
- Undoing today's completion updates the widget and all statistics immediately.

**Settings:**
- Enabled/disabled through a `Habits` toggle in Widgets → General and included in drag-and-drop widget ordering as `BangBarWidget.habits`.
- Widgets → Habits is a real secondary tab because it contains configuration and statistics.
- The Habits settings tab is a single column: summary strip, tracker (with the new-habit row as its last row), then activity heatmap. It uses the monospaced settings typography throughout.
- The configuration list supports adding, renaming, deleting, and drag-and-drop reordering.
- Habit titles are trimmed, must not be empty, and are limited to 80 characters. Duplicate titles are allowed because identity is UUID-based.
- Add and rename changes are persisted immediately. Delete presents a confirmation explaining that the habit's history will also be removed.
- The settings list and history/statistics view use the same shared `HabitService` data and update live after a widget toggle.

**Architecture and wiring:**
- `HabitService.swift` contains the persisted value types, storage migration/version handling, daily calendar logic, and testable statistics calculations.
- `HabitsWidget.swift` contains the widget and focused row/progress subviews.
- `SettingsView` owns the management and statistics surface but does not duplicate storage logic.
- `PanelContentView` receives or owns the shared service according to its existing service-lifetime pattern and only wires `HabitsWidget` into the ordered widget row.

### TranslatorWidget

- Fixed `150×110` widget implemented in `TranslatorWidget.swift`.
- Translates Russian to English and English to Russian with Apple's system Translation framework; no API key or remote service is required.
- The direction button swaps RU/EN. If a translation exists, the result becomes the new source text.
- Translation starts with Return or the submit button. The result can be copied to the clipboard.
- An expand button opens a resizable two-pane translator window for long messages, with scrollable source and result editors, clear/copy actions, and Command-Return translation.
- The selected direction persists in `UserDefaults`.
- Enabled/disabled through a `Translator` toggle in Widgets → General and included in drag-and-drop ordering as `BangBarWidget.translator`.
- Add `.habits` to `BangBarWidget`, use `PanelLayout.habitsWidgetWidth`, and extend enablement, ordering, width-budget validation, labels, and icon mapping without adding a separate panel-width constant.
- Add a dedicated settings asset (proposed name `widgetHabits`) consistent with the existing monochrome widget icon set.

**Acceptance criteria:**
1. The user can add, rename, delete, and reorder habits in Settings, and the widget reflects every change without relaunching.
2. Clicking an incomplete habit marks it complete; it stays in place, becomes dim white, and gains a strikethrough and checkmark.
3. Clicking a completed habit returns it to the near-white title and accent-ring incomplete state.
4. More habits than fit in `220×110` can be reached by vertical scrolling without expanding or overlapping the panel.
5. Reopening the app on the same date restores that day's states; opening it on a later local date shows all eligible habits incomplete while retaining prior history.
6. Seven-day, 30-day, per-habit streak, and 30-day history values follow the definitions above and update after every toggle.
7. Widget enablement, ordering, and panel width budgeting behave like existing optional widgets.
8. Empty, first-day, clock-change, time-zone-change, malformed-storage, rename, reorder, and confirmed-delete cases do not crash or corrupt other settings.

**Implementation plan:**
1. Add persisted models and pure date/statistics helpers, then cover rollover, streak, denominator, retention, and migration behavior with focused tests.
2. Implement `HabitService` CRUD, ordering, current-day toggling, `UserDefaults` persistence, pruning, and date-change observation.
3. Build the `220×110` widget with the approved row states, weekday strip, circular progress, seven-day history dots, current streak, scrolling, tooltip, and empty state.
4. Add `.habits` to widget metadata, settings keys/defaults, panel rendering, ordering, and width-budget calculations.
5. Build Settings → Widgets → Habits management, delete confirmation, 7/30-day summary, per-habit streaks, and 30-day history.
6. Add the matching widget icon asset and accessibility labels for toggle rows, completion controls, progress, and statistics.
7. Build and manually verify live updates, persistence across relaunch, midnight/time-zone rollover, scrolling, panel width limits, and behavior with zero, one, and many habits.

---

### CountdownWidget — Implemented

**Status:** ✅ Implemented.

**Goal:** Show a user-created countdown to a chosen future date.

**Data source:** Local app state only — no network or system permission required.

**Layout:** Fixed 150×110 widget (`PanelLayout.countdownWidgetWidth`), implemented in `CountdownWidget.swift`, with `CountdownService.swift` (persistence), `CountdownEditorView.swift` (create/edit window) and `CountdownFormatter.swift` (pure remaining-time formatting).

**Empty state:**
- Header row: dim `hourglass` icon on the left and a `plus` icon button on the right (icons as in the display below, with the hourglass dim white instead of accent).
- Centered text: `No countdown` with `pick a date` below it.
- The plus button, a click anywhere on the widget, or the context menu's `New Countdown…` opens the creation window.

**Create/edit flow:**
- `CountdownEditorWindowController` presents `CountdownEditorView` in a small dark titled window (`New Countdown` / `Edit Countdown`), the same way the add-reminder window is presented; the app is activated so the title field receives focus.
- Fields:
  - `TITLE` text field, trimmed, limited to 80 characters;
  - `DATE` compact date picker (defaults to seven days from today for a new countdown);
  - `TIME` switch; when on, a compact hour/minute picker appears and the countdown targets that exact time. When off, the countdown targets the start of the chosen local day.
- A live status line under the fields previews the result, e.g. `In 2y 3m 4d`.
- Actions:
  - `Cancel` (Escape) closes without saving;
  - `Create` (Return; labelled `Save` when editing) saves the countdown and updates the widget immediately, then shows a brief confirmation and closes;
  - `Delete` (only when editing) removes the countdown and returns the widget to the empty state.
- `Create`/`Save` is disabled until the trimmed title is non-empty. The date picker always holds a valid date.
- **Past dates are allowed, not rejected:** the status line switches to an accent-colored `Elapsed · the widget will show done`, and the widget shows `done`. This keeps renaming or editing an already-elapsed countdown possible without forcing a new date.

**Display:**
```
⌛                    ✎
       Trip to Tokyo
         2y 3m 4d
   ( JAN 17, 2029 · 05:55 )
```
- Header: `16 pt` tall row with two bare `11 pt` bold symbols, no background. Left: accent `hourglass` (`hourglass.bottomhalf.filled` once elapsed). Right: `pencil` edit button, white 50%.
- Everything below the header is centered horizontally; no divider lines and no glow.
- Title on one line, 13 pt semibold, near-white, truncated with `…`, pinned `2 pt` under the header. The date pill is pinned to the bottom and the remaining time is centered vertically between the title and the pill.
- Remaining time: 30 pt bold rounded, `.monospacedDigit()`, scaled down to fit (minimum 0.6) for very long ranges. The first (most significant) number uses the shared accent color, later numbers are near-white, and unit letters are 16 pt semibold and dim. `done` is shown entirely in the accent color.
- Target date pill: 9 pt monospaced, white 60%, uppercased (e.g. `JAN 17, 2029` or `JAN 17, 2029 · 05:55` when a time is set), in a capsule with white 6% fill and a `1 pt` white 10% border, `10 pt` × `3 pt` padding.
- Remaining time is calculated from the panel clock (`PanelContentView`'s shared timer), which runs at least once per minute while the countdown is on the visible expanded page and is refreshed whenever the panel opens.
- Compact format produced by `CountdownFormatter.remaining(now:target:includesTime:calendar:)`, using `Calendar.dateComponents` (so month ends follow Foundation clamping, e.g. Jan 31 → Feb 28 is `1m`):
  - at least one month left: years, months and days, e.g. `2y 3m 4d`;
  - under a month with a time: days and hours, e.g. `14d 6h`;
  - under a day: hours and minutes, e.g. `6h 20m`; under a minute: `<1m`;
  - date-only targets count whole calendar days from today and never show hours (`tomorrow` is `1d` even late in the evening);
  - zero-valued units are omitted (`1y 4d`, `14d`, `20m`);
  - `done` once the target instant (or, for date-only targets, the target day) has arrived.

**Persistence:**
- `CountdownService.shared` (`@MainActor final class`, `ObservableObject`) stores a versioned `Codable` JSON payload in `UserDefaults` under `BangBarSettings.Key.countdownData`.
- Persisted fields: title, target date/time, `includesTime`, `createdAt`, `updatedAt`. Editing keeps `createdAt` and refreshes `updatedAt`.
- Malformed or unknown-version data falls back to the empty state.
- V1 supports one active countdown. Multiple countdowns can be considered later if there is a clear UI need.

**Interactions:**
- Empty: plus button / widget click creates a countdown.
- Existing countdown: the pencil button or a click on the widget reopens the window to edit/replace it.
- Delete is available in the edit window and as `Remove Countdown` in the widget's context menu.

**Settings:** Enabled/disabled via a `Countdown` toggle (icon asset `widgetCountdown`, Tabler-style hourglass) in Widgets → General, default off (`BangBarSettings.Key.showCountdownWidget`), and included in drag-and-drop ordering and page assignment as `BangBarWidget.countdown`. Existing saved widget orders get it appended automatically. No separate Countdown settings tab.

**Tests:** `bash scripts/test_countdown_formatter.sh` compiles `CountdownFormatter.swift` with `Tests/CountdownFormatterTests.swift` and checks long ranges, under a month, under a day, date-only targets, exactly-now/past `done`, month-end clamping and daylight-saving changes.

---

### Companion Widget

**Status:** ❌ Dropped — not planned. The existing code and saved state remain in the project but stay hidden: `.companion` may remain in the internal `BangBarWidget` enum and legacy saved ordering for compatibility, but it must be excluded from user-visible widget cases, settings tabs, ordering controls, panel width calculation, and runtime rendering, and its runtime service is not started.

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

### AIUsageWidget

**Goal:** Show how much of the Codex and Claude Code subscription rate limits have been used, mirroring the always-on-menu-bar UX of [CodexBar](https://codexbar.app) but scoped to the two providers the user actually uses. Fully automatic — no API key entry, no settings beyond the enable toggle.

**Concept:** BangBar reuses the OAuth session each CLI already created on this Mac (the same approach CodexBar documents in its own provider guides) and calls the same usage endpoints the official `codex` and `claude` CLIs call. It never logs in, never stores a password, and never writes back to either CLI's credential file.

**Codex data source:**
- Reads `~/.codex/auth.json` (or `$CODEX_HOME/auth.json` when set). Shape:
  ```json
  {
    "OPENAI_API_KEY": null,
    "tokens": { "id_token": "...", "access_token": "...", "refresh_token": "...", "account_id": "..." },
    "last_refresh": "2026-08-01T12:00:00Z"
  }
  ```
- Calls `GET https://chatgpt.com/backend-api/wham/usage` with headers `Authorization: Bearer <tokens.access_token>`, `ChatGPT-Account-Id: <tokens.account_id>`, `User-Agent: BangBar`.
- Response:
  ```json
  {
    "plan_type": "pro",
    "rate_limit": {
      "primary_window": { "used_percent": 15, "reset_at": 1735401600, "limit_window_seconds": 18000 },
      "secondary_window": { "used_percent": 5, "reset_at": 1735920000, "limit_window_seconds": 604800 }
    }
  }
  ```
  `primary_window` and `secondary_window` do **not** reliably mean "5h" and "7d" — some ChatGPT plans expose only one pooled window (e.g. a weekly-only limit shared across Codex/Work/Workspace Agents), which still arrives as `primary_window`. The displayed duration label (`5h`, `36h`, `7d`, …) is derived from that window's own `limit_window_seconds`, never assumed from its position in the response. `reset_at` is Unix seconds.
- BangBar is read-only: it never redeems `refresh_token` or rewrites `auth.json`. Token refresh remains owned by the Codex CLI.

**Claude data source:**
- Credential lookup order:
  1. `~/.claude/.credentials.json` → `.claudeAiOauth.accessToken`.
  2. macOS Keychain generic-password item named `Claude Code-credentials` (the item Claude Code itself creates), read via `/usr/bin/security find-generic-password -s "Claude Code-credentials" -w` through `Process` — the same `Process`-based system-call pattern already used for `osascript` elsewhere in this app. The JSON payload is parsed for `.claudeAiOauth.accessToken`; an item containing only `.mcpOAuth` (no `claudeAiOauth`) is treated as Claude being unavailable.
  - The first Keychain read triggers a normal macOS access prompt naming BangBar; choosing "Always Allow" stops future prompts. A "Deny" is treated the same as "Claude not signed in" (row hidden), never surfaced as an error.
- Calls `GET https://api.anthropic.com/api/oauth/usage` with headers `Authorization: Bearer <accessToken>`, `anthropic-beta: oauth-2025-04-20`.
- Response fields used: `five_hour.utilization` / `five_hour.resets_at` (labeled `5h`), `seven_day.utilization` / `seven_day.resets_at` (labeled `7d`) — these labels are fixed because Anthropic's field names are a stable contract, unlike Codex's positional windows. Model-scoped windows (`seven_day_sonnet`, `seven_day_opus`) and `extra_usage` are ignored in v1.

**Availability and error handling:**
- A provider with no readable credentials is treated as "not in use" and its row is omitted entirely — no error state, no empty placeholder for that provider alone.
- `401`/`403` on either endpoint also means "not signed in" for display purposes (token expired/revoked) and hides the row the same way.
- A transient failure (network error, 5xx, decode failure) for a provider that previously loaded successfully keeps showing its last good snapshot rather than disappearing; no explicit "stale" marker in v1.
- When neither provider has usable credentials, the widget shows one quiet empty state: a gauge icon and "Sign in with `codex` or `claude` in Terminal".

**Service:** `AIUsageService: ObservableObject`
- `@Published private(set) var codex: ProviderUsage?` and `@Published private(set) var claude: ProviderUsage?`, each `nil` when that provider is unavailable.
  ```swift
  struct ProviderUsage {
      let planLabel: String?
      let primary: UsageWindow?    // Codex: primary_window; Claude: five_hour
      let secondary: UsageWindow?  // Codex: secondary_window; Claude: seven_day
  }
  struct UsageWindow {
      let label: String   // e.g. "5h", "36h", "7d" — derived from the window's own duration for Codex, fixed for Claude
      let usedPercent: Int
      let resetsAt: Date?
  }
  ```
- Polls both providers independently every 5 minutes while the widget is visible, matching `GitHubContributionsService`'s `.task(id:)` + `Task.sleep` loop; publishes on the main actor.
- All file, Keychain, and network work happens off the main thread; only the published snapshot hops to `DispatchQueue.main` / `@MainActor`, per the project's service convention.

**Display:**
- Fixed 140×110 surface, no scrolling.
- Header row: small gauge SF Symbol + "AI Usage" label.
- One block per available provider, in fixed order Codex then Claude: provider name + plan label (right-aligned, e.g. "Pro", "Max"), then one thin capsule progress bar per available window (primary, then secondary — Codex plans without a separate weekly cap show only one bar), each labeled with its actual duration and, trailing the bar on the same line, the used percentage plus a short countdown to when it unlocks (e.g. `100% ·3d`, `22% ·14h`, `4% ·22m`, or `·now` once the reset time has passed). A window at ≥90% used switches its bar and percentage to orange; the countdown stays dim regardless. The countdown is computed at render time from the window's `resetsAt`, so it advances on each 5-minute refresh rather than ticking live.
- Only one block renders when just one provider is signed in; the block fills the widget's vertical space instead of leaving a gap.
- No manual refresh control in v1.

**Settings:**
- Single "AI Usage" toggle in Settings → Widgets → General (`BangBarSettings.Key.showAIUsageWidget`, default off, like GitHub/System/Habits/Translator). No dedicated settings sub-tab — there is nothing to configure.

**Constraints:**
- Only calls the same public-facing endpoints the official CLIs call, using the user's own already-authorized session; no API key is ever entered or committed.
- No third-party dependencies; `URLSession` + `Codable` + `Process` (for the Keychain read) only.
- Included in widget ordering as `BangBarWidget.aiUsage`.

---

## Live Activities

Short notices that grow out of the notch for system events, so the notch reacts on its own instead of only on hover.

**Presentation:**
- All notch notices go through one `NotchNoticeCenter` owned by `AppDelegate`: one click-through `NSPanel` above the status bar, never part of the hover panel lifecycle. A new notice of any kind (layout switch or live activity) replaces the visible one, and the center drops notices while the expanded panel is open. The black body grows out of the notch through the same stem-and-fillet shape (`NotchNoticeShape`); on displays without a notch it floats below the menu bar with a thin light outline.
- Content: an SF Symbol tinted with the accent color, a white title, and a dimmer detail, on one line (e.g. `bolt.fill  Charging  82%`).
- Visible for 2.4 s, then shrinks back into the notch. A new activity replaces the current one immediately.
- Shown on the screen that has the notch, otherwise on the main screen.
- Not shown while the expanded panel is open; the panel already shows the system state. A visible notice is not hidden when the panel expands.

**Activities:**
- **Power** (`PowerSourceMonitor`): when the power adapter is connected or disconnected (`notify_register_dispatch` on `kIOPSNotifyPowerSource`, which posts only when the providing source switches, compared against the previous `kIOPSPowerSourceStateKey`). Connected shows `bolt.fill` · `Charged` when full, `Charging` while charging, otherwise `Plugged in` (charge limit or optimized charging hold) · battery percent; disconnected shows the battery symbol for the level (`BatteryStatus.symbolName`, shared with `SystemWidget`) · `On battery` · percent. Macs without an internal battery never post it. The state at launch is recorded without a notice.
- **Bluetooth audio** (`AudioOutputMonitor`): when the default output device changes to a device whose transport type is Bluetooth or Bluetooth LE (`kAudioHardwarePropertyDefaultOutputDevice` listener). Shows `headphones` · device name · `Connected`. Switching away from Bluetooth shows nothing. No Bluetooth permission is needed because only Core Audio is read.

- **Volume** (`AudioOutputMonitor`): whenever the default output device's volume or mute changes, from any source (keys, Control Center, AirPods controls). Listens to `kAudioHardwareServiceDeviceProperty_VirtualMainVolume` and `kAudioDevicePropertyMute` on the output scope and moves the listeners when the default output device changes; a device switch alone shows nothing, and volume changes in the first second after a switch are ignored (Bluetooth devices push a volume sync on connect, which would replace the `Connected` notice). Shows a speaker symbol for the level (`speaker.slash.fill` when muted or at 0, otherwise `speaker.wave.1/2/3.fill`), a `120 pt` accent-colored level bar and the percent. Visible for 1.5 s; repeated changes update the bar in place and restart the timer.
- **Replace system HUD** (`VolumeKeyInterceptor`, optional): a HID-level (`cghidEventTap`) event tap for `NX_SYSDEFINED` media key events swallows the key-down of volume up / down / mute and applies it itself, so the system HUD never appears. A session-level tap is too late: the system has already handled the key there. Key-ups pass through; on their own they do nothing. Option+Shift is read from the event flags and the live session modifier state, because media key events do not always carry them. The tap is an `EventTap`, the wrapper shared with the layout switcher: it installs on the main run loop once Accessibility is granted (polling every 2 s until then), re-enables itself after a timeout, and is driven by a single `isEnabled`. Steps are 1/16 of the range, 1/64 with Option+Shift (the system's fine step). Volume up while muted unmutes. A press that changes nothing (up at full volume, down at zero) fires no Core Audio listener, so the interceptor presents the volume notice itself. Mute passes through when the device has no settable main-element mute. Needs Accessibility; without it the tap cannot be created and the keys keep reaching the system (both HUDs then show).
  - Works through macOS 26. On macOS 27 the system handles the volume keys before even a HID-level tap (verified with real keys: the swallowed key-down still moves the volume a second step about 6 ms after ours). So 150 ms after each intercepted press the interceptor compares the volume and mute with what it set; when the mute state differs or the volume moved more than half a step further in the press direction (smaller differences are device quantization), it restores the single step the user asked for, stores the macOS major version in `volumeKeyInterceptionFailedOSMajor`, and interception stays off on that major version (a new major macOS tries again). `BangBarSettings` owns that record; the controller and the settings row both ask it. The settings row is then disabled with a subtitle explaining that the system indicator cannot be hidden on this version. A press that passes through, or disabling the interceptor, cancels the pending check. Keys also pass through unchanged while the expanded panel is open (notices are suppressed there) and when the output device has no settable volume, so the system can handle them.

**Settings:** Appearance → `LIVE ACTIVITIES` card:
- `Charging` (`liveActivityPowerEnabled`, default on) and `Bluetooth audio` (`liveActivityAudioEnabled`, default on). Disabling a toggle stops showing that activity; the monitors keep running because they cost nothing between events.
- `Volume` (`liveActivityVolumeEnabled`, default on).
- `Replace system HUD` (`volumeHUDReplacesSystem`, default on), disabled while `Volume` is off. Its subtitle says it needs Accessibility. The interceptor is enabled or disabled as soon as either toggle changes (KVO on the two defaults keys, not `UserDefaults.didChangeNotification`). Repeated volume notices with unchanged geometry only swap the content and restart the hide timer.

## Keyboard Layout Switcher

**Goal:** Fix text typed in the wrong keyboard layout (`ghbdtn` → `привет`, `руддщ` → `hello`) without retyping it by hand. Delivered in two phases: manual conversion by hotkey first, automatic detection later on top of the same machinery.

**Not a panel widget.** It is a background feature with no `BangBarWidget` case and no panel UI. `KeyboardSwitcherService` is owned by `AppDelegate`, starts at launch, and stays idle unless enabled in Settings.

### Files

- `KeyboardWordBuffer.swift` — pure logic with no AppKit/Carbon: the last-word keystroke buffer and the double-tap modifier detector. Covered by `Tests/KeyboardWordBufferTests.swift` (`scripts/test_keyboard_switcher.sh` runs all keyboard tests).
- `KeyboardLayouts.swift` — Text Input Sources wrapper: enabled keyboard layouts, current layout, selecting a layout, translating key codes to text with `UCKeyTranslate`, converting arbitrary text between layouts.
- `EventTap.swift` — event tap wrapper shared with the volume key interceptor: install once Accessibility is granted, re-enable after a timeout.
- `KeyboardSwitcherService.swift` — `CGEventTap`, buffer bookkeeping, trigger detection, choosing word vs. selection mode, last-word correction.
- `SelectedTextConverter.swift` — selection conversion through a pasteboard round-trip.
- `SyntheticKeyboard.swift` — posting marked synthetic key events (Backspace, Unicode text, ⌘C/⌘V, ⇧←), either at session level or through the tap proxy.
- `KeyboardAutoSwitchRules.swift` — pure decision rules for automatic conversion.
- `KeyboardLetterPatterns.swift` — pure lookup of letter combinations a language never uses, loaded from the bundled `KeyboardImpossibleLetters-en.txt` / `KeyboardImpossibleLetters-ru.txt` (generated by `scripts/build_keyboard_letter_patterns.py`; do not edit by hand).
- `KeyboardAutoSwitcher.swift` — spell-checker languages, ignored and learned words, excluded apps; produces an `AutoSwitchPlan` for a finished word and learns manual conversions.
- `KeyboardLearnedWords.swift` — pure storage for learned words.
- `KeyboardSwitcherSettingsView.swift` — Settings › Keyboard section.
- `KeyboardSwitchNotice.swift` — the notice shown at the text caret (or the notch) after an automatic switch.
- `FocusedTextElement.swift` — Accessibility lookups on the focused text field: selected range, caret line and field frame.

### Phase 1 — Manual Conversion (Implemented)

**Trigger** (Settings › Keyboard):
- `Double Shift` (default): two taps of either Shift within `0.4 s`. Each tap must be a clean press/release (held under `0.3 s`) with no other key, modifier, or mouse click in between, so typing capitals never triggers it. Shift events are passed through to apps unchanged.
- `Custom shortcut`: recorded with `ShortcutRecorderField` (key + modifiers, or `fn`). The matching key-down and key-up are swallowed so the focused app never sees them.

**Action:** converts text in the focused app into the next enabled keyboard layout and switches the system input source to that layout, so typing continues correctly.
- **Word mode** — when the word buffer is not empty (the user was just typing): converts the last typed word.
- **Selection mode** — when the word buffer is empty: converts the selected text. Selecting text by mouse, arrows, or ⌘A always resets the word buffer, and typing replaces any selection, so the two modes never compete.
- Pressing the trigger again without typing cycles to the next layout; with two layouts it toggles back to the original text (selection mode reselects the pasted text for this).
- If there is nothing to convert (empty buffer and no selection, or fewer than two enabled layouts) the trigger does nothing — no beep.
- A trigger while a selection conversion is still running is ignored.

**Word buffer** (keystrokes, not characters):
- Stores `(keyCode, shift, capsLock)` for each printable key-down, plus the layout the word was typed in. Storing key codes keeps the word layout-independent: the same keys are re-translated through any layout.
- Every printable key belongs to the word, including keys that are punctuation in one layout and letters in another (`,` ↔ `б`, `;` ↔ `ж`, `[` ↔ `х`, `` ` `` ↔ `ё`).
- Space after a word is kept as trailing spaces; the next printable key starts a new word. Conversion retypes the trailing spaces after the converted word.
- Backspace removes trailing spaces first, then the last keystroke; deleting a whole word brings back the word before it.
- Up to 3 earlier words separated from the current one only by spaces are kept as history (cleared by anything that resets the buffer). Automatic conversion uses it to fix short words before a switched word.
- Reset on: Return, Tab, Escape, arrows, Home/End/Page keys, forward delete, function keys, any key with ⌘/⌃/⌥, any mouse click, frontmost app change, or a key typed in a different layout than the rest of the word.
- Lives only in memory, holds at most the current word, is never logged or written to disk.

**Conversion:**
1. Translate the buffered keystrokes through the word's layout (text currently on screen) and through the next enabled layout (replacement), using `UCKeyTranslate` with the layout's `kTISPropertyUnicodeKeyLayoutData`.
   - The on-screen text is translated with dead-key composition, so layouts like U.S. International delete the right number of characters (`'` + `e` → `é` is one character; a pending dead key counts as one). The replacement is translated without dead keys, producing literal characters.
   - Whether a key is printable is decided by translating it through the current layout, not from the event's characters — dead keys (`'` = `э`, `` ` `` = `ё` in U.S. International) report no characters but are still part of the word.
2. Post Backspace × (on-screen length + trailing spaces).
3. Post the replacement text + trailing spaces as Unicode key events (`keyboardSetUnicodeString`), independent of the active layout, so there is no race with the input-source switch.
4. `TISSelectInputSource` the target layout; the buffer keeps the keystrokes and records the new layout for further cycling.
- All posted events carry explicit modifier flags (none for Backspace and text, so a held hotkey modifier never turns Backspace into ⌥⌫) and a private `eventSourceUserData` marker so the tap ignores its own events.

**Selection conversion** (`SelectedTextConverter`):
1. Check the focused element's `kAXSelectedTextRangeAttribute` (`0.25 s` messaging timeout). A zero-length selection aborts. Apps that do not expose it (many Electron apps and web views) fall through to the clipboard probe.
2. Snapshot every pasteboard item and type, suspend Clipboard History capture for the whole operation (`ClipboardHistoryService.suspendCapture()` / `resumeCapture()`; on resume the pasteboard's current state is adopted as already seen, not captured), post ⌘C, and wait up to `0.5 s` for `changeCount` to change. No change means nothing was selected — abort without touching the pasteboard.
3. Abort and restore if there is no plain text, or if Accessibility could not confirm a selection and the copied text ends with a line break — VS Code and JetBrains copy the whole current line when nothing is selected.
4. Source layout = the enabled layout that can type the most letters of the text; target = the next enabled layout. Each character is mapped back to its key in the source layout (`(keyCode, shift)`, main keys preferred over keypad) and translated through the target. Characters the source layout cannot type (text already in the target layout, emoji, line breaks) are kept as is, so mixed text like `ghbdtn мир` becomes `привет мир`.
5. Write the result with `org.nspasteboard.TransientType` (so third-party clipboard managers skip it), post ⌘V, then ⇧← × length to reselect it (only up to 1,000 characters), and select the target layout.
6. After `0.4 s` (the app reads the pasteboard while handling ⌘V) restore the snapshot, then resume capture.

**Layouts:** enabled, selectable keyboard layouts (`kTISTypeKeyboardLayout`) with Unicode layout data, in system order. Input methods (e.g. Japanese) are ignored; their underlying keyboard layout is used.

**Event tap:**
- Session-level active `CGEventTap` on the main run loop for key-down, key-up, flags-changed, and mouse-down events.
- Re-enabled automatically after `tapDisabledByTimeout` / `tapDisabledByUserInput`.
- Secure input (password fields, Terminal secure keyboard entry) hides keystrokes from the tap, so passwords never enter the buffer.

**Permission:** requires Accessibility (System Settings › Privacy & Security › Accessibility). Enabling the switcher without access shows the system prompt; while enabled and not yet trusted the service rechecks every `2 s` and installs the tap as soon as access is granted.

### Phase 2 — Automatic Conversion (Implemented)

Off by default; enabled with "Switch automatically" in Settings › Keyboard (only shown while the switcher is on).

**When:** on Space, Return, or keypad Enter (without ⌘/⌃/⌥) right after a word — the buffer is not empty and has no trailing spaces yet — and the frontmost app is not excluded.

**Decision** (`KeyboardAutoSwitcher` + pure `KeyboardAutoSwitchRules`, covered by `Tests/KeyboardAutoSwitchRulesTests.swift`):
- Each layout's spell-check language is the first of its `kTISPropertyInputSourceLanguages` that `NSSpellChecker` supports (`en`, `ru`). Layouts without a supported language never take part.
- For every other enabled layout in cycle order, translate each keystroke in both layouts. Convert into the first layout where the typed word is **not** a word and the candidate **is**:
  - Edge keys outside the candidate's letters are punctuation and are not spell-checked (`ghbdtn?` → `привет,`, `руддщб` → `hello,`). A typed letter may only become sentence punctuation (`,.;:!?'"()`) there — `ещё` must never be judged as `to` after its `ё` turns into `§`.
  - The candidate core may contain only letters, `-`, and `'` (no digits).
  - The typed word counts as a word only if it has no punctuation inside (the spell checker skips punctuation, so `dc§` for `всё` would pass as `dc`) and `NSSpellChecker` accepts it.
  - Candidates of 3+ letters must pass `NSSpellChecker`. Two-letter candidates convert only into a short list of common words (`не`, `да`, `на`, … / `it`, `is`, `to`, …). Single letters never convert on their own.
- **Words before a switched word:** when a word switches, the words right before it in the history (same original layout, not yet converted) switch with it while each becomes a common short word in the target language, including single letters (`я в с к у о и а` / `I a`): `z nt,z` → `я тебя`, `vs c nj,jq` → `мы с тобой`. The switched word is the evidence a dictionary cannot give for `z` alone. English `a` / `I` typed in Russian become `ф` / `Ш`, which are not Russian words, so English text is unaffected.
- **Unknown in both dictionaries** (slang like `закомить`, `пофиксить`, names): converts only on letter-shape evidence (`KeyboardAutoSwitchRules.isUnknownWordConvertible`), otherwise nothing happens (`kubernetes`, `json`, `privet`):
  - The candidate core has at least 4 letters, letters only, is lowercase or capitalised (never `CGEvent`-style identifiers or ALL-CAPS acronyms), its language has a letter-pattern table, and it contains no letter combination that language never uses.
  - Then either the typed core has at least 2 letter pairs/triples its own language never uses (`pfrjvbnm` has `vb`, `frj`, `bnm`, `nm$`) — one is not enough, code prefixes like `cgevent` have one —
  - or the candidate has at least 5 letters, is 1 edit (case-insensitive Levenshtein) from one of `NSSpellChecker`'s guesses, and the typed word is more than 1 edit from all of its own guesses (`rhby;` → `кринж`). Guesses cost 5–20 ms each, so this runs only when the letter rule did not decide; the letter rule itself takes under 1 ms.
- **Letter-pattern tables:** a pair or triple (`^` / `$` mark word edges) is impossible when it never occurs in a large word list (English: macOS `/usr/share/dict` web2/web2a/words; Russian: hunspell-ru stems by A. Lebedev, BSD-style licence) and also never occurs in a running-text corpus (random Wikipedia intros), which removes inflected forms the stems miss. Nothing containing `ё` counts as impossible, because word lists often spell it `е`. Triples whose own pairs are already impossible are left out. Only English and Russian have tables; other languages never take part in unknown-word conversion.
- Words in the ignored list are skipped.
- **Learned words** convert without any dictionary check — this is how slang and terms the dictionaries lack (`гитхаб`, `деплой`) get switched. See below.
- Measured on this machine's U.S. International – PC / Russian – PC dictionaries: zero false positives on a mixed English/Russian/code-word sample; ~70–80% of wrong-layout words fixed by the dictionaries alone (misses were slang, abbreviations, single letters).
- Unknown-word conversion, measured on held-out Wikipedia words neither dictionary knows (tables built without them): Russian typed in English 89% converted, 0 of 4,621 Russian words typed correctly converted; English typed in Russian 84% converted, 5 of 2,797 English words typed correctly converted (rare acronyms and names; ALL-CAPS acronyms are now excluded). Remaining misses are mostly short words and transliterated foreign names.
- Dictionaries and letter-pattern tables are warmed up / loaded when the feature turns on (tables again when enabled layouts change), so the first check never stalls the tap.

**Correction:** done synchronously inside the tap callback and posted with `CGEventTapPostEvent` through the tap proxy, so the deletes, the replacement, and a copy of the boundary key reach the app in order before any key the user pressed afterward. The original boundary event is swallowed. The target layout is selected and the buffer keeps the word (in the new layout) plus the space.

**Undo:**
- Backspace immediately after an automatic switch on Space restores the typed words (including short words switched with it), consumes the space (as Backspace would), switches back to the original layout, and counts the undo for the typed word (`keyboardSwitcherUndoCounts`). On the 5th undo of the same word (`KeyboardAutoSwitcher.undosBeforeException`) it is added to the ignored list, its count is dropped, and it is forgotten if it was learned; before that the word keeps switching.
- Triggering a manual conversion right after an automatic switch counts as the same undo (and is not learned).
- Any other key, click, or app switch ends the undo window. Return has no undo (the text may already be sent).

**Learning from manual conversions** (`KeyboardLearnedWords`, covered by `Tests/KeyboardLearnedWordsTests.swift`):
- Converting the last word with the trigger records `(source layout, target layout, converted word core)`, e.g. `us → ru, гитхаб`. From then on automatic switching converts that word from that layout whenever its candidate core matches, regardless of case or edge punctuation (`Гитхаб`, `гитхаб,`). Learned words work only while automatic switching is on.
- The lesson is relative to the word as first typed: pressing the trigger repeatedly (cycling layouts) re-learns the final result and forgets the intermediate ones; converting back to the layout it was typed in forgets it.
- Never learned: words whose typed core is a real word in the typed layout (so a stray conversion of `hello` cannot break English), results shorter than 2 letters, manual reverts of an automatic switch, and selection conversions.
- Learning a word removes it from the ignored list and resets its undo count; the 5th undo of a learned switch forgets it and ignores it.
- At most 500 entries; re-learning moves an entry to the end and the oldest drop out first.

**Settings** (stored as newline-separated strings):
- `keyboardSwitcherAutoEnabled` — default `false`.
- `keyboardSwitcherExceptions` — ignored words (lowercased typed form), shown in Settings as "Ignored words" with a Clear button (which also resets the undo counts).
- `keyboardSwitcherUndoCounts` — undos per typed word (lowercased) not yet ignored, one `word<TAB>count` per line.
- `keyboardSwitcherLearnedWords` — learned words, one tab-separated `source target word` per line, shown as "Learned words" with a Clear button.
- `keyboardSwitcherExcludedApps` — bundle IDs with no automatic switching (the manual trigger still works). Defaults: Terminal, iTerm2, Ghostty, Warp, Xcode, VS Code. Apps are added via an open panel and removed per row.

**Switch notice** (`KeyboardSwitchNotice.swift`, setting `keyboardSwitcherShowsNotice`, default on, "Show what was changed" in the Automatic card):
- After every automatic switch, `original → replacement` (including short words switched with it; dimmed original, accent arrow, white replacement, 13 pt medium) is shown for `1.8 s`, then collapses. A new switch while it is visible updates the text and restarts the timer; an undo dismisses it immediately. Manual conversions show nothing.
- Placement: next to the text caret when the focused app exposes it through Accessibility (`kAXSelectedTextRangeAttribute` + `kAXBoundsForRangeParameterizedAttribute`, falling back to the bounds of the character before the caret; field frame from `kAXPosition`/`kAXSize`; looked up off the main thread with a `0.25 s` messaging timeout). The body sits above the focused field (`6 pt` gap) when the field is at most `120 pt` tall (inputs, chat boxes — so it never covers the field), otherwise above the caret line (`14 pt` gap, which also clears the field's own padding); it grows upward. When there is no room above within the screen's visible frame it sits the same distance below and grows downward. Its right edge is `14 pt` past the caret so the replacement ends over the replaced word, clamped to the visible frame. It is a plain rounded body (no stem) with a `1 pt` white 14% stroke. Otherwise (no caret, e.g. many Electron apps and web views) it grows out of the notch as below.
- Notch shape: a stem exactly the notch's width behind the physical notch, flaring through `8 pt` concave fillets into a `30 pt` tall body with `12 pt` corners. The body is the text width plus padding, at least notch width + 40 pt, at most 300 pt (longer text truncates in the middle). Because only the notch-wide stem overlaps the menu bar row, the compact panel's artwork and indicator stay visible; the body hangs below the compact panel.
- Displays without a notch: a rounded body floating `6 pt` below the menu bar.
- Reveal: spring (`response 0.32`, `damping 0.82`) of the body height from 0; hide: `0.22 s` ease-in, then the window is ordered out.
- Shown through the shared `NotchNoticeCenter` (see Live Activities): a borderless, non-activating, click-through `NSPanel` one level above the hover panel, on all Spaces and over full-screen apps; the notch fallback uses `NSScreen.main`. It never touches the hover panel's lifecycle and is skipped while the hover panel is expanded. It replaces a visible live activity, and an undo dismisses only a layout switch notice.

**Not yet implemented:** letter-pattern tables for languages other than English and Russian.

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
- `KEYBOARD`
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
- Every secondary-tab button uses the full visual tab rectangle as its hit target, not only the text glyphs.
- Sidebar navigation rows likewise use the full highlighted row as their hit target while retaining their centered, fixed-width layout.
- Closing and reopening Settings always returns to `WIDGETS → General`, regardless of the previously selected sidebar item or widget tab.
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
- Toggle: GitHub — show/hide `GitHubWidget`
- Toggle: Focus Timer — show/hide `PomodoroWidget`
- Toggle: Countdown — show/hide `CountdownWidget`
- Toggle: Notion — show/hide `NotionWidget`
- Toggle: Habits — show/hide `HabitsWidget`
- Toggle: Mirror — show/hide `MirrorWidget`

**Shared tooltips:**
- Tooltip width is content-adaptive: short text hugs its content, with a minimum width of `44 pt`.
- Long text wraps at a maximum tooltip width of `260 pt`; height is then calculated from the wrapped text.
- Tooltips are clamped to the active screen's visible frame and suppressed during panel transitions to avoid detached or stale overlays.

**Permissions section:**
- Toggle: Open BangBar at login (via `SMAppService`)
- Camera: shows authorization status, requests access or opens System Settings
- Calendar: shows authorization status, requests full access or opens System Settings
- Location: requested from the Moon settings when automatic location is enabled; denial falls back to the saved city
- Automation: opens System Settings › Privacy › Automation (required for Spotify/Music AppleScript control)
- Accessibility: shows trust status, shows the system prompt or opens System Settings › Privacy › Accessibility (required for the keyboard layout switcher)

**Appearance section:**
- Accent color picker is shown as a wide swatch button with the current hex value; clicking it opens the system color panel, stores the value as a hex string in `UserDefaults`, and defaults to `#FF383C`. Reset button disables itself when the current value equals the default.
- Toggle: Tint walking figure — applies accent color to the no-plans MP4 animation.

**Clipboard section:**
- Storage card selects the total history limit, shows current disk usage and the fixed item limits, and provides Clear History.
- Temporary Changes card enables delayed stable-content capture and selects the wait duration.
- Transcription card enables shortcut-based suppression, records the shortcut (including `fn`), and selects the post-release protection duration.

**Keyboard section:**
- Layout Switcher card: toggle "Convert wrong layout" (default off), trigger picker (`Double Shift` / `Custom shortcut`), shortcut recorder when the trigger is custom.
- Accessibility row inside the card shows trust status with Request/Open actions while the switcher needs it.
- Layouts row lists the enabled keyboard layouts in cycle order (`ABC → Russian – PC`) and warns when fewer than two are enabled.
- Automatic card (shown while the switcher is on): "Switch automatically" toggle; when on, "Show at the notch", the learned-words and ignored-words rows (each with Clear), and the excluded-apps list (icon, name, bundle ID, Remove; "Add App…").

**Accent color** is read via `@AppStorage` in `ClockWidget` (day number), `ArtworkPlaceholder` (glow + icon), `PomodoroWidget`, `MoonWidget`, `HabitsWidget` (incomplete rows and progress), `CountdownWidget` (leading number and status icon), and `SettingsView`. The `Color(hex:)` / `hexString` helpers live in `BangBarSettings.swift`.

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
[NowPlayingWidget] | Divider | [ClockWidget] | Divider | [RemindersWidget] | Divider | [HabitsWidget] | Divider | [NotionWidget] | Divider | [MoonWidget] | [PomodoroWidget] | [CountdownWidget] | Divider | [MirrorWidget]
```

Panel width may need to increase to accommodate all widgets.
Each widget separated by `Divider` at 35pt height.

`RemindersWidget` and `CountdownWidget` can be added as optional widgets once the settings panel can enable/disable optional surfaces.

---

## Widget Pages (Swipe Between Surfaces) — Implemented

**Status:** ✅ Implemented.

**Goal:** Let the user swipe left/right on the expanded panel to switch between two pages ("surfaces") of widgets, so more widgets can be enabled overall without one page becoming too wide/crowded.

**Concept:**
- Every widget is assigned to Page 1 or Page 2. All widgets default to Page 1 (the primary/home surface) unless reassigned, so the feature is additive and does not change the default layout.
- Two-finger trackpad swipe over the expanded panel content (not the compact panel) moves between pages, using the same trackpad scroll-wheel interception mechanism as Clipboard History's vertical swipe (`HoverHostingView.handlePanelScrollWheel`), branching on horizontal vs. vertical dominant-axis deltas in the same function.
- Paging is only active when Page 2 has at least one fitted widget; with an empty Page 2 the panel behaves exactly as before this feature, with no indicator and no swipe response.
- Settings → Widgets → General gains a per-widget Page 1 / Page 2 picker next to each widget's enable toggle (`WidgetSettingsRow`).

**Panel width across pages:**
- Each page has its own independent width, computed the same way the single page always was: `PanelLayout.fittedWidgets(forPage:on:)` / `expandedWidth(forPage:on:)`, capped only by the shared `maximumExpandedWidth(on:)` — Page 2 is not constrained by Page 1's width.
- The `NSPanel` frame animates its width live during the swipe, pinned to the top edge and horizontally re-centered on screen, via the existing `animateFrame` interpolation helper in `HoverPanel` (the same mechanism already used for compact↔expanded transitions) — driven by `advancePage(by:)`.
- `PanelContentView` renders each page's widget row (`pageLayer(page:hideExpandedArtwork:)`) offset by that specific page's own width in the correct direction — never by a shared/live container width — so a narrower off-screen page can never bleed into view under a wider active page (or vice versa) while the frame is mid-resize.
- Settings applies the same per-page width-budget guard independently to each page (`canEnableWidget`, `canAssign(_:toPage:)`, `pageEnabledWidgets(_:excluding:)` in `SettingsView`), reusing the exact validation pattern the app already used for the single-page case.

**Page indicator:**
- Two small dots, shown only when Page 2 has fitted widgets, hidden in compact mode and while Clipboard History is open.
- Positioned with SwiftUI `.position(x: geo.size.width / 2, y: ...)` — true absolute placement in the panel's coordinate space, not a `.frame(width:alignment:)`-based layout — wrapped in `.transaction { $0.animation = nil; $0.disablesAnimations = true }` so it never participates in the page-swipe animation and always renders at the same screen point regardless of which page (or width) is active.

**Gesture safety:**
- Reuses `containsSwipeExclusion`/`PanelSwipeExclusionView` unchanged, so `HabitsWidget` stays excluded from page-swipe the same way it's excluded from Clipboard History's vertical swipe.
- Horizontal page-swipe is gated off while Clipboard History is open, in compact mode, or while a frame animation is already in flight.
- Does not conflict with `NowPlayingWidget`'s scrub bar or any click-drag gesture, since trackpad-swipe interception and `DragGesture` are different input channels.

**Settings:**
- `BangBarSettings.Key.widgetPages` stores a JSON `[widgetRawValue: pageIndex]` dictionary (missing entry = Page 1), separate from the existing `widgetOrder` key/format.
- `BangBarSettings.Key.pageSwipeInverted` (Settings → Widgets → General → "Invert page swipe direction") swaps which two-finger swipe direction advances to the next page, mirroring the existing Clipboard swipe-inversion toggle.

---

## Refactoring Backlog

Found by the whole-project `/simplify` review (October 2026). Safe, locally verifiable fixes were applied in commits `a4227c8`, `6f1b244`, `79aabd4`. Everything below was deliberately postponed because it touches panel lifecycle or UI behavior that can only be verified by running the app, or because the fix would change behavior. Take items one at a time; each lists the problem, the intended fix, and how to verify it.

Priority: **P1** — real cost or fragility users can hit; **P2** — duplication that slows every change in the area; **P3** — cleanup.

### Panel lifecycle (needs manual regression pass from "Hover Stability")

1. **P1 — Timing hacks instead of a target frame.** `AppDelegate.compactExpansionGraceUntil` (0.85 s), `HoverPanel.slideOut`'s `openedAt > 0.5 s` guard, the `!isAnimatingFrame` early return, and `TooltipManager.suppressShowing(for:)` (0.7 s / 0.5 s) all paper over one cause: `evaluateHover` tests the mouse against `panel.frame` while it is still animating from compact size.
   - Fix: store the destination frame in `animateFrame` / `slideIn` and expose it as `HoverPanel.restingFrame`; hover tests use it. Remove the grace timestamps; end tooltip suppression in the frame-animation completion.
   - Verify: the manual regression list under "Hover Stability", plus compact → expanded with the mouse resting on the boundary.
2. **P1 — Compact content decided in ~8 places.** "clipboard group collecting / Pomodoro running / music playing" and the choice of `PanelState.CompactContent` are re-derived in three Combine sinks, `slideOut`, `recoverAfterSystemTransition` and `exitCompactMode`; `compactWidth` special-cases the clipboard group (`+110`).
   - Fix: one `desiredCompactContent: CompactContent?` from a single `Publishers.CombineLatest3(...).map(...).removeDuplicates()` sink, used everywhere; move the extra width onto `CompactContent` (e.g. `extraWidth`).
   - Verify: start/stop music, Pomodoro and image collection in every combination while hidden, compact and expanded.
3. **P2 — Page layout computed three times.** Which widgets sit on which page (and whether page 2 exists) is computed separately in `PanelContentView.activeWidgets(forPage:)` (`NSScreen.main`), `HoverPanel` (`self.screen`, swipe eligibility, `advancePage`) and `SettingsView.canEnableWidget` — on a second display or right after a settings change they can disagree.
   - Fix: `HoverPanel` computes `pages: [[BangBarWidget]]` for its own screen on `UserDefaults.didChangeNotification` and publishes it on `PanelState`; the view renders `state.pages`, swipes use `state.pages.count`.
   - Verify: two displays with different widths, toggle widgets with the panel open, swipe pages.
4. **P2 — Widget-specific work in the root view.** `PanelContentView` calls `mirror.stop()` in 4 handlers (already done by `MirrorWidget`), `reminders.stop()` (already done by `RemindersWidget`), `dayPlans.reload()` on every open (bypasses `syncFromStorageIfChanged`), starts/refreshes calendar events from the clock tick, and hard-codes tick rates per widget (`.clock` → 1 s, `.moon` / `.countdown` → 60 s).
   - Fix: delete the root-level calls; `ClockWidget` refreshes events from its own `onChange(of: date)`; add `BangBarWidget.tickInterval` and use the minimum over visible widgets.
5. **P2 — Scroll workaround copy-pasted.** `HabitsWidget` and `DayPlansWidget` both enable their `ScrollView` after a 500 ms sleep and reset its identity after 120 ms; `PanelSwipeExclusionView` / `ScrollElasticityDisabler` (panel infrastructure) live in `HabitsWidget.swift` next to a second mechanism, `HoverHostingView.isInsideVerticalScrollView`.
   - Fix: one `PanelScrollList` view/modifier; drive enabling from a `PanelState` "settled" flag set when slide-in finishes; move exclusion types next to `HoverHostingView`.
6. **P3 — `PanelTopBar` uses `NSScreen.main`** instead of the panel's own screen. Pass the panel screen in (use `PanelLayout.notchRect(on:)`).

### Efficiency (main thread is shared with the keyboard event tap)

7. ~~P1 — Now Playing polling.~~ Done: event-driven refresh, cheap state script, details only on track change.
8. ~~P1 — Root panel view re-renders on every service tick.~~ Done: the root holds the services as plain `let`, clipboard controls in `PanelTopBar` observe `ClipboardHistoryService` themselves (only while the history is shown), visualizer levels live in `LiveAudioLevels` observed only by the compact bars, the panel clock is held in `@State` and read through `PanelClockReader` only by Clock, Moon and Countdown (Clock refreshes calendar events from its own date change), and both pages are computed from one settings decode per body. Remaining: services are still `ObservableObject`, so a widget re-renders on any published change of its service; moving to `@Observable` would make tracking per property.
9. ~~P1 — Clipboard copies do heavy work on the main thread.~~ Done: image hashing off main, debounced background index writes. Remaining (P3): text payloads still live inside `index.json`; storing them in files like images would shrink each write.
10. **P2 — Synchronous startup and open-path work.** Clipboard history load checks up to 200 image files and rewrites both indexes even when nothing was pruned; `DayPlanService.shared` reads iCloud Drive synchronously (blocks if the file is evicted); `CalendarEventService.start()` runs EventKit queries on the main thread 1–2× per panel open; the health monitor writes a checkpoint file on every hover-open; services for disabled widgets are created anyway.
    - Fix: save only if load pruned something; load in the background; call only `refreshIfNeeded` and fetch EventKit off the main thread; throttle checkpoints or write them in the background; create services lazily per enabled widget.
11. **P3 — `AppDelegate.evaluateHover` on every system-wide mouse move** queries screens and defaults and, in compact mode, builds a `NotchPanelShape` path; inside the panel it runs twice per move. Return early when the pointer is well below the top edge and the panel is hidden.
12. **P3 — Keyboard switcher leftovers.** Memoize `KeyboardLayouts` character maps per layout ID (selection conversion builds ~512 `UCKeyTranslate` calls per layout each time); a small LRU of `NSSpellChecker` results keyed by (word, language).

### Duplication

13. **P2 — Finish widget-visibility centralization.** Keys and defaults now live on `BangBarWidget`, but `PanelContentView` and `SettingsView` still declare 14 `@AppStorage` flags each plus a `switch` (`isWidgetVisible`, `toggleBinding(for:)`) to stay reactive. Replace with one observable store publishing `[BangBarWidget: Bool]` (or bindings built from `visibilityKey`).
14. **P2 — Small modal windows.** `AddReminderWindowController` and `CountdownEditorWindowController` build the same dark window; "show or bring to front" is repeated in `RemindersWidget`, `CountdownWidget`, `DayPlansWindow`, `TranslatorWidget` and `ClipboardImagePreviewWindow`; the success overlay, `TITLE` label + focused field and close-after-0.75 s are duplicated in both editors. Fix: one `DarkModalWindowController<Content>` with `present()`, plus shared editor pieces.
15. **P2 — Settings rows and controls.** The "title + description + trailing control" row is rebuilt by hand ~15 times (spacing already drifts: 5 vs 7, fixed height vs padding); the bordered background is repeated ~9 times; GitHub-username and City fields are identical; the Reminders and Calendar-alert menu labels drifted (height 28 vs 30, chevron colors); `MoonLocationSettingsCard` uses a system `Toggle` that looks different from every other switch. Fix: `SettingsRow<Trailing>`, `settingsBorderedBackground()`, `SettingsTextField`, `SettingsMenuLabel`; rebuild `SettingsToggleRow`, `clipboardPickerRow` and `PermissionRow` on them.
16. **P2 — Translator logic twice.** `TranslatorWidget` and its window both implement `switchLanguages`, `requestTranslation`, `performTranslation`, language setup and copy-to-pasteboard. Fold into the existing `TranslatorWindowModel` (rename `TranslatorModel`) used by both.
17. **P2 — EventKit authorization twice.** `CalendarEventService` and `ReminderService` declare the same `AuthorizationState` and status mapping; `SettingsView` requests calendar access inline in two more places. Share one `EventKitAuthorizationState(EKAuthorizationStatus)` and route Settings through the service.
18. **P3 — Clipboard item views.** `ClipboardTextRow` and `ClipboardHistoryCard` duplicate `copyWithFeedback()`, `elapsedTime(at:)` and the Copy/Pin/Delete context menu. Extract `ClipboardItem.elapsedLabel(at:)`, `ClipboardItemContextMenu` and a small copy-feedback state.
19. **P3 — Application Support folder resolved four ways** (`ClipboardHistoryService` and `AppHealthMonitor` fall back to temp, `DayPlanService` to `~/Library/Application Support`, `CompanionService` returns nil). One `BangBarPaths.applicationSupport(_:)`; decide the fallback once (behavior change for some services).
20. **P3 — Clipboard ignore-shortcut monitors.** Three global monitors plus one local, and two handlers repeating the same guard and grace-period tail. One `[.keyDown, .keyUp]` monitor and a single `handleShortcut(_:)` → `setShortcutPressed(_:)`.
21. **P3 — Accent color lookup** (`@AppStorage(accentColorHex)` + `Color(hex:)`) is repeated in ~28 views; one environment value or property wrapper.
22. **P3 — Day Plans external-storage monitoring.** Each client keeps its own `isMonitoringExternalChanges` flag around `beginExternalStorageMonitoring()` / `end…`; a missed `end` leaks an 8 s timer. Return an `AnyCancellable` whose cancellation ends monitoring.

### Simplification

23. **P3 — `SettingsView` `@State widgetPages` mirrors `widgetPagesRaw`** with a load/persist/`onChange` cycle. Make it a computed property and write through `pageBinding` (keep `widgetOrder` as `@State` — drag reordering animates it).
24. **P3 — Settings tab wrapper.** Each `mainContent` case repeats `singleColumnContent(title:) { … .frame(width: 884) }` with titles duplicating `SettingsTab.title`, plus ~15 copies of `VStack { SettingsSectionLabel; card }`. Use `selectedSettingsTab.title` and a `labeledSection(_:content:)` helper.
25. **P3 — Calendar alert blur applied twice.** The service re-applies blur on settings changes and in `present()`, and the SwiftUI view does the same through `CalendarAlertWindowBlurUpdater` with a duplicated clamp. Keep one mechanism (check the live preview in Settings still updates).

### Behavior changes to decide on

26. **Skip concealed / transient pasteboard items in Clipboard History** (`org.nspasteboard.ConcealedType`, `TransientType`, `AutoGeneratedType` — the nspasteboard.org convention password managers use). Clipboard History currently records passwords copied from password managers.
27. ~~`NSAppleScript` → `/usr/bin/osascript`.~~ Done: `AppleScriptRunner`.

### Second pass (October 17, 2026)

Found by a second whole-project `/simplify` review; safe fixes were applied in the same change. Deferred:

28. **P2 — `UserDefaults.didChangeNotification` fan-out.** Every defaults write (habit toggle, countdown save, learned word) reaches every observer: `KeyboardSwitcherService` re-parses up to 500 learned words, `HoverPanel` re-applies its frame, Pomodoro and Calendar alerts diff their own snapshots, and `KeyboardAutoSwitcher.save` avoids writes to limit the damage. Fix: one `BangBarSettings.changes(_ read: () -> T) -> AnyPublisher<T, Never>` (map → `removeDuplicates` → `dropFirst`) so each service subscribes only to the values it reads. Verify: change each setting and confirm its consumer still reacts.
29. **P3 — Ignored words stored twice.** `keyboardSwitcherExceptions` and `keyboardSwitcherUndoCounts` encode one fact ("ignored after 5 undos") kept in sync by hand in `rememberUndo`, `learnManualConversion` and Settings → Clear. Keep only the counts, derive "ignored" from the threshold, migrate old exceptions once as count = threshold; a small pure struct makes it testable in `test_keyboard_switcher.sh`.
30. **P2 — Selection conversion through the pasteboard.** `SelectedTextConverter` relies on a 400 ms sleep before restoring the pasteboard and on ⌘C/⌘V. Where `kAXSelectedTextAttribute` is readable and settable, replace the selection through Accessibility and keep the pasteboard path as a fallback. Verify in native text views, Safari, VS Code and an Electron app.
31. **P3 — Layout switch notice timing.** `KeyboardSwitchNoticeController` uses three cancellation mechanisms (`generation`, `hideWorkItem`, `orderOutWorkItem`) and a timer that repeats `hideAnimationDuration`. One `Task` per show (caret lookup → present → sleep → hide), ordered out in the `withAnimation` completion. Needs a visual check.
32. ~~P3 — Now Playing optimistic toggles.~~ Done: `commandGeneration`.
33. **P2 — Calendar alerts query EventKit on main every 15 s.** Cache the next 1–2 h of candidate events, re-query on `.EKEventStoreChanged`, wake, settings change or window expiry; or schedule a one-shot timer at the next trigger date.
34. **P3 — Keyboard switcher leftovers.** `FocusedTextElement.caret()` could fetch range, position and size in one `AXUIElementCopyMultipleAttributeValues` call; letter patterns (~5 ms) could load off main at launch; the three retype paths in `KeyboardSwitcherService` (manual, auto, undo) could share one helper.
35. ~~P3 — Automation probe.~~ Done: sleeps only after launching the player; the script runs off main.
36. **P3 — `HoverPanel.advancePage`** builds its target frame by hand instead of using `expandedFrame(on:page:)`; take it together with item 1.

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

### SystemLoadWidget — Implemented

- Shows live CPU and memory usage, battery/charging state or free disk space, thermal health, and the active local IPv4 address.
- CPU and RAM use compact 24-sample sparkline cards; new samples arrive every two seconds.
- The health dot uses a restrained breathing halo, and graph endpoints use the same subtle pulse.
- System accents follow the user-selected accent color; warning states switch to orange.
- Clicking the IPv4 address copies it to the clipboard.
- Refreshes while visible on a two-second interval and stops polling when removed from the view hierarchy.
- Remains optional and disabled by default for existing users.

### NextAlarmWidget

- Shows the next alarm or timer if a reliable macOS data source is available.
- Feasibility needs investigation; this should not be built until the API path is clear.
