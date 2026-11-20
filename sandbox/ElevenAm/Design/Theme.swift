import AppKit
import SwiftUI

enum Appearance: String, CaseIterable, Identifiable, Codable {
    case system, light, dark

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

enum DisplayFace: String, CaseIterable, Identifiable, Codable {
    case alteHaas, sfPro, newYork

    var id: String { rawValue }

    var title: String {
        switch self {
        case .alteHaas: return "Alte Haas Grotesk"
        case .sfPro: return "SF Pro"
        case .newYork: return "New York"
        }
    }
}

/// The system material behind everything, blurred from the desktop.
enum BackdropMaterial: String, CaseIterable, Identifiable, Codable {
    case underWindow, sidebar, hud, popover, menu

    var id: String { rawValue }

    var title: String {
        switch self {
        case .underWindow: return "Under window"
        case .sidebar: return "Sidebar"
        case .hud: return "HUD"
        case .popover: return "Popover"
        case .menu: return "Menu"
        }
    }

    var material: NSVisualEffectView.Material {
        switch self {
        case .underWindow: return .underWindowBackground
        case .sidebar: return .sidebar
        case .hud: return .hudWindow
        case .popover: return .popover
        case .menu: return .menu
        }
    }
}

/// Every tunable value of the look. The Design Lab edits these live; "Copy values" exports them as JSON.
/// Defaults are the values picked in the first round of feedback.
struct ThemeValues: Codable, Equatable {
    var appearance: Appearance = .system
    /// 0 = pure white paper, 1 = warm vellum.
    var paperTone: Double = 0.152
    /// How milky the vellum is: 0 = clear glass, 1 = white paper.
    var frost: Double = 0.896
    /// How much of the desktop shows through as it is, unblurred: 0 = all frosted, 1 = see-through.
    var clarity: Double = 0.55
    /// Paper fibre / grain strength.
    var grain: Double = 0.2
    /// How far layers lift off each other (shadow + separation).
    var depth: Double = 0.2
    var cornerRadius: Double = 10.69
    /// 0 = pure black ink, 1 = soft graphite.
    var inkSoftness: Double = 1
    /// 0 = still, 1 = lively. Reduce Motion in System Settings always wins.
    var motion: Double = 0.6
    var displayFace: DisplayFace = .sfPro
    var backdrop: BackdropMaterial = .sidebar

    init() {}

    /// Missing keys fall back to defaults, so adding a value never wipes someone's tuned look.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = ThemeValues()
        appearance = (try? c.decodeIfPresent(Appearance.self, forKey: .appearance)) ?? d.appearance
        paperTone = (try? c.decodeIfPresent(Double.self, forKey: .paperTone)) ?? d.paperTone
        frost = (try? c.decodeIfPresent(Double.self, forKey: .frost)) ?? d.frost
        clarity = (try? c.decodeIfPresent(Double.self, forKey: .clarity)) ?? d.clarity
        grain = (try? c.decodeIfPresent(Double.self, forKey: .grain)) ?? d.grain
        depth = (try? c.decodeIfPresent(Double.self, forKey: .depth)) ?? d.depth
        cornerRadius = (try? c.decodeIfPresent(Double.self, forKey: .cornerRadius)) ?? d.cornerRadius
        inkSoftness = (try? c.decodeIfPresent(Double.self, forKey: .inkSoftness)) ?? d.inkSoftness
        motion = (try? c.decodeIfPresent(Double.self, forKey: .motion)) ?? d.motion
        displayFace = (try? c.decodeIfPresent(DisplayFace.self, forKey: .displayFace)) ?? d.displayFace
        backdrop = (try? c.decodeIfPresent(BackdropMaterial.self, forKey: .backdrop)) ?? d.backdrop
    }
}

@MainActor
final class Theme: ObservableObject {
    @Published var values: ThemeValues {
        didSet { persist() }
    }

    // v2: the round-one picks became the defaults, so everyone starts from them.
    private static let storageKey = "theme.values.v2"

    init() {
        if let data = UserDefaults.standard.data(forKey: Theme.storageKey),
           let saved = try? JSONDecoder().decode(ThemeValues.self, from: data) {
            values = saved
        } else {
            values = ThemeValues()
        }
    }

    func reset() {
        values = ThemeValues()
    }

    func exportJSON() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(values), let text = String(data: data, encoding: .utf8) else { return "{}" }
        return text
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(values) {
            UserDefaults.standard.set(data, forKey: Theme.storageKey)
        }
    }

    // MARK: Colour
    //
    // Brand v2: ink and paper at full strength, both ways round. Dark mode is the ink theme. The old tunables
    // (paper tone, ink softness, frost, corners) are fixed by the brand now and no longer change the look.

    /// The ground: paper (#ffffff), or ink (#0a0a0a) in the ink theme.
    func paper(_ scheme: ColorScheme) -> Color { BrandTokens.paper(scheme) }

    /// Text and fills, always full strength.
    func ink(_ scheme: ColorScheme) -> Color { BrandTokens.ink(scheme) }

    /// Text is never faded in brand v2: hierarchy comes from size, weight and Courier labels, and anything that should
    /// sit back goes under a sheet. These stay as names so every screen moves at once.
    func inkSecondary(_ scheme: ColorScheme) -> Color { ink(scheme) }
    func inkTertiary(_ scheme: ColorScheme) -> Color { ink(scheme) }

    /// Structural hairlines only (hour lines, sheet grids). Cards, fields and buttons don't get outlines.
    func edge(_ scheme: ColorScheme) -> Color { ink(scheme).opacity(scheme == .dark ? 0.16 : 0.1) }

    /// No lit top edge any more.
    func highlight(_ scheme: ColorScheme) -> Color { .clear }

    /// Fields and wells: white paper lifted off paper, or sheet-ink on ink.
    func well(_ scheme: ColorScheme) -> Color { scheme == .dark ? BrandTokens.sheetInk : BrandTokens.paperHex }

    /// A raised tab: the selected row lifts rather than changing colour.
    func raised(_ scheme: ColorScheme) -> Color { scheme == .dark ? Color.white.opacity(0.18) : BrandTokens.paperHex }

    var backdropOpacity: Double { 1 }
    var sheetBackdropOpacity: Double { 1 }
    func frostOpacity(level: Int) -> Double { 1 }

    func shadowOpacity(_ scheme: ColorScheme) -> Double { scheme == .dark ? 0.4 : 0.08 }

    /// The system is square.
    var radius: CGFloat { BrandTokens.radius }

    // MARK: Motion

    var motionEnabled: Bool {
        values.motion > 0.02 && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    /// The spring for most UI changes. A little livelier as Motion goes up; none when motion is off.
    var spring: Animation? {
        guard motionEnabled else { return nil }
        let m = values.motion
        return .spring(response: 0.46 - 0.1 * m, dampingFraction: 0.9 - 0.1 * m)
    }

    /// How far things rise as they appear, in points.
    var rise: CGFloat { motionEnabled ? 4 + 8 * values.motion : 0 }

    /// How far a hovered tile lifts, in points.
    var lift: CGFloat { motionEnabled ? 1 + 2 * values.motion : 0 }

    // MARK: Type

    /// Headings: Schibsted Grotesk, pushed hard in weight.
    func display(_ size: CGFloat) -> Font { BrandFont.heading(size, weight: size >= 30 ? .black : .heavy) }

    func monogramFont(_ size: CGFloat) -> Font { BrandFont.heading(size, weight: .black) }

    private func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double {
        a + (b - a) * max(0, min(1, t))
    }
}
