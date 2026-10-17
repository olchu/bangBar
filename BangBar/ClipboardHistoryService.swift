import AppKit
import Combine
import CryptoKit
import ImageIO
import UniformTypeIdentifiers

enum ClipboardItemKind: String, Codable {
    case text
    case image
}

struct ClipboardHistoryItem: Identifiable, Codable, Equatable {
    let id: UUID
    let kind: ClipboardItemKind
    let payload: String
    let contentHash: String
    let byteCount: Int
    let createdAt: Date
    let groupID: UUID?
    var isPinned: Bool

    private enum CodingKeys: String, CodingKey {
        case id, kind, payload, contentHash, byteCount, createdAt, groupID, isPinned
    }

    init(
        id: UUID,
        kind: ClipboardItemKind,
        payload: String,
        contentHash: String,
        byteCount: Int,
        createdAt: Date,
        groupID: UUID?,
        isPinned: Bool = false
    ) {
        self.id = id
        self.kind = kind
        self.payload = payload
        self.contentHash = contentHash
        self.byteCount = byteCount
        self.createdAt = createdAt
        self.groupID = groupID
        self.isPinned = isPinned
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        kind = try container.decode(ClipboardItemKind.self, forKey: .kind)
        payload = try container.decode(String.self, forKey: .payload)
        contentHash = try container.decode(String.self, forKey: .contentHash)
        byteCount = try container.decode(Int.self, forKey: .byteCount)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        groupID = try container.decodeIfPresent(UUID.self, forKey: .groupID)
        isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
    }

    var text: String? {
        kind == .text ? payload : nil
    }

    var imageFileName: String? {
        kind == .image ? payload : nil
    }
}

struct ClipboardImageGroup: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    let createdAt: Date
    var isPinned: Bool

    private enum CodingKeys: String, CodingKey {
        case id, name, createdAt, isPinned
    }

    init(id: UUID, name: String, createdAt: Date, isPinned: Bool = false) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.isPinned = isPinned
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
    }
}

private struct LegacyClipboardHistoryItem: Codable {
    let id: UUID
    let kind: ClipboardItemKind
    let data: Data
    let createdAt: Date
}

private enum ClipboardImageSource: Sendable {
    case pngData(Data)
    case encodedData(Data)
    case file(URL)
}

@MainActor
final class ClipboardHistoryService: ObservableObject {
    static let maximumItemCount = 200
    static let maximumItemBytes = 20 * 1_024 * 1_024

    @Published private(set) var items: [ClipboardHistoryItem] = []
    @Published private(set) var groups: [ClipboardImageGroup] = []
    @Published private(set) var totalBytes = 0
    @Published private(set) var activeGroupID: UUID?
    @Published private(set) var collectionSecondsRemaining = 0

    private let pasteboard: NSPasteboard
    private let rootDirectory: URL
    private let imagesDirectory: URL
    private let indexURL: URL
    private let legacyIndexURL: URL
    private let groupsURL: URL
    private let thumbnailCache = NSCache<NSString, NSImage>()
    private let imageProcessingQueue = DispatchQueue(
        label: "BangBar.ClipboardImageProcessing",
        qos: .utility
    )
    private var timer: Timer?
    private var settingsObserver: AnyCancellable?
    private var shortcutSettingObserver: AnyCancellable?
    private var lastChangeCount: Int
    private var collectionStartedAt: Date?
    private var lastGroupCaptureAt: Date?
    private var pendingCaptureDeadline: Date?
    private var lastStableFingerprint: String?
    private var imageCaptureGeneration = 0
    private var shortcutMonitors: [Any] = []
    private var shortcutIsPressed = false
    private var shortcutSuppressedUntil = Date.distantPast

    private let collectionInactivityTimeout: TimeInterval = 2 * 60
    private let collectionMaximumDuration: TimeInterval = 15 * 60
    private let collectionMaximumItems = 30

