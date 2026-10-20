import CoreGraphics
import Foundation

/// Follows the album playing in Yandex Music. A track change shows up first in the app's HTTP cache, where it stores
/// the new album's cover in two sizes at once, and about 10 s later in its play log, which then repeats the current
/// album every 10 s. The cache gives the change at once; the log stays authoritative and corrects a cache guess,
/// such as covers cached while browsing albums. Used by one refresh task at a time.
nonisolated final class YandexMusicTracker: @unchecked Sendable {
    private var logStamp: Date?
    private var cacheStamp: Date?
    private var current: (albumID: String, since: Date)?

    /// Cheap while nothing changes: it compares two modification dates before reading anything.
    func currentAlbumID() -> String? {
        let logDate = YandexMusicArtwork.newestLogDate()
        if logDate != logStamp {
            logStamp = logDate
            // Only records newer than the shown album count, so a late record of the previous track cannot undo a change.
            if let play = YandexMusicArtwork.latestPlay(), current.map({ play.date > $0.since }) ?? true {
                current = (play.albumID, play.date)
            }
        }
        let cacheDate = YandexMusicArtwork.cacheDirectoryDate()
        if cacheDate != cacheStamp {
            cacheStamp = cacheDate
            if let pair = YandexMusicArtwork.latestCoverPair(), current.map({ pair.date > $0.since }) ?? true {
                current = (pair.albumID, pair.date)
            }
        }
        return current?.albumID
    }
}

/// Yandex Music publishes its artwork only to the system Now Playing, which needs MediaRemote. Its own files still
/// name the current album: the play log in its IndexedDB records the album of each play, and its HTTP cache holds
/// that album's cover address. Both formats are undocumented, so anything unexpected yields nil and the icon stays.
nonisolated enum YandexMusicArtwork {
    static let bundleIdentifier = "ru.yandex.desktop.music"

    private static let root = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/YandexMusic", isDirectory: true)
    /// New records are appended to the log, so the end of it holds the current play.
    private static let logTailBytes = 64 * 1024
    private static let cacheKeyBytes = 4 * 1024
    private static let coverSize = "400x400"

    /// A cover pair counts only while it is fresh; older entries are cache history, not a track change.
    private static let coverPairWindow: TimeInterval = 60
    private static let coverPairSizes: Set<String> = ["200x200", "800x800"]

    private static let logDirectory = root.appendingPathComponent("IndexedDB/music-application_desktop_0.indexeddb.leveldb")
    private static let cacheDirectory = root.appendingPathComponent("Cache/Cache_Data")
    /// Each play record holds `timestamp` and, right after it, `albumId`, both as length-prefixed strings.
    private static let playPattern = try! NSRegularExpression(
        pattern: #"timestamp"[\s\S](\d{4}-\d\d-\d\dT[\d:.]+Z)[\s\S]{0,4}albumId"[\s\S](\d+)"#
    )
    private static let coverKeyPattern = try! NSRegularExpression(
        pattern: #"https://avatars\.yandex\.net/get-music-content/\d+/[0-9a-f]+\.a\.(\d+)-\d+/(\d+x\d+)"#
    )

    static func newestLogDate() -> Date? {
        files(in: logDirectory, withExtension: "log").first.flatMap(modificationDate)
    }

    static func cacheDirectoryDate() -> Date? {
        modificationDate(of: cacheDirectory)
    }

    /// The newest play-log record. Blocks on file reads; call off the main thread.
    static func latestPlay() -> (albumID: String, date: Date)? {
        for log in files(in: logDirectory, withExtension: "log") {
            guard let text = tail(of: log, bytes: logTailBytes),
                  let match = playPattern.matches(in: text, range: NSRange(text.startIndex..., in: text)).last,
                  let dateRange = Range(match.range(at: 1), in: text),
                  let albumRange = Range(match.range(at: 2), in: text),
                  let date = try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(String(text[dateRange]))
            else { continue }
            return (String(text[albumRange]), date)
        }
        return nil
    }

    /// The newest album whose cover the app just cached in both of the sizes its player loads together.
    static func latestCoverPair() -> (albumID: String, date: Date)? {
        var sizes: [String: Set<String>] = [:]
        var newest: [String: Date] = [:]
        let cutoff = Date().addingTimeInterval(-coverPairWindow)
        for entry in files(in: cacheDirectory, withExtension: nil) {
            guard let date = modificationDate(of: entry), date > cutoff else { break }
            guard let text = head(of: entry),
                  let match = coverKeyPattern.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  let albumRange = Range(match.range(at: 1), in: text),
                  let sizeRange = Range(match.range(at: 2), in: text) else { continue }
            let album = String(text[albumRange])
            sizes[album, default: []].insert(String(text[sizeRange]))
            newest[album] = max(newest[album] ?? .distantPast, date)
        }
        return newest
            .filter { coverPairSizes.isSubset(of: sizes[$0.key] ?? []) }
            .max { $0.value < $1.value }
            .map { ($0.key, $0.value) }
    }

    /// The album's cover from Yandex's public image CDN, at the address the app cached for it.
    @concurrent
    static func cover(albumID: String) async -> CGImage? {
        guard let base = cachedCoverBase(albumID: albumID), let url = URL(string: base + coverSize) else { return nil }
        return await WebMediaLookup.thumbnail(at: url)
    }

    /// `https://avatars.yandex.net/get-music-content/<shard>/<hash>.a.<album>-<n>/`, from a cache entry's key.
    private static func cachedCoverBase(albumID: String) -> String? {
        guard let pattern = try? NSRegularExpression(
            pattern: #"https://avatars\.yandex\.net/get-music-content/\d+/[0-9a-f]+\.a\.\#(albumID)-\d+/"#
        ) else { return nil }
        for entry in files(in: cacheDirectory, withExtension: nil) {
            guard let text = head(of: entry),
                  let match = pattern.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  let range = Range(match.range, in: text) else { continue }
            return String(text[range])
        }
        return nil
    }

    /// Newest first, so the current play and the latest cached cover are found without reading everything.
    private static func files(in directory: URL, withExtension pathExtension: String?) -> [URL] {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .isRegularFileKey]
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys)) ?? []
        return urls
            .filter { pathExtension == nil || $0.pathExtension == pathExtension }
            .compactMap { url -> (URL, Date)? in
                guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { return nil }
                return (url, values.contentModificationDate ?? .distantPast)
            }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
    }

    private static func modificationDate(of url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }

    /// A cache entry starts with its key, the URL it stores.
    private static func head(of url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: cacheKeyBytes) else { return nil }
        return String(data: data, encoding: .isoLatin1)
    }

    /// Latin-1 keeps every byte as one character, so ASCII markers inside the binary format stay intact.
    private static func tail(of url: URL, bytes: Int) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return nil }
        try? handle.seek(toOffset: size > UInt64(bytes) ? size - UInt64(bytes) : 0)
        guard let data = try? handle.readToEnd() else { return nil }
        return String(data: data, encoding: .isoLatin1)
    }
}
