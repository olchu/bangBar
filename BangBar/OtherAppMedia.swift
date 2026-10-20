import AppKit
import ImageIO

/// Now Playing info for an app other than the players: the playing browser tab when it can be found,
/// otherwise the app's name and icon.
final class OtherAppMedia {
    private static let fastRefreshInterval: TimeInterval = 5
    private static let slowRefreshInterval: TimeInterval = 15
    /// Autoplay moves on soon after a page change, so refreshes slow down only once the page has settled.
    private static let settleTime: TimeInterval = 30
    private static let cacheLimit = 8

    /// Called when a refresh changes `info`; `track(_:)` does not call it because its caller reads `info` right after.
    var onChange: (() -> Void)?

    func info(isPlaying: Bool) -> NowPlayingInfo? {
        guard let app else { return nil }
        return NowPlayingInfo(
            title: page.map(\.title).flatMap { $0.isEmpty ? nil : $0 } ?? app.name,
            artist: page?.subtitle ?? (isPlaying ? "Playing audio" : "Paused"),
            isPlaying: isPlaying,
            artwork: page?.artwork ?? icon
        )
    }

    private var app: AudioApp?
    private var icon: NSImage?
    private var page: WebMedia?
    private var pageChangedAt = Date.distantPast
    private var timer: Timer?
    private var refreshTask: Task<Void, Never>?
    /// Lookups by media key, so a refresh of the same page or a return to it costs no network request.
    private var cache: [String: WebMedia] = [:]
    private var cacheOrder: [String] = []

    func track(_ app: AudioApp?) {
        // Another helper process of the same app taking over the audio is still the same page.
        let isSameApp = app?.bundleIdentifier == self.app?.bundleIdentifier
            && app?.processIdentifier == self.app?.processIdentifier
        self.app = app
        guard !isSameApp else { return }

        timer?.invalidate()
        timer = nil
        refreshTask?.cancel()
        refreshTask = nil
        page = nil
        icon = app.flatMap { NSRunningApplication(processIdentifier: $0.processIdentifier)?.icon }
        guard let app, let browser = Browser(bundleIdentifier: app.bundleIdentifier) else { return }
        refresh(browser)
    }

    private func refresh(_ browser: Browser) {
        refreshTask = Task { [weak self] in
            let tab = await Task.detached(priority: .utility) { browser.playingTab() }.value
            guard let self, !Task.isCancelled else { return }
            let page = await page(for: tab)
            guard !Task.isCancelled else { return }
            if self.page != page {
                self.page = page
                pageChangedAt = Date()
                onChange?()
            }
            let isSettled = Date().timeIntervalSince(pageChangedAt) > Self.settleTime
            scheduleRefresh(browser, after: isSettled ? Self.slowRefreshInterval : Self.fastRefreshInterval)
        }
    }

    private func scheduleRefresh(_ browser: Browser, after interval: TimeInterval) {
        let timer = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh(browser) }
        }
        timer.tolerance = 1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func page(for tab: BrowserTab?) async -> WebMedia? {
        guard let tab else { return nil }
        let key = WebMediaLookup.key(for: tab.url)
        if let cached = cache[key] {
            cacheOrder.removeAll { $0 == key }
            cacheOrder.append(key)
            return cached
        }

        let info = await WebMediaLookup.info(for: tab)
        let page = WebMedia(
            title: info.title,
            subtitle: info.subtitle,
            artwork: info.image.map { NSImage(cgImage: $0, size: .zero) }
        )
        // Other tabs cost no request and their titles change; a cancelled lookup returns its fallback, not the media.
        guard WebMediaLookup.isMediaPage(tab.url), !Task.isCancelled else { return page }
        if cacheOrder.count >= Self.cacheLimit {
            cache[cacheOrder.removeFirst()] = nil
        }
        cache[key] = page
        cacheOrder.append(key)
        return page
    }
}

private struct WebMedia: Equatable {
    let title: String
    let subtitle: String
    let artwork: NSImage?
}

nonisolated struct BrowserTab: Sendable {
    let url: URL
    let title: String
}

