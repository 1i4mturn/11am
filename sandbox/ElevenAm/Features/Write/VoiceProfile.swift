import Foundation

/// How you write. William learns it; Marc borrows it for every reply.
/// In the sandbox it's notes plus a few samples you paste. The real thing learns from sent mail and documents.
@MainActor
final class VoiceProfile: ObservableObject {
    @Published var notes: String { didSet { defaults.set(notes, forKey: "voice.notes") } }
    @Published var samples: String { didSet { defaults.set(samples, forKey: "voice.samples") } }

    static let defaultNotes = "Short, plain sentences. Friendly but direct. Australian spelling. No emoji, no exclamation marks, no corporate words like \"leverage\" or \"circle back\". Sign off with my first name only."

    private let defaults = UserDefaults.standard

    init() {
        notes = defaults.string(forKey: "voice.notes") ?? VoiceProfile.defaultNotes
        samples = defaults.string(forKey: "voice.samples") ?? ""
    }

    /// The voice, ready to drop into a system prompt.
    var instructions: String {
        var parts = ["How the user writes: \(notes.trimmingCharacters(in: .whitespacesAndNewlines))"]
        let trimmed = samples.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            parts.append("Examples of their writing (match the voice, not the content):\n\(String(trimmed.prefix(1_500)))")
        }
        return parts.joined(separator: "\n\n")
    }
}
