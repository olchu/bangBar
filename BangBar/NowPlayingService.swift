import AppKit
import Combine

struct NowPlayingInfo {
    var title: String = ""
    var artist: String = ""
    var isPlaying: Bool = false
    var artwork: NSImage? = nil
}

private enum Player: String, CaseIterable {
    case spotify = "Spotify"
    case music   = "Music"

    var bundleId: String {
        switch self {
        case .spotify: "com.spotify.client"
        case .music:   "com.apple.Music"
        }
    }

    var isRunning: Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == bundleId }
    }

    // Returns: title\nartist\nartworkHint
    // Spotify: artworkHint = CDN URL
    // Music:   artworkHint = /tmp/bangbar_artwork.jpg (written by AppleScript)
    var trackInfoScript: String {
        switch self {
        case .spotify:
            return """
            tell application "Spotify"
                if player state is not stopped then
                    set t to name of current track
                    set a to artist of current track
                    set u to artwork url of current track
                    if player state is playing then
                        set p to "1"
                    else
                        set p to "0"
                    end if
                    return t & "\n" & a & "\n" & u & "\n" & p
                else
                    return ""
                end if
            end tell
            """
        case .music:
            return """
            tell application "Music"
                if player state is not stopped then
                    set t to name of current track
                    set a to artist of current track
                    if player state is playing then
                        set p to "1"
                    else
                        set p to "0"
                    end if
                    set tmpPath to "/tmp/bangbar_artwork.jpg"
                    try
                        set imgData to raw data of artwork 1 of current track
                        set f to open for access POSIX file tmpPath with write permission
                        set eof of f to 0
                        write imgData to f
                        close access f
                        return t & "\n" & a & "\n" & tmpPath & "\n" & p
                    on error
                        return t & "\n" & a & "\n" & "" & "\n" & p
                    end try
                else
                    return ""
                end if
            end tell
            """
        }
    }

    var playPauseScript: String { "tell application \"\(rawValue)\" to playpause" }
    var nextScript: String      { "tell application \"\(rawValue)\" to next track" }
    var prevScript: String      { "tell application \"\(rawValue)\" to previous track" }
}

final class NowPlayingService: ObservableObject {
    @Published var info = NowPlayingInfo()
    @Published var isAvailable = false

    private var timer: Timer?
    private var activePlayer: Player?
    private var artworkTask: URLSessionDataTask?

    init() {
        poll()
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            self?.poll()
        }
    }

    private func poll() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            for player in Player.allCases where player.isRunning {
                guard let result = self?.runScript(player.trackInfoScript), !result.isEmpty else { continue }
                let parts     = result.components(separatedBy: "\n")
                let title     = parts.count > 0 ? parts[0] : ""
                let artist    = parts.count > 1 ? parts[1] : ""
                let hint      = parts.count > 2 ? parts[2] : ""
                let isPlaying = parts.count > 3 ? parts[3] == "1" : false
                guard !title.isEmpty else { continue }

                let artwork = self?.loadArtwork(hint: hint, player: player)
                DispatchQueue.main.async {
                    self?.activePlayer = player
                    self?.isAvailable  = true
                    self?.info = NowPlayingInfo(title: title, artist: artist, isPlaying: isPlaying, artwork: artwork)
                }
                return
            }
            DispatchQueue.main.async {
                self?.activePlayer = nil
                self?.isAvailable  = false
            }
        }
    }

    private func loadArtwork(hint: String, player: Player) -> NSImage? {
        guard !hint.isEmpty else { return nil }
        switch player {
        case .spotify:
            guard let url = URL(string: hint),
                  let data = try? Data(contentsOf: url) else { return nil }
            return NSImage(data: data)
        case .music:
            return NSImage(contentsOfFile: hint)
        }
    }

    private func runScript(_ source: String) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", source]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError  = Pipe()
        guard (try? p.run()) != nil else { return nil }
        p.waitUntilExit()
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return out?.isEmpty == false ? out : nil
    }

    func togglePlayPause() { sendCommand(activePlayer?.playPauseScript) }
    func nextTrack()        { sendCommand(activePlayer?.nextScript) }
    func previousTrack()    { sendCommand(activePlayer?.prevScript) }

    private func sendCommand(_ source: String?) {
        guard let source else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            _ = self?.runScript(source)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self?.poll() }
        }
    }
}
