import AppKit
import Carbon.HIToolbox
import Combine

/// One shell in the panel's terminal.
struct TerminalTab: Identifiable, Equatable {
    let id = UUID()
    var path: String?
    /// The git branch of `path`, or a short commit hash when HEAD is detached.
    var branch: String?
    /// The command line while one runs.
    var runningCommand: String?
    fileprivate let surface: TerminalSurfaceView

    var title: String {
        guard let path, path != FileManager.default.homeDirectoryForCurrentUser.path else { return "~" }
        return URL(fileURLWithPath: path).lastPathComponent
    }
}

/// Owns the terminal tabs for the life of the app, so hiding the panel never ends a shell.
final class TerminalSessionService: ObservableObject {
    @Published private(set) var tabs: [TerminalTab] = []
    @Published private(set) var selectedTabID: UUID?
    @Published private(set) var canCopyLastOutput = false

    /// The last tab closed; the panel returns to the widgets.
    var onAllTabsClosed: (() -> Void)?
    /// The selected tab's `contentHeight` changed, or another tab was selected.
    var onContentHeightChange: (() -> Void)?
    private weak var container: NSView?
    private var surfaceSize = CGSize.zero
    private var visibleHeight: CGFloat = 0
    private var accentColor = NSColor.white
    private var layoutBeforeFocus: KeyboardLayout?

    private var selectedSurface: TerminalSurfaceView? {
        tabs.first { $0.id == selectedTabID }?.surface
    }

    var hasKeyboardFocus: Bool {
        selectedSurface?.hasKeyboardFocus == true
    }

    /// The height the selected tab needs to show its rows in use.
    var contentHeight: CGFloat {
        selectedSurface?.contentHeight ?? TerminalSurfaceView.contentHeight(rows: 1)
    }

    /// Every tab keeps the full `size` in the clipping container, so a panel that grows or shrinks with the
    /// content never resizes a PTY. A tab is pinned to the top while its rows in use fit `visibleHeight`; when
    /// they do not (mid-animation, or a height that came out a row short), it moves up so the cursor row stays
    /// at the bottom edge and the oldest row is the one cut off, never the prompt. Runs on every animation
    /// step, so background tabs are only resized; they are placed when selected.
    func layoutSurfaces(size: CGSize, visibleHeight: CGFloat) {
        self.visibleHeight = visibleHeight
        if surfaceSize != size {
            surfaceSize = size
            tabs.forEach { $0.surface.setFrameSize(size) }
        }
        if let selectedSurface {
            selectedSurface.frame = surfaceFrame(for: selectedSurface)
        }
    }

    private func surfaceFrame(for surface: TerminalSurfaceView) -> CGRect {
        // Clamped: right after the PTY shrinks (a lower maximum) the rows in use still hold the old count
        // until the deferred shrink lands, which would push the whole tab out of view.
        let overflow = min(surface.contentHeight, surfaceSize.height) - visibleHeight
        return CGRect(origin: CGPoint(x: 0, y: -max(overflow, 0)), size: surfaceSize)
    }

    func copyLastOutput() -> Bool {
        let copied = selectedSurface?.copyLastCommandOutput() == true
        selectedSurface?.focusTerminal()
        return copied
    }

    /// Shows the selected tab in `container`, starting the first shell if there is none.
    func present(in container: NSView, accentColor: NSColor) {
        self.container = container
        self.accentColor = accentColor
        if tabs.isEmpty {
            newTab()
        } else {
            showSelectedTab()
        }
        guard layoutBeforeFocus == nil, let current = KeyboardLayouts.current() else { return }
        layoutBeforeFocus = current
        if current.language != "en", let english = KeyboardLayouts.enabled().first(where: { $0.language == "en" }) {
            KeyboardLayouts.select(english)
        }
    }

    func didHide() {
        container = nil
        selectedSurface?.setVisible(false)
        if let layoutBeforeFocus {
            KeyboardLayouts.select(layoutBeforeFocus)
            self.layoutBeforeFocus = nil
        }
    }

    func newTab() {
        let directory = Self.startingDirectory()
        let surface = TerminalSurfaceView(startingDirectory: directory)
        // Known before the first OSC 7, which shells without the zsh integration never send.
        let tab = TerminalTab(path: directory, surface: surface)
        // The id, not the tab: the tab holds the surface, which holds these closures.
        let id = tab.id
        surface.onProcessTermination = { [weak self] in
            self?.removeTab(id: id)
        }
        surface.onDirectoryChange = { [weak self] path in
            self?.updateDirectory(of: id, path: path)
        }
        surface.onRunningCommandChange = { [weak self] command in
            self?.updateTab(id) { $0.runningCommand = command.isEmpty ? nil : command }
        }
        surface.onShortcut = { [weak self] event in
            self?.handleShortcut(event) ?? false
        }
        surface.onContentHeightChange = { [weak self] in
            guard let self, self.selectedTabID == id else { return }
            self.onContentHeightChange?()
        }
        surface.onCopyOutputAvailabilityChange = { [weak self] in
            guard let self, self.selectedTabID == id else { return }
            self.updateCopyOutputAvailability()
        }
        tabs.append(tab)
        updateDirectory(of: id, path: directory)
        select(tab.id)
    }

