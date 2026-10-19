import Foundation
import OSLog

enum AppleScriptResult {
    case success(String)
    case failure(String)
}

nonisolated enum AppleScriptRunner {
    private static let logger = Logger(subsystem: "BangBar", category: "AppleScript")

    /// Runs through `/usr/bin/osascript` because `NSAppleScript` breaks under Hardened Runtime. Blocks; call off the main thread.
    static func run(_ source: String) -> AppleScriptResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", source]
        let output = Pipe()
        let error = Pipe()
        process.standardOutput = output
        process.standardError = error

        do {
            try process.run()
        } catch {
            logger.error("osascript failed to launch: \(error.localizedDescription, privacy: .public)")
            return .failure(error.localizedDescription)
        }
        let outputData = output.fileHandleForReading.readDataToEndOfFile()
        let errorData = error.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let message = String(decoding: errorData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            logger.error("AppleScript failed: \(message, privacy: .public)")
            return .failure(message.isEmpty ? "Unknown AppleScript error" : message)
        }
        // Strip only osascript's trailing newline: callers split on "\n", and empty leading fields must survive.
        var text = String(decoding: outputData, as: UTF8.self)
        if text.hasSuffix("\n") {
            text.removeLast()
        }
        return .success(text)
    }

    static func output(of source: String) -> String? {
        guard case .success(let output) = run(source), !output.isEmpty else { return nil }
        return output
    }
}
