import AppKit
import SwiftUI

// The 11am design system, copied from the brand's tokens.json (brand guidelines v2, UI kit v1). Nothing outside this
// file types a colour, a radius or a shadow. Two colours at full strength, no hue, no grey: to recede, go under vellum.

enum BrandTokens {
    // MARK: Colour

    /// #0a0a0a: text, solid squares, fills and inverted panels.
    static let inkHex = Color(red: 10 / 255, green: 10 / 255, blue: 10 / 255)
    static let paperHex = Color.white
    /// True black, for the drop only.
    static let drop = Color.black

    /// The ground: paper in the paper theme, ink in the ink theme (dark mode).
    static func paper(_ scheme: ColorScheme) -> Color { scheme == .dark ? inkHex : paperHex }
    /// Text and fills: always full strength, never faded.
    static func ink(_ scheme: ColorScheme) -> Color { scheme == .dark ? paperHex : inkHex }

    /// Vellum sheet: paper at 56%, veils what's behind; never carries text over ink.
    static let sheet = Color.white.opacity(0.56)
    /// Vellum note: paper at 82%, the post-it that carries text.
    static let note = Color.white.opacity(0.82)
    /// Sheet on ink: paper at 12%, for the puck, voice and resting circles, and surfaces in the ink theme.
    static let sheetInk = Color.white.opacity(0.12)
    static let halo = Color.white.opacity(0.9)

    // MARK: Radius

    /// The system is square: squares, notes, cards, fields, dialogs and windows.
    static let radius: CGFloat = 0
    /// The lifted selected row inside a menu.
    static let radiusRow: CGFloat = 8
    /// The notification inside the drop.
    static let radiusNotice: CGFloat = 12
    /// The drop's lower corners.
    static let radiusDrop: CGFloat = 36

    // MARK: Spacing

    static let gap: CGFloat = 16
    static let pad: CGFloat = 24
    static let fieldHeight: CGFloat = 48
    /// The minimum target. Inside dense app toolbars, like the drop and its notices, 34 is allowed.
    static let hit: CGFloat = 44
    static let hitCompact: CGFloat = 34

    // MARK: Shadow

    /// A layer of a shadow token: `0 y blur rgba(10,10,10,alpha)`.
    struct Shadow {
        var y: CGFloat
        var blur: CGFloat
        var alpha: Double
    }

    /// Paper lifting off paper: fields, menus, cards, the nav bar. In place of an outline.
    static let lift = [Shadow(y: 1, blur: 2, alpha: 0.06), Shadow(y: 6, blur: 20, alpha: 0.08)]
    /// A field in use, a dialog, an open window.
    static let liftHi = [Shadow(y: 2, blur: 4, alpha: 0.08), Shadow(y: 16, blur: 40, alpha: 0.14)]
    /// The selected row in a menu.
    static let liftRow = [Shadow(y: 8, blur: 22, alpha: 0.14), Shadow(y: 1, blur: 3, alpha: 0.08)]
    /// The only outline: open pills, open chips, empty choices, page numbers.
    static let ruleOpen: CGFloat = 1.5
    /// The ink bar on the left of a field with an error.
    static let errorBar: CGFloat = 3

    // MARK: Blur

    static let blurSheet: CGFloat = 8
    static let blurNote: CGFloat = 10
    static let blurHalo: CGFloat = 14
}

// MARK: - Type

/// The brand's faces. Schibsted Grotesk for the wordmark, numerals and headings; Instrument Sans for reading;
/// Courier Prime for labels; Hack for code; Reenie Beanie for a few handwritten words (Biro Script waits on its licence).
enum BrandFont {
    static func heading(_ size: CGFloat, weight: Font.Weight = .heavy) -> Font {
        .custom(headingName(weight), size: size)
    }

    static func headingName(_ weight: Font.Weight) -> String {
        switch weight {
        case .black: return "SchibstedGrotesk-Black"
        case .heavy: return "SchibstedGrotesk-ExtraBold"
        default: return "SchibstedGrotesk-Bold"
        }
    }

    static func body(_ size: CGFloat, weight: Font.Weight? = nil) -> Font {
        .custom(bodyName(weight), size: size)
    }

    static func bodyName(_ weight: Font.Weight?) -> String {
        switch weight {
        case .some(.medium): return "InstrumentSans-Medium"
        case .some(.semibold), .some(.bold), .some(.heavy), .some(.black): return "InstrumentSans-SemiBold"
        default: return "InstrumentSans-Regular"
        }
    }

    static func label(_ size: CGFloat = 12) -> Font { .custom("CourierPrime-Regular", size: size) }

    static func code(_ size: CGFloat = 13, weight: Font.Weight? = nil) -> Font {
        .custom(weight == .bold || weight == .semibold || weight == .heavy || weight == .black ? "Hack-Bold" : "Hack-Regular", size: size)
    }

    static func hand(_ size: CGFloat = 22) -> Font { .custom("ReenieBeanie", size: size) }

    /// AppKit faces for text views and drawing.
    static func nsBody(_ size: CGFloat, weight: Font.Weight? = nil) -> NSFont {
        NSFont(name: bodyName(weight), size: size) ?? .systemFont(ofSize: size)
    }

    static func nsCode(_ size: CGFloat) -> NSFont {
        NSFont(name: "Hack-Regular", size: size) ?? .monospacedSystemFont(ofSize: size, weight: .regular)
    }
}

extension Font {
    /// The interface face at a given size: a drop-in for `.system(size:weight:design:)`. Reading text is Instrument Sans;
    /// big bold numbers and titles move up to Schibsted Grotesk; monospaced text is Hack.
    static func brand(size: CGFloat, weight: Font.Weight? = nil, design: Font.Design? = nil) -> Font {
        if design == .monospaced { return BrandFont.code(size, weight: weight) }
        if size >= 20, let weight, weight == .bold || weight == .heavy || weight == .black {
            return BrandFont.heading(size, weight: weight == .black ? .black : .heavy)
        }
        return BrandFont.body(size, weight: weight)
    }
}

// MARK: - Surfaces

/// The tracing-paper tooth every vellum surface and every ink panel carries, tiled at 256pt.
struct Tooth: View {
    var body: some View {
        Image("tracing-paper")
            .resizable(resizingMode: .tile)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

extension View {
    /// Paper lifting off paper: no outline, a soft shadow. `hi` for a field in use, a dialog, an open window.
    func lift(hi: Bool = false, row: Bool = false) -> some View {
        let layers = row ? BrandTokens.liftRow : (hi ? BrandTokens.liftHi : BrandTokens.lift)
        return self
            .shadow(color: Color.black.opacity(layers[0].alpha), radius: layers[0].blur / 2, y: layers[0].y)
            .shadow(color: Color.black.opacity(layers[1].alpha), radius: layers[1].blur / 2, y: layers[1].y)
    }

    /// The `rule-open` outline: 1.5pt ink, inside the shape.
    func ruleOpen<S: InsettableShape>(_ shape: S, color: Color) -> some View {
        overlay { shape.strokeBorder(color, lineWidth: BrandTokens.ruleOpen) }
    }
}
