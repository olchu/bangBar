import CoreGraphics
import Foundation

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

    private static let albumPattern = try! NSRegularExpression(pattern: #"albumId"[\s\S](\d+)"#)

    /// The album of the newest play-log record. Blocks on file reads; call off the main thread.
    static func currentAlbumID() -> String? {
        let directory = root.appendingPathComponent("IndexedDB/music-application_desktop_0.indexeddb.leveldb")
        for log in files(in: directory, withExtension: "log") {
            guard let text = tail(of: log, bytes: logTailBytes),
                  let match = albumPattern.matches(in: text, range: NSRange(text.startIndex..., in: text)).last,
                  let range = Range(match.range(at: 1), in: text) else { continue }
            return String(text[range])
        }
        return nil
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
        for entry in files(in: root.appendingPathComponent("Cache/Cache_Data"), withExtension: nil) {
            guard let handle = try? FileHandle(forReadingFrom: entry) else { continue }
            defer { try? handle.close() }
            guard let data = try? handle.read(upToCount: cacheKeyBytes),
                  let text = String(data: data, encoding: .isoLatin1),
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
