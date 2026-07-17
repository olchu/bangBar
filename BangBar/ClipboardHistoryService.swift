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

    var text: String? {
        kind == .text ? payload : nil
    }

    var imageFileName: String? {
        kind == .image ? payload : nil
    }
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
    @Published private(set) var totalBytes = 0

    private let pasteboard: NSPasteboard
    private let rootDirectory: URL
    private let imagesDirectory: URL
    private let indexURL: URL
    private let legacyIndexURL: URL
    private let imageCache = NSCache<NSString, NSImage>()
    private var timer: Timer?
    private var settingsObserver: AnyCancellable?
    private var lastChangeCount: Int

    var storageLimitBytes: Int {
        max(BangBarSettings.clipboardStorageLimitMB, 1) * 1_024 * 1_024
    }

    var formattedUsage: String {
        ByteCountFormatter.string(fromByteCount: Int64(totalBytes), countStyle: .file)
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

        prepareDirectories()
        load()
        startMonitoring()
        observeSettings()
    }

    deinit {
        timer?.invalidate()
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

    func remove(_ item: ClipboardHistoryItem) {
        deletePayload(for: item)
        items.removeAll { $0.id == item.id }
        refreshUsage()
        saveIndex()
    }

    func clear() {
        for item in items {
            deletePayload(for: item)
        }
        imageCache.removeAllObjects()
        items.removeAll()
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
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount

        if let imageData = normalizedImageData(from: pasteboard) {
            insertImage(imageData)
        } else if let text = pasteboard.string(forType: .string), !text.isEmpty,
                  let data = text.data(using: .utf8) {
            insertText(text, data: data)
        }
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
            insert(kind: .image, payload: fileName, data: data)
        } catch {
            NSLog("BangBar clipboard image save failed: %@", error.localizedDescription)
        }
    }

    private func insert(kind: ClipboardItemKind, payload: String, data: Data) {
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
                createdAt: Date()
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
                byteCount: data.count, createdAt: createdAt
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
}