private nonisolated struct Browser: Sendable {
    let bundleIdentifier: String
    let frontTab: String
    let titleProperty: String

    init?(bundleIdentifier: String) {
        switch bundleIdentifier {
        case "com.apple.Safari", "com.apple.SafariTechnologyPreview":
            (frontTab, titleProperty) = ("current tab", "name")
        case "com.google.Chrome", "com.google.Chrome.beta", "com.google.Chrome.dev", "com.google.Chrome.canary",
             "com.brave.Browser", "com.microsoft.edgemac", "company.thebrowser.Browser", "com.vivaldi.Vivaldi",
             "ru.yandex.desktop.yandex-browser", "org.chromium.Chromium":
            (frontTab, titleProperty) = ("active tab", "title")
        default:
            return nil
        }
        self.bundleIdentifier = bundleIdentifier
    }

    /// Bulk property reads cost three Apple Events however many tabs are open; lists of lists flatten
    /// into one line per tab. Returns the front tab URL, all tab URLs and all tab titles, separated by RS.
    private var tabsScript: String {
        """
        if application id "\(bundleIdentifier)" is not running then return ""
        set AppleScript's text item delimiters to linefeed
        tell application id "\(bundleIdentifier)"
            set frontURL to ""
            try
                set frontURL to (URL of \(frontTab) of front window) as text
            end try
            set tabURLs to ""
            set tabTitles to ""
            try
                set tabURLs to (URL of every tab of every window) as text
                set tabTitles to (\(titleProperty) of every tab of every window) as text
            end try
        end tell
        return frontURL & character id 30 & tabURLs & character id 30 & tabTitles
        """
    }

    /// Blocks on osascript; call off the main thread.
    func playingTab() -> BrowserTab? {
        guard let output = AppleScriptRunner.output(of: tabsScript) else { return nil }
        let sections = output.components(separatedBy: "\u{1E}")
        guard sections.count == 3 else { return nil }
        let frontURL = URL(string: sections[0])
        let urls = sections[1].components(separatedBy: "\n")
        var titles = sections[2].components(separatedBy: "\n")
        // A title with a line break would shift every later title, so titles are dropped rather than mismatched.
        if titles.count != urls.count {
            titles = Array(repeating: "", count: urls.count)
        }
        let tabs = zip(urls, titles).compactMap { url, title -> BrowserTab? in
            guard let url = URL(string: url), url.scheme?.hasPrefix("http") == true else { return nil }
            return BrowserTab(url: url, title: title)
        }
        // A media page is the likely source; among several, the front tab, which the user usually just started.
        let mediaTabs = tabs.filter { WebMediaLookup.isMediaPage($0.url) }
        return mediaTabs.first { $0.url == frontURL } ?? mediaTabs.first ?? tabs.first { $0.url == frontURL }
    }
}

nonisolated struct WebMediaInfo: Sendable {
    let title: String
    let subtitle: String
    let image: CGImage?
}

