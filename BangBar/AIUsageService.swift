import Combine
import Foundation

struct AIProviderUsage {
    let primary: AIUsageWindow?
    let secondary: AIUsageWindow?
}

struct AIUsageWindow {
    let label: String
    let usedPercent: Int
    let resetsAt: Date?
}

/// Codex's `primary_window`/`secondary_window` don't reliably mean "5h"/"7d" — some ChatGPT plans
/// only expose a single pooled window (e.g. weekly-only), which still arrives as `primary_window`.
/// The label must come from the window's actual duration, not its position in the response.
private func windowDurationLabel(seconds: TimeInterval) -> String {
    guard seconds > 0 else { return "—" }
    let hours = seconds / 3600
    if hours < 36 { return "\(Int(hours.rounded()))h" }
    let days = Int((seconds / 86400).rounded())
    return days == 7 ? "W" : "\(days)d"
}

private enum AIUsageFetchOutcome {
    case notSignedIn
    case usage(AIProviderUsage)
    case transientFailure
}

@MainActor
final class AIUsageService: ObservableObject {
    static let refreshInterval: Duration = .seconds(5 * 60)
    /// Right after boot the network can still be coming up when the first fetch fires;
    /// retry quickly instead of leaving the widget empty for a full refreshInterval.
    static let retryInterval: Duration = .seconds(15)

    @Published private(set) var codex: AIProviderUsage?
    @Published private(set) var claude: AIProviderUsage?

    @discardableResult
    func refresh() async -> Bool {
        async let codexOutcome = Self.fetchCodexUsage()
        async let claudeOutcome = Self.fetchClaudeUsage()

        let codexNeedsRetry = apply(await codexOutcome, to: \.codex)
        let claudeNeedsRetry = apply(await claudeOutcome, to: \.claude)

        return codexNeedsRetry || claudeNeedsRetry
    }

    private func apply(_ outcome: AIUsageFetchOutcome, to keyPath: ReferenceWritableKeyPath<AIUsageService, AIProviderUsage?>) -> Bool {
        switch outcome {
        case .notSignedIn:
            self[keyPath: keyPath] = nil
            return false
        case .usage(let usage):
            self[keyPath: keyPath] = usage
            return false
        case .transientFailure:
            return self[keyPath: keyPath] == nil
        }
    }

    // MARK: - Codex

    private static func fetchCodexUsage() async -> AIUsageFetchOutcome {
        guard let (accessToken, accountId) = await codexAccessToken() else { return .notSignedIn }

        var request = URLRequest(url: URL(string: "https://chatgpt.com/backend-api/wham/usage")!)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("BangBar", forHTTPHeaderField: "User-Agent")
        if let accountId {
            request.setValue(accountId, forHTTPHeaderField: "ChatGPT-Account-Id")
        }

        return await fetchUsage(request, as: CodexUsageResponse.self) { payload in
            AIProviderUsage(
                primary: payload.rateLimit?.primaryWindow?.usageWindow,
                secondary: payload.rateLimit?.secondaryWindow?.usageWindow
            )
        }
    }

    private static func fetchUsage<Payload: Decodable>(
        _ request: URLRequest,
        as type: Payload.Type,
        makeUsage: (Payload) -> AIProviderUsage
    ) async -> AIUsageFetchOutcome {
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse else { return .transientFailure }

        if http.statusCode == 401 || http.statusCode == 403 { return .notSignedIn }
        guard (200..<300).contains(http.statusCode),
              let payload = try? snakeCaseDecoder().decode(type, from: data) else {
            return .transientFailure
        }
        return .usage(makeUsage(payload))
    }

