import AppKit
@preconcurrency import SwiftTerm

/// One shell session in a PTY, adapted from DropTerm's terminal surface.
final class TerminalSurfaceView: NSView {
    var onProcessTermination: (() -> Void)?

    private static let fontSize: CGFloat = 12
    private static let contentPadding: CGFloat = 6
    private static let copyOutputImage = NSImage(
        systemSymbolName: "doc.on.doc",
        accessibilityDescription: "Copy last command output"
    )
    private static let copyOutputRefreshDelay: TimeInterval = 0.25
    private let terminalView: OutputObservingTerminalView
    private let copyOutputButton = NSButton()
    private var eventMonitors: [Any] = []
    private var isVisible = false
    private var hasStartedSession = false
    private var lastAvailableSize: CGSize = .zero
    private var copyOutputRefreshScheduled = false
    private var lastDataReceived: TimeInterval = 0

    init() {
        terminalView = OutputObservingTerminalView(
            frame: .zero,
            font: Self.preferredTerminalFont(),
            options: TerminalOptions(cursorStyle: .blinkBar)
        )
        super.init(frame: .zero)
        terminalView.processDelegate = self
        terminalView.onDataReceived = { [weak self] in
            self?.scheduleCopyOutputRefresh()
        }
        wantsLayer = true
        installTerminalView()
        installCopyOutputButton()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        // Sized before the shell starts, so its first prompt is drawn at the final width.
        fitTerminalToBounds()
        startSessionIfNeeded()
    }

    override func layout() {
        super.layout()
        fitTerminalToBounds()
    }

    private func fitTerminalToBounds() {
        let availableFrame = bounds.insetBy(dx: Self.contentPadding, dy: Self.contentPadding)
        guard availableFrame.width > 0, availableFrame.height > 0,
              lastAvailableSize != availableFrame.size else { return }
        lastAvailableSize = availableFrame.size
        terminalView.frame = availableFrame
        terminalView.layoutSubtreeIfNeeded()

        // Snapping to whole cells keeps the grid from showing a partial row or column at the edges.
        let gridSize = terminalView.getOptimalFrameSize().size
        terminalView.frame = CGRect(
            x: availableFrame.minX,
            y: availableFrame.maxY - min(gridSize.height, availableFrame.height),
            width: min(gridSize.width, availableFrame.width),
            height: min(gridSize.height, availableFrame.height)
        ).integral
    }

    var hasKeyboardFocus: Bool {
        window?.firstResponder === terminalView
    }

    func focusTerminal() {
        window?.makeFirstResponder(terminalView)
    }

    func setAccentColor(_ color: NSColor) {
        terminalView.caretColor = color
        copyOutputButton.contentTintColor = color
    }

    /// Event monitors and the copy-button refresh run only while the terminal is on screen.
    func setVisible(_ visible: Bool) {
        guard isVisible != visible else { return }
        isVisible = visible
        if visible {
            installEventMonitors()
            scheduleCopyOutputRefresh()
        } else {
            removeEventMonitors()
        }
    }

    func terminateSession() {
        removeEventMonitors()
        guard hasStartedSession else { return }
        hangUp()
        terminalView.terminate()
        hasStartedSession = false
    }

    /// SwiftTerm only sends SIGTERM to the shell, which an interactive zsh ignores, and the pty stays open while
    /// its read is pending, so the kernel never hangs up the session. Hang up like Terminal.app does: SIGHUP the
    /// terminal's foreground process group and the shell, which forwards it to its jobs.
    private func hangUp() {
        guard let process = terminalView.process, process.running else { return }
        let foreground = tcgetpgrp(process.childfd)
        if foreground > 0 { killpg(foreground, SIGHUP) }
        if process.shellPid > 0 { kill(process.shellPid, SIGHUP) }
    }

    private func installTerminalView() {
        terminalView.autoresizingMask = []
        terminalView.nativeForegroundColor = .white
        terminalView.nativeBackgroundColor = .clear
        terminalView.backgroundOpacity = 0
        terminalView.optionAsMetaKey = true
        terminalView.subviews
            .compactMap { $0 as? NSScroller }
            .forEach { $0.isHidden = true }
        addSubview(terminalView)
    }

