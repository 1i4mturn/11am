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

    /// The vellum itself: white to warm, or smoked graphite in dark mode.
    func paper(_ scheme: ColorScheme) -> Color {
        let t = values.paperTone
        if scheme == .dark {
            return Color(red: lerp(0.11, 0.14, t), green: lerp(0.11, 0.13, t), blue: lerp(0.12, 0.115, t))
        }
        return Color(red: lerp(1.0, 0.968, t), green: lerp(1.0, 0.95, t), blue: lerp(1.0, 0.915, t))
    }

    func ink(_ scheme: ColorScheme) -> Color {
        let soft = values.inkSoftness
        if scheme == .dark {
            let v = 0.97 - soft * 0.17
            return Color(red: v, green: v, blue: v)
        }
        let v = 0.04 + soft * 0.16
        return Color(red: v, green: v, blue: v)
    }

    func inkSecondary(_ scheme: ColorScheme) -> Color { ink(scheme).opacity(0.68) }
    func inkTertiary(_ scheme: ColorScheme) -> Color { ink(scheme).opacity(0.46) }

    /// Hairline edge of a vellum sheet.
    func edge(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.08)
    }

    /// The light catching the top edge of a sheet.
    func highlight(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.10) : Color.white.opacity(0.75)
    }

    /// Wells, inputs and badges. In light mode they're a brighter sheet laid on the paper, never a grey dip.
    func well(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.07) : Color.white.opacity(0.62)
    }

    /// A raised tab: the selected row, a hovered tile.
    func raised(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.11) : Color.white.opacity(0.92)
    }

    /// How much of the blurred backdrop is drawn behind the window and sidebar.
    /// The rest shows the desktop exactly as it is, so windows and wallpaper read through.
    var backdropOpacity: Double { 1 - values.clarity * 0.8 }

    /// Sheets keep more frost than the window so text stays easy to read.
    var sheetBackdropOpacity: Double { 1 - values.clarity * 0.25 }

    /// Opacity of the vellum wash for a level: 0 = window and sidebar, 1 = side sheet, 2 = main sheet, 3 = card.
    /// Sheets carry their own frosted backdrop, so these don't stack on the window wash.
    func frostOpacity(level: Int) -> Double {
        let f = values.frost
        switch level {
        case 0: return min(0.08 + f * 0.46, 0.94)
        case 1: return min(0.16 + f * 0.48, 0.95)
        case 2: return min(0.22 + f * 0.5, 0.96)
        default: return min(0.10 + f * 0.34, 0.9)
        }
    }

    func shadowOpacity(_ scheme: ColorScheme) -> Double {
        (scheme == .dark ? 0.35 : 0.08) * (0.4 + values.depth)
    }

    var radius: CGFloat { CGFloat(values.cornerRadius) }

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

    func display(_ size: CGFloat) -> Font {
        switch values.displayFace {
        case .alteHaas: return .custom("AlteHaasGrotesk_Bold", size: size)
        case .sfPro: return .system(size: size, weight: .bold, design: .default)
        case .newYork: return .system(size: size, weight: .semibold, design: .serif)
        }
    }

    func monogramFont(_ size: CGFloat) -> Font {
        .custom("AlteHaasGrotesk_Bold", size: size)
    }

    private func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double {
        a + (b - a) * max(0, min(1, t))
    }
}
