import AppKit
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

// MARK: - Action icons

/// An action's icon. Where 11am has drawn its own line version it uses that (1.5pt ink, round ends, on a 24-point
/// square); anything else is the SF Symbol in the current ink. Sized by the font like a symbol, so it can stand in for
/// `Image(systemName:)` anywhere.
struct Icon: View {
    var name: String

    init(_ name: String) { self.name = name }

    var body: some View {
        if let drawn = ActionGlyph.drawn(name) {
            // A hidden symbol takes the size the font gives it; the drawing fills that square.
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

enum ActionGlyph {
    static let names: Set<String> = [
        "xmark", "plus", "minus", "ellipsis", "ellipsis.circle", "trash", "square.and.arrow.up", "square.and.arrow.down",
        "scissors", "plus.square.on.square", "magnifyingglass", "plus.magnifyingglass", "minus.magnifyingglass",
        "sparkle.magnifyingglass", "sparkle", "sparkles", "exclamationmark.triangle", "exclamationmark.circle", "chevron.right",
        "chevron.left", "chevron.down", "chevron.up", "play", "pause", "stop", "lock", "lock.open", "arrow.uturn.backward",
        "arrow.uturn.forward", "checkmark", "checkmark.circle", "calendar", "checklist", "doc", "doc.text", "repeat", "moon.zzz",
        "music.note", "stopwatch", "clock", "minus.circle", "plus.circle", "xmark.circle", "bell", "envelope", "folder", "person",
        "person.2", "eye", "arrow.right", "arrow.left", "arrow.up", "arrow.down", "arrow.clockwise", "star", "flag", "archivebox",
        "paperplane", "mic", "camera", "photo", "tag", "globe", "bubble.left", "tablecells", "list.bullet", "link", "house",
        "square.grid.2x2", "chart.bar", "printer", "pencil", "wand.and.stars", "circle", "circle.fill", "square", "info.circle",
    ]

    /// Every name with a line drawing: the first set here and the rest in `MoreGlyphs`.
    static let all: Set<String> = names.union(MoreGlyphs.names)

    /// The drawn name for a symbol, if there is one. Filled versions use the line drawing (the brand fills nothing but
    /// the ink recording dot), so "play.fill" draws "play" and "xmark.octagon.fill" draws "xmark.octagon".
    static func drawn(_ name: String) -> String? {
        if all.contains(name) { return name }
        let plain = name.hasSuffix(".fill") ? String(name.dropLast(5)) : name.replacingOccurrences(of: ".fill.", with: ".")
        return all.contains(plain) ? plain : nil
    }

    private static var images: [String: NSImage] = [:]

    /// A drawn glyph as a template image, for places that only take an image (menus, Settings tabs, text): stroked at
    /// 1.5pt for the size it's drawn at, tinted like any symbol.
    static func image(_ name: String, size: CGFloat) -> NSImage {
        let key = "\(name)@\(size)"
        if let cached = images[key] { return cached }
        let path = ActionGlyphShape(name: name).path(in: CGRect(x: 0, y: 0, width: 24, height: 24)).cgPath
        let image = NSImage(size: NSSize(width: size, height: size), flipped: true) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.scaleBy(x: size / 24, y: size / 24)
            context.addPath(path)
            context.setLineWidth(1.5 * 24 / size)
            context.setLineCap(.round)
            context.setLineJoin(.round)
            context.setStrokeColor(NSColor.black.cgColor)
            context.strokePath()
            return true
        }
        image.isTemplate = true
        images[key] = image
        return image
    }
}

extension Image {
    /// An action's icon as an `Image`, for menus, Settings tabs and text, where only an image will do. The brand's line
    /// drawing where there is one, otherwise the SF Symbol. Elsewhere use `Icon`, which grows with the font.
    static func brand(_ name: String, size: CGFloat = 15) -> Image {
        guard let drawn = ActionGlyph.drawn(name) else { return Image(systemName: name) }
        return Image(nsImage: ActionGlyph.image(drawn, size: size)).renderingMode(.template)
    }
}

/// Recording, the brand's way: an open ink ring that fills while it records and breathes slowly (still, with reduced
/// motion). No red anywhere.
struct RecordingDot: View {
    var recording = true
    var size: CGFloat = 10
    @Environment(\.colorScheme) private var scheme
    @State private var breath = false

    var body: some View {
        let ink = BrandTokens.ink(scheme)
        Circle()
            .fill(recording ? ink : Color.clear)
            .overlay { Circle().strokeBorder(ink, lineWidth: BrandTokens.ruleOpen) }
            .frame(width: size, height: size)
            .scaleEffect(recording && breath ? 1.25 : 1)
            .opacity(recording && breath ? 0.7 : 1)
            .animation(recording && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
                       ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true) : .default, value: breath)
            .onAppear { breath = recording }
            .onChange(of: recording) { _, value in breath = value }
            .accessibilityLabel(recording ? "Recording" : "Not recording")
    }
}

struct ActionGlyphShape: Shape {
    var name: String

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
        func arc(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat, from: CGFloat, to: CGFloat, start: Bool = true) {
            let steps = 24
            for step in 0...steps {
                let angle = (from + (to - from) * CGFloat(step) / CGFloat(steps)) * .pi / 180
                let point = CGPoint(x: cx + r * cos(angle), y: cy + r * sin(angle))
                if step == 0 && start { p.move(to: point) } else { p.addLine(to: point) }
            }
        }
        func dots() { circle(6.5, 12, 0.9); circle(12, 12, 0.9); circle(17.5, 12, 0.9) }
        func lens() { circle(10.5, 10.5, 6.5); line([(15.3, 15.3), (20.5, 20.5)]) }
        func star(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat) {
            line([(cx, cy - r), (cx + r * 0.22, cy - r * 0.22), (cx + r, cy), (cx + r * 0.22, cy + r * 0.22),
                  (cx, cy + r), (cx - r * 0.22, cy + r * 0.22), (cx - r, cy), (cx - r * 0.22, cy - r * 0.22)], closed: true)
        }
        func page() {
            line([(6, 3), (14, 3), (19, 8), (19, 21), (6, 21)], closed: true)
            line([(14, 3), (14, 8), (19, 8)])
        }
        func openBox() { line([(8, 10), (5, 10), (5, 20), (19, 20), (19, 10), (16, 10)]) }
        func shackle() {
            line([(8, 11), (8, 8)])
            arc(12, 8, 4, from: 180, to: 360, start: false)
        }

