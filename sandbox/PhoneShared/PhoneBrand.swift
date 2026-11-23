import CoreText
import SwiftUI
import UIKit

// Brand v2 on the iPhone: the same faces, monograms, tooth and two colours as the Mac (the assets and glyphs come from
// Shared/), with the iPhone's own exceptions: notifications round at 22, swipe rows at 16, and 44pt targets.

enum PhoneBrand {
    static let inkHex = Color(red: 10 / 255, green: 10 / 255, blue: 10 / 255)
    static let paperHex = Color.white
    static let drop = Color.black
    static let note = Color.white.opacity(0.82)
    static let sheetInk = Color.white.opacity(0.12)
    static let ruleOpen: CGFloat = 1.5
    static let errorBar: CGFloat = 3
    static let radiusRow: CGFloat = 8
    static let radiusNotice: CGFloat = 12
    static let radiusDrop: CGFloat = 36
    /// iPhone exceptions, as approved on the canvas.
    static let radiusNotification: CGFloat = 22
    static let radiusSwipeRow: CGFloat = 16
    static let hit: CGFloat = 44

    static func ink(_ scheme: ColorScheme) -> Color { scheme == .dark ? paperHex : inkHex }
    static func paper(_ scheme: ColorScheme) -> Color { scheme == .dark ? inkHex : paperHex }

    private static var registered = false

    /// The brand faces, registered for this process from the app's own bundle.
    static func registerFonts() {
        guard !registered else { return }
        registered = true
        for url in (Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: nil) ?? []) {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}

enum BrandFace {
    static func heading(_ size: CGFloat, black: Bool = false) -> Font {
        .custom(black ? "SchibstedGrotesk-Black" : "SchibstedGrotesk-ExtraBold", size: size)
    }

    static func body(_ size: CGFloat, weight: Font.Weight? = nil) -> Font {
        switch weight {
        case .some(.medium): return .custom("InstrumentSans-Medium", size: size)
        case .some(.semibold), .some(.bold), .some(.heavy), .some(.black): return .custom("InstrumentSans-SemiBold", size: size)
        default: return .custom("InstrumentSans-Regular", size: size)
        }
    }

    /// Labels: Courier Prime, lowercase, full ink.
    static func label(_ size: CGFloat = 12) -> Font { .custom("CourierPrime-Regular", size: size) }

    static func code(_ size: CGFloat) -> Font { .custom("Hack-Regular", size: size) }
}

extension Font {
    /// The interface face at a size, standing in for `.system(size:weight:)`: Instrument Sans for reading, Schibsted
    /// Grotesk for big bold titles and numbers, Hack for anything monospaced.
    static func brand(size: CGFloat, weight: Font.Weight? = nil, design: Font.Design? = nil) -> Font {
        if design == .monospaced { return BrandFace.code(size) }
        if size >= 20, let weight, weight == .bold || weight == .heavy || weight == .black || weight == .semibold {
            return BrandFace.heading(size, black: weight == .black)
        }
        return BrandFace.body(size, weight: weight == .light ? nil : weight)
    }
}

/// An action's icon in the brand's line, sized by the font like a symbol (the SF Symbol when there's no drawing).
struct Icon: View {
    var name: String

    init(_ name: String) { self.name = name }

    var body: some View {
        if let drawn = ActionGlyph.drawn(name) {
            Image(systemName: "square")
                .hidden()
                .overlay {
                    GeometryReader { proxy in
                        let side = min(proxy.size.width, proxy.size.height)
                        ActionGlyphShape(name: drawn)
                            .stroke(style: StrokeStyle(lineWidth: 1.5 * 24 / max(side, 8), lineCap: .round, lineJoin: .round))
                            .scaleEffect(side / 24, anchor: .topLeading)
                            .frame(width: side, height: side, alignment: .topLeading)
                            .frame(width: proxy.size.width, height: proxy.size.height)
                    }
                }
                .accessibilityLabel(name)
        } else {
            Image(systemName: name)
        }
    }
}

/// The agents, by their brand codes.
enum PhoneAgents {
    static let order = ["le", "mr", "wi", "jm", "ge", "cr", "rb", "jo", "hr", "ce", "bn"]

    static func name(_ code: String) -> String {
        switch code {
        case "le": return "Leo"
        case "mr": return "Marc"
        case "wi": return "William"
        case "jm": return "James"
        case "ge": return "George"
        case "cr": return "Conner"
        case "rb": return "Robert"
        case "jo": return "Johnny"
        case "hr": return "Harris"
        case "ce": return "Cole"
        case "bn": return "Bolton"
        default: return "11am"
        }
    }

    static func role(_ code: String) -> String {
        switch code {
        case "le": return "chief of staff"
        case "mr": return "mail"
        case "wi": return "writing"
        case "jm": return "research"
        case "ge": return "money"
        case "cr": return "business"
        case "rb": return "design"
        case "jo": return "build"
        case "hr": return "energy and learning"
        case "ce": return "video and audio"
        default: return "notes and files"
        }
    }
}

/// An agent in a circle: the locked monogram on ink, paper or sheet-ink.
struct PhoneAgentCircle: View {
    enum Style { case ink, paper, sheetInk }
    var code: String
    var size: CGFloat = 44
    var style: Style = .sheetInk

    var body: some View {
        Image(code == "11" ? "logo-11" : "logo-\(code)")
            .renderingMode(.template)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
            .foregroundStyle(style == .paper ? PhoneBrand.inkHex : .white)
            .background {
                switch style {
                case .ink: Circle().fill(PhoneBrand.inkHex)
                case .paper: Circle().fill(Color.white)
                case .sheetInk: Circle().fill(PhoneBrand.sheetInk)
                }
            }
            .clipShape(Circle())
            .accessibilityLabel(PhoneAgents.name(code))
    }
}

/// The tracing-paper tooth that ink and vellum carry.
struct PhoneTooth: View {
    var body: some View {
        Image("tracing-paper")
            .resizable(resizingMode: .tile)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