    private func installEventMonitors() {
        let keyboard = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self,
                  event.window === self.window,
                  event.window?.firstResponder === self.terminalView,
                  let key = event.charactersIgnoringModifiers?.lowercased() else {
                return event
            }

            // Only the shortcut modifiers: Caps Lock would otherwise turn ⌘C into an unmatched combination.
            switch (event.modifierFlags.intersection([.command, .shift, .option, .control]), key) {
            case (.command, "c"): self.terminalView.copy(self)
            case (.command, "v"): self.terminalView.paste(self)
            case (.command, "a"): self.terminalView.selectAll(self)
            case ([.command, .shift], "c"): self.copyLastCommandOutput()
            default: return event
            }
            return nil
        }
        let pointer = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .flagsChanged]) { [weak self] event in
            guard let self, event.window === self.window else { return event }
            self.terminalView.updateLinkPointerCursor(modifierFlags: event.modifierFlags)
            return event
        }
        eventMonitors = [keyboard, pointer].compactMap { $0 }
    }

    private func removeEventMonitors() {
        eventMonitors.forEach(NSEvent.removeMonitor)
        eventMonitors = []
    }

    private func installCopyOutputButton() {
        copyOutputButton.bezelStyle = .recessed
        copyOutputButton.isBordered = false
        copyOutputButton.image = Self.copyOutputImage
        copyOutputButton.toolTip = "Copy last command output (⇧⌘C)"
        copyOutputButton.target = self
        copyOutputButton.action = #selector(copyLastOutput(_:))
        copyOutputButton.translatesAutoresizingMaskIntoConstraints = false
        copyOutputButton.isHidden = true
        addSubview(copyOutputButton)

        NSLayoutConstraint.activate([
            copyOutputButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            copyOutputButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
            copyOutputButton.widthAnchor.constraint(equalToConstant: 26),
            copyOutputButton.heightAnchor.constraint(equalToConstant: 26)
        ])
    }

    @objc private func copyLastOutput(_ sender: Any?) {
        copyLastCommandOutput()
        focusTerminal()
    }

    private func copyLastCommandOutput() {
        guard let output = lastCommandOutput(), !output.isEmpty else {
            NSSound.beep()
            return
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(output, forType: .string)
        copyOutputButton.image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: "Copied")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            self?.copyOutputButton.image = Self.copyOutputImage
        }
    }

    /// The output between the last two prompts, found through the shell integration's OSC 133 marks.
    /// Walks back from the end of the buffer, so the cost follows the last command, not the scrollback.
    private func lastCommandOutput() -> String? {
        let terminal = terminalView.terminal!
        var lastRow = terminal.buffer.yDisp + terminal.rows - 1
        while terminal.semanticContent(at: Position(col: 0, row: lastRow + 1)) != nil {
            lastRow += 1
        }

        var promptRows: [Int] = []
        var row = lastRow
        while row >= 0, promptRows.count < 2 {
            if terminal.semanticPromptMarks(at: row).contains(where: { $0.kind == .initial }) {
                promptRows.append(row)
            }
            row -= 1
        }
        guard promptRows.count == 2 else { return nil }

        let outputRows = (promptRows[1]..<promptRows[0]).filter { candidateRow in
            (0..<terminal.cols).contains { column in
                terminal.semanticContent(at: Position(col: column, row: candidateRow)) == .output
            }
        }
        guard let firstRow = outputRows.first, let lastOutputRow = outputRows.last else { return nil }
        return terminal.getText(
            start: Position(col: 0, row: firstRow),
            end: Position(col: terminal.cols - 1, row: lastOutputRow)
        ).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Checks once output has been quiet for a moment: a command's output only becomes the last one when the
    /// prompt returns, and continuous output would otherwise rescan it several times a second.
    private func scheduleCopyOutputRefresh() {
        lastDataReceived = ProcessInfo.processInfo.systemUptime
        guard isVisible, !copyOutputRefreshScheduled else { return }
        copyOutputRefreshScheduled = true
        refreshCopyOutputWhenQuiet()
    }

    private func refreshCopyOutputWhenQuiet() {
        let quietFor = ProcessInfo.processInfo.systemUptime - lastDataReceived
        let remaining = Self.copyOutputRefreshDelay - quietFor
        guard remaining <= 0 else {
            DispatchQueue.main.asyncAfter(deadline: .now() + remaining) { [weak self] in
                self?.refreshCopyOutputWhenQuiet()
            }
            return
        }
        copyOutputRefreshScheduled = false
        guard isVisible else { return }
        copyOutputButton.isHidden = lastCommandOutput()?.isEmpty != false
    }

    private func startSessionIfNeeded() {
        guard !hasStartedSession else { return }

        let shell = loginShell()
        let executableName = URL(fileURLWithPath: shell).lastPathComponent
        var environment = Terminal.getEnvironmentVariables(termName: "xterm-256color", trueColor: true)
        if executableName == "zsh", let integrationDirectory = Self.zshIntegrationDirectory {
            environment.removeAll { $0.hasPrefix("ZDOTDIR=") }
            environment.append("ZDOTDIR=\(integrationDirectory.path)")
        }

        hasStartedSession = true
        terminalView.startProcess(
            executable: shell,
            environment: environment,
            execName: "-\(executableName)",
            currentDirectory: FileManager.default.homeDirectoryForCurrentUser.path
        )
    }

    private func loginShell() -> String {
        guard let entry = getpwuid(getuid()), let shellPointer = entry.pointee.pw_shell else { return "/bin/zsh" }
        let shell = String(cString: shellPointer)
        return FileManager.default.isExecutableFile(atPath: shell) ? shell : "/bin/zsh"
    }

    /// Wraps the user's own zsh startup files and adds OSC 133 prompt marks, per-command history writes and
    /// prefix history search, without touching the files in the home directory. Written once per launch.
    private static let zshIntegrationDirectory: URL? = {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BangBarTerminal", isDirectory: true)
        let home = FileManager.default.homeDirectoryForCurrentUser
        let integration = """
        autoload -Uz add-zsh-hook add-zle-hook-widget
        _bangbar_preexec() { printf '\\e]133;C\\a' }
        _bangbar_precmd() {
          # The PTY can close without giving an interactive shell time to exit cleanly.
          [[ -n "$HISTFILE" ]] && fc -AI "$HISTFILE"
          # Powerlevel10k owns PROMPT when loaded; replacing it from a precmd hook breaks instant prompt.
          (( ${+functions[p10k]} )) || PROMPT='%3~ '
          printf '\\e]133;D\\a\\e]133;A;cl=w\\a'
        }
        _bangbar_line_init() { printf '\\e]133;B\\a' }
        add-zsh-hook preexec _bangbar_preexec
        add-zsh-hook precmd _bangbar_precmd
        add-zle-hook-widget line-init _bangbar_line_init

        if [[ -r "$ZSH/plugins/history-substring-search/history-substring-search.plugin.zsh" ]]; then
          HISTORY_SUBSTRING_SEARCH_PREFIXED=true
          source "$ZSH/plugins/history-substring-search/history-substring-search.plugin.zsh"
          for keymap in emacs viins; do
            for key in '^[[A' '^[OA'; do bindkey -M $keymap $key history-substring-search-up; done
            for key in '^[[B' '^[OB'; do bindkey -M $keymap $key history-substring-search-down; done
          done
          [[ -n "$terminfo[kcuu1]" ]] && bindkey -M emacs "$terminfo[kcuu1]" history-substring-search-up
          [[ -n "$terminfo[kcud1]" ]] && bindkey -M emacs "$terminfo[kcud1]" history-substring-search-down
        else
          for key in '^[[A' '^[OA'; do bindkey -M emacs $key history-beginning-search-backward; done
          for key in '^[[B' '^[OB'; do bindkey -M emacs $key history-beginning-search-forward; done
        fi
        """

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

            for fileName in [".zshenv", ".zprofile", ".zlogin", ".zlogout"] {
                let userFile = shellQuote(home.appendingPathComponent(fileName).path)
                // `if` rather than `&&`: a missing file must not leave the first prompt with exit status 1.
                let wrapper = "if [[ -r \(userFile) ]]; then source \(userFile); fi\n"
                try wrapper.write(to: directory.appendingPathComponent(fileName), atomically: true, encoding: .utf8)
            }

            let userRC = shellQuote(home.appendingPathComponent(".zshrc").path)
            // /etc/zshrc has already derived HISTFILE from the private ZDOTDIR, and user configs such as
            // `${ZDOTDIR:-~}/.p10k.zsh` look there too: point both back at the home directory before the user's rc.
            let rcWrapper = """
            if [[ "$HISTFILE" == "$ZDOTDIR/.zsh_history" ]]; then HISTFILE="$HOME/.zsh_history"; fi
            ZDOTDIR=\(shellQuote(home.path))
            if [[ -r \(userRC) ]]; then source \(userRC); fi
            \(integration)
            if (( ${+functions[p10k]} )); then
              typeset -g POWERLEVEL9K_SHORTEN_STRATEGY=truncate_to_last
              typeset -g POWERLEVEL9K_SHORTEN_DIR_LENGTH=3
              typeset -g POWERLEVEL9K_DIR_MAX_LENGTH=0
              p10k reload
              p10k finalize
            fi
            """
            try rcWrapper.write(to: directory.appendingPathComponent(".zshrc"), atomically: true, encoding: .utf8)
            return directory
        } catch {
            return nil
        }
    }()

    private static func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    private static func preferredTerminalFont() -> NSFont {
        for fontName in ["MesloLGS-NF-Regular", "MesloLGS NF", "MesloLGS Nerd Font"] {
            if let font = NSFont(name: fontName, size: fontSize) {
                return font
            }
        }
        return NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
    }
}

