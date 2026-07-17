import AppKit
import Combine
import CryptoKit

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
}

private struct LegacyClipboardHistoryItem: Codable {
    let id: UUID
    let kind: ClipboardItemKind
    let data: Data
    let createdAt: Date
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
    private let imageCache = NSCache<NSString, NSImage>()
    private var timer: Timer?
    private var settingsObserver: AnyCancellable?
    private var lastChangeCount: Int
    private var collectionStartedAt: Date?
    private var lastGroupCaptureAt: Date?
    private var pendingCaptureDeadline: Date?
    private var lastStableFingerprint: String?
    private var shortcutKeyDownMonitor: Any?
    private var shortcutKeyUpMonitor: Any?
    private var shortcutFlagsMonitor: Any?
    private var shortcutLocalMonitor: Any?
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

        prepareDirectories()
        load()
        lastStableFingerprint = currentPasteboardFingerprint()
        startMonitoring()
        startShortcutMonitoring()
        observeSettings()
    }

    deinit {
        timer?.invalidate()
        if let shortcutKeyDownMonitor { NSEvent.removeMonitor(shortcutKeyDownMonitor) }
        if let shortcutKeyUpMonitor { NSEvent.removeMonitor(shortcutKeyUpMonitor) }
        if let shortcutFlagsMonitor { NSEvent.removeMonitor(shortcutFlagsMonitor) }
        if let shortcutLocalMonitor { NSEvent.removeMonitor(shortcutLocalMonitor) }
    }

    func image(for item: ClipboardHistoryItem) -> NSImage? {
        guard let fileName = item.imageFileName else { return nil }
        let key = fileName as NSString
        if let cached = imageCache.object(forKey: key) {
            return cached
        }

        guard let image = NSImage(contentsOf: imagesDirectory.appendingPathComponent(fileName)) else {
            return nil
        }
        imageCache.setObject(image, forKey: key)
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
        items.filter { $0.groupID == group.id && $0.kind == .image }
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

    func delete(_ group: ClipboardImageGroup) {
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
        for item in items {
            deletePayload(for: item)
        }
        imageCache.removeAllObjects()
        items.removeAll()
        groups.removeAll()
        stopCollecting()
        refreshUsage()
        saveIndex()
    }

    private func startMonitoring() {
        let timer = Timer(timeInterval: 0.6, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.capturePasteboardIfNeeded()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func observeSettings() {
        settingsObserver = NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.enforceLimitsAndSave()
            }
    }

    private func capturePasteboardIfNeeded() {
        updateCollectionSession()

        if let pendingCaptureDeadline,
           Date() >= pendingCaptureDeadline,
           !isShortcutSuppressionActive,
           pasteboard.changeCount == lastChangeCount {
            self.pendingCaptureDeadline = nil
            captureCurrentPasteboardIfNew()
        }

        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount

        if isShortcutSuppressionActive {
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
        let fingerprint = currentPasteboardFingerprint()
        guard fingerprint != lastStableFingerprint else { return }
        lastStableFingerprint = fingerprint

        if let imageData = normalizedImageData(from: pasteboard) {
            insertImage(imageData)
        } else if let text = pasteboard.string(forType: .string), !text.isEmpty,
                  let data = text.data(using: .utf8) {
            insertText(text, data: data)
        }
    }

    private var isShortcutSuppressionActive: Bool {
        UserDefaults.standard.bool(forKey: BangBarSettings.Key.clipboardIgnoreShortcutEnabled)
            && (shortcutIsPressed || Date() < shortcutSuppressedUntil)
    }

    private func startShortcutMonitoring() {
        shortcutKeyDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            Task { @MainActor [weak self] in self?.handleShortcutEvent(event, isDown: true) }
        }
        shortcutKeyUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyUp) { [weak self] event in
            Task { @MainActor [weak self] in self?.handleShortcutEvent(event, isDown: false) }
        }
        shortcutFlagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            Task { @MainActor [weak self] in self?.handleModifierShortcutEvent(event) }
        }
        shortcutLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { [weak self] event in
            Task { @MainActor [weak self] in
                if event.type == .flagsChanged {
                    self?.handleModifierShortcutEvent(event)
                } else {
                    self?.handleShortcutEvent(event, isDown: event.type == .keyDown)
                }
            }
            return event
        }
    }

    private func handleModifierShortcutEvent(_ event: NSEvent) {
        let defaults = UserDefaults.standard
        let expectedModifiers = UInt(defaults.integer(forKey: BangBarSettings.Key.clipboardIgnoreShortcutModifiers))
        guard defaults.bool(forKey: BangBarSettings.Key.clipboardIgnoreShortcutEnabled),
              expectedModifiers == NSEvent.ModifierFlags.function.rawValue,
              Int(event.keyCode) == defaults.integer(forKey: BangBarSettings.Key.clipboardIgnoreShortcutKeyCode) else {
            return
        }

        let isDown = event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.function)
        shortcutIsPressed = isDown
        if !isDown {
            let graceMS = max(defaults.integer(forKey: BangBarSettings.Key.clipboardIgnoreShortcutGraceMS), 0)
            shortcutSuppressedUntil = Date().addingTimeInterval(Double(graceMS) / 1000)
        }
    }

    private func handleShortcutEvent(_ event: NSEvent, isDown: Bool) {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: BangBarSettings.Key.clipboardIgnoreShortcutEnabled),
              defaults.integer(forKey: BangBarSettings.Key.clipboardIgnoreShortcutKeyCode) >= 0,
              Int(event.keyCode) == defaults.integer(forKey: BangBarSettings.Key.clipboardIgnoreShortcutKeyCode) else {
            return
        }
        let expected = UInt(defaults.integer(forKey: BangBarSettings.Key.clipboardIgnoreShortcutModifiers))
        let actual = event.modifierFlags.intersection(.deviceIndependentFlagsMask).rawValue
        guard actual == expected else { return }

        shortcutIsPressed = isDown
        if !isDown {
            let graceMS = max(defaults.integer(forKey: BangBarSettings.Key.clipboardIgnoreShortcutGraceMS), 0)
            shortcutSuppressedUntil = Date().addingTimeInterval(Double(graceMS) / 1000)
        }
    }

    private func currentPasteboardFingerprint() -> String? {
        if let imageData = normalizedImageData(from: pasteboard) {
            return "image:" + SHA256.hash(data: imageData).map { String(format: "%02x", $0) }.joined()
        }
        if let text = pasteboard.string(forType: .string),
           let data = text.data(using: .utf8) {
            return "text:" + SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        }
        return nil
    }

    private func normalizedImageData(from pasteboard: NSPasteboard) -> Data? {
        for type in [NSPasteboard.PasteboardType.png, .tiff] {
            guard let sourceData = pasteboard.data(forType: type),
                  let image = NSImage(data: sourceData),
                  let tiff = image.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiff),
                  let png = bitmap.representation(using: .png, properties: [:]) else {
                continue
            }
            return png
        }
        return nil
    }

    private func insertText(_ text: String, data: Data) {
        guard data.count <= Self.maximumItemBytes else { return }
        insert(kind: .text, payload: text, data: data)
    }

    private func insertImage(_ data: Data) {
        guard data.count <= Self.maximumItemBytes else { return }
        let fileName = "\(UUID().uuidString).png"
        do {
            try data.write(to: imagesDirectory.appendingPathComponent(fileName), options: .atomic)
            insert(kind: .image, payload: fileName, data: data, groupID: activeGroupID)
            if activeGroupID != nil {
                lastGroupCaptureAt = Date()
                updateCollectionSession()
            }
        } catch {
            NSLog("BangBar clipboard image save failed: %@", error.localizedDescription)
        }
    }

    private func insert(
        kind: ClipboardItemKind,
        payload: String,
        data: Data,
        groupID: UUID? = nil
    ) {
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        if let existing = items.first(where: { $0.kind == kind && $0.contentHash == hash }) {
            deletePayload(for: existing)
            items.removeAll { $0.id == existing.id }
        }

        items.insert(
            ClipboardHistoryItem(
                id: UUID(),
                kind: kind,
                payload: payload,
                contentHash: hash,
                byteCount: data.count,
                createdAt: Date(),
                groupID: groupID
            ),
            at: 0
        )
        enforceLimitsAndSave()
    }

    private func enforceLimitsAndSave() {
        refreshUsage()
        while items.count > Self.maximumItemCount || totalBytes > storageLimitBytes {
            guard let oldest = items.last else { break }
            deletePayload(for: oldest)
            items.removeLast()
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
        imageCache.removeObject(forKey: fileName as NSString)
        try? FileManager.default.removeItem(at: imagesDirectory.appendingPathComponent(fileName))
    }

    private func refreshUsage() {
        totalBytes = items.reduce(0) { $0 + $1.byteCount }
    }

    private func updateCollectionSession(now: Date = Date()) {
        guard activeGroupID != nil,
              let collectionStartedAt,
              let lastGroupCaptureAt else {
            collectionSecondsRemaining = 0
            return
        }

        let inactivityRemaining = collectionInactivityTimeout - now.timeIntervalSince(lastGroupCaptureAt)
        let durationRemaining = collectionMaximumDuration - now.timeIntervalSince(collectionStartedAt)
        collectionSecondsRemaining = max(0, Int(ceil(min(inactivityRemaining, durationRemaining))))

        if inactivityRemaining <= 0 || durationRemaining <= 0 || activeGroupItemCount >= collectionMaximumItems {
            stopCollecting()
        }
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
