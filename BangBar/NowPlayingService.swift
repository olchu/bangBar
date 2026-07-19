import AppKit
import Combine

struct NowPlayingInfo {
    var title: String = ""
    var artist: String = ""
    var isPlaying: Bool = false
    var artwork: NSImage? = nil
    var position: Double = 0
    var duration: Double = 0
    var shuffleEnabled: Bool = false
    var repeatMode: RepeatMode = .off
    var isFavorited: Bool = false
    var canFavorite: Bool = false
}

enum RepeatMode: String {
    case off
    case one
    case all
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

    // Returns: title\nartist\nartworkHint\nisPlaying\nposition\nduration\nshuffle\nrepeat\nfavorite\ncanFavorite
    var trackInfoScript: String {
        switch self {
        case .spotify:
            return """
            tell application "Spotify"
                if player state is not stopped then
                    set t to name of current track
                    set a to artist of current track
                    set u to artwork url of current track
                    set pos to ((player position as integer) as string)
                    set dur to (((duration of current track) / 1000 as integer) as string)
                    if player state is playing then
                        set p to "1"
                    else
                        set p to "0"
                    end if
                    if shuffling then
                        set s to "1"
                    else
                        set s to "0"
                    end if
                    if repeating then
                        set r to "all"
                    else
                        set r to "off"
                    end if
                    return t & "\n" & a & "\n" & u & "\n" & p & "\n" & pos & "\n" & dur & "\n" & s & "\n" & r & "\n0\n0"
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
                    set pos to ((player position as integer) as string)
                    set dur to ((duration of current track as integer) as string)
                    if player state is playing then
                        set p to "1"
                    else
                        set p to "0"
                    end if
                    if shuffle enabled then
                        set s to "1"
                    else
                        set s to "0"
                    end if
                    set r to song repeat as string
                    set loved to "0"
                    set canLove to "0"
                    try
                        if favorited of current track then set loved to "1"
                        set canLove to "1"
                    end try
                    try
                        set libraryMatches to every track of library playlist 1 whose name is t and artist is a
                        repeat with libraryTrack in libraryMatches
                            if favorited of libraryTrack then
                                set loved to "1"
                                exit repeat
                            end if
                        end repeat
                    end try
                    set tmpPath to "/tmp/bangbar_artwork.png"
                    try
                        set imgData to data of artwork 1 of current track
                        set f to open for access POSIX file tmpPath with write permission
                        set eof of f to 0
                        write imgData to f
                        close access f
                        return t & "\n" & a & "\n" & tmpPath & "\n" & p & "\n" & pos & "\n" & dur & "\n" & s & "\n" & r & "\n" & loved & "\n" & canLove
                    on error
                        return t & "\n" & a & "\n" & "" & "\n" & p & "\n" & pos & "\n" & dur & "\n" & s & "\n" & r & "\n" & loved & "\n" & canLove
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

    var toggleShuffleScript: String {
        switch self {
        case .spotify:
            return "tell application \"Spotify\" to set shuffling to not shuffling"
        case .music:
            return "tell application \"Music\" to set shuffle enabled to not shuffle enabled"
        }
    }

    var cycleRepeatScript: String {
        switch self {
        case .spotify:
            return "tell application \"Spotify\" to set repeating to not repeating"
        case .music:
            return """
            tell application "Music"
                if song repeat is off then
                    set song repeat to all
                else if song repeat is all then
                    set song repeat to one
                else
                    set song repeat to off
                end if
            end tell
            """
        }
    }

    func setFavoriteScript(to isFavorited: Bool) -> String? {
        switch self {
        case .spotify:
            return nil
        case .music:
            if isFavorited {
                return """
                tell application "Music"
                    set currentName to name of current track
                    set currentArtist to artist of current track
                    set libraryMatches to {}
                    try
                        set libraryMatches to every track of library playlist 1 whose name is currentName and artist is currentArtist
                    end try
                    if (count of libraryMatches) is 0 then
                        try
                            duplicate current track to library playlist 1
                            set libraryMatches to every track of library playlist 1 whose name is currentName and artist is currentArtist
                        end try
                    end if
                    repeat with libraryTrack in libraryMatches
                        try
                            set favorited of libraryTrack to true
                        end try
                    end repeat
                    try
                        set favorited of current track to true
                    end try
                end tell
                """
            }
            return """
            tell application "Music"
                set currentName to name of current track
                set currentArtist to artist of current track
                try
                    set favorited of current track to false
                end try
                try
                    set libraryMatches to every track of library playlist 1 whose name is currentName and artist is currentArtist
                    repeat with libraryTrack in libraryMatches
                        try
                            set favorited of libraryTrack to false
                        end try
                    end repeat
                end try
            end tell
            """
        }
    }
}

final class NowPlayingService: ObservableObject {
    @Published var info = NowPlayingInfo()
    @Published var isAvailable = false

    var isCurrentlyPlaying: Bool {
        isAvailable && info.isPlaying
    }

    private var pollTimer: Timer?
    private var tickTimer: Timer?
    private var activePlayer: Player?
    private var artworkCacheKey: String = ""
    private var artworkCacheImage: NSImage?
    private var pendingFavorite: PendingFavorite?

    private struct PendingFavorite {
        let trackKey: String
        let value: Bool
        let expiresAt: Date
    }

    init() {
        poll()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            self?.poll()
        }
        tickTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, self.info.isPlaying, self.info.duration > 0 else { return }
            self.info.position = min(self.info.position + 1, self.info.duration)
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
                let position  = parts.count > 4 ? Double(parts[4]) ?? 0 : 0
                let duration  = parts.count > 5 ? Double(parts[5]) ?? 0 : 0
                let shuffleEnabled = parts.count > 6 ? parts[6] == "1" : false
                let repeatMode = parts.count > 7 ? RepeatMode(rawValue: parts[7]) ?? .off : .off
                let isFavorited = parts.count > 8 ? parts[8] == "1" : false
                let canFavorite = parts.count > 9 ? parts[9] == "1" : false
                guard !title.isEmpty else { continue }

                let artwork = self?.loadArtwork(hint: hint, player: player, title: title, artist: artist)
                DispatchQueue.main.async {
                    guard let self else { return }
                    let trackKey = "\(title)|\(artist)"
                    var displayedFavorite = isFavorited
                    if let pending = self.pendingFavorite, pending.trackKey == trackKey {
                        if pending.value == isFavorited {
                            self.pendingFavorite = nil
                        } else if pending.expiresAt > Date() {
                            displayedFavorite = pending.value
                        } else {
                            self.pendingFavorite = nil
                        }
                    } else if self.pendingFavorite != nil {
                        self.pendingFavorite = nil
                    }

                    self.activePlayer = player
                    self.isAvailable  = true
                    self.info = NowPlayingInfo(
                        title: title, artist: artist,
                        isPlaying: isPlaying, artwork: artwork,
                        position: position, duration: duration,
                        shuffleEnabled: shuffleEnabled,
                        repeatMode: repeatMode,
                        isFavorited: displayedFavorite,
                        canFavorite: canFavorite
                    )
                }
                return
            }
            DispatchQueue.main.async {
                self?.activePlayer = nil
                self?.isAvailable  = false
                self?.info = NowPlayingInfo()
            }
        }
    }

    private func loadArtwork(hint: String, player: Player, title: String, artist: String) -> NSImage? {
        switch player {
        case .spotify:
            guard !hint.isEmpty,
                  let url = URL(string: hint),
                  let data = try? Data(contentsOf: url) else { return nil }
            return NSImage(data: data)
        case .music:
            if !hint.isEmpty, let img = NSImage(contentsOfFile: hint) {
                return img
            }
            let cacheKey = "\(title)|\(artist)"
            if cacheKey == artworkCacheKey, let cached = artworkCacheImage {
                return cached
            }
            let img = fetchITunesArtwork(title: title, artist: artist)
            artworkCacheKey = cacheKey
            artworkCacheImage = img
            return img
        }
    }

    private func fetchITunesArtwork(title: String, artist: String) -> NSImage? {
        let query = "\(title) \(artist)"
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        guard let url = URL(string: "https://itunes.apple.com/search?term=\(query)&entity=song&limit=1&media=music"),
              let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]],
              let first = results.first,
              let artworkUrl = first["artworkUrl100"] as? String else { return nil }
        let hiRes = artworkUrl.replacingOccurrences(of: "100x100bb", with: "300x300bb")
        guard let imgUrl = URL(string: hiRes),
              let imgData = try? Data(contentsOf: imgUrl) else { return nil }
        return NSImage(data: imgData)
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
    func toggleShuffle()    { sendCommand(activePlayer?.toggleShuffleScript) }
    func cycleRepeat()      { sendCommand(activePlayer?.cycleRepeatScript) }
    func toggleFavorite() {
        guard info.canFavorite else { return }
        info.isFavorited.toggle()
        let newValue = info.isFavorited
        pendingFavorite = PendingFavorite(
            trackKey: "\(info.title)|\(info.artist)",
            value: newValue,
            expiresAt: Date().addingTimeInterval(8)
        )
        sendCommand(activePlayer?.setFavoriteScript(to: newValue))
    }

    func seek(to position: Double) {
        guard let player = activePlayer else { return }
        let clamped = max(0, min(position, info.duration))
        info.position = clamped
        let script: String
        switch player {
        case .spotify:
            script = "tell application \"Spotify\" to set player position to \(Int(clamped))"
        case .music:
            script = "tell application \"Music\" to set player position to \(clamped)"
        }
        sendCommand(script)
    }

    func openPlayer() {
        guard let player = activePlayer,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: player.bundleId) else { return }
        NSWorkspace.shared.open(url)
    }

    private func sendCommand(_ source: String?) {
        guard let source else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            _ = self?.runScript(source)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self?.poll() }
        }
    }
}
