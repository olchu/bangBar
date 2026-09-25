import Foundation
import OSLog

/// Leaves a small session marker on disk so the next launch can distinguish a
/// normal quit from a crash, force-quit, or system termination.
final class AppHealthMonitor {
    private struct Session: Codable {
        let id: UUID
        let startedAt: Date
        var lastCheckpointAt: Date
        var lastContext: String
        let processIdentifier: Int32
        let appVersion: String
        let appBuild: String
        let operatingSystem: String
    }

    private struct UnexpectedTermination: Codable {
        let detectedAt: Date
        let previousSession: Session
    }

    private let logger = Logger(subsystem: "BangBar", category: "AppHealth")
    private let fileManager = FileManager.default
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private var session: Session?

    private var diagnosticsDirectory: URL {
        applicationSupportDirectory.appendingPathComponent("Diagnostics", isDirectory: true)
    }

    private var markerURL: URL {
        diagnosticsDirectory.appendingPathComponent("active-session.json")
    }

    private var applicationSupportDirectory: URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return base.appendingPathComponent("BangBar", isDirectory: true)
    }

    func start() {
        do {
            try fileManager.createDirectory(
                at: diagnosticsDirectory,
                withIntermediateDirectories: true
            )
            archivePreviousSessionIfNeeded()

            let bundle = Bundle.main
            let now = Date()
            session = Session(
                id: UUID(),
                startedAt: now,
                lastCheckpointAt: now,
                lastContext: "launch-completed",
                processIdentifier: ProcessInfo.processInfo.processIdentifier,
                appVersion: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
                appBuild: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
                operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString
            )
            try persistSession()
        } catch {
            logger.error("Unable to start health monitor: \(error.localizedDescription, privacy: .public)")
        }
    }

    func checkpoint(_ context: String) {
        guard session != nil else { return }
        session?.lastCheckpointAt = Date()
        session?.lastContext = context
        do {
            try persistSession()
        } catch {
            logger.error("Unable to save health checkpoint: \(error.localizedDescription, privacy: .public)")
        }
    }

    func markCleanShutdown() {
        session = nil
        do {
            if fileManager.fileExists(atPath: markerURL.path) {
                try fileManager.removeItem(at: markerURL)
            }
        } catch {
            logger.error("Unable to clear health marker: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func persistSession() throws {
        guard let session else { return }
        try encoder.encode(session).write(to: markerURL, options: .atomic)
    }

    private func archivePreviousSessionIfNeeded() {
        guard fileManager.fileExists(atPath: markerURL.path) else { return }
        defer { try? fileManager.removeItem(at: markerURL) }

        guard let data = try? Data(contentsOf: markerURL),
              let previousSession = try? decoder.decode(Session.self, from: data) else {
            logger.error("Unable to read the previous health marker")
            return
        }
        let incident = UnexpectedTermination(detectedAt: Date(), previousSession: previousSession)
        let timestamp = Int(Date().timeIntervalSince1970)
        let incidentURL = diagnosticsDirectory
            .appendingPathComponent(
                "unexpected-termination-\(timestamp)-\(previousSession.id.uuidString).json"
            )
        do {
            try encoder.encode(incident).write(to: incidentURL, options: .atomic)
        } catch {
            logger.error("Unable to archive the previous health marker: \(error.localizedDescription, privacy: .public)")
            return
        }
        logger.fault(
            "Previous session ended unexpectedly; last context: \(previousSession.lastContext, privacy: .public)"
        )
        trimArchivedIncidents()
    }

    private func trimArchivedIncidents() {
        guard let urls = try? fileManager.contentsOfDirectory(
            at: diagnosticsDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        let incidents = urls
            .filter { $0.lastPathComponent.hasPrefix("unexpected-termination-") }
            .sorted {
                let lhs = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                    ?? .distantPast
                let rhs = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                    ?? .distantPast
                return lhs > rhs
            }

        for url in incidents.dropFirst(10) {
            try? fileManager.removeItem(at: url)
        }
    }
}
