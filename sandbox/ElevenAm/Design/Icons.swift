import SwiftUI

/// The brand has no icon set, so 11am draws its own: each app as a few strokes of 1.5pt ink on a 24-point square,
/// to match the `rule-open` outline. Square caps and joins, no fills, no colour.
struct AppGlyph: View {
    @EnvironmentObject private var theme: Theme
    @Environment(\.colorScheme) private var scheme
    var section: AppSection
    var size: CGFloat = 18
    var color: Color?

    var body: some View {
        AppGlyphShape(section: section)
            .stroke(color ?? theme.ink(scheme), style: StrokeStyle(lineWidth: 1.5 * 24 / max(size, 12), lineCap: .square, lineJoin: .miter))
            .scaleEffect(size / 24, anchor: .topLeading)
            .frame(width: size, height: size, alignment: .topLeading)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// The strokes for each app, on a 24 by 24 square.
struct AppGlyphShape: Shape {
    var section: AppSection

    func path(in rect: CGRect) -> Path {
        var p = Path()
        func line(_ points: [(CGFloat, CGFloat)], closed: Bool = false) {
            guard let first = points.first else { return }
            p.move(to: CGPoint(x: first.0, y: first.1))
            for point in points.dropFirst() { p.addLine(to: CGPoint(x: point.0, y: point.1)) }
            if closed { p.closeSubpath() }
        }
        func box(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) { p.addRect(CGRect(x: x, y: y, width: w, height: h)) }
        func circle(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) { p.addEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)) }
        /// An arc as points, so its direction never depends on the coordinate system (degrees, y down).
        func arc(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat, from: CGFloat, to: CGFloat, start: Bool) {
            let steps = 28
            for step in 0...steps {
                let angle = (from + (to - from) * CGFloat(step) / CGFloat(steps)) * .pi / 180
                let point = CGPoint(x: cx + r * cos(angle), y: cy + r * sin(angle))
                if step == 0 && start { p.move(to: point) } else { p.addLine(to: point) }
            }
        }

        switch section {
        case .today:
            // A clock at eleven.
            circle(12, 12, 9)
            line([(12, 12), (12, 5.5)])
            line([(12, 12), (8.5, 6)])
        case .calendar:
            box(3, 5, 18, 16)
            line([(3, 10), (21, 10)])
            line([(8, 3), (8, 7)])
            line([(16, 3), (16, 7)])
        case .tasks:
            box(3, 4, 6, 6)
            line([(4.5, 7), (6, 8.5), (8.5, 5)])
            line([(12, 7), (21, 7)])
            box(3, 14, 6, 6)
            line([(12, 17), (21, 17)])
        case .mail:
            box(3, 6, 18, 13)
            line([(3, 6), (12, 13.5), (21, 6)])
        case .notes:
            line([(5, 3), (15, 3), (19, 7), (19, 21), (5, 21)], closed: true)
            line([(15, 3), (15, 7), (19, 7)])
            line([(8, 12), (16, 12)])
            line([(8, 16), (14, 16)])
        case .write:
            line([(15, 4), (20, 9), (9, 20), (4, 20), (4, 15)], closed: true)
            line([(12.5, 6.5), (17.5, 11.5)])
        case .files:
            line([(3, 6), (9, 6), (11, 8.5), (21, 8.5), (21, 19), (3, 19)], closed: true)
            line([(3, 11.5), (21, 11.5)])
        case .pdf:
            line([(6, 3), (14, 3), (19, 8), (19, 21), (6, 21)], closed: true)
            line([(14, 3), (14, 8), (19, 8)])
            line([(9, 13), (16, 13)])
            line([(9, 17), (16, 17)])
        case .research:
            circle(10.5, 10.5, 6.5)
            line([(15.3, 15.3), (20.5, 20.5)])
        case .money:
            box(3, 7, 18, 11)
            circle(12, 12.5, 2.6)
            line([(6, 10), (6, 15)])
            line([(18, 10), (18, 15)])
        case .sheets:
            box(3, 4, 18, 16)
            line([(9, 4), (9, 20)])
            line([(15, 4), (15, 20)])
            line([(3, 9.5), (21, 9.5)])
            line([(3, 14.5), (21, 14.5)])
        case .business:
            box(3, 8, 18, 12)
            line([(9, 8), (9, 5), (15, 5), (15, 8)])
            line([(3, 13), (21, 13)])
        case .decks:
            box(3, 4, 18, 12)
            line([(12, 16), (12, 20)])
            line([(8, 20.5), (16, 20.5)])
            line([(7, 12), (10, 9), (13, 11), (17, 7.5)])
        case .design:
            circle(8.5, 8.5, 5)
            box(11, 11, 10, 10)
        case .photo:
            line([(3, 8), (7.5, 8), (9, 5), (15, 5), (16.5, 8), (21, 8), (21, 19), (3, 19)], closed: true)
            circle(12, 13.2, 3.4)
        case .video:
            box(3, 6, 13, 12)
            line([(16, 10), (21, 7), (21, 17), (16, 14)])
        case .audio:
            line([(4, 10), (4, 14)])
            line([(8, 7), (8, 17)])
            line([(12, 4), (12, 20)])
            line([(16, 7), (16, 17)])
            line([(20, 10), (20, 14)])
        case .learn:
            line([(12, 6), (12, 20)])
            line([(12, 6), (3, 4.5), (3, 18.5), (12, 20)])
            line([(12, 6), (21, 4.5), (21, 18.5), (12, 20)])
        case .build:
            box(3, 4, 18, 16)
            line([(7, 10), (10, 12.5), (7, 15)])
            line([(12, 15.5), (17, 15.5)])
        case .overnight:
            // A crescent: the part of one circle outside another.
            arc(12, 12, 8.5, from: 14.8, to: 262, start: true)
            arc(16.5, 8, 7.2, from: 217.8, to: 58.9, start: false)
            p.closeSubpath()
        case .suite:
            box(4, 4, 7, 7)
            box(13, 4, 7, 7)
            box(4, 13, 7, 7)
            box(13, 13, 7, 7)
        case .lab:
            line([(9, 3), (9, 9), (4, 20), (20, 20), (15, 9), (15, 3)])
            line([(7.5, 3), (16.5, 3)])
            line([(6.3, 15), (17.7, 15)])
        }
        return p
    }
}

/// The small label at the top of an app, like a window's title bar: the agent's circle and `leo · calendar`.
struct AppLabel: View {
    @EnvironmentObject private var theme: Theme
    @Environment(\.colorScheme) private var scheme
    var section: AppSection

    var body: some View {
        HStack(spacing: 8) {
            AgentCircle(code: section.monogram, size: 22, style: .ink)
            AppGlyph(section: section, size: 15)
            Text("\(AgentCode.name(section.monogram).lowercased()) · \(section.title.lowercased())")
                .font(BrandFont.label(12))
                .foregroundStyle(theme.ink(scheme))
        }
    }
}
