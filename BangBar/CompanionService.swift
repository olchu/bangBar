import AppKit
import Combine
import CoreGraphics
import Foundation

enum CompanionStage: String, Codable {
    case arrival
    case baby
    case child
    case teen
    case adult
}

enum CompanionNeed: String, Codable {
    case hungry
    case attention
    case dirty
}

struct CompanionState: Codable {
    static let currentVersion = 1

    var version = currentVersion
    var id = UUID()
    var createdAt = Date()
    var lastUpdatedAt = Date()
    var activeUseSeconds: TimeInterval = 0
    var stage: CompanionStage = .arrival
    var hunger = 4
    var happiness = 4
    var cleanliness = 4
    var discipline = 0
    var consecutiveUnresolvedNeeds = 0
    var careMistakes = 0
    var currentNeed: CompanionNeed?
    var currentNeedStartedAt: Date?
    var isSleeping = false
    var hungerProgress: TimeInterval = 0
    var happinessProgress: TimeInterval = 0
    var cleanlinessProgress: TimeInterval = 0
}

enum CompanionRules {
    static let meterRange = 0...4
    static let idleThreshold: TimeInterval = 10 * 60
    static let hungerStep: TimeInterval = 3 * 60 * 60
    static let happinessStep: TimeInterval = 4 * 60 * 60
    static let cleanlinessStep: TimeInterval = 6 * 60 * 60
    static let saveInterval: TimeInterval = 60
}

@MainActor
final class CompanionService: ObservableObject {
    static let shared = CompanionService()

    @Published private(set) var state: CompanionState
    @Published private(set) var reaction: String?

    private var timer: Timer?
    private var lastTick = Date()
    private var lastSave = Date.distantPast
    private var isSystemAvailable = true
    private var isFocusRunning = false
    private var reactionWorkItem: DispatchWorkItem?

    private init() {
        state = Self.load() ?? CompanionState()
        observeSystemState()
        startTimer()
    }

    var statusText: String {
        if let reaction { return reaction }
        switch state.currentNeed {
        case .hungry: return "A little hungry"
        case .attention: return "Wants company"
        case .dirty: return "Needs cleaning"
        case nil: return state.isSleeping ? "Resting" : "Feeling calm"
        }
    }

    func setFocusRunning(_ running: Bool) {
        isFocusRunning = running
        lastTick = Date()
    }

    func feed() {
        state.hunger = min(state.hunger + 2, CompanionRules.meterRange.upperBound)
        resolve(.hungry, reaction: "Yum!")
    }

    func pet() {
        state.happiness = min(state.happiness + 1, CompanionRules.meterRange.upperBound)
        resolve(.attention, reaction: "Happy to see you")
    }

    func clean() {
        state.cleanliness = CompanionRules.meterRange.upperBound
        resolve(.dirty, reaction: "All clean")
    }

    func reset() {
        state = CompanionState()
        reaction = "Hello!"
        persist()
        clearReaction(after: 1.8)
    }

    private func startTimer() {
        let timer = Timer(timeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        let now = Date()
        defer { lastTick = now }
        guard isSystemAvailable, !isFocusRunning, idleSeconds < CompanionRules.idleThreshold else { return }

        let elapsed = min(max(now.timeIntervalSince(lastTick), 0), 30)
        guard elapsed > 0 else { return }
        var updated = state
        updated.activeUseSeconds += elapsed
        updated.hungerProgress += elapsed
        updated.happinessProgress += elapsed
        updated.cleanlinessProgress += elapsed
        applyDecay(progress: &updated.hungerProgress, interval: CompanionRules.hungerStep, value: &updated.hunger)
        applyDecay(progress: &updated.happinessProgress, interval: CompanionRules.happinessStep, value: &updated.happiness)
        applyDecay(progress: &updated.cleanlinessProgress, interval: CompanionRules.cleanlinessStep, value: &updated.cleanliness)
        updated.currentNeed = mostImportantNeed(in: updated)
        if updated.currentNeed != nil, updated.currentNeedStartedAt == nil { updated.currentNeedStartedAt = now }
        if updated.currentNeed == nil { updated.currentNeedStartedAt = nil }
        updated.lastUpdatedAt = now
        state = updated

        if now.timeIntervalSince(lastSave) >= CompanionRules.saveInterval { persist() }
    }

    private func mostImportantNeed(in state: CompanionState) -> CompanionNeed? {
        if state.hunger <= 1 { return .hungry }
        if state.cleanliness <= 1 { return .dirty }
        if state.happiness <= 1 { return .attention }
        return nil
    }

    private var idleSeconds: TimeInterval {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .null)
    }

    private func applyDecay(progress: inout TimeInterval, interval: TimeInterval, value: inout Int) {
        while progress >= interval {
            progress -= interval
            value = max(value - 1, CompanionRules.meterRange.lowerBound)
        }
    }

    private func resolve(_ need: CompanionNeed, reaction: String) {
        if state.currentNeed == need {
            state.currentNeed = nil
            state.currentNeedStartedAt = nil
            state.consecutiveUnresolvedNeeds = 0
        }
        state.lastUpdatedAt = Date()
        self.reaction = reaction
        persist()
        clearReaction(after: 1.8)
    }

    private func clearReaction(after delay: TimeInterval) {
        reactionWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in self?.reaction = nil }
        reactionWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func observeSystemState() {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.isSystemAvailable = false
                self?.persist()
            }
        }
        center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.isSystemAvailable = true
                self?.lastTick = Date()
            }
        }
        center.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.isSystemAvailable = false
                self?.persist()
            }
        }
        center.addObserver(forName: NSWorkspace.sessionDidBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.isSystemAvailable = true
                self?.lastTick = Date()
            }
        }
    }

    private func persist() {
        state.lastUpdatedAt = Date()
        lastSave = Date()
        guard let data = try? JSONEncoder().encode(state), let url = Self.stateURL else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    private static func load() -> CompanionState? {
        guard let url = stateURL, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(CompanionState.self, from: data)
    }

    private static var stateURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("BangBar/Companion/companion.json")
    }
}
