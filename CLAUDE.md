# BangBar — Claude Instructions

## Project
macOS menu bar app that shows a hover panel near the MacBook notch.
Panel slides in when the mouse enters the notch zone, slides out when it leaves.

## Spec
All planned features and widget specs are in **SPEC.md**. Before implementing any widget or feature, read SPEC.md first and follow the spec exactly.

## Tech Stack
- Swift / SwiftUI (macOS 26.4+)
- NSPanel with `.nonactivatingPanel`, `.fullSizeContentView`, `.borderless`
- No storyboards — code-only UI
- AppleScript via `/usr/bin/osascript` through `Process` (NOT `NSAppleScript` — breaks with Hardened Runtime)
- Shell commands via `Process` for system data

## Constraints
- **No Developer ID** — no private frameworks, no special entitlements
- `ENABLE_APP_SANDBOX = NO`
- `ENABLE_HARDENED_RUNTIME = NO` (required for osascript)
- No MediaRemote.framework (blocked on macOS 15 without Developer ID)
- Network requests: only public APIs, no auth keys committed to repo

## Architecture
- `HoverPanel` — NSPanel subclass, manages show/hide animation and frame
- `PanelState` — ObservableObject with `isExpanded` and `contentVisible`
- `PanelContentView` — root SwiftUI view, hosts all widgets in an HStack
- Each widget is a self-contained SwiftUI `View` struct
- Each data service is a `final class` conforming to `ObservableObject`

## Panel Dimensions
- Width: 620pt, Height: 155pt
- Horizontal padding: 50pt (accounts for NotchPanelShape corner clipping)
- `NotchPanelShape`: topRadius=14, bottomRadius=14, topEarInset=10

## Widget Layout
Current layout (left → right):
```
[NowPlayingWidget] | Divider | [ClockWidget]
```
New widgets are added to this HStack. Each widget should be self-contained and handle its own data loading.

## Code Style
- No comments unless the WHY is non-obvious
- No `// MARK:` sections unless the file is long
- Prefer `@StateObject` for services owned by a view, `@ObservedObject` for injected ones
- Services poll on a background thread, publish updates on `DispatchQueue.main`
- Keep widget Views small — extract sub-views if body exceeds ~40 lines
