import Foundation

struct TuneChange: Identifiable, Hashable {
    var id: String { name }
    let name: String
    let from: String
    let to: String
}

struct TuneRecord: Identifiable {
    let id = UUID()
    let request: String
    let before: ThemeValues
    let after: ThemeValues
    let date = Date()
}

/// Plain-English requests that change the look, understood without any model at all.
enum TuneRules {
    static func apply(_ request: String, to values: ThemeValues) -> ThemeValues {
        let text = request.lowercased()
        var v = values
        func has(_ words: String...) -> Bool { words.contains { text.contains($0) } }
        let lot = has("a lot", "much", "very", "way more", "really")
        let step = lot ? 0.3 : 0.15

        if has("reset", "default", "start over") { return ThemeValues() }
        if has("warmer", "warm", "cream", "vellum") { v.paperTone += step * 1.5 }
        if has("cooler", "whiter", "pure white", "colder") { v.paperTone -= step * 1.5 }
        if has("more transparent", "see-through", "see through", "clearer", "more glass", "see behind", "more clarity") {
            v.clarity += step
            v.frost -= step / 2
        }
        if has("less transparent", "more solid", "opaque", "frostier", "more frost", "less see") {
            v.clarity -= step
            v.frost += step / 2
        }
        if has("dark mode", "darker", "dark theme", "night") { v.appearance = .dark }
        if has("light mode", "lighter theme", "light theme") { v.appearance = .light }
        if has("follow the system", "match the system", "automatic") { v.appearance = .system }
        if has("rounder", "softer corners", "more rounded") { v.cornerRadius += lot ? 8 : 4 }
        if has("sharper", "squarer", "less rounded", "tighter corners") { v.cornerRadius -= lot ? 6 : 3 }
        if has("calmer", "less motion", "less movement", "still", "no animation") { v.motion -= lot ? 0.5 : 0.25 }
        if has("livelier", "more motion", "more movement", "bouncier", "more animation") { v.motion += lot ? 0.4 : 0.2 }
        if has("more grain", "more texture", "grainier", "papery") { v.grain += step }
        if has("less grain", "smoother", "no grain", "cleaner") { v.grain -= step }
        if has("softer text", "graphite", "softer ink") { v.inkSoftness += step * 2 }
        if has("crisper", "blacker", "more contrast", "sharper text", "darker text") { v.inkSoftness -= step * 2 }
        if has("deeper", "more depth", "more shadow", "layered") { v.depth += step }
        if has("flatter", "less shadow", "no shadow") { v.depth -= step }
        if has("serif", "new york") { v.displayFace = .newYork }
        if has("alte haas", "grotesk") { v.displayFace = .alteHaas }
        if has("sf pro", "system font", "san francisco") { v.displayFace = .sfPro }
        return clamped(v)
    }

    static func clamped(_ values: ThemeValues) -> ThemeValues {
        var v = values
        v.paperTone = min(max(v.paperTone, 0), 1)
        v.frost = min(max(v.frost, 0), 1)
        v.clarity = min(max(v.clarity, 0), 1)
        v.grain = min(max(v.grain, 0), 1)
        v.depth = min(max(v.depth, 0), 1)
        v.inkSoftness = min(max(v.inkSoftness, 0), 1)
        v.motion = min(max(v.motion, 0), 1)
        v.cornerRadius = min(max(v.cornerRadius, 6), 30)
        return v
    }