extension TerminalSurfaceView: LocalProcessTerminalViewDelegate {
    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

    func processTerminated(source: TerminalView, exitCode: Int32?) {
        hasStartedSession = false
        onProcessTermination?()
    }
}

private final class OutputObservingTerminalView: LocalProcessTerminalView {
    var onDataReceived: (() -> Void)?
    private var isDraggingPointer = false

    override func mouseDown(with event: NSEvent) {
        isDraggingPointer = false
        super.mouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        isDraggingPointer = true
        super.mouseDragged(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        let shouldMoveCursor = event.clickCount == 1
            && !isDraggingPointer
            && event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty
        let target = shouldMoveCursor ? terminalPosition(at: convert(event.locationInWindow, from: nil)) : nil

        // SwiftTerm waits for the full double-click interval before routing a semantic prompt click.
        // Disable that deferred route for this event and perform the same movement immediately below.
        let clickBehavior = terminal.semanticPromptClickBehavior
        terminal.semanticPromptClickBehavior = .disabled
        super.mouseUp(with: event)
        terminal.semanticPromptClickBehavior = clickBehavior

        if let target {
            _ = terminal.handleSemanticPromptClick(at: target)
            setNeedsDisplay(bounds)
        }
    }

    private func terminalPosition(at point: CGPoint) -> Position? {
        guard terminal.cols > 0, terminal.rows > 0,
              bounds.width > 0, bounds.height > 0 else { return nil }
        let cellWidth = bounds.width / CGFloat(terminal.cols)
        let cellHeight = bounds.height / CGFloat(terminal.rows)
        let column = min(max(Int(point.x / cellWidth), 0), terminal.cols - 1)
        let visibleRow = min(max(Int((bounds.height - point.y) / cellHeight), 0), terminal.rows - 1)
        return Position(col: column, row: visibleRow + terminal.buffer.yDisp)
    }

    func updateLinkPointerCursor(modifierFlags: NSEvent.ModifierFlags) {
        guard let window, let contentView = window.contentView else { return }

        let windowPoint = window.mouseLocationOutsideOfEventStream
        // `hitTest` takes the superview's coordinates; the panel's content view is flipped, its frame view is not.
        let hitView = contentView.hitTest(contentView.superview?.convert(windowPoint, from: nil) ?? windowPoint)
        guard hitView === self || hitView?.isDescendant(of: self) == true else { return }

        let point = convert(windowPoint, from: nil)
        guard modifierFlags.contains(.command),
              let position = terminalPosition(at: point),
              terminal.link(at: .buffer(position), mode: .explicitAndImplicit) != nil else {
            NSCursor.iBeam.set()
            return
        }

        NSCursor.pointingHand.set()
    }

    // LocalProcess delivers PTY data on the main queue by default.
    override func dataReceived(slice: ArraySlice<UInt8>) {
        super.dataReceived(slice: slice)
        onDataReceived?()
    }
}
