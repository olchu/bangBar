import AppKit
import Combine

enum ClipboardItemKind: String, Codable {
    case text
    case image
}

struct ClipboardHistoryItem: Identifiable, Codable, Equatable {
    let id: UUID
    let kind: ClipboardItemKind
    let data: Data
    let createdAt: Date

    var text: String? {
        guard kind == .text else { return nil }
        return String(data: data, encoding: .utf8)
    }

    var image: NSImage? {
        guard kind == .image else { return nil }
        return NSImage(data: data)
    }
}

@MainActor
final class ClipboardHistoryService: ObservableObject {
    @Published private(set) var items: [ClipboardHistoryItem] = []

    private let pasteboard: NSPasteboard
    private let storageURL: URL
    private var timer: Timer?
    private var lastChangeCount: Int
    private let maximumItemCount = 50

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
        self.lastChangeCount = pasteboard.changeCount

        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        storageURL = applicationSupport
            .appendingPathComponent("BangBar", isDirectory: true)
            .appendingPathComponent("clipboard-history.json")

        load()
        startMonitoring()
    }

    deinit {
        timer?.invalidate()
    }

    func copy(_ item: ClipboardHistoryItem) {
        pasteboard.clearContents()

        switch item.kind {
        case .text:
            guard let text = item.text else { return }
            pasteboard.setString(text, forType: .string)
        case .image:
            guard let image = item.image else { return }
            pasteboard.writeObjects([image])
        }

        lastChangeCount = pasteboard.changeCount
    }

    func remove(_ item: ClipboardHistoryItem) {
        items.removeAll { $0.id == item.id }
        save()
    }

    func clear() {
        items.removeAll()
        save()
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

    private func capturePasteboardIfNeeded() {
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount

        if let imageData = normalizedImageData(from: pasteboard) {
            insert(kind: .image, data: imageData)
        } else if let text = pasteboard.string(forType: .string), !text.isEmpty,
                  let data = text.data(using: .utf8) {
            insert(kind: .text, data: data)
        }
    }

    private func normalizedImageData(from pasteboard: NSPasteboard) -> Data? {
        let types: [NSPasteboard.PasteboardType] = [.png, .tiff]
        for type in types {
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

    private func insert(kind: ClipboardItemKind, data: Data) {
        if let existingIndex = items.firstIndex(where: { $0.kind == kind && $0.data == data }) {
            items.remove(at: existingIndex)
        }

        items.insert(
            ClipboardHistoryItem(id: UUID(), kind: kind, data: data, createdAt: Date()),
            at: 0
        )
        if items.count > maximumItemCount {
            items.removeLast(items.count - maximumItemCount)
        }
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: storageURL),
              let decoded = try? JSONDecoder().decode([ClipboardHistoryItem].self, from: data) else {
            return
        }
        items = Array(decoded.prefix(maximumItemCount))
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(
                at: storageURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(items)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            NSLog("BangBar clipboard history save failed: %@", error.localizedDescription)
        }
    }
}
