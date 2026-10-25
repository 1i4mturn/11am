import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Apple's on-device model (macOS 26+ with Apple Intelligence on).
/// It ships with the OS and is shared by the system, so 11am loads nothing extra into memory:
/// the best possible local brain for an 8 GB Mac.
struct AppleOnDeviceProvider: BrainProvider {
    let kind = ProviderKind.appleOnDevice
    let label = "Apple on-device"

    /// Its context window is small (about 4K tokens), so long prompts are trimmed.
    private let maxPromptCharacters = 9_000

    func availability() -> (available: Bool, detail: String) {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return (true, "Ready")
            case .unavailable(let reason):
                return (false, AppleOnDeviceProvider.describe(reason))
            @unknown default:
                return (false, "Unavailable")
            }
        }
        #endif
        return (false, "Needs macOS 26 with Apple Intelligence turned on")
    }

    func stream(_ request: BrainRequest) -> AsyncThrowingStream<BrainChunk, Error> {
        let prompt = String(request.prompt.prefix(maxPromptCharacters))
        let instructions = request.system
        return AsyncThrowingStream { continuation in
            let task = Task {
                #if canImport(FoundationModels)
                if #available(macOS 26.0, *) {
                    do {
                        let session = LanguageModelSession(instructions: instructions)
                        let response = try await session.respond(to: prompt)
                        continuation.yield(.model("apple-on-device"))
                        continuation.yield(.delta(response.content))
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                    return
                }
                #endif
                continuation.finish(throwing: BrainError.unavailable("Apple's on-device model needs macOS 26 with Apple Intelligence."))
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    #if canImport(FoundationModels)
    @available(macOS 26.0, *)
    private static func describe(_ reason: SystemLanguageModel.Availability.UnavailableReason) -> String {
        switch reason {
        case .deviceNotEligible: return "This Mac can't run Apple Intelligence"
        case .appleIntelligenceNotEnabled: return "Turn on Apple Intelligence in System Settings"
        case .modelNotReady: return "The model is still downloading"
        @unknown default: return "Unavailable right now"
        }
    }
    #endif
}