        switch name {
        case "xmark": line([(6, 6), (18, 18)]); line([(18, 6), (6, 18)])
        case "plus": line([(12, 5), (12, 19)]); line([(5, 12), (19, 12)])
        case "minus": line([(5, 12), (19, 12)])
        case "ellipsis": dots()
        case "ellipsis.circle": circle(12, 12, 9); circle(8, 12, 0.8); circle(12, 12, 0.8); circle(16, 12, 0.8)
        case "trash":
            line([(4, 7), (20, 7)]); line([(9, 7), (9, 4), (15, 4), (15, 7)])
            line([(6, 7), (7, 20), (17, 20), (18, 7)]); line([(10, 11), (10, 16)]); line([(14, 11), (14, 16)])
        case "square.and.arrow.up": openBox(); line([(12, 3), (12, 14)]); line([(8, 7), (12, 3), (16, 7)])
        case "square.and.arrow.down": openBox(); line([(12, 3), (12, 14)]); line([(8, 10), (12, 14), (16, 10)])
        case "scissors": circle(7, 17, 3); circle(17, 17, 3); line([(9, 14.8), (18, 4)]); line([(15, 14.8), (6, 4)])
        case "plus.square.on.square":
            line([(3, 16), (3, 3), (16, 3)]); box(8, 8, 13, 13); line([(14.5, 11), (14.5, 18)]); line([(11, 14.5), (18, 14.5)])
        case "magnifyingglass": lens()
        case "plus.magnifyingglass": lens(); line([(10.5, 8), (10.5, 13)]); line([(8, 10.5), (13, 10.5)])
        case "minus.magnifyingglass": lens(); line([(8, 10.5), (13, 10.5)])
        case "sparkle.magnifyingglass": lens(); star(10.5, 10.5, 3.2)
        case "sparkle": star(12, 12, 9)
        case "sparkles", "wand.and.stars": star(10, 14, 7); star(18.5, 5.5, 3)
        case "exclamationmark.triangle": line([(12, 3), (22, 20), (2, 20)], closed: true); line([(12, 9), (12, 14)]); circle(12, 17, 0.5)
        case "exclamationmark.circle": circle(12, 12, 9); line([(12, 7), (12, 13)]); circle(12, 16.5, 0.5)
        case "info.circle": circle(12, 12, 9); line([(12, 11), (12, 17)]); circle(12, 7.5, 0.5)
        case "chevron.right": line([(9, 5), (16, 12), (9, 19)])
        case "chevron.left": line([(15, 5), (8, 12), (15, 19)])
        case "chevron.down": line([(5, 9), (12, 16), (19, 9)])
        case "chevron.up": line([(5, 15), (12, 8), (19, 15)])
        case "play": line([(7, 4), (20, 12), (7, 20)], closed: true)
        case "pause": line([(8, 5), (8, 19)]); line([(16, 5), (16, 19)])
        case "stop": box(5, 5, 14, 14)
        case "lock": box(5, 11, 14, 10); shackle()
        case "lock.open": box(5, 11, 14, 10); line([(16, 11), (16, 8)]); arc(12, 8, 4, from: 0, to: -180, start: false)
        case "arrow.uturn.backward":
            line([(4, 9), (14, 9)]); arc(14, 14, 5, from: -90, to: 90, start: false); line([(14, 19), (9, 19)])
            line([(8, 5), (4, 9), (8, 13)])
        case "arrow.uturn.forward":
            line([(20, 9), (10, 9)]); arc(10, 14, 5, from: 270, to: 90, start: false); line([(10, 19), (15, 19)])
            line([(16, 5), (20, 9), (16, 13)])
        case "checkmark": line([(5, 12.5), (10, 17.5), (19, 6.5)])
        case "checkmark.circle": circle(12, 12, 9); line([(8, 12.5), (11, 15.5), (16.5, 9)])
        case "calendar": box(3, 5, 18, 16); line([(3, 10), (21, 10)]); line([(8, 3), (8, 7)]); line([(16, 3), (16, 7)])
        case "checklist":
            line([(3, 7), (5, 9), (8, 5)]); line([(11, 7), (21, 7)]); line([(3, 16), (5, 18), (8, 14)]); line([(11, 16), (21, 16)])
        case "list.bullet":
            circle(5, 7, 0.8); circle(5, 12, 0.8); circle(5, 17, 0.8)
            line([(9, 7), (20, 7)]); line([(9, 12), (20, 12)]); line([(9, 17), (20, 17)])
        case "doc": page()
        case "doc.text": page(); line([(9, 13), (16, 13)]); line([(9, 17), (14, 17)])
        case "repeat":
            line([(4, 11), (4, 7), (19, 7)]); line([(16, 4), (19, 7), (16, 10)])
            line([(20, 13), (20, 17), (5, 17)]); line([(8, 14), (5, 17), (8, 20)])
        case "arrow.clockwise": arc(12, 12, 8, from: -60, to: 240); line([(15, 2.5), (16, 5.1), (13.2, 6.4)])
        case "moon.zzz":
            arc(11, 13, 7.5, from: 14.8, to: 262); arc(15, 9.5, 6.4, from: 217.8, to: 58.9, start: false); p.closeSubpath()
            line([(16, 2.5), (20, 2.5), (16, 6.5), (20, 6.5)])
        case "music.note": circle(8, 17, 3); line([(11, 17), (11, 4), (18, 7)])
        case "stopwatch": circle(12, 13.5, 7.5); line([(12, 13.5), (12, 9.5)]); line([(10, 3), (14, 3)]); line([(12, 3), (12, 6)])
        case "clock": circle(12, 12, 9); line([(12, 7), (12, 12), (15.5, 14)])
        case "minus.circle": circle(12, 12, 9); line([(7.5, 12), (16.5, 12)])
        case "plus.circle": circle(12, 12, 9); line([(7.5, 12), (16.5, 12)]); line([(12, 7.5), (12, 16.5)])
        case "xmark.circle": circle(12, 12, 9); line([(8.5, 8.5), (15.5, 15.5)]); line([(15.5, 8.5), (8.5, 15.5)])
        case "circle": circle(12, 12, 7)
        case "square": box(5, 5, 14, 14)
        case "bell":
            line([(5, 17), (19, 17)]); line([(6.5, 17), (6.5, 11)]); arc(12, 11, 5.5, from: 180, to: 360, start: false)
            line([(17.5, 11), (17.5, 17)]); line([(10, 20.5), (14, 20.5)])
        case "envelope": box(3, 6, 18, 13); line([(3, 6), (12, 13.5), (21, 6)])
        case "folder": line([(3, 6), (9, 6), (11, 8.5), (21, 8.5), (21, 19), (3, 19)], closed: true)
        case "person": circle(12, 8, 4); arc(12, 21, 8, from: 180, to: 360)
        case "person.2": circle(9, 8, 3.5); arc(9, 20, 6.5, from: 180, to: 360); circle(17, 9, 2.8); arc(17, 20, 5, from: 230, to: 360)
        case "eye":
            p.move(to: CGPoint(x: 2, y: 12))
            p.addQuadCurve(to: CGPoint(x: 22, y: 12), control: CGPoint(x: 12, y: 2))
            p.addQuadCurve(to: CGPoint(x: 2, y: 12), control: CGPoint(x: 12, y: 22))
            circle(12, 12, 3)
        case "arrow.right": line([(5, 12), (19, 12)]); line([(13, 6), (19, 12), (13, 18)])
        case "arrow.left": line([(19, 12), (5, 12)]); line([(11, 6), (5, 12), (11, 18)])
        case "arrow.up": line([(12, 19), (12, 5)]); line([(6, 11), (12, 5), (18, 11)])
        case "arrow.down": line([(12, 5), (12, 19)]); line([(6, 13), (12, 19), (18, 13)])
        case "star":
            var points: [(CGFloat, CGFloat)] = []
            for index in 0..<10 {
                let angle = (CGFloat(index) * 36 - 90) * .pi / 180
                let radius: CGFloat = index % 2 == 0 ? 9.5 : 4
                points.append((12 + radius * cos(angle), 12.8 + radius * sin(angle)))
            }
            line(points, closed: true)
        case "flag": line([(5, 21), (5, 4)]); line([(5, 4), (18, 4), (15, 8.5), (18, 13), (5, 13)])
        case "archivebox": box(3, 4, 18, 5); line([(5, 9), (5, 20), (19, 20), (19, 9)]); line([(10, 13), (14, 13)])
        case "paperplane": line([(3, 11), (21, 3), (14, 21), (11, 13)], closed: true); line([(11, 13), (21, 3)])
        case "mic":
            p.addRoundedRect(in: CGRect(x: 9, y: 3, width: 6, height: 11), cornerSize: CGSize(width: 3, height: 3))
            arc(12, 11, 6, from: 180, to: 0, start: true); line([(12, 17), (12, 21)])
        case "camera":
            line([(3, 8), (7.5, 8), (9, 5), (15, 5), (16.5, 8), (21, 8), (21, 19), (3, 19)], closed: true); circle(12, 13.2, 3.4)
        case "photo": box(3, 5, 18, 14); line([(3, 17), (9, 11), (13, 15), (16, 12), (21, 17)]); circle(16, 9, 1.5)
        case "tag": line([(3, 3), (11, 3), (21, 13), (13, 21), (3, 11)], closed: true); circle(7.5, 7.5, 1.3)
        case "globe": circle(12, 12, 9); p.addEllipse(in: CGRect(x: 8, y: 3, width: 8, height: 18)); line([(3, 12), (21, 12)])
        case "bubble.left": line([(3, 4), (21, 4), (21, 16), (10, 16), (5, 20), (5, 16), (3, 16)], closed: true)
        case "tablecells":
            box(3, 4, 18, 16); line([(9, 4), (9, 20)]); line([(15, 4), (15, 20)]); line([(3, 9.5), (21, 9.5)]); line([(3, 14.5), (21, 14.5)])
        case "link":
            p.addRoundedRect(in: CGRect(x: 2.5, y: 9, width: 11, height: 6), cornerSize: CGSize(width: 3, height: 3))
            p.addRoundedRect(in: CGRect(x: 10.5, y: 9, width: 11, height: 6), cornerSize: CGSize(width: 3, height: 3))
        case "house": line([(3, 11), (12, 3), (21, 11)]); line([(5, 9.5), (5, 20), (19, 20), (19, 9.5)]); line([(10, 20), (10, 14), (14, 14), (14, 20)])
        case "square.grid.2x2": box(4, 4, 7, 7); box(13, 4, 7, 7); box(4, 13, 7, 7); box(13, 13, 7, 7)
        case "chart.bar": line([(3, 20), (21, 20)]); box(5, 12, 3.5, 8); box(10.25, 7, 3.5, 13); box(15.5, 4, 3.5, 16)
        case "printer": box(6, 3, 12, 6); box(3, 9, 18, 8); box(6, 14, 12, 7)
        case "pencil": line([(15, 4), (20, 9), (9, 20), (4, 20), (4, 15)], closed: true); line([(12.5, 6.5), (17.5, 11.5)])
        default: p = MoreGlyphs.path(name)
        }
        return p
    }
}

/// Every drawn icon with its name, for checking the set by eye (`-glyphSheet YES`).
struct GlyphSheet: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 10)], spacing: 14) {
                ForEach(ActionGlyph.all.sorted(), id: \.self) { name in
                    VStack(spacing: 6) {
                        Icon(name)
                            .font(.brand(size: 26))
                            .frame(height: 30)
                        Text(name)
                            .font(BrandFont.label(9))
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .frame(height: 24, alignment: .top)
                    }
                    .foregroundStyle(BrandTokens.ink(scheme))
                }
            }
            .padding(20)
        }
        .background(BrandTokens.paper(scheme))
    }
}
