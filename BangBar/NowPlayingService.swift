import AppKit
import Combine
import OSLog

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

private extension NowPlayingInfo {
    func matchesMetadata(
        title: String,
        artist: String,
        isPlaying: Bool,
        duration: Double,
        shuffleEnabled: Bool,
        repeatMode: RepeatMode,
        isFavorited: Bool,
        canFavorite: Bool
    ) -> Bool {
        self.title == title
            && self.artist == artist
            && self.isPlaying == isPlaying
            && self.duration == duration
            && self.shuffleEnabled == shuffleEnabled
            && self.repeatMode == repeatMode
            && self.isFavorited == isFavorited
            && self.canFavorite == canFavorite
    }
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
    private static let logger = Logger(subsystem: "BangBar", category: "NowPlaying")

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
    private var isPollInFlight = false
    private var pollRequested = false

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
        guard !isPollInFlight else {
            pollRequested = true
            return
        }
        isPollInFlight = true

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
                    self.isAvailable = true
                    if self.info.matchesMetadata(
                        title: title,
                        artist: artist,
                        isPlaying: isPlaying,
                        duration: duration,
                        shuffleEnabled: shuffleEnabled,
                        repeatMode: repeatMode,
                        isFavorited: displayedFavorite,
                        canFavorite: canFavorite
                    ) {
                        self.info.position = position
                    } else {
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
                    self.finishPoll()
                }
                return
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.activePlayer = nil
                self.isAvailable  = false
                self.info = NowPlayingInfo()
                self.finishPoll()
            }
        }
    }

    private func finishPoll() {
        isPollInFlight = false
        guard pollRequested else { return }
        pollRequested = false
        poll()
    }

    private func loadArtwork(hint: String, player: Player, title: String, artist: String) -> NSImage? {
        let cacheKey = "\(player.rawValue)|\(hint)|\(title)|\(artist)"
        if cacheKey == artworkCacheKey, let cached = artworkCacheImage {
            return cached
        }

        func cache(_ image: NSImage?) -> NSImage? {
            artworkCacheKey = cacheKey
            artworkCacheImage = image
            return image
        }

        switch player {
        case .spotify:
            guard !hint.isEmpty,
                  let url = URL(string: hint),
                  let data = try? Data(contentsOf: url) else { return nil }
            return cache(NSImage(data: data))
        case .music:
            if !hint.isEmpty, let img = NSImage(contentsOfFile: hint) {
                return cache(img)
            }
            return cache(fetchITunesArtwork(title: title, artist: artist))
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
        guard let script = NSAppleScript(source: source) else { return nil }
        var errorInfo: NSDictionary?
        let result = script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            let message = errorInfo[NSAppleScript.errorMessage] as? String ?? "Unknown AppleScript error"
            let number = errorInfo[NSAppleScript.errorNumber] as? Int ?? 0
            Self.logger.error("AppleScript failed: \(message, privacy: .public) (\(number))")
            return nil
        }
        let output = result.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
        return output?.isEmpty == false ? output : nil
    }

    func togglePlayPause() {
        guard isAvailable else { return }
        info.isPlaying.toggle()
        sendCommand(activePlayer?.playPauseScript)
    }

    func nextTrack() {
        guard isAvailable else { return }
        info.position = 0
        sendCommand(activePlayer?.nextScript)
    }

    func previousTrack() {
        guard isAvailable else { return }
        info.position = 0
        sendCommand(activePlayer?.prevScript)
    }

    func toggleShuffle() {
        guard isAvailable else { return }
        info.shuffleEnabled.toggle()
        sendCommand(activePlayer?.toggleShuffleScript)
    }

    func cycleRepeat() {
        guard let player = activePlayer else { return }
        switch player {
        case .spotify:
            info.repeatMode = info.repeatMode == .off ? .all : .off
        case .music:
            info.repeatMode = switch info.repeatMode {
            case .off: .all
            case .all: .one
            case .one: .off
            }
        }
        sendCommand(player.cycleRepeatScript)
    }
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
            DispatchQueue.main.async { self?.poll() }
        }
    }
}