    /// What changed, in words, for the preview.
    static func changes(from old: ThemeValues, to new: ThemeValues) -> [TuneChange] {
        var list: [TuneChange] = []
        func number(_ name: String, _ a: Double, _ b: Double) {
            if abs(a - b) > 0.001 { list.append(TuneChange(name: name, from: String(format: "%.2f", a), to: String(format: "%.2f", b))) }
        }
        if old.appearance != new.appearance { list.append(TuneChange(name: "Appearance", from: old.appearance.title, to: new.appearance.title)) }
        number("Paper tone", old.paperTone, new.paperTone)
        number("Frost", old.frost, new.frost)
        number("Clarity", old.clarity, new.clarity)
        number("Grain", old.grain, new.grain)
        number("Depth", old.depth, new.depth)
        number("Ink softness", old.inkSoftness, new.inkSoftness)
        number("Motion", old.motion, new.motion)
        if abs(old.cornerRadius - new.cornerRadius) > 0.01 {
            list.append(TuneChange(name: "Corner radius", from: "\(Int(old.cornerRadius))", to: "\(Int(new.cornerRadius))"))
        }
        if old.displayFace != new.displayFace { list.append(TuneChange(name: "Display face", from: old.displayFace.title, to: new.displayFace.title)) }
        if old.backdrop != new.backdrop { list.append(TuneChange(name: "Backdrop", from: old.backdrop.title, to: new.backdrop.title)) }
        return list
    }
}

/// Plain-English colour looks, understood without any model: "warm film with soft blacks", "moody and blue", "punchy black and white".
enum LookRules {
    static func settings(for request: String) -> GradeSettings? {
        let text = request.lowercased()
        func has(_ words: String...) -> Bool { words.contains { text.contains($0) } }
        let lot = has("a lot", "very", "really", "heavy", "strong")
        let gentle = has("subtle", "slight", "a bit", "a little", "gentle", "soft ")
        let k = lot ? 1.4 : (gentle ? 0.6 : 1)
        var s = GradeSettings()
        var matched = false
        func apply(_ change: (inout GradeSettings) -> Void) {
            change(&s)
            matched = true
        }

        if has("film", "analog", "analogue", "kodak", "portra", "35mm") {
            apply {
                $0.contrast += 0.15 * k
                $0.fade += 0.3 * k
                $0.saturation -= 0.1 * k
                $0.lift = ColorWheel(hue: 190, amount: 0.22 * k, luma: 0)
                $0.gain = ColorWheel(hue: 38, amount: 0.18 * k, luma: 0)
                $0.grain += 0.3 * k
            }
        }
        if has("teal", "orange", "cinematic", "blockbuster", "hollywood") {
            apply {
                $0.contrast += 0.15 * k
                $0.lift = ColorWheel(hue: 195, amount: 0.35 * k, luma: $0.lift.luma)
                $0.gain = ColorWheel(hue: 30, amount: 0.3 * k, luma: $0.gain.luma)
                $0.hsl[1].saturation += 0.15 * k
                $0.hsl[4].saturation += 0.2 * k
            }
        }
        if has("warm", "golden", "sunset", "summer", "cosy", "cozy") { apply { $0.temperature += 0.3 * k; $0.tint += 0.03 * k } }
        if has("cool", "cold", "icy", "winter", "blue") { apply { $0.temperature -= 0.3 * k } }
        if has("moody", "dark", "dramatic", "noir") {
            apply {
                $0.exposure -= 0.3 * k
                $0.contrast += 0.25 * k
                $0.shadows -= 0.15 * k
                $0.saturation -= 0.25 * k
                $0.vignette += 0.3 * k
            }
        }
        if has("bright", "airy", "light and", "clean") {
            apply {
                $0.exposure += 0.3 * k
                $0.shadows += 0.3 * k
                $0.highlights -= 0.25 * k
                $0.vibrance += 0.15 * k
            }
        }
        if has("faded", "matte", "vintage", "washed", "soft blacks", "lifted") { apply { $0.fade += 0.4 * k; $0.contrast -= 0.1 * k } }
        if has("punchy", "vivid", "pop", "vibrant", "saturated") { apply { $0.vibrance += 0.35 * k; $0.contrast += 0.2 * k } }
        if has("muted", "desaturated", "pastel", "calm") { apply { $0.saturation -= 0.35 * k } }
        if has("black and white", "black & white", "b&w", "mono", "greyscale", "grayscale") {
            apply {
                $0.saturation = -1
                $0.contrast += 0.25 * k
            }
        }
        if has("grain", "gritty", "texture") { apply { $0.grain = max($0.grain, 0.35 * k) } }
        if has("vignette") { apply { $0.vignette = max($0.vignette, 0.4 * k) } }
        if has("green", "forest", "jungle") { apply { $0.hsl[3].saturation += 0.2 * k; $0.hsl[3].hue -= 0.1 * k } }
        if has("skin", "portrait", "people") { apply { $0.hsl[1].luminance += 0.12 * k; $0.hsl[1].saturation -= 0.05 * k } }
        if has("sharp", "crisp", "detail") { apply { $0.sharpen = max($0.sharpen, 0.4 * k) } }
        guard matched else { return nil }
        s.clamp()
        return s
    }

