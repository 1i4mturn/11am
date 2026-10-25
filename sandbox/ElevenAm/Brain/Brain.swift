import Foundation
import SwiftUI

/// How the brain is allowed to think.
enum BrainMode: String, CaseIterable, Identifiable {
    /// Never leaves this Mac.
    case onDevice
    /// Quick work on this Mac; heavier work uses Claude if you've added a key and allowed it.
    case balanced
    /// Prefers Claude whenever a key is set (still falls back to this Mac).
    case cloud

    var id: String { rawValue }

    var title: String {
        switch self {
        case .onDevice: return "On this Mac only"
        case .balanced: return "Balanced"
        case .cloud: return "Prefer Claude"
        }
    }

    var detail: String {
        switch self {
        case .onDevice: return "Free, private, works offline. Answers are shorter and simpler."
        case .balanced: return "Quick things stay on this Mac. Deeper work (briefs, research) can use Claude."
        case .cloud: return "Best answers. Costs a little per request on your Claude API key."
        }
    }
}

/// Quick = classify, short rewrites, small answers. Deep = briefs, synthesis, longer reasoning.
enum TaskWeight {
    case quick, deep
}

struct BrainRequest {
    var system: String
    var prompt: String
    var weight: TaskWeight = .quick
    var allowsCloud = true

    var maxTokens: Int { weight == .quick ? 4_000 : 16_000 }
}

enum BrainChunk {
    case delta(String)
    case usage(input: Int, output: Int)
    case model(String)
    case refusal
}

enum BrainError: LocalizedError {
    case unavailable(String)
    case missingKey
    case http(Int, String)
    case badResponse

    var errorDescription: String? {
        switch self {
        case .unavailable(let reason): return reason
        case .missingKey: return "Add a Claude API key in Settings › Brain to use the cloud."
        case .http(let code, let message): return "Claude returned \(code): \(message)"
        case .badResponse: return "The response couldn't be read."
        }
    }
}

enum ProviderKind: String {
    case appleOnDevice, localServer, claude

    var isLocal: Bool { self != .claude }
}

protocol BrainProvider {
    var kind: ProviderKind { get }
    var label: String { get }
    func stream(_ request: BrainRequest) -> AsyncThrowingStream<BrainChunk, Error>
}

/// One request through the brain. Views observe it while it streams.
@MainActor
final class BrainRun: ObservableObject, Identifiable {
    enum Status: Equatable {
        case routing, working, done, failed(String)
    }

    let id = UUID()
    let prompt: String
    let startedAt = Date()
    @Published var text = ""
    @Published var status: Status = .routing
    @Published var providerLabel = ""
    @Published var isLocal = true
    @Published var costUSD: Double = 0

    init(prompt: String) {
        self.prompt = prompt
    }

    var isFinished: Bool {
        switch status {
        case .done, .failed: return true
        default: return false
        }
    }

    /// Waits until the run has finished streaming.
    func finished() async {
        while !isFinished {
            try? await Task.sleep(nanoseconds: 150_000_000)
        }
    }
}

/// Routes every request to the cheapest brain that can do it well:
/// Apple's on-device model, a local model server, or Claude with the user's own key.
@MainActor
final class Brain: ObservableObject {
    @Published var mode: BrainMode { didSet { defaults.set(mode.rawValue, forKey: "brain.mode") } }
    @Published var claudeModel: String { didSet { defaults.set(claudeModel, forKey: "brain.claudeModel") } }
    @Published var monthlyBudgetUSD: Double { didSet { defaults.set(monthlyBudgetUSD, forKey: "brain.budget") } }
    @Published var allowCloudOvernight: Bool { didSet { defaults.set(allowCloudOvernight, forKey: "brain.cloudOvernight") } }
    @Published var localServerEnabled: Bool { didSet { defaults.set(localServerEnabled, forKey: "brain.local.enabled") } }
    @Published var localServerURL: String { didSet { defaults.set(localServerURL, forKey: "brain.local.url") } }
    @Published var localServerModel: String { didSet { defaults.set(localServerModel, forKey: "brain.local.model") } }

    @Published private(set) var hasClaudeKey = false
    @Published private(set) var spentThisMonthUSD: Double = 0
    @Published private(set) var activeRuns = 0
    @Published private(set) var lastRun: BrainRun?

    private let defaults = UserDefaults.standard
    private let apple = AppleOnDeviceProvider()