    func select(_ id: UUID) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        selectedSurface?.setVisible(false)
        selectedTabID = id
        showSelectedTab()
        updateCopyOutputAvailability()
        onContentHeightChange?()
    }

    private func updateCopyOutputAvailability() {
        let canCopy = selectedSurface?.canCopyLastOutput == true
        if canCopyLastOutput != canCopy {
            canCopyLastOutput = canCopy
        }
    }

    func closeTab(id: UUID) {
        guard let tab = tabs.first(where: { $0.id == id }) else { return }
        tab.surface.terminateSession()
        removeTab(id: id)
    }

    func terminate() {
        didHide()
        tabs.forEach {
            $0.surface.terminateSession()
            $0.surface.removeFromSuperview()
        }
        tabs = []
        selectedTabID = nil
    }

    private func removeTab(id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        let removed = tabs.remove(at: index)
        removed.surface.setVisible(false)
        removed.surface.removeFromSuperview()
        guard !tabs.isEmpty else {
            selectedTabID = nil
            onAllTabsClosed?()
            return
        }
        if selectedTabID == id {
            select(tabs[min(index, tabs.count - 1)].id)
        }
    }

    /// Background tabs stay in the container, hidden, so switching back does not resize their PTY.
    private func showSelectedTab() {
        guard let container, let selected = selectedSurface else { return }
        // Sized before it joins the window, so a new tab's shell draws its first prompt at the final size.
        selected.frame = surfaceFrame(for: selected)
        for tab in tabs {
            if tab.surface.superview !== container {
                container.addSubview(tab.surface)
            }
            tab.surface.isHidden = tab.surface !== selected
        }
        selected.setAccentColor(accentColor)
        selected.setVisible(true)
        selected.focusTerminal()
    }

    /// Reported before every prompt, so the branch is re-read after each command too.
    private func updateDirectory(of id: UUID, path: String) {
        updateTab(id) { $0.path = path }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let branch = GitHead.branch(inDirectory: path)
            DispatchQueue.main.async {
                self?.updateTab(id) { tab in
                    guard tab.path == path else { return }
                    tab.branch = branch
                }
            }
        }
    }

    /// Publishes only when the tab really changed: every prompt reports the same folder again.
    private func updateTab(_ id: UUID, _ change: (inout TerminalTab) -> Void) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        var tab = tabs[index]
        change(&tab)
        if tab != tabs[index] {
            tabs[index] = tab
        }
    }

    private func handleShortcut(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
        let keyCode = Int(event.keyCode)
        if modifiers == .command {
            if keyCode == kVK_ANSI_T {
                newTab()
                return true
            }
            if keyCode == kVK_ANSI_W, let selectedTabID {
                closeTab(id: selectedTabID)
                return true
            }
            if let number = Self.digitKeyCodes.firstIndex(of: keyCode), number < tabs.count {
                select(tabs[number].id)
                return true
            }
        }
        if modifiers == [.command, .shift], keyCode == kVK_ANSI_LeftBracket || keyCode == kVK_ANSI_RightBracket {
            selectRelativeTab(offset: keyCode == kVK_ANSI_LeftBracket ? -1 : 1)
            return true
        }
        return false
    }

    private func selectRelativeTab(offset: Int) {
        guard let index = tabs.firstIndex(where: { $0.id == selectedTabID }), tabs.count > 1 else { return }
        select(tabs[(index + offset + tabs.count) % tabs.count].id)
    }

    private static let digitKeyCodes = [
        kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5, kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9
    ]

    private static func startingDirectory() -> String {
        let configured = UserDefaults.standard.string(forKey: BangBarSettings.Key.terminalStartingDirectory)
            ?? BangBarSettings.defaultTerminalStartingDirectory
        let path = NSString(string: configured).expandingTildeInPath
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return FileManager.default.homeDirectoryForCurrentUser.path
        }
        return path
    }
}

/// Reads the branch from `.git/HEAD` directly, without starting `git` on every prompt.
private enum GitHead {
    static func branch(inDirectory path: String) -> String? {
        let fileManager = FileManager.default
        var directory = URL(fileURLWithPath: path, isDirectory: true)
        while true {
            let dotGit = directory.appendingPathComponent(".git")
            var isDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: dotGit.path, isDirectory: &isDirectory) {
                let gitDirectory = isDirectory.boolValue ? dotGit : linkedGitDirectory(file: dotGit, in: directory)
                return gitDirectory.flatMap(headName(gitDirectory:))
            }
            let parent = directory.deletingLastPathComponent()
            guard parent.path != directory.path else { return nil }
            directory = parent
        }
    }

    /// A worktree or submodule has a `.git` file: `gitdir: <path>`, absolute or relative to its folder.
    private static func linkedGitDirectory(file: URL, in directory: URL) -> URL? {
        guard let contents = try? String(contentsOf: file, encoding: .utf8),
              contents.hasPrefix("gitdir:") else { return nil }
        let path = contents.dropFirst("gitdir:".count).trimmingCharacters(in: .whitespacesAndNewlines)
        return path.hasPrefix("/") ? URL(fileURLWithPath: path) : directory.appendingPathComponent(path)
    }

    private static func headName(gitDirectory: URL) -> String? {
        guard let head = try? String(contentsOf: gitDirectory.appendingPathComponent("HEAD"), encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
        if head.hasPrefix("ref: ") {
            let reference = head.dropFirst("ref: ".count)
            return reference.hasPrefix("refs/heads/") ? String(reference.dropFirst("refs/heads/".count)) : String(reference)
        }
        return head.isEmpty ? nil : String(head.prefix(7))
    }
}
