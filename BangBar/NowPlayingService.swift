import AppKit
import Combine
import OSLog

struct NowPlayingInfo: Equatable {
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

    /// Spotify only toggles repeat; Music cycles off → all → one.
    func next(for player: MusicPlayer) -> RepeatMode {
        switch (player, self) {
        case (.spotify, .off): .all
        case (.spotify, _): .off
        case (.appleMusic, .off): .all
        case (.appleMusic, .all): .one
        case (.appleMusic, .one): .off
        }
    }
}

private nonisolated extension MusicPlayer {
    var isRunning: Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == bundleIdentifier }
    }

    /// Posted by the player on play, pause, and track changes, so polling is only a fallback.
    var playbackNotificationName: Notification.Name {
        switch self {
        case .spotify: Notification.Name("com.spotify.client.PlaybackStateChanged")
        case .appleMusic: Notification.Name("com.apple.Music.playerInfo")
        }
    }

    // The running check stops a refresh fired by the player's own quit notification from relaunching it.
    // Cheap enough to run on every poll. Returns: trackID\ntitle\nartist\nisPlaying\nposition\nduration\nshuffle\nrepeat
    var stateScript: String {
        switch self {
        case .spotify:
            return """
            if application "Spotify" is not running then return ""
            tell application "Spotify"
                if player state is not stopped then
                    set i to id of current track
                    set t to name of current track
                    set a to artist of current track
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
                    return i & "\n" & t & "\n" & a & "\n" & p & "\n" & pos & "\n" & dur & "\n" & s & "\n" & r
                else
                    return ""
                end if
            end tell
            """
        case .appleMusic:
            return """
            if application "Music" is not running then return ""
            tell application "Music"
                if player state is not stopped then
                    set i to persistent ID of current track
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
                    return i & "\n" & t & "\n" & a & "\n" & p & "\n" & pos & "\n" & dur & "\n" & s & "\n" & r
                else
                    return ""
                end if
            end tell
            """
        }
    }

    // Scans the library and writes artwork to disk, so it runs only when the track changes.
    // Returns: artworkHint\nfavorite\ncanFavorite
    var detailsScript: String {
        switch self {
        case .spotify:
            return """
            tell application "Spotify"
                return (artwork url of current track) & "\n0\n0"
            end tell
            """
        case .appleMusic:
            return """
            tell application "Music"
                set t to name of current track
                set a to artist of current track
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
                on error
                    set tmpPath to ""
                end try
                return tmpPath & "\n" & loved & "\n" & canLove
            end tell
            """
        }
    }

    var playPauseScript: String { "tell application \"\(applicationName)\" to playpause" }
    var nextScript: String      { "tell application \"\(applicationName)\" to next track" }
    var prevScript: String      { "tell application \"\(applicationName)\" to previous track" }

    var toggleShuffleScript: String {
        switch self {
        case .spotify:
            return "tell application \"Spotify\" to set shuffling to not shuffling"
        case .appleMusic:
            return "tell application \"Music\" to set shuffle enabled to not shuffle enabled"
        }
    }

    var cycleRepeatScript: String {
        switch self {
        case .spotify:
            return "tell application \"Spotify\" to set repeating to not repeating"
        case .appleMusic:
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
        case .appleMusic:
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

private nonisolated struct PlaybackState {
    let trackID: String
    let title: String
    let artist: String
    let isPlaying: Bool
    let position: Double
    let duration: Double
    let shuffleEnabled: Bool
    let repeatMode: RepeatMode

    var detailsKey: String { "\(trackID)|\(title)|\(artist)" }

    init?(output: String) {
        let part = scriptFields(output)
        guard !part(1).isEmpty else { return nil }
        trackID = part(0)
        title = part(1)
        artist = part(2)
        isPlaying = part(3) == "1"
        position = Double(part(4)) ?? 0
        duration = Double(part(5)) ?? 0
        shuffleEnabled = part(6) == "1"
        repeatMode = RepeatMode(rawValue: part(7)) ?? .off
    }
}

/// Splits newline-separated script output into a lookup that returns "" for missing fields.
private nonisolated func scriptFields(_ output: String?) -> (Int) -> String {
    let parts = output?.components(separatedBy: "\n") ?? []
    return { index in index < parts.count ? parts[index] : "" }
}

private nonisolated struct TrackDetails {
    let artwork: NSImage?
    let isFavorited: Bool
    let canFavorite: Bool
    /// false when the details script failed, so the next refresh retries instead of caching the empty result.
    let isComplete: Bool
}

private nonisolated struct PlayerSnapshot {
    let player: MusicPlayer
    let state: PlaybackState
    /// nil when the track has not changed since the last details fetch.
    let details: TrackDetails?
}

final class LiveAudioLevels: ObservableObject {
    private static let idle = [0.18, 0.28, 0.22, 0.34]

    @Published private(set) var values = idle

    /// Skips identical values (silence, repeated resets) so the bars are not re-rendered for nothing.
    fileprivate func update(_ newValues: [Double]) {
        if values != newValues {
            values = newValues
        }
    }

    fileprivate func reset() {
        update(Self.idle)
    }
}

final class NowPlayingService: NSObject, ObservableObject {
    private static let logger = Logger(subsystem: "BangBar", category: "NowPlaying")
    private static let visiblePollInterval: TimeInterval = 10
    private static let backgroundPollInterval: TimeInterval = 30
    /// Players post several notifications per track change; one refresh covers the burst.
    private static let notificationCoalescingDelay: TimeInterval = 0.2
    private static let artworkRetryDelay: TimeInterval = 1
    private static let maximumArtworkRetries = 3
    /// Serial so rapid commands reach the player in the order they were issued.
    private static let commandQueue = DispatchQueue(label: "BangBar.NowPlaying.commands", qos: .userInitiated)

    @Published private(set) var info = NowPlayingInfo()
    @Published private(set) var isAvailable = false
    /// Set while `info` shows another app's audio instead of a player. Its playback is controlled through the
    /// system media keys; seeking, shuffle, repeat and favorites need a player.
    @Published private(set) var audioApp: AudioApp?
    /// Separate from `info` so visualizer ticks do not re-render every observer of the service.
    let audioLevels = LiveAudioLevels()

    var isCurrentlyPlaying: Bool {
        isAvailable && info.isPlaying
    }

    var canControlPlayer: Bool {
        isAvailable && audioApp == nil
    }

    /// Play, pause, next and previous, which also work for another app through the media keys.
    var canControlPlayback: Bool {
        isAvailable
    }

    /// The player's own state, nil without a player; `info` shows it unless another app plays while the player does not.
    private var playerInfo: NowPlayingInfo?
    private let audioActivity = AudioActivityMonitor()
    private let otherAppMedia = OtherAppMedia()
    private var otherAudioObservation: NSKeyValueObservation?
    /// A play or pause just sent to another app, shown until its audio confirms it. A paused app keeps its stream
    /// quiet, so without this it would leave Now Playing and could not be resumed from the panel.
    private var audioAppCommand: (app: AudioApp, isPlaying: Bool)?
    private var audioAppCommandTimer: Timer?
    private var lastMonitoredApp: AudioApp?
    private static let pausedAudioAppHold: TimeInterval = 120
    private static let resumedAudioAppHold: TimeInterval = 4

    private var pollTimer: Timer?
    private var tickTimer: Timer?
    private var activePlayer: MusicPlayer?
    private var detailsKey: String?
    /// Artwork fetches used for a track; once past the maximum the artwork is final, found or not.
    private var artworkAttempts: (key: String, count: Int)?
    private var detailsRefreshRequested = false
    /// Bumped by every command so a poll that started before it cannot revert the optimistic UI.
    private var commandGeneration = 0
    /// A poll started while a command is still running reads the state before that command, so it is discarded too.
    private var commandsInFlight = 0
    private var pendingFavorite: PendingFavorite?
    private var isPollInFlight = false
    private var pollRequested = false
    private var audioLevelMonitor: AudioLevelMonitor?
    private var isAudioLevelMonitoringRequested = false
    private var positionUpdatesRequested = false
    private var workspaceObservers: [NSObjectProtocol] = []
    private var coalescedPoll: DispatchWorkItem?

    private struct PendingFavorite {
        let trackKey: String
        let value: Bool
        let expiresAt: Date
    }

    override init() {
        super.init()
        observePlayers()
        observeOtherAudio()
        poll()
        schedulePollTimer()
    }

    deinit {
        pollTimer?.invalidate()
        tickTimer?.invalidate()
        audioAppCommandTimer?.invalidate()
        coalescedPoll?.cancel()
        DistributedNotificationCenter.default().removeObserver(self)
        workspaceObservers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
    }

    private func observePlayers() {
        // AppKit suspends distributed notifications while the app is inactive, which for a menu bar app is nearly always.
        let distributed = DistributedNotificationCenter.default()
        for player in MusicPlayer.allCases {
            distributed.addObserver(
                self,
                selector: #selector(playerNotificationReceived),
                name: player.playbackNotificationName,
                object: nil,
                suspensionBehavior: .deliverImmediately
            )
        }

        let workspace = NSWorkspace.shared.notificationCenter
        workspaceObservers = [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification].map { name in
            workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                MainActor.assumeIsolated {
                    if name == NSWorkspace.didTerminateApplicationNotification, let app {
                        self?.audioAppTerminated(app.processIdentifier)
                    }
                    guard MusicPlayer(bundleIdentifier: app?.bundleIdentifier) != nil else { return }
                    self?.playerNotificationReceived()
                }
            }
        }
    }

    private func observeOtherAudio() {
        audioActivity.onChange = { [weak self] in
            self?.audioActivityChanged()
        }
        otherAppMedia.onChange = { [weak self] in
            self?.publish()
        }
        // KVO on this key only: UserDefaults.didChangeNotification fires for every write in the app.
        otherAudioObservation = UserDefaults.standard.observe(\.nowPlayingShowsOtherAudio, options: [.initial]) { [weak self] defaults, _ in
            let isEnabled = defaults.nowPlayingShowsOtherAudio
            DispatchQueue.main.async {
                self?.audioActivity.isEnabled = isEnabled
                // Turning the monitor off reports no change when nothing was audible, as during a held pause.
                if !isEnabled, self?.audioAppCommand != nil {
                    self?.clearAudioAppCommand()
                    self?.publish()
                }
            }
        }
    }

    @objc private func playerNotificationReceived() {
        schedulePoll(after: Self.notificationCoalescingDelay)
    }

    /// One pending poll at a time: a notification burst and a details retry collapse into a single refresh.
    private func schedulePoll(after delay: TimeInterval) {
        coalescedPoll?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.coalescedPoll = nil
            self?.poll()
        }
        coalescedPoll = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func schedulePollTimer() {
        pollTimer?.invalidate()
        let interval = positionUpdatesRequested ? Self.visiblePollInterval : Self.backgroundPollInterval
        pollTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.poll()
        }
        pollTimer?.tolerance = interval / 6
    }

    private func poll(refreshingDetails: Bool = false) {
        if refreshingDetails {
            detailsRefreshRequested = true
        }
        guard !isPollInFlight else {
            pollRequested = true
            return
        }
        isPollInFlight = true
        // A pending favorite keeps re-reading details so a failed command reverts once it expires.
        let isArtworkRetryPending = artworkAttempts.map {
            $0.key == detailsKey && $0.count <= Self.maximumArtworkRetries
        } ?? false
        let knownDetailsKey = detailsRefreshRequested || pendingFavorite != nil || isArtworkRetryPending ? nil : detailsKey
        detailsRefreshRequested = false
        let generation = commandsInFlight == 0 ? commandGeneration : nil
        // The last active player answers first, so an idle player does not cost an extra osascript launch per poll.
        let players = MusicPlayer.allCases.filter { $0 == activePlayer } + MusicPlayer.allCases.filter { $0 != activePlayer }
        // The iTunes Search fallback costs two network requests; usually the player has the artwork by the first retry.
        let artworkFallbackKey = artworkAttempts.flatMap { $0.count >= Self.maximumArtworkRetries ? $0.key : nil }

        DispatchQueue.global(qos: .utility).async { [weak self] in
            let snapshot = NowPlayingService.fetchSnapshot(
                players: players, knownDetailsKey: knownDetailsKey, artworkFallbackKey: artworkFallbackKey
            )
            DispatchQueue.main.async {
                guard let self else { return }
                if generation == self.commandGeneration {
                    self.apply(snapshot)
                }
                self.finishPoll()
            }
        }
    }

    private nonisolated static func fetchSnapshot(
        players: [MusicPlayer], knownDetailsKey: String?, artworkFallbackKey: String?
    ) -> PlayerSnapshot? {
        for player in players where player.isRunning {
            guard let output = AppleScriptRunner.output(of: player.stateScript),
                  let state = PlaybackState(output: output) else { continue }
            let details = state.detailsKey == knownDetailsKey ? nil : fetchDetails(
                player: player, state: state, allowsArtworkFallback: state.detailsKey == artworkFallbackKey
            )
            return PlayerSnapshot(player: player, state: state, details: details)
        }
        return nil
    }

    private nonisolated static func fetchDetails(player: MusicPlayer, state: PlaybackState, allowsArtworkFallback: Bool) -> TrackDetails {
        let output = AppleScriptRunner.output(of: player.detailsScript)
        let part = scriptFields(output)
        return TrackDetails(
            artwork: loadArtwork(
                hint: part(0), player: player, title: state.title, artist: state.artist, allowsFallback: allowsArtworkFallback
            ),
            isFavorited: part(1) == "1",
            canFavorite: part(2) == "1",
            isComplete: output != nil
        )
    }

    private func apply(_ snapshot: PlayerSnapshot?) {
        guard let snapshot else {
            activePlayer = nil
            detailsKey = nil
            playerInfo = nil
            publish()
            return
        }

        let state = snapshot.state
        activePlayer = snapshot.player

        var next = playerInfo ?? NowPlayingInfo()
        next.title = state.title
        next.artist = state.artist
        next.isPlaying = state.isPlaying
        next.duration = state.duration
        next.shuffleEnabled = state.shuffleEnabled
        next.repeatMode = state.repeatMode
        if let details = snapshot.details {
            detailsKey = details.isComplete ? state.detailsKey : nil
            if details.isComplete {
                recordArtworkAttempt(for: state.detailsKey, found: details.artwork != nil)
            }
            next.artwork = details.artwork
            next.isFavorited = displayedFavorite(details.isFavorited, trackKey: state.detailsKey)
            next.canFavorite = details.canFavorite
        }

        // Position ticks locally while visible; republishing it from a background poll would re-render every observer.
        let metadataChanged = snapshot.details != nil || next != playerInfo
        if metadataChanged || positionUpdatesRequested {
            next.position = state.position
        }
        playerInfo = next
        publish()
    }

    private func audioActivityChanged() {
        let current = audioActivity.playingApp
        if let command = audioAppCommand {
            // A resume ends once any app is heard. A pause ends when the app starts again after its audio stopped,
            // or when another app starts; while the paused stream merely stays open, the pause holds. Apps compare by
            // process, because another helper of the same app may take over the audio.
            let confirmed = command.isPlaying
                ? current != nil
                : current.map {
                    $0.processIdentifier != command.app.processIdentifier || lastMonitoredApp == nil
                } ?? false
            if confirmed { clearAudioAppCommand() }
        }
        lastMonitoredApp = current
        publish()
    }

    private func setAudioAppCommand(_ app: AudioApp, isPlaying: Bool) {
        audioAppCommand = (app, isPlaying)
        audioAppCommandTimer?.invalidate()
        let hold = isPlaying ? Self.resumedAudioAppHold : Self.pausedAudioAppHold
        audioAppCommandTimer = Timer.scheduledTimer(withTimeInterval: hold, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.clearAudioAppCommand()
                self?.publish()
            }
        }
        publish()
    }

    private func audioAppTerminated(_ processIdentifier: pid_t) {
        guard audioAppCommand?.app.processIdentifier == processIdentifier else { return }
        clearAudioAppCommand()
        publish()
    }

    private func clearAudioAppCommand() {
        audioAppCommand = nil
        audioAppCommandTimer?.invalidate()
        audioAppCommandTimer = nil
    }

    /// A playing player always wins; otherwise another app's audio replaces the paused or missing player.
    private func publish() {
        if playerInfo?.isPlaying == true, audioAppCommand != nil {
            clearAudioAppCommand()
        }
        let app = playerInfo?.isPlaying == true ? nil : audioAppCommand?.app ?? audioActivity.playingApp
        if audioApp != app {
            audioApp = app
            otherAppMedia.track(app)
        }
        let next = otherAppMedia.info(isPlaying: audioAppCommand?.isPlaying ?? true) ?? playerInfo ?? NowPlayingInfo()
        let available = app != nil || playerInfo != nil
        if isAvailable != available { isAvailable = available }
        if info != next { info = next }
        updateAudioLevelMonitoring()
    }

    /// Sends a command to the shown player with optimistic feedback; the refresh after it confirms or reverts the change.
    @discardableResult
    private func perform(
        refreshingDetails: Bool = false,
        _ change: (inout NowPlayingInfo, MusicPlayer) -> Void,
        script: (MusicPlayer) -> String?
    ) -> Bool {
        guard audioApp == nil, let player = activePlayer, var next = playerInfo else { return false }
        change(&next, player)
        playerInfo = next
        publish()
        sendCommand(script(player), refreshingDetails: refreshingDetails)
        return true
    }

    /// Right after a track change the player may not have the artwork yet, so a missing one is re-fetched shortly,
    /// a few times per track, instead of on every fallback poll. A poll already pending re-fetches it anyway.
    private func recordArtworkAttempt(for key: String, found: Bool) {
        let previous = artworkAttempts.flatMap { $0.key == key ? $0.count : nil } ?? 0
        let count = found ? Self.maximumArtworkRetries + 1 : previous + 1
        artworkAttempts = (key, count)
        if count <= Self.maximumArtworkRetries, coalescedPoll == nil {
            schedulePoll(after: Self.artworkRetryDelay)
        }
    }

    private func displayedFavorite(_ reported: Bool, trackKey: String) -> Bool {
        guard let pending = pendingFavorite else { return reported }
        if pending.trackKey == trackKey, pending.value != reported, pending.expiresAt > Date() {
            return pending.value
        }
        pendingFavorite = nil
        return reported
    }

    private func finishPoll() {
        isPollInFlight = false
        guard pollRequested else { return }
        pollRequested = false
        poll()
    }

    private nonisolated static func loadArtwork(
        hint: String, player: MusicPlayer, title: String, artist: String, allowsFallback: Bool
    ) -> NSImage? {
        switch player {
        case .spotify:
            guard !hint.isEmpty,
                  let url = URL(string: hint),
                  let data = try? Data(contentsOf: url) else { return nil }
            return NSImage(data: data)
        case .appleMusic:
            if !hint.isEmpty, let img = NSImage(contentsOfFile: hint) {
                return img
            }
            return allowsFallback ? fetchITunesArtwork(title: title, artist: artist) : nil
        }
    }

    private nonisolated static func fetchITunesArtwork(title: String, artist: String) -> NSImage? {
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

    func togglePlayPause() {
        if let audioApp {
            if SystemMediaKey.playPause.post() {
                setAudioAppCommand(audioApp, isPlaying: !info.isPlaying)
            }
            return
        }
        perform({ info, _ in info.isPlaying.toggle() }, script: { $0.playPauseScript })
    }

    func nextTrack() {
        if audioApp != nil {
            SystemMediaKey.next.post()
            return
        }
        perform({ info, _ in info.position = 0 }, script: { $0.nextScript })
    }

    func previousTrack() {
        if audioApp != nil {
            SystemMediaKey.previous.post()
            return
        }
        perform({ info, _ in info.position = 0 }, script: { $0.prevScript })
    }

    func toggleShuffle() {
        perform({ info, _ in info.shuffleEnabled.toggle() }, script: { $0.toggleShuffleScript })
    }

    func cycleRepeat() {
        perform({ info, player in info.repeatMode = info.repeatMode.next(for: player) }, script: { $0.cycleRepeatScript })
    }

    func toggleFavorite() {
        guard let playerInfo, playerInfo.canFavorite, let detailsKey else { return }
        let newValue = !playerInfo.isFavorited
        let sent = perform(refreshingDetails: true, { info, _ in info.isFavorited = newValue }, script: {
            $0.setFavoriteScript(to: newValue)
        })
        guard sent else { return }
        pendingFavorite = PendingFavorite(
            trackKey: detailsKey,
            value: newValue,
            expiresAt: Date().addingTimeInterval(8)
        )
    }

    func seek(to position: Double) {
        guard let duration = playerInfo?.duration else { return }
        let clamped = max(0, min(position, duration))
        perform({ info, _ in info.position = clamped }, script: { player in
            switch player {
            case .spotify: "tell application \"Spotify\" to set player position to \(Int(clamped))"
            case .appleMusic: "tell application \"Music\" to set player position to \(clamped)"
            }
        })
    }

    func openPlayer() {
        // Opening through Launch Services, unlike activate(), brings the app forward while BangBar is not active.
        if let audioApp {
            if let url = NSRunningApplication(processIdentifier: audioApp.processIdentifier)?.bundleURL {
                NSWorkspace.shared.open(url)
            }
            return
        }
        let player = activePlayer ?? BangBarSettings.preferredMusicPlayer
        guard let url = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: player.bundleIdentifier
        ) else {
            Self.logger.error("Unable to find \(player.title, privacy: .public)")
            return
        }
        NSWorkspace.shared.open(url)
    }

    func setAudioLevelMonitoringRequested(_ isRequested: Bool) {
        guard isAudioLevelMonitoringRequested != isRequested else { return }
        isAudioLevelMonitoringRequested = isRequested
        updateAudioLevelMonitoring()
    }

    func setPositionUpdatesRequested(_ isRequested: Bool) {
        guard positionUpdatesRequested != isRequested else { return }
        positionUpdatesRequested = isRequested
        tickTimer?.invalidate()
        tickTimer = nil
        schedulePollTimer()

        guard isRequested else { return }
        poll()
        // Ticks only while the player plays, and a playing player is always what `info` shows.
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, let player = self.playerInfo, player.isPlaying, player.duration > 0 else { return }
            let position = min(player.position + 1, player.duration)
            self.playerInfo?.position = position
            self.info.position = position
        }
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        tickTimer = timer
    }

    private func updateAudioLevelMonitoring() {
        guard isAudioLevelMonitoringRequested,
              isAvailable,
              info.isPlaying,
              let audioBundleIdentifier = audioApp?.audioBundleIdentifier ?? activePlayer?.bundleIdentifier else {
            audioLevelMonitor?.stop()
            audioLevelMonitor = nil
            audioLevels.reset()
            return
        }

        if audioLevelMonitor == nil {
            audioLevelMonitor = AudioLevelMonitor { [weak self] levels in
                self?.receiveLiveAudioLevels(levels)
            }
        }
        audioLevelMonitor?.start(bundleIdentifier: audioBundleIdentifier)
    }

    private func receiveLiveAudioLevels(_ levels: [Double]) {
        guard isAudioLevelMonitoringRequested, info.isPlaying else { return }
        audioLevels.update(levels)
    }

    private func sendCommand(_ source: String?, refreshingDetails: Bool = false) {
        guard let source else { return }
        commandGeneration += 1
        commandsInFlight += 1
        Self.commandQueue.async { [weak self] in
            _ = AppleScriptRunner.run(source)
            DispatchQueue.main.async {
                guard let self else { return }
                self.commandsInFlight -= 1
                self.poll(refreshingDetails: refreshingDetails)
            }
        }
    }
}