    init() {
        let stored = UserDefaults.standard
        mode = BrainMode(rawValue: stored.string(forKey: "brain.mode") ?? "") ?? .balanced
        claudeModel = stored.string(forKey: "brain.claudeModel") ?? ClaudeModel.defaultID
        monthlyBudgetUSD = stored.object(forKey: "brain.budget") as? Double ?? 5
        allowCloudOvernight = stored.bool(forKey: "brain.cloudOvernight")
        localServerEnabled = stored.bool(forKey: "brain.local.enabled")
        localServerURL = stored.string(forKey: "brain.local.url") ?? "http://localhost:11434/v1"
        localServerModel = stored.string(forKey: "brain.local.model") ?? "qwen3.5:4b"
        hasClaudeKey = Keychain.read(account: Keychain.claudeAccount) != nil
        loadSpend()
    }

    var appleStatus: (available: Bool, detail: String) { apple.availability() }

    var isBusy: Bool { activeRuns > 0 }

    var budgetRemaining: Double { max(0, monthlyBudgetUSD - spentThisMonthUSD) }

    // MARK: Key

    func saveClaudeKey(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        hasClaudeKey = Keychain.save(trimmed, account: Keychain.claudeAccount)
    }

    func removeClaudeKey() {
        Keychain.delete(account: Keychain.claudeAccount)
        hasClaudeKey = false
    }

    // MARK: Running

    func run(_ request: BrainRequest) -> BrainRun {
        let run = BrainRun(prompt: request.prompt)
        lastRun = run
        activeRuns += 1
        Task { @MainActor in
            defer { self.activeRuns -= 1 }
            guard let provider = await self.route(request) else {
                run.status = .failed(self.noBrainMessage)
                return
            }
            run.providerLabel = provider.label
            run.isLocal = provider.kind.isLocal
            run.status = .working

            var model = provider.label
            var inputTokens = 0
            var outputTokens = 0
            do {
                for try await chunk in provider.stream(request) {
                    switch chunk {
                    case .delta(let text):
                        run.text += text
                    case .usage(let input, let output):
                        if input > 0 { inputTokens = input }
                        if output > 0 { outputTokens = output }
                    case .model(let name):
                        model = name
                    case .refusal:
                        run.text += run.text.isEmpty ? "Claude declined this request." : "\n\n(Claude stopped here.)"
                    }
                }
                if provider.kind == .claude {
                    let cost = Pricing.cost(model: model, inputTokens: inputTokens, outputTokens: outputTokens)
                    run.costUSD = cost
                    self.recordSpend(cost)
                }
                run.status = .done
            } catch {
                run.status = .failed(error.localizedDescription)
            }
        }
        return run
    }

    /// Picks a provider for this request, respecting mode, key, budget and what this Mac can do.
    func route(_ request: BrainRequest) async -> BrainProvider? {
        let local = await localProvider()
        let claude = claudeProvider(allowed: request.allowsCloud)

        switch mode {
        case .onDevice:
            return local
        case .balanced:
            if request.weight == .deep, let claude { return claude }
            return local ?? claude
        case .cloud:
            return claude ?? local
        }
    }

    private func localProvider() async -> BrainProvider? {
        if apple.availability().available { return apple }
        if localServerEnabled {
            let server = LocalServerProvider(baseURL: localServerURL, model: localServerModel)
            if await server.isReachable() { return server }
        }
        return nil
    }

    private func claudeProvider(allowed: Bool) -> BrainProvider? {
        guard allowed, mode != .onDevice, budgetRemaining > 0.001,
              let key = Keychain.read(account: Keychain.claudeAccount) else { return nil }
        return ClaudeProvider(apiKey: key, model: claudeModel)
    }

    private var noBrainMessage: String {
        let apple = appleStatus
        var parts = ["No brain is available for this yet."]
        if !apple.available { parts.append("Apple's on-device model: \(apple.detail).") }
        if !hasClaudeKey { parts.append("Add a Claude API key in Settings › Brain, or switch on a local model server.") }
        else if budgetRemaining <= 0.001 { parts.append("This month's Claude budget is used up.") }
        else if mode == .onDevice { parts.append("Mode is On this Mac only.") }
        return parts.joined(separator: " ")
    }

    // MARK: Spend

    private var monthKey: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        return formatter.string(from: Date())
    }

    private func loadSpend() {
        if defaults.string(forKey: "brain.spend.month") != monthKey {
            defaults.set(monthKey, forKey: "brain.spend.month")
            defaults.set(0.0, forKey: "brain.spend.usd")
        }
        spentThisMonthUSD = defaults.double(forKey: "brain.spend.usd")
    }

    private func recordSpend(_ amount: Double) {
        loadSpend()
        spentThisMonthUSD += amount
        defaults.set(spentThisMonthUSD, forKey: "brain.spend.usd")
    }
}