    var storageLimitBytes: Int {
        max(BangBarSettings.clipboardStorageLimitMB, 1) * 1_024 * 1_024
    }

    var formattedUsage: String {
        ByteCountFormatter.string(fromByteCount: Int64(totalBytes), countStyle: .file)
    }

    var activeGroup: ClipboardImageGroup? {
        guard let activeGroupID else { return nil }
        return groups.first { $0.id == activeGroupID }
    }

    var isCollectingImages: Bool {
        activeGroupID != nil
    }

    var activeGroupItemCount: Int {
        guard let activeGroupID else { return 0 }
        return items.count { $0.groupID == activeGroupID }
    }

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
        self.lastChangeCount = pasteboard.changeCount

        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        let bangBarDirectory = applicationSupport.appendingPathComponent("BangBar", isDirectory: true)
        rootDirectory = bangBarDirectory.appendingPathComponent("ClipboardHistory", isDirectory: true)
        imagesDirectory = rootDirectory.appendingPathComponent("Images", isDirectory: true)
        indexURL = rootDirectory.appendingPathComponent("index.json")
        legacyIndexURL = bangBarDirectory.appendingPathComponent("clipboard-history.json")
        groupsURL = rootDirectory.appendingPathComponent("groups.json")

        thumbnailCache.countLimit = 40
        thumbnailCache.totalCostLimit = 32 * 1_024 * 1_024

