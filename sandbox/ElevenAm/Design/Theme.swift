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
struct ThemeValues: Codable, Equatable {
    var appearance: Appearance = .system
    /// 0 = pure white paper, 1 = warm vellum.
    var paperTone: Double = 0.35
    /// 0 = clear glass, 1 = nearly opaque paper.
    var frost: Double = 0.55
    /// Paper fibre / grain strength.
    var grain: Double = 0.35
    /// How far layers lift off each other (shadow + separation).
    var depth: Double = 0.45
    var cornerRadius: Double = 18
    /// 0 = pure black ink, 1 = soft graphite.
    var inkSoftness: Double = 0.12
    var displayFace: DisplayFace = .alteHaas
    var backdrop: BackdropMaterial = .underWindow
}

@MainActor
final class Theme: ObservableObject {
    @Published var values: ThemeValues {
        didSet { persist() }
    }

    private static let storageKey = "theme.values.v1"

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

    /// Wells and inputs pressed into the paper.
    func well(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.045)
    }

    /// Opacity of the vellum tint for a stacking level: 0 = window wash, 1 = side sheet, 2 = main sheet.
    func frostOpacity(level: Int) -> Double {
        let base = 0.18 + values.frost * 0.62
        switch level {
        case 0: return min(base * 0.45, 0.9)
        case 1: return min(base * 0.8, 0.92)
        default: return min(base, 0.95)
        }
    }

    func shadowOpacity(_ scheme: ColorScheme) -> Double {
        (scheme == .dark ? 0.35 : 0.08) * (0.4 + values.depth)
    }

    var radius: CGFloat { CGFloat(values.cornerRadius) }

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