    /// A short name for the look from what was asked.
    static func name(for request: String) -> String {
        let words = request.split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "&" }).prefix(4)
        let name = words.map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }.joined(separator: " ")
        return name.isEmpty ? "My look" : String(name.prefix(32))
    }
}

/// Johnny in the sandbox: Tune (describe a change to 11am, preview it, apply it, undo it) and a terminal
/// where Johnny can suggest commands but nothing runs until you press Run.
@MainActor
final class BuildModel: ObservableObject {
    // Tune
    @Published var request = ""
    @Published private(set) var proposal: ThemeValues?
    @Published private(set) var proposalRequest = ""
    @Published private(set) var history: [TuneRecord] = []
    @Published private(set) var tuneRun: BrainRun?
    @Published var tuneNotice: String?

    // Looks
    @Published var lookRequest = ""
    @Published private(set) var lookRun: BrainRun?
    @Published private(set) var madeLook: Look?
    @Published var lookNotice: String?

    @Published var tab: BuildTab = BuildTab(rawValue: UserDefaults.standard.string(forKey: "build.tab") ?? "") ?? .terminal {
        didSet { UserDefaults.standard.set(tab.rawValue, forKey: "build.tab") }
    }

    private let brain: Brain
    private let theme: Theme
    private let looks: LookLibrary
    private var lookName = ""

    init(brain: Brain, theme: Theme, looks: LookLibrary) {
        self.brain = brain
        self.theme = theme
        self.looks = looks
    }

    var proposalChanges: [TuneChange] {
        guard let proposal else { return [] }
        return TuneRules.changes(from: theme.values, to: proposal)
    }

    // MARK: Tune

    func propose() {
        let text = request.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        tuneNotice = nil
        proposalRequest = text
        let ruled = TuneRules.apply(text, to: theme.values)
        if ruled != theme.values {
            proposal = ruled
            return
        }
        // Not a phrase Johnny knows by heart: ask the brain for a spec diff.
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let current = (try? encoder.encode(theme.values)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        let system = """
        You are Johnny, the builder inside 11am. Turn the request into changes to 11am's look. \
        Reply with only a JSON object containing the keys you'd change. Allowed keys: \
        appearance ("system", "light", "dark"), paperTone (0 white to 1 warm), frost (0 clear to 1 milky), \
        clarity (0 frosted to 1 see-through), grain, depth, inkSoftness (0 black to 1 graphite), motion (all 0 to 1), \
        cornerRadius (6 to 30), displayFace ("alteHaas", "sfPro", "newYork"), backdrop ("underWindow", "sidebar", "hud", "popover", "menu").
        """
        tuneRun = brain.run(BrainRequest(system: system, prompt: "Current: \(current)\nRequest: \(text)", weight: .quick))
    }

    /// Reads the JSON the brain wrote and turns it into a proposal. Unknown keys are ignored; values are clamped.
    func adoptBrainProposal(from text: String) {
        defer { tuneRun = nil }
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"),
              let data = String(text[start...end]).data(using: .utf8),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            tuneNotice = "Johnny couldn't turn that into a change. Try \"warmer\", \"more see-through\" or \"calmer\"."
            return
        }
        var v = theme.values
        if let raw = object["appearance"] as? String, let value = Appearance(rawValue: raw) { v.appearance = value }
        if let raw = object["displayFace"] as? String, let value = DisplayFace(rawValue: raw) { v.displayFace = value }
        if let raw = object["backdrop"] as? String, let value = BackdropMaterial(rawValue: raw) { v.backdrop = value }
        func number(_ key: String) -> Double? { (object[key] as? NSNumber)?.doubleValue }
        if let value = number("paperTone") { v.paperTone = value }
        if let value = number("frost") { v.frost = value }
        if let value = number("clarity") { v.clarity = value }
        if let value = number("grain") { v.grain = value }
        if let value = number("depth") { v.depth = value }
        if let value = number("inkSoftness") { v.inkSoftness = value }
        if let value = number("motion") { v.motion = value }
        if let value = number("cornerRadius") { v.cornerRadius = value }
        let result = TuneRules.clamped(v)
        if result == theme.values {
            tuneNotice = "That wouldn't change anything."
        } else {
            proposal = result
        }
    }

