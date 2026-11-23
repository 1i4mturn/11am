import AppKit
import CoreText
import SwiftUI

/// The overprint: how a section opens. Three layers on the grid of squares: a solid square holding the number, a huge
/// outlined word in Schibsted Black running behind, and a vellum note carrying the heading, stepped half a square
/// across both. The note always carries something. As the page scrolls, the word and the note drift a little at
/// different speeds (not with reduced motion).
struct Opener: View {
    var numeral: String
    var word: String
    var label: String
    var heading: String
    var line: String
    /// One square of the grid; the gap between squares is the brand's 16.
    var square: CGFloat = 112
    /// How far the page has scrolled past the opener, for the drift.
    var scrolled: CGFloat = 0

    @Environment(\.colorScheme) private var scheme

    static let gap: CGFloat = 16

    /// Six squares across, and the note's half-step below the second row.
    static func size(square: CGFloat) -> CGSize {
        let half = (square + gap) / 2
        return CGSize(width: square * 6 + gap * 5, height: square * 2 + gap + half)
    }

    private var half: CGFloat { (square + Self.gap) / 2 }
    private var two: CGFloat { square * 2 + Self.gap }
    private var pad: CGFloat { max(14, square * 0.16) }
    private var drifts: Bool { !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    // Ink on paper; on the ink theme the square turns paper and the word's outline turns white.
    private var squareFill: Color { scheme == .dark ? .white : BrandTokens.inkHex }
    private var squareInk: Color { scheme == .dark ? BrandTokens.inkHex : .white }
    private var wordStroke: Color { scheme == .dark ? .white : BrandTokens.inkHex }

    var body: some View {
        let size = Self.size(square: square)
        ZStack(alignment: .topLeading) {
            // Behind: the word, across the last four squares of the first row, set to its bottom right.
            OutlinedWord(text: word, size: square * 0.92)
                .stroke(wordStroke, lineWidth: 1.4)
                .frame(width: square * 4 + Self.gap * 3, height: square)
                .offset(x: (square + Self.gap) * 2, y: drifts ? -scrolled * 0.05 : 0)
                .accessibilityHidden(true)

            // The square: two by two, the number at its foot.
            ZStack(alignment: .bottomLeading) {
                Rectangle().fill(squareFill)
                Tooth()
                Text(numeral)
                    .font(.custom(BrandFont.headingName(.black), size: square * 1.25))
                    .tracking(-square * 1.25 * 0.075)
                    .foregroundStyle(squareInk)
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.leading, pad)
                    .padding(.bottom, pad * 0.55)
            }
            .frame(width: two, height: two)
            .clipped()

            // In front: the note, stepped half a square right and down across both.
            VStack(alignment: .leading, spacing: 10) {
                Text(label)
                    .font(BrandFont.label(12))
                    .lineLimit(2)
                Text(heading)
                    .font(BrandFont.heading(square * 0.27, weight: .heavy))
                    .tracking(-square * 0.27 * 0.035)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .fixedSize(horizontal: false, vertical: true)
                Text(line)
                    .font(BrandFont.body(max(13, square * 0.13), weight: .medium))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .foregroundStyle(BrandTokens.inkHex)
            .padding(pad)
            .frame(width: two, height: two, alignment: .topLeading)
            .noteSurface()
            .environment(\.colorScheme, .light)
            .offset(x: square + Self.gap + half, y: half + (drifts ? scrolled * 0.04 : 0))
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(heading) \(line)")
    }
}

/// A word as the outline of its letters in Schibsted Black, for stroking at the brand's hairline. Its right edge sits on
/// the frame's right and its baseline just above the frame's foot.
struct OutlinedWord: Shape {
    var text: String
    var size: CGFloat

    func path(in rect: CGRect) -> Path {
        let font = CTFontCreateWithName(BrandFont.headingName(.black) as CFString, size, nil)
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTKernAttributeName as String): -size * 0.05,
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        let glyphs = CGMutablePath()
        for run in (CTLineGetGlyphRuns(line) as? [CTRun]) ?? [] {
            let count = CTRunGetGlyphCount(run)
            guard count > 0 else { continue }
            var ids = [CGGlyph](repeating: 0, count: count)
            var positions = [CGPoint](repeating: .zero, count: count)
            CTRunGetGlyphs(run, CFRange(location: 0, length: 0), &ids)
            CTRunGetPositions(run, CFRange(location: 0, length: 0), &positions)
            for index in 0..<count {
                guard let outline = CTFontCreatePathForGlyph(font, ids[index], nil) else { continue }
                glyphs.addPath(outline, transform: CGAffineTransform(translationX: positions[index].x, y: positions[index].y))
            }
        }
        let width = glyphs.boundingBoxOfPath.maxX
        let descent = CTFontGetDescent(font)
        // Core Text draws upward from the baseline; flip it, then set it to the right and near the foot.
        let place = CGAffineTransform(translationX: rect.maxX - width, y: rect.maxY - descent * 0.35)
            .scaledBy(x: 1, y: -1)
        return Path(glyphs).applying(place)
    }
}