        prepareDirectories()
        load()
        lastStableFingerprint = currentPasteboardFingerprint()
        startMonitoring()
        observeSettings()
    }

    deinit {
        timer?.invalidate()
        shortcutMonitors.forEach(NSEvent.removeMonitor)
    }

    func image(for item: ClipboardHistoryItem) -> NSImage? {
        guard let fileName = item.imageFileName else { return nil }
        return NSImage(contentsOf: imagesDirectory.appendingPathComponent(fileName))
    }

    func releaseCachedImages() {
        thumbnailCache.removeAllObjects()
    }

    func thumbnail(for item: ClipboardHistoryItem) -> NSImage? {
        guard let fileName = item.imageFileName else { return nil }
        let key = fileName as NSString
        if let cached = thumbnailCache.object(forKey: key) {
            return cached
        }

        let url = imagesDirectory.appendingPathComponent(fileName) as CFURL
        guard let source = CGImageSourceCreateWithURL(url, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(
                source,
                0,
                [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 320,
                    kCGImageSourceShouldCacheImmediately: true
                ] as CFDictionary
              ) else {
            return nil
        }

        let image = NSImage(cgImage: cgImage, size: .zero)
        let decodedByteCost = cgImage.bytesPerRow * cgImage.height
        thumbnailCache.setObject(image, forKey: key, cost: decodedByteCost)
        return image
    }

    func copy(_ item: ClipboardHistoryItem) {
        switch item.kind {
        case .text:
            guard let text = item.text else { return }
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
        case .image:
            guard let image = image(for: item) else { return }
            pasteboard.clearContents()
            pasteboard.writeObjects([image])
        }

        lastChangeCount = pasteboard.changeCount
    }

    func startNewGroup() {
        stopCollecting()
        let group = ClipboardImageGroup(
            id: UUID(),
            name: "Group \(groups.count + 1)",
            createdAt: Date()
        )
        groups.insert(group, at: 0)
        activeGroupID = group.id
        collectionStartedAt = Date()
        lastGroupCaptureAt = Date()
        collectionSecondsRemaining = Int(collectionInactivityTimeout)
        saveGroups()
    }

    func stopCollecting() {
        activeGroupID = nil
        collectionStartedAt = nil
        lastGroupCaptureAt = nil
        collectionSecondsRemaining = 0
        removeEmptyGroups()
        saveGroups()
    }

    func items(in group: ClipboardImageGroup) -> [ClipboardHistoryItem] {
        pinnedFirst(items.filter { $0.groupID == group.id && $0.kind == .image })
    }

    func pinnedFirst(_ items: [ClipboardHistoryItem]) -> [ClipboardHistoryItem] {
        items.sorted {
            if $0.isPinned != $1.isPinned { return $0.isPinned }
            return $0.createdAt > $1.createdAt
        }
    }

    var pinnedFirstGroups: [ClipboardImageGroup] {
        groups.sorted {
            if $0.isPinned != $1.isPinned { return $0.isPinned }
            return $0.createdAt > $1.createdAt
        }
    }

    func copy(_ group: ClipboardImageGroup) {
        // Multiple NSImage objects are exposed as independent pasteboard items.
        // Many destination apps only consume one of those items. File URLs make
        // the group an explicit multi-file paste that Finder and editors can read.
        let fileURLs = items(in: group)
            .reversed()
            .compactMap { item -> NSURL? in
                guard let fileName = item.imageFileName else { return nil }
                let url = imagesDirectory.appendingPathComponent(fileName)
                guard FileManager.default.fileExists(atPath: url.path) else { return nil }
                return url as NSURL
            }
        guard !fileURLs.isEmpty else { return }
        pasteboard.clearContents()
        pasteboard.writeObjects(fileURLs)
        lastChangeCount = pasteboard.changeCount
    }

    func rename(_ group: ClipboardImageGroup, to newName: String) {
        let trimmedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty,
              let index = groups.firstIndex(where: { $0.id == group.id }) else { return }
        groups[index].name = trimmedName
        saveGroups()
    }

    func togglePin(_ item: ClipboardHistoryItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].isPinned.toggle()
        saveIndex()
    }

    func togglePin(_ group: ClipboardImageGroup) {
        guard let index = groups.firstIndex(where: { $0.id == group.id }) else { return }
        groups[index].isPinned.toggle()
        saveGroups()
    }

    func delete(_ group: ClipboardImageGroup) {
        imageCaptureGeneration += 1
        if activeGroupID == group.id {
            stopCollecting()
        }
        let groupItems = items(in: group)
        for item in groupItems {
            deletePayload(for: item)
        }
        items.removeAll { $0.groupID == group.id }
        groups.removeAll { $0.id == group.id }
        refreshUsage()
        saveIndex()
        saveGroups()
    }

    func remove(_ item: ClipboardHistoryItem) {
        deletePayload(for: item)
        items.removeAll { $0.id == item.id }
        refreshUsage()
        saveIndex()
        removeEmptyGroups()
        saveGroups()
    }

    func clear() {
        imageCaptureGeneration += 1
        stopCollecting()
        let pinnedGroupIDs = Set(groups.filter(\.isPinned).map(\.id))
        let removedItems = items.filter {
            !$0.isPinned && !($0.groupID.map(pinnedGroupIDs.contains) ?? false)
        }
        for item in removedItems {
            deletePayload(for: item)
        }
        items.removeAll { removedItems.contains($0) }
        let retainedGroupIDs = Set(items.compactMap(\.groupID))
        groups.removeAll { !$0.isPinned && !retainedGroupIDs.contains($0.id) }
        refreshUsage()
        saveIndex()
        saveGroups()
    }

    private func startMonitoring() {
        let timer = Timer(timeInterval: 0.6, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.capturePasteboardIfNeeded() }
        }
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func observeSettings() {
        // Any defaults write in the app lands here; only a new storage limit needs the history rewritten.
        settingsObserver = NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .map { _ in BangBarSettings.clipboardStorageLimitMB }
            .prepend(BangBarSettings.clipboardStorageLimitMB)
            .removeDuplicates()
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.enforceLimitsAndSave()
            }
        // The shortcut is off by default; without it there is no reason to see every keystroke in the system.
        shortcutSettingObserver = NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .map { _ in UserDefaults.standard.bool(forKey: BangBarSettings.Key.clipboardIgnoreShortcutEnabled) }
            .prepend(UserDefaults.standard.bool(forKey: BangBarSettings.Key.clipboardIgnoreShortcutEnabled))
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] isEnabled in
                self?.setShortcutMonitoring(isEnabled)
            }
    }

    private func capturePasteboardIfNeeded() {
        updateCollectionSession()

        if Self.needsResyncAfterSuspension, Self.externalSuspensionCount == 0 {
            Self.needsResyncAfterSuspension = false
            pendingCaptureDeadline = nil
            lastChangeCount = pasteboard.changeCount
            lastStableFingerprint = currentPasteboardFingerprint()
            return
        }

        if let pendingCaptureDeadline,
           Date() >= pendingCaptureDeadline,
           !isCaptureSuppressed,
           pasteboard.changeCount == lastChangeCount {
            self.pendingCaptureDeadline = nil
            captureCurrentPasteboardIfNew()
        }

        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount

        if isCaptureSuppressed {
            pendingCaptureDeadline = nil
            lastStableFingerprint = currentPasteboardFingerprint()
            return
        }

        if UserDefaults.standard.bool(forKey: BangBarSettings.Key.clipboardIgnoreTransientChanges) {
            let delayMS = max(
                UserDefaults.standard.integer(forKey: BangBarSettings.Key.clipboardTransientDelayMS),
                100
            )
            pendingCaptureDeadline = Date().addingTimeInterval(Double(delayMS) / 1000)
            return
        }

        captureCurrentPasteboardIfNew()
    }

    private func captureCurrentPasteboardIfNew() {
        let fileURLs = fileURLs(from: pasteboard)
        if !fileURLs.isEmpty {
            let fingerprint = fileFingerprint(fileURLs)
            guard fingerprint != lastStableFingerprint else { return }
            lastStableFingerprint = fingerprint
            for url in fileURLs where isImageFile(url) {
                scheduleImageCapture(from: .file(url), groupID: activeGroupID)
            }
        } else if let (source, fingerprintData) = imageSource(from: pasteboard) {
            let fingerprint = dataFingerprint(fingerprintData, prefix: "image-source:")
            guard fingerprint != lastStableFingerprint else { return }
            lastStableFingerprint = fingerprint
            scheduleImageCapture(from: source, groupID: activeGroupID)
        } else if let text = pasteboard.string(forType: .string), !text.isEmpty,
                  let data = text.data(using: .utf8) {
            let contentHash = Self.dataHash(data)
            let fingerprint = "text:" + contentHash
            guard fingerprint != lastStableFingerprint else { return }
            lastStableFingerprint = fingerprint
            insertText(text, data: data, contentHash: contentHash)
        }
    }

    private static var externalSuspensionCount = 0
    private static var needsResyncAfterSuspension = false

    /// Lets other features use the pasteboard as scratch space (copy → transform → paste → restore).
    /// Nothing written until the matching `resumeCapture()` reaches the history, however long it takes,
    /// and whatever the pasteboard holds afterwards is adopted as already seen rather than captured.
    static func suspendCapture() {
        externalSuspensionCount += 1
    }

    static func resumeCapture() {
        externalSuspensionCount = max(externalSuspensionCount - 1, 0)
        if externalSuspensionCount == 0 {
            needsResyncAfterSuspension = true
        }
    }

    private var isCaptureSuppressed: Bool {
        isShortcutSuppressionActive || Self.externalSuspensionCount > 0
    }

    private var isShortcutSuppressionActive: Bool {
        UserDefaults.standard.bool(forKey: BangBarSettings.Key.clipboardIgnoreShortcutEnabled)
            && (shortcutIsPressed || Date() < shortcutSuppressedUntil)
    }

    private func setShortcutMonitoring(_ isEnabled: Bool) {
        shortcutMonitors.forEach(NSEvent.removeMonitor)
        shortcutMonitors = []
        shortcutIsPressed = false
        guard isEnabled else { return }

        // Both kinds of monitor call back on the main thread.
        let types: NSEvent.EventTypeMask = [.keyDown, .keyUp, .flagsChanged]
        let global = NSEvent.addGlobalMonitorForEvents(matching: types) { [weak self] event in
            MainActor.assumeIsolated { self?.handleShortcutEvent(event) }
        }
        let local = NSEvent.addLocalMonitorForEvents(matching: types) { [weak self] event in
            MainActor.assumeIsolated { self?.handleShortcutEvent(event) }
            return event
        }
        shortcutMonitors = [global, local].compactMap { $0 }
    }

    private func handleShortcutEvent(_ event: NSEvent) {
        let defaults = UserDefaults.standard
        let keyCode = defaults.integer(forKey: BangBarSettings.Key.clipboardIgnoreShortcutKeyCode)
        let expectedModifiers = UInt(defaults.integer(forKey: BangBarSettings.Key.clipboardIgnoreShortcutModifiers))
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard keyCode >= 0, Int(event.keyCode) == keyCode else { return }

        let isDown: Bool
        if event.type == .flagsChanged {
            guard expectedModifiers == NSEvent.ModifierFlags.function.rawValue else { return }
            isDown = modifiers.contains(.function)
        } else {
            guard modifiers.rawValue == expectedModifiers else { return }
            isDown = event.type == .keyDown
        }

        shortcutIsPressed = isDown
        if !isDown {
            let graceMS = max(defaults.integer(forKey: BangBarSettings.Key.clipboardIgnoreShortcutGraceMS), 0)
            shortcutSuppressedUntil = Date().addingTimeInterval(Double(graceMS) / 1000)
        }
    }

    private func currentPasteboardFingerprint() -> String? {
        let fileURLs = fileURLs(from: pasteboard)
        if !fileURLs.isEmpty {
            return fileFingerprint(fileURLs)
        }
        if let (_, fingerprintData) = imageSource(from: pasteboard) {
            return dataFingerprint(fingerprintData, prefix: "image-source:")
        }
        if let text = pasteboard.string(forType: .string),
           let data = text.data(using: .utf8) {
            return dataFingerprint(data, prefix: "text:")
        }
        return nil
    }

    private func fileFingerprint(_ urls: [URL]) -> String? {
        let value = urls.map(\.path).sorted().joined(separator: "\n")
        guard let data = value.data(using: .utf8) else { return nil }
        return dataFingerprint(data, prefix: "files:")
    }

    private func dataFingerprint(_ data: Data, prefix: String) -> String {
        prefix + Self.dataHash(data)
    }

    private nonisolated static func dataHash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func fileURLs(from pasteboard: NSPasteboard) -> [URL] {
        let objects = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) ?? []
        return objects.compactMap { ($0 as? NSURL).map { $0 as URL } }
    }

    private func isImageFile(_ url: URL) -> Bool {
        guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true,
              let type = UTType(filenameExtension: url.pathExtension) else {
            return false
        }
        return type.conforms(to: .image)
    }

    private func imageSource(from pasteboard: NSPasteboard) -> (ClipboardImageSource, Data)? {
        if let png = pasteboard.data(forType: .png) {
            return (.pngData(png), png)
        }
        if let encodedData = pasteboard.data(forType: .tiff) {
            return (.encodedData(encodedData), encodedData)
        }
        return nil
    }

    private func scheduleImageCapture(from source: ClipboardImageSource, groupID: UUID?) {
        let imagesDirectory = imagesDirectory
        let maximumItemBytes = Self.maximumItemBytes
        let generation = imageCaptureGeneration
        imageProcessingQueue.async { [weak self] in
            guard self != nil else { return }
            guard let data = Self.normalizedImageData(from: source),
                  data.count <= maximumItemBytes else { return }

            let contentHash = Self.dataHash(data)
            let fileName = "\(UUID().uuidString).png"
            let fileURL = imagesDirectory.appendingPathComponent(fileName)
            do {
                try data.write(to: fileURL, options: .atomic)
            } catch {
                NSLog("BangBar clipboard image save failed: %@", error.localizedDescription)
                return
            }

            DispatchQueue.main.async { [weak self] in
                guard let self else {
                    try? FileManager.default.removeItem(at: fileURL)
                    return
                }
                guard self.imageCaptureGeneration == generation,
                      groupID == nil || self.groups.contains(where: { $0.id == groupID }) else {
                    try? FileManager.default.removeItem(at: fileURL)
                    return
                }
                self.insertStoredImage(
                    fileName: fileName,
                    byteCount: data.count,
                    contentHash: contentHash,
                    groupID: groupID
                )
            }
        }
    }

    private nonisolated static func normalizedImageData(from source: ClipboardImageSource) -> Data? {
        switch source {
        case .pngData(let data):
            return data
        case .encodedData(let data):
            return pngData(from: data)
        case .file(let url):
            guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
            if url.pathExtension.lowercased() == "png" { return data }
            return pngData(from: data)
        }
    }

    private nonisolated static func pngData(from encodedData: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(encodedData as CFData, nil),
              let output = CFDataCreateMutable(nil, 0),
              let destination = CGImageDestinationCreateWithData(
                output,
                UTType.png.identifier as CFString,
                1,
                nil
              ) else { return nil }

        CGImageDestinationAddImageFromSource(destination, source, 0, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    private func insertText(_ text: String, data: Data, contentHash: String? = nil) {
        guard data.count <= Self.maximumItemBytes else { return }
        insert(
            kind: .text,
            payload: text,
            byteCount: data.count,
            contentHash: contentHash ?? Self.dataHash(data)
        )
    }

    private func insertStoredImage(
        fileName: String,
        byteCount: Int,
        contentHash: String,
        groupID: UUID?
    ) {
        insert(
            kind: .image,
            payload: fileName,
            byteCount: byteCount,
            contentHash: contentHash,
            groupID: groupID
        )
        if groupID != nil, activeGroupID == groupID {
            lastGroupCaptureAt = Date()
            updateCollectionSession()
        }
    }

    private func insert(
        kind: ClipboardItemKind,
        payload: String,
        byteCount: Int,
        contentHash: String,
        groupID: UUID? = nil
    ) {
        let existing = items.first { $0.kind == kind && $0.contentHash == contentHash }
        if let existing {
            deletePayload(for: existing)
            items.removeAll { $0.id == existing.id }
        }

        items.insert(
            ClipboardHistoryItem(
                id: UUID(),
                kind: kind,
                payload: payload,
                contentHash: contentHash,
                byteCount: byteCount,
                createdAt: Date(),
                groupID: groupID,
                isPinned: existing?.isPinned ?? false
            ),
            at: 0
        )
        enforceLimitsAndSave()
    }

    private func enforceLimitsAndSave() {
        refreshUsage()
        while items.count > Self.maximumItemCount || totalBytes > storageLimitBytes {
            let pinnedGroupIDs = Set(groups.filter(\.isPinned).map(\.id))
            guard let oldest = items.last(where: {
                !$0.isPinned && !($0.groupID.map(pinnedGroupIDs.contains) ?? false)
            }) else { break }
            deletePayload(for: oldest)
            items.removeAll { $0.id == oldest.id }
            totalBytes -= oldest.byteCount
        }
        refreshUsage()
        saveIndex()
        removeEmptyGroups()
        saveGroups()
    }

    private func load() {
        if let data = try? Data(contentsOf: indexURL),
           let decoded = try? JSONDecoder().decode([ClipboardHistoryItem].self, from: data) {
            items = decoded.filter { item in
                item.kind == .text || imageFileExists(for: item)
            }
        } else {
            migrateLegacyHistory()
        }
        if let data = try? Data(contentsOf: groupsURL),
           let decodedGroups = try? JSONDecoder().decode([ClipboardImageGroup].self, from: data) {
            groups = decodedGroups
        }
        removeEmptyGroups()
        enforceLimitsAndSave()
    }

    private func migrateLegacyHistory() {
        guard let data = try? Data(contentsOf: legacyIndexURL),
              let legacyItems = try? JSONDecoder().decode([LegacyClipboardHistoryItem].self, from: data) else {
            return
        }

        for legacyItem in legacyItems.reversed() where legacyItem.data.count <= Self.maximumItemBytes {
            switch legacyItem.kind {
            case .text:
                guard let text = String(data: legacyItem.data, encoding: .utf8) else { continue }
                insertMigrated(kind: .text, payload: text, data: legacyItem.data, createdAt: legacyItem.createdAt)
            case .image:
                let fileName = "\(legacyItem.id.uuidString).png"
                do {
                    try legacyItem.data.write(to: imagesDirectory.appendingPathComponent(fileName), options: .atomic)
                    insertMigrated(kind: .image, payload: fileName, data: legacyItem.data, createdAt: legacyItem.createdAt)
                } catch {
                    NSLog("BangBar clipboard migration failed: %@", error.localizedDescription)
                }
            }
        }
    }

    private func insertMigrated(kind: ClipboardItemKind, payload: String, data: Data, createdAt: Date) {
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        items.insert(
            ClipboardHistoryItem(
                id: UUID(), kind: kind, payload: payload, contentHash: hash,
                byteCount: data.count, createdAt: createdAt, groupID: nil
            ),
            at: 0
        )
    }

    private func imageFileExists(for item: ClipboardHistoryItem) -> Bool {
        guard let fileName = item.imageFileName else { return false }
        return FileManager.default.fileExists(atPath: imagesDirectory.appendingPathComponent(fileName).path)
    }

    private func deletePayload(for item: ClipboardHistoryItem) {
        guard let fileName = item.imageFileName else { return }
        thumbnailCache.removeObject(forKey: fileName as NSString)
        try? FileManager.default.removeItem(at: imagesDirectory.appendingPathComponent(fileName))
    }

    private func refreshUsage() {
        totalBytes = items.reduce(0) { $0 + $1.byteCount }
    }

    private func updateCollectionSession(now: Date = Date()) {
        guard activeGroupID != nil,
              let collectionStartedAt,
              let lastGroupCaptureAt else {
            setCollectionSecondsRemaining(0)
            return
        }

        let inactivityRemaining = collectionInactivityTimeout - now.timeIntervalSince(lastGroupCaptureAt)
        let durationRemaining = collectionMaximumDuration - now.timeIntervalSince(collectionStartedAt)
        setCollectionSecondsRemaining(max(0, Int(ceil(min(inactivityRemaining, durationRemaining)))))

        if inactivityRemaining <= 0 || durationRemaining <= 0 || activeGroupItemCount >= collectionMaximumItems {
            stopCollecting()
        }
    }

    // Runs on every pasteboard poll; @Published notifies even for an unchanged value, which would re-render
    // every observer of the service twice a second.
    private func setCollectionSecondsRemaining(_ seconds: Int) {
        guard collectionSecondsRemaining != seconds else { return }
        collectionSecondsRemaining = seconds
    }

    private func removeEmptyGroups() {
        let populatedGroupIDs = Set(items.compactMap(\.groupID))
        groups.removeAll { !populatedGroupIDs.contains($0.id) && $0.id != activeGroupID }
    }

    private func prepareDirectories() {
        do {
            try FileManager.default.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
        } catch {
            NSLog("BangBar clipboard directory creation failed: %@", error.localizedDescription)
        }
    }

    private func saveIndex() {
        do {
            let data = try JSONEncoder().encode(items)
            try data.write(to: indexURL, options: .atomic)
        } catch {
            NSLog("BangBar clipboard history save failed: %@", error.localizedDescription)
        }
    }

    private func saveGroups() {
        do {
            let data = try JSONEncoder().encode(groups)
            try data.write(to: groupsURL, options: .atomic)
        } catch {
            NSLog("BangBar clipboard groups save failed: %@", error.localizedDescription)
        }
    }
}