    private nonisolated static func snakeCaseDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }

    private nonisolated static func codexAccessToken() async -> (accessToken: String, accountId: String?)? {
        await Task.detached(priority: .utility) {
            let codexHome = ProcessInfo.processInfo.environment["CODEX_HOME"].map(NSString.init(string:))?
                .expandingTildeInPath
                ?? (NSHomeDirectory() as NSString).appendingPathComponent(".codex")
            let authURL = URL(fileURLWithPath: codexHome).appendingPathComponent("auth.json")

            guard let data = try? Data(contentsOf: authURL),
                  let auth = try? snakeCaseDecoder().decode(CodexAuthFile.self, from: data),
                  let accessToken = auth.tokens?.accessToken else { return nil }

            return (accessToken, auth.tokens?.accountId)
        }.value
    }

    private nonisolated struct CodexAuthFile: Decodable {
        struct Tokens: Decodable {
            let accessToken: String?
            let accountId: String?
        }

        let tokens: Tokens?
    }

    private struct CodexUsageResponse: Decodable {
        struct RateLimit: Decodable {
            struct Window: Decodable {
                let usedPercent: Int
                let resetAt: TimeInterval
                let limitWindowSeconds: TimeInterval

                var usageWindow: AIUsageWindow {
                    AIUsageWindow(
                        label: windowDurationLabel(seconds: limitWindowSeconds),
                        usedPercent: usedPercent,
                        resetsAt: Date(timeIntervalSince1970: resetAt)
                    )
                }
            }

            let primaryWindow: Window?
            let secondaryWindow: Window?
        }

        let rateLimit: RateLimit?
    }

    // MARK: - Claude

    private static func fetchClaudeUsage() async -> AIUsageFetchOutcome {
        guard let accessToken = await claudeAccessToken() else { return .notSignedIn }

        var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")

        return await fetchUsage(request, as: ClaudeUsageResponse.self) { payload in
            AIProviderUsage(
                primary: payload.fiveHour?.usageWindow(label: "5h"),
                secondary: payload.sevenDay?.usageWindow(label: "W")
            )
        }
    }

    /// Anthropic may return ISO-8601 timestamps either with or without fractional seconds.
    private static func parseISO8601Date(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }

    private nonisolated static func claudeAccessToken() async -> String? {
        if let token = await claudeAccessTokenFromFile() {
            return token
        }
        return await claudeAccessTokenFromKeychain()
    }

    private nonisolated static func claudeAccessTokenFromFile() async -> String? {
        await Task.detached(priority: .utility) {
            let path = (NSHomeDirectory() as NSString).appendingPathComponent(".claude/.credentials.json")
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return nil }
            return decodeClaudeOAuthToken(from: data)
        }.value
    }

    private nonisolated static func claudeAccessTokenFromKeychain() async -> String? {
        await Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
            process.arguments = ["find-generic-password", "-s", "Claude Code-credentials", "-w"]

            let stdout = Pipe()
            process.standardOutput = stdout
            process.standardError = Pipe()

            guard (try? process.run()) != nil else { return nil }
            let data = stdout.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()

            guard process.terminationStatus == 0, !data.isEmpty else { return nil }
            var payload = data
            if payload.last == 0x0A { payload.removeLast() }
            return decodeClaudeOAuthToken(from: payload)
        }.value
    }

    private nonisolated static func decodeClaudeOAuthToken(from data: Data) -> String? {
        try? JSONDecoder().decode(ClaudeCredentialsFile.self, from: data).claudeAiOauth?.accessToken
    }

    private nonisolated struct ClaudeCredentialsFile: Decodable {
        struct OAuth: Decodable {
            let accessToken: String?
        }

        let claudeAiOauth: OAuth?
    }

    private struct ClaudeUsageResponse: Decodable {
        struct Window: Decodable {
            let utilization: Double
            let resetsAt: String?

            func usageWindow(label: String) -> AIUsageWindow {
                AIUsageWindow(
                    label: label,
                    usedPercent: Int(utilization.rounded()),
                    resetsAt: resetsAt.flatMap(parseISO8601Date)
                )
            }
        }

        let fiveHour: Window?
        let sevenDay: Window?
    }
}