/// Public page metadata: oEmbed where a site offers it without a key, otherwise the page's Open Graph tags.
nonisolated enum WebMediaLookup {
    /// Ephemeral and uncached: no cookies are sent, and responses are not kept twice next to `OtherAppMedia`'s cache.
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 6
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"
        ]
        return URLSession(configuration: configuration)
    }()

    private static let pageByteLimit = 512 * 1024
    private static let headCheckInterval = 16 * 1024
    /// About twice the largest artwork on screen.
    private static let thumbnailPixelSize = 320

    private static let youtubeOEmbed = "https://www.youtube.com/oembed?format=json&url="
    private static let oEmbedEndpoints = [
        "vimeo.com": "https://vimeo.com/api/oembed.json?url=",
        "soundcloud.com": "https://soundcloud.com/oembed?format=json&url=",
        "open.spotify.com": "https://open.spotify.com/oembed?url=",
        "dailymotion.com": "https://www.dailymotion.com/services/oembed?format=json&url="
    ]
    /// Media sites without oEmbed; their Open Graph tags describe the media.
    private static let openGraphMediaHosts = [
        "twitch.tv", "music.apple.com", "bandcamp.com", "deezer.com", "tidal.com", "music.yandex.ru",
        "music.yandex.com", "rutube.ru", "netflix.com", "kinopoisk.ru", "primevideo.com", "disneyplus.com", "tv.apple.com"
    ]
    private static let mediaHosts = openGraphMediaHosts + oEmbedEndpoints.keys

    static func isMediaPage(_ url: URL) -> Bool {
        youtubeVideoID(in: url) != nil || mediaHosts.contains { host(of: url, matches: $0) }
    }

    /// Identifies the media rather than the URL, so a timestamp or playlist parameter does not trigger a new lookup.
    static func key(for url: URL) -> String {
        if let id = youtubeVideoID(in: url) { return "youtube:\(id)" }
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.fragment = nil
        return components?.string ?? url.absoluteString
    }

    /// Only media pages are looked up; for any other tab the title and site name are already known.
    @concurrent
    static func info(for tab: BrowserTab) async -> WebMediaInfo {
        let fallback = WebMediaInfo(title: tab.title, subtitle: siteName(of: tab.url), image: nil)
        guard isMediaPage(tab.url) else { return fallback }

        let found: (title: String?, subtitle: String?, imageURL: URL?)?
        if let id = youtubeVideoID(in: tab.url) {
            let oEmbed = await oEmbed(youtubeOEmbed, for: "https://www.youtube.com/watch?v=\(id)")
            // mqdefault is 16:9 without the letterbox bars of hqdefault.
            found = (oEmbed?.title, oEmbed?.authorName ?? "YouTube", URL(string: "https://i.ytimg.com/vi/\(id)/mqdefault.jpg"))
        } else if let endpoint = oEmbedEndpoints.first(where: { host(of: tab.url, matches: $0.key) })?.value,
                  let oEmbed = await oEmbed(endpoint, for: tab.url.absoluteString) {
            found = (oEmbed.title, oEmbed.authorName, oEmbed.thumbnailUrl)
        } else if let tags = await openGraphTags(of: tab.url) {
            let image = tags["og:image"] ?? tags["og:image:url"] ?? tags["twitter:image"]
            found = (
                tags["og:title"] ?? tags["twitter:title"],
                tags["og:site_name"],
                image.flatMap { URL(string: $0, relativeTo: tab.url)?.absoluteURL }
            )
        } else {
            found = nil
        }
        guard let found else { return fallback }

        var image: CGImage?
        if let imageURL = found.imageURL {
            image = await thumbnail(at: imageURL)
        }
        return WebMediaInfo(title: found.title ?? fallback.title, subtitle: found.subtitle ?? fallback.subtitle, image: image)
    }

    private static func youtubeVideoID(in url: URL) -> String? {
        guard let host = url.host?.lowercased() else { return nil }
        let path = url.pathComponents.filter { $0 != "/" }
        if host == "youtu.be" { return path.first }
        guard host == "youtube.com" || host.hasSuffix(".youtube.com") else { return nil }
        if path.first == "watch" {
            return URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first { $0.name == "v" }?.value
        }
        if path.count >= 2, ["shorts", "live", "embed"].contains(path[0]) { return path[1] }
        return nil
    }

    private static func host(of url: URL, matches domain: String) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return host == domain || host.hasSuffix(".\(domain)")
    }

    private static func siteName(of url: URL) -> String {
        let host = url.host ?? ""
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    private struct OEmbed: Decodable {
        let title: String?
        let authorName: String?
        let thumbnailUrl: URL?
    }

    private static func oEmbed(_ endpoint: String, for pageURL: String) async -> OEmbed? {
        guard let encoded = pageURL.addingPercentEncoding(withAllowedCharacters: .alphanumerics),
              let url = URL(string: endpoint + encoded),
              let (data, response) = try? await session.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try? decoder.decode(OEmbed.self, from: data)
    }

    /// Reads only up to `</head>`, where Open Graph tags live.
    private static func openGraphTags(of url: URL) async -> [String: String]? {
        var request = URLRequest(url: url)
        request.setValue("text/html", forHTTPHeaderField: "Accept")
        guard let (bytes, response) = try? await session.bytes(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        let headEnds = [Data("</head>".utf8), Data("</HEAD>".utf8)]
        var data = Data()
        data.reserveCapacity(pageByteLimit)
        do {
            for try await byte in bytes {
                data.append(byte)
                guard data.count % headCheckInterval == 0 else { continue }
                let recent = max(data.count - headCheckInterval - headEnds[0].count, 0)..<data.count
                if data.count >= pageByteLimit || headEnds.contains(where: { data.range(of: $0, in: recent) != nil }) { break }
            }
        } catch {
            return nil
        }
        return metaTags(in: String(decoding: data, as: UTF8.self))
    }

    /// The first value per name wins, so head tags win over any in the body.
    private static func metaTags(in html: String) -> [String: String] {
        var tags: [String: String] = [:]
        for tag in html.matches(of: /(?i)<meta\s[^>]*>/) {
            var attributes: [String: String] = [:]
            for attribute in tag.output.matches(of: /([a-zA-Z:-]+)\s*=\s*(?:"([^"]*)"|'([^']*)')/) {
                attributes[attribute.output.1.lowercased()] = String(attribute.output.2 ?? attribute.output.3 ?? "")
            }
            guard let name = (attributes["property"] ?? attributes["name"])?.lowercased(), tags[name] == nil,
                  let content = attributes["content"].map(decodeEntities), !content.isEmpty else { continue }
            tags[name] = content
        }
        return tags
    }

    private static func decodeEntities(_ text: String) -> String {
        [("&quot;", "\""), ("&#39;", "'"), ("&#039;", "'"), ("&apos;", "'"), ("&lt;", "<"), ("&gt;", ">"), ("&amp;", "&")]
            .reduce(text) { $0.replacingOccurrences(of: $1.0, with: $1.1) }
    }

    /// Decoded and scaled here, off the main thread, so a large og:image is never kept or drawn at full size.
    private static func thumbnail(at url: URL) async -> CGImage? {
        guard let (data, _) = try? await session.data(from: url),
              let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: thumbnailPixelSize
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