    func applyProposal() {
        guard let proposal else { return }
        history.insert(TuneRecord(request: proposalRequest, before: theme.values, after: proposal), at: 0)
        theme.values = proposal
        self.proposal = nil
        request = ""
    }

    func discardProposal() {
        proposal = nil
    }

    func revert(_ record: TuneRecord) {
        history.insert(TuneRecord(request: "Undo: \(record.request)", before: theme.values, after: record.before), at: 0)
        theme.values = record.before
    }

    // MARK: Looks

    /// Turns a description into a colour look saved for Photo and Video. Known words work offline; anything else asks the brain.
    func makeLook() {
        let text = lookRequest.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        lookNotice = nil
        madeLook = nil
        lookName = LookRules.name(for: text)
        if let settings = LookRules.settings(for: text) {
            saveLook(settings)
            return
        }
        let system = """
        You are Johnny, the builder inside 11am. Turn the description into a colour grade for photos and video. \
        Reply with only a JSON object containing the keys you'd change. Keys and ranges: \
        exposure (-3 to 3 stops), contrast, highlights, shadows, temperature (-1 cool to 1 warm), tint (-1 green to 1 magenta), \
        vibrance, saturation (all -1 to 1); lift, gamma, gain (shadow, midtone and highlight wheels), each an object \
        {"hue": 0-360 degrees, "amount": 0-1, "luma": -1 to 1}; hsl, an array of 8 objects {"hue", "saturation", "luminance"} \
        each -1 to 1, for red, orange, yellow, green, aqua, blue, purple, magenta; curve, 5 points {"x", "y"} from 0 to 1; \
        sharpen, noiseReduction, fade, vignette, grain (all 0 to 1). Keep it tasteful: most values well under 0.5.
        """
        lookRun = brain.run(BrainRequest(system: system, prompt: text, weight: .quick))
    }

    /// Reads the grade the brain wrote. Unknown keys are ignored and every value is clamped.
    func adoptBrainLook(from text: String) {
        defer { lookRun = nil }
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"),
              let data = String(text[start...end]).data(using: .utf8),
              let settings = try? JSONDecoder().decode(GradeSettings.self, from: data) else {
            lookNotice = "Johnny couldn't turn that into a look. Try words like \"warm film\", \"moody blue\" or \"punchy black and white\"."
            return
        }
        if settings == GradeSettings() {
            lookNotice = "That wouldn't change anything."
            return
        }
        saveLook(settings)
    }

    private func saveLook(_ settings: GradeSettings) {
        let look = looks.save(settings, as: lookName)
        madeLook = look
        lookRequest = ""
        lookNotice = "Saved \u{201C}\(look.name)\u{201D}. It's under Looks in Photo and Video, and in Looks/\(look.name).json if you want to tweak it by hand."
    }

    // MARK: Terminal

    static func parseSuggestion(_ text: String) -> (command: String, why: String) {
        var command = ""
        var why = ""
        for raw in text.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.uppercased().hasPrefix("COMMAND:") {
                command = line.dropFirst(8).trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "`"))
            } else if line.uppercased().hasPrefix("WHY:") {
                why = line.dropFirst(4).trimmingCharacters(in: .whitespaces)
            }
        }
        return (command, why)
    }

}
