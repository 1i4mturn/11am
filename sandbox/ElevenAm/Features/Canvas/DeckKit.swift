import CoreGraphics
import Foundation

/// Conner's decks: slides built from layouts and a theme on Robert's canvas, so they render, export to PDF and
/// PowerPoint, and present with the same engine as designs.

enum SlideLayout: String, Codable, CaseIterable, Identifiable, Sendable {
    case title, section, statement, bullets, twoColumns, image, bigNumber, quote, chart, table, team, timeline, closing

    var id: String { rawValue }

    var title: String {
        switch self {
        case .title: return "Title"
        case .section: return "Section"
        case .statement: return "Statement"
        case .bullets: return "Bullets"
        case .twoColumns: return "Two columns"
        case .image: return "Picture"
        case .bigNumber: return "Big number"
        case .quote: return "Quote"
        case .chart: return "Chart"
        case .table: return "Table"
        case .team: return "Team"
        case .timeline: return "Timeline"
        case .closing: return "Closing"
        }
    }

    var symbol: String {
        switch self {
        case .title: return "textformat.size.larger"
        case .section: return "rectangle.split.1x2"
        case .statement: return "text.quote"
        case .bullets: return "list.bullet"
        case .twoColumns: return "rectangle.split.2x1"
        case .image: return "photo"
        case .bigNumber: return "number"
        case .quote: return "quote.opening"
        case .chart: return "chart.bar"
        case .table: return "tablecells"
        case .team: return "person.3"
        case .timeline: return "arrow.right.to.line"
        case .closing: return "flag.checkered"
        }
    }
}

/// What a slide says, independent of how it's laid out.
struct SlideContent: Codable, Hashable, Sendable {
    var title = ""
    var subtitle = ""
    var bullets: [String] = []
    /// The second column, for two columns.
    var secondary: [String] = []
    var number = ""
    var caption = ""
    var quote = ""
    var attribution = ""
    /// An image asset id.
    var image: String?
    var chart: [ChartPoint] = []
    var table: [[String]] = []
}

struct ChartPoint: Codable, Hashable, Sendable {
    var label: String
    var value: Double
}

struct Slide: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var layout: SlideLayout
    var content = SlideContent()
    var notes = ""
    var hidden = false
    /// Set once the slide's layers are moved or edited by hand, so changing the theme keeps your changes.
    var customised = false
    var canvas: CanvasDocument

    init(layout: SlideLayout, content: SlideContent = SlideContent(), notes: String = "", theme: DeckTheme) {
        self.layout = layout
        self.content = content
        self.notes = notes
        self.canvas = DeckLayoutEngine.canvas(layout, content, theme)
    }
}

struct DeckTheme: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var name: String
    var background: CanvasColor
    var ink: CanvasColor
    var accent: CanvasColor
    var soft: CanvasColor
    var headingFont = "System"
    var bodyFont = "System"
    var headingWeight: TextWeight = .bold
    /// Section and title slides in the accent colour.
    var boldSections = true
    var footer = ""

    static let paper = DeckTheme(id: "paper", name: "Paper", background: CanvasColor(red: 0.98, green: 0.97, blue: 0.95),
                                 ink: CanvasColor(red: 0.08, green: 0.08, blue: 0.09), accent: CanvasColor(red: 0.08, green: 0.08, blue: 0.09),
                                 soft: CanvasColor(red: 0.89, green: 0.87, blue: 0.84))
    static let ink = DeckTheme(id: "ink", name: "Ink", background: CanvasColor(red: 0.07, green: 0.07, blue: 0.08),
                               ink: CanvasColor(red: 0.96, green: 0.95, blue: 0.93), accent: CanvasColor(red: 0.96, green: 0.95, blue: 0.93),
                               soft: CanvasColor(red: 0.2, green: 0.2, blue: 0.22), boldSections: false)
    static let ember = DeckTheme(id: "ember", name: "Ember", background: .white, ink: CanvasColor(red: 0.1, green: 0.09, blue: 0.09),
                                 accent: CanvasColor(red: 0.93, green: 0.36, blue: 0.2), soft: CanvasColor(red: 0.98, green: 0.91, blue: 0.87))
    static let harbour = DeckTheme(id: "harbour", name: "Harbour", background: CanvasColor(red: 0.96, green: 0.97, blue: 0.98),
                                   ink: CanvasColor(red: 0.07, green: 0.13, blue: 0.22), accent: CanvasColor(red: 0.13, green: 0.36, blue: 0.67),
                                   soft: CanvasColor(red: 0.87, green: 0.91, blue: 0.96), headingWeight: .semibold)
    static let grove = DeckTheme(id: "grove", name: "Grove", background: CanvasColor(red: 0.97, green: 0.97, blue: 0.94),
                                 ink: CanvasColor(red: 0.11, green: 0.17, blue: 0.13), accent: CanvasColor(red: 0.18, green: 0.45, blue: 0.3),
                                 soft: CanvasColor(red: 0.88, green: 0.92, blue: 0.86), headingFont: "New York", headingWeight: .semibold)

    static let all: [DeckTheme] = [paper, ink, ember, harbour, grove]

    /// A theme from the brand kit.
    static func brand(_ brand: CanvasBrand) -> DeckTheme {
        DeckTheme(id: "brand", name: brand.name, background: brand.paper, ink: brand.primary, accent: brand.accent, soft: brand.soft,
                  headingFont: brand.headingFont, bodyFont: brand.bodyFont, footer: brand.footer)
    }
}

struct SlideDeck: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var name: String
    var theme: DeckTheme
    var slides: [Slide]
    var modified = Date()

    static let size = CanvasSize(width: 1920, height: 1080)

    /// Lays every slide out again in the theme, except the ones edited by hand (those get the new colours only).
    mutating func apply(_ theme: DeckTheme) {
        let old = self.theme
        self.theme = theme
        for index in slides.indices {
            if slides[index].customised {
                DeckLayoutEngine.recolour(&slides[index].canvas, from: old, to: theme)
            } else {
                slides[index].canvas = DeckLayoutEngine.canvas(slides[index].layout, slides[index].content, theme)
            }
        }
    }

    mutating func relayout(_ index: Int) {
        guard slides.indices.contains(index) else { return }
        slides[index].canvas = DeckLayoutEngine.canvas(slides[index].layout, slides[index].content, theme)
        slides[index].customised = false
    }

    var visibleSlides: [Slide] { slides.filter { !$0.hidden } }
}

// MARK: Layout

enum DeckLayoutEngine {
    static let margin = 120.0

    private static func style(_ theme: DeckTheme, _ size: Double, heading: Bool, weight: TextWeight? = nil, color: CanvasColor? = nil,
                              alignment: TextAlignment = .left, lineHeight: Double = 1.15) -> TextStyle {
        var style = TextStyle()
        style.font = heading ? theme.headingFont : theme.bodyFont
        style.size = size
        style.weight = weight ?? (heading ? theme.headingWeight : .regular)
        style.color = color ?? theme.ink
        style.alignment = alignment
        style.lineHeight = lineHeight
        style.tracking = heading && size >= 80 ? -size * 0.02 : 0
        return style
    }

    /// The layers for a slide, from its layout, content and theme.
    static func canvas(_ layout: SlideLayout, _ content: SlideContent, _ theme: DeckTheme) -> CanvasDocument {
        let size = SlideDeck.size
        let w = size.width, h = size.height, m = margin
        var layers: [CanvasLayer] = []
        var background = theme.background
        func text(_ value: String, _ style: TextStyle, _ frame: CanvasRect, _ role: String) {
            guard !value.isEmpty else { return }
            var fitted = style
            fitted.size = CanvasRenderer.fittingSize(value, style, in: frame, minimum: max(14, style.size * 0.45))
            layers.append(.textLayer(value, fitted, frame: frame, role: role))
        }
        func bulletText(_ items: [String]) -> String { items.map { "•  " + $0 }.joined(separator: "\n") }

        switch layout {
        case .title:
            if theme.boldSections { background = theme.accent }
            let ink = theme.boldSections ? theme.background : theme.ink
            layers.append(.shapeLayer(.rectangle, frame: CanvasRect(x: m, y: h * 0.38 - 28, width: 120, height: 10), fill: .solid(theme.boldSections ? theme.background : theme.accent), role: "accent"))
            text(content.title, style(theme, 120, heading: true, color: ink, lineHeight: 1.02), CanvasRect(x: m, y: h * 0.38, width: w - m * 2, height: 330), "title")
            text(content.subtitle, style(theme, 44, heading: false, color: ink.withAlpha(0.75)), CanvasRect(x: m, y: h * 0.38 + 360, width: w - m * 2, height: 140), "subtitle")
        case .section:
            if theme.boldSections { background = theme.accent }
            let ink = theme.boldSections ? theme.background : theme.ink
            text(content.subtitle, style(theme, 34, heading: false, weight: .semibold, color: ink.withAlpha(0.7)), CanvasRect(x: m, y: h * 0.4 - 70, width: w - m * 2, height: 60), "kicker")
            text(content.title, style(theme, 104, heading: true, color: ink, lineHeight: 1.04), CanvasRect(x: m, y: h * 0.4, width: w - m * 2, height: 300), "title")
        case .statement:
            text(content.title, style(theme, 96, heading: true, alignment: .center, lineHeight: 1.08), CanvasRect(x: m * 1.5, y: h * 0.22, width: w - m * 3, height: h * 0.5), "title")
            text(content.subtitle, style(theme, 36, heading: false, color: theme.ink.withAlpha(0.65), alignment: .center), CanvasRect(x: m * 1.5, y: h * 0.76, width: w - m * 3, height: 100), "subtitle")
        case .bullets:
            text(content.title, style(theme, 72, heading: true), CanvasRect(x: m, y: 110, width: w - m * 2, height: 180), "title")
            text(bulletText(content.bullets), style(theme, 44, heading: false, lineHeight: 1.45), CanvasRect(x: m, y: 330, width: w - m * 2, height: h - 330 - 140), "body")
        case .twoColumns:
            text(content.title, style(theme, 72, heading: true), CanvasRect(x: m, y: 110, width: w - m * 2, height: 180), "title")
            let column = (w - m * 2 - 100) / 2
            text(bulletText(content.bullets), style(theme, 38, heading: false, lineHeight: 1.45), CanvasRect(x: m, y: 340, width: column, height: h - 480), "body")
            layers.append(.shapeLayer(.rectangle, frame: CanvasRect(x: m + column + 48, y: 340, width: 4, height: h - 520), fill: .solid(theme.soft), role: "divider"))
            text(bulletText(content.secondary), style(theme, 38, heading: false, lineHeight: 1.45), CanvasRect(x: m + column + 100, y: 340, width: column, height: h - 480), "body2")
        case .image:
            var picture = CanvasLayer(name: "Picture", content: .image(content.image ?? "", .fill), frame: CanvasRect(x: w * 0.5, y: 0, width: w * 0.5, height: h), role: "photo")
            if content.image == nil { picture.content = .shape(.rectangle); picture.fill = .solid(theme.soft) }
            layers.append(picture)
            text(content.title, style(theme, 76, heading: true, lineHeight: 1.05), CanvasRect(x: m, y: h * 0.3, width: w * 0.5 - m * 1.6, height: 320), "title")
            text(content.caption.isEmpty ? content.subtitle : content.caption, style(theme, 36, heading: false, color: theme.ink.withAlpha(0.7)),
                 CanvasRect(x: m, y: h * 0.3 + 350, width: w * 0.5 - m * 1.6, height: 220), "caption")
        case .bigNumber:
            text(content.number, style(theme, 300, heading: true, weight: .heavy, color: theme.accent, lineHeight: 1), CanvasRect(x: m, y: h * 0.16, width: w - m * 2, height: 380), "number")
            text(content.title, style(theme, 60, heading: true, lineHeight: 1.1), CanvasRect(x: m, y: h * 0.16 + 420, width: w - m * 2, height: 170), "title")
            text(content.caption.isEmpty ? content.subtitle : content.caption, style(theme, 34, heading: false, color: theme.ink.withAlpha(0.65)),
                 CanvasRect(x: m, y: h * 0.16 + 600, width: w - m * 2, height: 120), "caption")
        case .quote:
            text("\u{201C}", style(theme, 320, heading: true, color: theme.accent, lineHeight: 1), CanvasRect(x: m - 10, y: 40, width: 260, height: 300), "mark")
            text(content.quote.isEmpty ? content.title : content.quote, style(theme, 68, heading: true, weight: .medium, lineHeight: 1.18),
                 CanvasRect(x: m, y: 300, width: w - m * 2, height: 440), "quote")
            text(content.attribution.isEmpty ? "" : "— " + content.attribution, style(theme, 36, heading: false, weight: .semibold, color: theme.ink.withAlpha(0.7)),
                 CanvasRect(x: m, y: 780, width: w - m * 2, height: 80), "attribution")
        case .chart:
            text(content.title, style(theme, 64, heading: true), CanvasRect(x: m, y: 100, width: w - m * 2, height: 160), "title")
            layers += bars(content.chart, theme, in: CanvasRect(x: m, y: 320, width: w - m * 2, height: h - 320 - 150))
            text(content.caption, style(theme, 28, heading: false, color: theme.ink.withAlpha(0.6)), CanvasRect(x: m, y: h - 120, width: w - m * 2, height: 60), "caption")
        case .table:
            text(content.title, style(theme, 64, heading: true), CanvasRect(x: m, y: 100, width: w - m * 2, height: 160), "title")
            layers += table(content.table, theme, in: CanvasRect(x: m, y: 310, width: w - m * 2, height: h - 310 - 120))
        case .team:
            text(content.title, style(theme, 64, heading: true), CanvasRect(x: m, y: 100, width: w - m * 2, height: 160), "title")
            let people = Array(content.bullets.prefix(4))
            let count = max(1, people.count)
            let gap = 60.0
            let card = (w - m * 2 - gap * Double(count - 1)) / Double(count)
            for (index, person) in people.enumerated() {
                let x = m + Double(index) * (card + gap)
                let parts = person.components(separatedBy: " — ")
                let side = min(card * 0.6, 300)
                layers.append(.shapeLayer(.ellipse, frame: CanvasRect(x: x + (card - side) / 2, y: 340, width: side, height: side), fill: .solid(theme.soft), role: "avatar"))
                let initials = parts[0].split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined()
                text(initials, style(theme, side * 0.32, heading: true, color: theme.accent, alignment: .center),
                     CanvasRect(x: x + (card - side) / 2, y: 340 + side * 0.31, width: side, height: side * 0.4), "initials")
                text(parts[0], style(theme, 40, heading: true, weight: .semibold, alignment: .center), CanvasRect(x: x, y: 340 + side + 40, width: card, height: 60), "name")
                if parts.count > 1 {
                    text(parts[1], style(theme, 30, heading: false, color: theme.ink.withAlpha(0.65), alignment: .center), CanvasRect(x: x, y: 340 + side + 110, width: card, height: 90), "role")
                }
            }
        case .timeline:
            text(content.title, style(theme, 64, heading: true), CanvasRect(x: m, y: 100, width: w - m * 2, height: 160), "title")
            let steps = Array(content.bullets.prefix(5))
            let lineY = h * 0.52
            layers.append(.shapeLayer(.rectangle, frame: CanvasRect(x: m, y: lineY - 3, width: w - m * 2, height: 6), fill: .solid(theme.soft), role: "line"))
            let count = max(1, steps.count)
            let span = (w - m * 2) / Double(count)
            for (index, step) in steps.enumerated() {
                let x = m + span * Double(index)
                layers.append(.shapeLayer(.ellipse, frame: CanvasRect(x: x, y: lineY - 18, width: 36, height: 36), fill: .solid(theme.accent), role: "dot"))
                let parts = step.components(separatedBy: ": ")
                if parts.count > 1 {
                    text(parts[0], style(theme, 34, heading: true, weight: .semibold, color: theme.accent), CanvasRect(x: x, y: lineY - 110, width: span - 30, height: 60), "when")
                    text(parts.dropFirst().joined(separator: ": "), style(theme, 32, heading: false, lineHeight: 1.3), CanvasRect(x: x, y: lineY + 50, width: span - 40, height: 220), "what")
                } else {
                    text(step, style(theme, 32, heading: false, lineHeight: 1.3), CanvasRect(x: x, y: lineY + 50, width: span - 40, height: 220), "what")
                }
            }
        case .closing:
            if theme.boldSections { background = theme.accent }
            let ink = theme.boldSections ? theme.background : theme.ink
            text(content.title.isEmpty ? "Thank you" : content.title, style(theme, 120, heading: true, color: ink, alignment: .center, lineHeight: 1.04),
                 CanvasRect(x: m, y: h * 0.3, width: w - m * 2, height: 280), "title")
            text(content.subtitle, style(theme, 40, heading: false, color: ink.withAlpha(0.75), alignment: .center), CanvasRect(x: m, y: h * 0.3 + 310, width: w - m * 2, height: 160), "subtitle")
        }
        if !theme.footer.isEmpty && layout != .title && layout != .closing && layout != .section {
            var footer = style(theme, 22, heading: false, weight: .medium, color: theme.ink.withAlpha(0.45))
            footer.tracking = 0.5
            layers.append(.textLayer(theme.footer, footer, frame: CanvasRect(x: m, y: h - 70, width: 600, height: 34), role: "footer"))
        }
        return CanvasDocument(name: content.title.isEmpty ? layout.title : content.title, size: size, background: .solid(background), layers: layers)
    }

    /// A bar chart drawn as shapes, so it exports anywhere.
    static func bars(_ points: [ChartPoint], _ theme: DeckTheme, in box: CanvasRect) -> [CanvasLayer] {
        guard !points.isEmpty else { return [] }
        let top = max(points.map(\.value).max() ?? 1, 0.0001)
        let labelHeight = 56.0, valueHeight = 50.0
        let gap = box.width * 0.04
        let barWidth = (box.width - gap * Double(points.count - 1)) / Double(points.count)
        let plot = box.height - labelHeight - valueHeight
        var layers: [CanvasLayer] = []
        layers.append(.shapeLayer(.rectangle, frame: CanvasRect(x: box.minX, y: box.maxY - labelHeight - 2, width: box.width, height: 3), fill: .solid(theme.soft), role: "axis"))
        for (index, point) in points.enumerated() {
            let x = box.minX + Double(index) * (barWidth + gap)
            let height = max(4, plot * max(0, point.value) / top)
            let y = box.maxY - labelHeight - height
            let last = index == points.count - 1
            layers.append(.shapeLayer(.rectangle, frame: CanvasRect(x: x, y: y, width: barWidth, height: height),
                                      fill: .solid(last ? theme.accent : theme.ink.withAlpha(0.22)), radius: min(16, barWidth / 6), role: "bar"))
            var value = TextStyle()
            value.font = theme.bodyFont
            value.size = 30
            value.weight = .semibold
            value.color = theme.ink
            value.alignment = .center
            layers.append(.textLayer(ChartPoint.format(point.value), value, frame: CanvasRect(x: x, y: y - valueHeight, width: barWidth, height: valueHeight), role: "value"))
            var label = value
            label.weight = .regular
            label.size = 28
            label.color = theme.ink.withAlpha(0.65)
            layers.append(.textLayer(point.label, label, frame: CanvasRect(x: x, y: box.maxY - labelHeight + 12, width: barWidth, height: labelHeight - 12), role: "label"))
        }
        return layers
    }

    static func table(_ rows: [[String]], _ theme: DeckTheme, in box: CanvasRect) -> [CanvasLayer] {
        guard let first = rows.first, !first.isEmpty else { return [] }
        let columns = rows.map(\.count).max() ?? first.count
        let rowHeight = min(96, box.height / Double(rows.count))
        let width = box.width / Double(columns)
        var layers: [CanvasLayer] = []
        for (r, row) in rows.enumerated() {
            let y = box.minY + Double(r) * rowHeight
            if r == 0 {
                layers.append(.shapeLayer(.rectangle, frame: CanvasRect(x: box.minX, y: y, width: box.width, height: rowHeight), fill: .solid(theme.soft), radius: 12, role: "header"))
            } else {
                layers.append(.shapeLayer(.rectangle, frame: CanvasRect(x: box.minX, y: y + rowHeight - 2, width: box.width, height: 2), fill: .solid(theme.soft), role: "rule"))
            }
            for (c, cell) in row.enumerated() {
                var style = TextStyle()
                style.font = theme.bodyFont
                style.size = min(34, rowHeight * 0.4)
                style.weight = r == 0 ? .semibold : .regular
                style.color = theme.ink
                style.alignment = c == 0 ? .left : .right
                let inset = 24.0
                layers.append(.textLayer(cell, style, frame: CanvasRect(x: box.minX + Double(c) * width + inset, y: y + (rowHeight - style.size * 1.3) / 2,
                                                                       width: width - inset * 2, height: style.size * 1.4), role: "cell"))
            }
        }
        return layers
    }

    /// Swaps a hand-edited slide's colours from one theme to another.
    static func recolour(_ canvas: inout CanvasDocument, from old: DeckTheme, to new: DeckTheme) {
        func swap(_ color: CanvasColor) -> CanvasColor {
            func close(_ a: CanvasColor, _ b: CanvasColor) -> Bool { abs(a.red - b.red) + abs(a.green - b.green) + abs(a.blue - b.blue) < 0.04 }
            var result = color
            if close(color, old.background) { result = new.background }
            else if close(color, old.ink) { result = new.ink }
            else if close(color, old.accent) { result = new.accent }
            else if close(color, old.soft) { result = new.soft }
            result.alpha = color.alpha
            return result
        }
        func swap(_ fill: CanvasFill) -> CanvasFill {
            switch fill {
            case .none: return .none
            case .solid(let color): return .solid(swap(color))
            case .linear(let a, let b, let angle): return .linear(swap(a), swap(b), angle: angle)
            }
        }
        canvas.background = swap(canvas.background)
        for index in canvas.layers.indices {
            canvas.layers[index].fill = swap(canvas.layers[index].fill)
            if case .text(let text, var style) = canvas.layers[index].content {
                style.color = swap(style.color)
                if style.font == old.headingFont { style.font = new.headingFont }
                canvas.layers[index].content = .text(text, style)
            }
        }
    }
}

extension ChartPoint {
    /// 1.2m, 48k, 3.5, 120.
    static func format(_ value: Double) -> String {
        let magnitude = abs(value)
        func trim(_ number: Double) -> String {
            let text = String(format: "%.1f", number)
            return text.hasSuffix(".0") ? String(text.dropLast(2)) : text
        }
        if magnitude >= 1_000_000 { return trim(value / 1_000_000) + "m" }
        if magnitude >= 10_000 { return trim(value / 1_000) + "k" }
        return value == value.rounded() ? String(Int(value)) : trim(value)
    }
}

extension CanvasColor {
    func withAlpha(_ alpha: Double) -> CanvasColor {
        var copy = self
        copy.alpha = alpha
        return copy
    }
}

// MARK: Outlines

/// A deck from a Markdown outline, the way people already write them:
/// `# Title` then a line for the subtitle; `## Heading` with `- bullets`; `> A quote — Person`;
/// a heading that's a number ("## $1.2m ARR") becomes a big number; `Label: 12` lines become a chart;
/// `| a | b |` rows become a table; `Notes:` lines become speaker notes.
enum DeckOutline {
    static func slides(from markdown: String, theme: DeckTheme) -> [Slide] {
        var slides: [Slide] = []
        var current: (layout: SlideLayout, content: SlideContent, notes: [String])?
        func flush() {
            guard let item = current else { return }
            var content = item.content
            var layout = item.layout
            // Decide the layout from what the section turned out to hold.
            if layout == .bullets {
                if !content.table.isEmpty { layout = .table }
                else if content.chart.count >= 2 && content.bullets.isEmpty { layout = .chart }
                else if !content.quote.isEmpty && content.bullets.isEmpty { layout = .quote }
                else if content.bullets.isEmpty && !content.number.isEmpty { layout = .bigNumber }
                else if content.bullets.isEmpty && ["thank", "questions", "thanks", "q&a"].contains(where: { content.title.lowercased().hasPrefix($0) }) { layout = .closing }
                else if content.bullets.isEmpty { layout = content.subtitle.isEmpty ? .section : .statement }
                else if content.bullets.count >= 3 && content.bullets.allSatisfy({ $0.contains(" — ") }) && content.title.lowercased().contains("team") { layout = .team }
                else if content.bullets.count >= 3 && content.bullets.allSatisfy({ $0.range(of: #"^[^:]{1,24}: "#, options: .regularExpression) != nil })
                            && (content.title.lowercased().contains("plan") || content.title.lowercased().contains("roadmap") || content.title.lowercased().contains("timeline")) {
                    layout = .timeline
                } else if content.bullets.count > 7 {
                    let half = (content.bullets.count + 1) / 2
                    content.secondary = Array(content.bullets[half...])
                    content.bullets = Array(content.bullets[..<half])
                    layout = .twoColumns
                }
            }
            slides.append(Slide(layout: layout, content: content, notes: item.notes.joined(separator: "\n"), theme: theme))
            current = nil
        }
        for raw in markdown.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if line.hasPrefix("# ") {
                flush()
                var content = SlideContent()
                content.title = String(line.dropFirst(2))
                current = (slides.isEmpty ? .title : .section, content, [])
            } else if line.hasPrefix("## ") || line.hasPrefix("### ") {
                flush()
                var content = SlideContent()
                let heading = line.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces)
                // "$1.2m ARR" or "48% retention": a big number with the rest as its title.
                if let match = heading.range(of: #"^[$€£]?[0-9][0-9.,]*[%kmbx+]*\b"#, options: .regularExpression), heading.count < 60 {
                    content.number = String(heading[match])
                    content.title = heading[match.upperBound...].trimmingCharacters(in: .whitespaces)
                } else {
                    content.title = heading
                }
                current = (.bullets, content, [])
            } else if line.lowercased().hasPrefix("notes:") {
                current?.notes.append(String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces))
            } else if line.hasPrefix(">") {
                let text = line.drop { $0 == ">" || $0 == " " }
                let parts = text.components(separatedBy: " — ")
                // A quote gets its own slide, unless it follows a heading that's waiting for something to say.
                if let section = current {
                    let content = section.content
                    let waiting = content.subtitle.isEmpty && content.bullets.isEmpty && content.number.isEmpty && content.chart.isEmpty && content.table.isEmpty
                    if !waiting || section.layout == .title { flush() }
                }
                if current == nil { current = (.quote, SlideContent(), []) }
                current?.content.quote = parts[0].trimmingCharacters(in: CharacterSet(charactersIn: "\"\u{201C}\u{201D} "))
                if parts.count > 1 { current?.content.attribution = parts.dropFirst().joined(separator: " — ") }
            } else if line.hasPrefix("|") {
                let cells = line.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
                if cells.allSatisfy({ $0.allSatisfy { $0 == "-" || $0 == ":" } }) { continue }
                if current == nil { current = (.table, SlideContent(), []) }
                current?.content.table.append(cells)
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") || line.range(of: #"^[0-9]+\. "#, options: .regularExpression) != nil {
                let item = line.hasPrefix("- ") || line.hasPrefix("* ") ? String(line.dropFirst(2)) : line.replacingOccurrences(of: #"^[0-9]+\. "#, with: "", options: .regularExpression)
                if current == nil { current = (.bullets, SlideContent(), []) }
                // "Q3: 48" with a number is a chart point.
                if let colon = item.range(of: ": "), let value = Double(item[colon.upperBound...].replacingOccurrences(of: ",", with: "").replacingOccurrences(of: "$", with: "")) {
                    current?.content.chart.append(ChartPoint(label: String(item[..<colon.lowerBound]), value: value))
                } else {
                    current?.content.bullets.append(item)
                }
            } else if current != nil {
                if current?.content.subtitle.isEmpty == true && current?.content.bullets.isEmpty == true {
                    current?.content.subtitle = line
                } else if current?.layout == .bullets {
                    current?.content.caption = line
                }
            }
        }
        flush()
        // Points that were really bullets ("Q3: 48" mixed with prose) go back to bullets.
        for index in slides.indices where slides[index].layout != .chart && !slides[index].content.chart.isEmpty {
            slides[index].content.bullets += slides[index].content.chart.map { "\($0.label): \(ChartPoint.format($0.value))" }
            slides[index].content.chart = []
            slides[index].canvas = DeckLayoutEngine.canvas(slides[index].layout, slides[index].content, theme)
        }
        return slides
    }
}

// MARK: PowerPoint

/// Writes a deck as a .pptx that opens in PowerPoint, Keynote and Google Slides: one slide per slide, with text,
/// shapes and pictures as real objects, and speaker notes left out (they need a notes master; PDF carries them instead).
enum PPTXWriter {
    /// 1 canvas point is 6,350 EMU, so 1920 × 1080 is PowerPoint's 13.333 × 7.5 inch widescreen.
    static let emu = 6_350.0

    static func data(_ deck: SlideDeck, imageData: (String) -> Data?) -> Data {
        var zip = ZipWriter()
        let slides = deck.visibleSlides
        var mediaCount = 0
        var slideFiles: [(xml: String, rels: String)] = []
        for slide in slides {
            var rels: [String] = ["<Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideLayout\" Target=\"../slideLayouts/slideLayout1.xml\"/>"]
            var shapes: [String] = []
            var shapeID = 2
            for layer in slide.canvas.layers where !layer.hidden {
                shapeID += 1
                switch layer.content {
                case .image(let asset, _):
                    guard let data = imageData(asset) else { continue }
                    mediaCount += 1
                    let ext = data.starts(with: [0xFF, 0xD8]) ? "jpeg" : "png"
                    let name = "image\(mediaCount).\(ext)"
                    zip.add("ppt/media/\(name)", data)
                    let rid = "rId\(rels.count + 1)"
                    rels.append("<Relationship Id=\"\(rid)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/image\" Target=\"../media/\(name)\"/>")
                    shapes.append(picture(layer, id: shapeID, rid: rid))
                case .qr(let message):
                    guard let code = CanvasRenderer.qrImage(message), let data = CanvasRenderer.encode(code, as: .png) else { continue }
                    mediaCount += 1
                    let name = "image\(mediaCount).png"
                    zip.add("ppt/media/\(name)", data)
                    let rid = "rId\(rels.count + 1)"
                    rels.append("<Relationship Id=\"\(rid)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/image\" Target=\"../media/\(name)\"/>")
                    shapes.append(picture(layer, id: shapeID, rid: rid))
                default:
                    shapes.append(shape(layer, id: shapeID))
                }
            }
            let background = slide.canvas.background.firstColor ?? .white
            let xml = """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <p:sld xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"><p:cSld><p:bg><p:bgPr><a:solidFill>\(color(background))</a:solidFill><a:effectLst/></p:bgPr></p:bg><p:spTree><p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/><a:chOff x="0" y="0"/><a:chExt cx="0" cy="0"/></a:xfrm></p:grpSpPr>\(shapes.joined())</p:spTree></p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:sld>
            """
            let relsXML = """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\(rels.joined())</Relationships>
            """
            slideFiles.append((xml, relsXML))
        }

        var overrides = slideFiles.indices.map { "<Override PartName=\"/ppt/slides/slide\($0 + 1).xml\" ContentType=\"application/vnd.openxmlformats-officedocument.presentationml.slide+xml\"/>" }
        overrides += [
            "<Override PartName=\"/ppt/presentation.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.presentationml.presentation.main+xml\"/>",
            "<Override PartName=\"/ppt/slideMasters/slideMaster1.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.presentationml.slideMaster+xml\"/>",
            "<Override PartName=\"/ppt/slideLayouts/slideLayout1.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.presentationml.slideLayout+xml\"/>",
            "<Override PartName=\"/ppt/theme/theme1.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.theme+xml\"/>",
            "<Override PartName=\"/ppt/presProps.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.presentationml.presProps+xml\"/>",
            "<Override PartName=\"/ppt/viewProps.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.presentationml.viewProps+xml\"/>",
            "<Override PartName=\"/ppt/tableStyles.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.presentationml.tableStyles+xml\"/>",
            "<Override PartName=\"/docProps/core.xml\" ContentType=\"application/vnd.openxmlformats-package.core-properties+xml\"/>",
            "<Override PartName=\"/docProps/app.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.extended-properties+xml\"/>",
        ]
        zip.add("[Content_Types].xml", """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Default Extension="png" ContentType="image/png"/><Default Extension="jpeg" ContentType="image/jpeg"/>\(overrides.joined())</Types>
        """)
        zip.add("_rels/.rels", """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="ppt/presentation.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/><Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties" Target="docProps/app.xml"/></Relationships>
        """)
        let stamp = ISO8601DateFormatter().string(from: Date())
        zip.add("docProps/core.xml", """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"><dc:title>\(escape(deck.name))</dc:title><dc:creator>11am</dc:creator><dcterms:created xsi:type="dcterms:W3CDTF">\(stamp)</dcterms:created><dcterms:modified xsi:type="dcterms:W3CDTF">\(stamp)</dcterms:modified></cp:coreProperties>
        """)
        zip.add("docProps/app.xml", """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties"><Application>11am</Application><Slides>\(slideFiles.count)</Slides></Properties>
        """)
        let width = Int(SlideDeck.size.width * emu), height = Int(SlideDeck.size.height * emu)
        let slideIDs = slideFiles.indices.map { "<p:sldId id=\"\(256 + $0)\" r:id=\"rId\($0 + 2)\"/>" }.joined()
        zip.add("ppt/presentation.xml", """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <p:presentation xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main" saveSubsetFonts="1"><p:sldMasterIdLst><p:sldMasterId id="2147483648" r:id="rId1"/></p:sldMasterIdLst><p:sldIdLst>\(slideIDs)</p:sldIdLst><p:sldSz cx="\(width)" cy="\(height)"/><p:notesSz cx="6858000" cy="9144000"/><p:defaultTextStyle><a:defPPr><a:defRPr lang="en-AU"/></a:defPPr></p:defaultTextStyle></p:presentation>
        """)
        var presentationRels = ["<Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideMaster\" Target=\"slideMasters/slideMaster1.xml\"/>"]
        presentationRels += slideFiles.indices.map { "<Relationship Id=\"rId\($0 + 2)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide\" Target=\"slides/slide\($0 + 1).xml\"/>" }
        let base = slideFiles.count + 2
        presentationRels += [
            "<Relationship Id=\"rId\(base)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/presProps\" Target=\"presProps.xml\"/>",
            "<Relationship Id=\"rId\(base + 1)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/viewProps\" Target=\"viewProps.xml\"/>",
            "<Relationship Id=\"rId\(base + 2)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/theme\" Target=\"theme/theme1.xml\"/>",
            "<Relationship Id=\"rId\(base + 3)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/tableStyles\" Target=\"tableStyles.xml\"/>",
        ]
        zip.add("ppt/_rels/presentation.xml.rels", """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\(presentationRels.joined())</Relationships>
        """)
        zip.add("ppt/presProps.xml", """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <p:presentationPr xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"/>
        """)
        zip.add("ppt/viewProps.xml", """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <p:viewPr xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"><p:normalViewPr><p:restoredLeft sz="15620"/><p:restoredTop sz="94660"/></p:normalViewPr><p:gridSpacing cx="76200" cy="76200"/></p:viewPr>
        """)
        zip.add("ppt/tableStyles.xml", """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <a:tblStyleLst xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" def="{5C22544A-7EE6-4342-B048-85BDC9FD1C3A}"/>
        """)
        zip.add("ppt/slideMasters/slideMaster1.xml", """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <p:sldMaster xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"><p:cSld><p:bg><p:bgRef idx="1001"><a:schemeClr val="bg1"/></p:bgRef></p:bg><p:spTree><p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/><a:chOff x="0" y="0"/><a:chExt cx="0" cy="0"/></a:xfrm></p:grpSpPr></p:spTree></p:cSld><p:clrMap bg1="lt1" tx1="dk1" bg2="lt2" tx2="dk2" accent1="accent1" accent2="accent2" accent3="accent3" accent4="accent4" accent5="accent5" accent6="accent6" hlink="hlink" folHlink="folHlink"/><p:sldLayoutIdLst><p:sldLayoutId id="2147483649" r:id="rId1"/></p:sldLayoutIdLst><p:txStyles><p:titleStyle><a:lvl1pPr><a:defRPr sz="4400"/></a:lvl1pPr></p:titleStyle><p:bodyStyle><a:lvl1pPr><a:defRPr sz="2800"/></a:lvl1pPr></p:bodyStyle><p:otherStyle><a:lvl1pPr><a:defRPr sz="1800"/></a:lvl1pPr></p:otherStyle></p:txStyles></p:sldMaster>
        """)
        zip.add("ppt/slideMasters/_rels/slideMaster1.xml.rels", """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideLayout" Target="../slideLayouts/slideLayout1.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/theme" Target="../theme/theme1.xml"/></Relationships>
        """)
        zip.add("ppt/slideLayouts/slideLayout1.xml", """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <p:sldLayout xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main" type="blank" preserve="1"><p:cSld name="Blank"><p:spTree><p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/><a:chOff x="0" y="0"/><a:chExt cx="0" cy="0"/></a:xfrm></p:grpSpPr></p:spTree></p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:sldLayout>
        """)
        zip.add("ppt/slideLayouts/_rels/slideLayout1.xml.rels", """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideMaster" Target="../slideMasters/slideMaster1.xml"/></Relationships>
        """)
        zip.add("ppt/theme/theme1.xml", theme(deck.theme))
        for (index, file) in slideFiles.enumerated() {
            zip.add("ppt/slides/slide\(index + 1).xml", file.xml)
            zip.add("ppt/slides/_rels/slide\(index + 1).xml.rels", file.rels)
        }
        return zip.finish()
    }

    private static func e(_ value: Double) -> Int { Int((value * emu).rounded()) }

    private static func transform(_ layer: CanvasLayer) -> String {
        let rotation = layer.rotation == 0 ? "" : " rot=\"\(Int((layer.rotation * 60_000).rounded()))\""
        return "<a:xfrm\(rotation)><a:off x=\"\(e(layer.frame.x))\" y=\"\(e(layer.frame.y))\"/><a:ext cx=\"\(e(max(1, layer.frame.width)))\" cy=\"\(e(max(1, layer.frame.height)))\"/></a:xfrm>"
    }

    private static func color(_ color: CanvasColor) -> String {
        let hex = String(color.hex.dropFirst().prefix(6))
        return color.alpha < 1 ? "<a:srgbClr val=\"\(hex)\"><a:alpha val=\"\(Int(color.alpha * 100_000))\"/></a:srgbClr>" : "<a:srgbClr val=\"\(hex)\"/>"
    }

    private static func fill(_ fill: CanvasFill) -> String {
        switch fill {
        case .none: return "<a:noFill/>"
        case .solid(let value): return "<a:solidFill>\(color(value))</a:solidFill>"
        case .linear(let from, let to, let angle):
            return "<a:gradFill rotWithShape=\"1\"><a:gsLst><a:gs pos=\"0\">\(color(from))</a:gs><a:gs pos=\"100000\">\(color(to))</a:gs></a:gsLst><a:lin ang=\"\(Int(angle * 60_000))\" scaled=\"0\"/></a:gradFill>"
        }
    }

    private static func shape(_ layer: CanvasLayer, id: Int) -> String {
        func preset(_ name: String) -> String { "<a:prstGeom prst=\"\(name)\"><a:avLst/></a:prstGeom>" }
        var geometry = preset("rect")
        var shapeFill = fill(layer.fill)
        var line = "<a:ln><a:noFill/></a:ln>"
        if let stroke = layer.stroke, layer.strokeWidth > 0 {
            line = "<a:ln w=\"\(e(layer.strokeWidth))\"><a:solidFill>\(color(stroke))</a:solidFill></a:ln>"
        }
        var body = ""
        switch layer.content {
        case .shape(let kind):
            switch kind {
            case .rectangle:
                if layer.cornerRadius > 0 {
                    let short = max(1, min(layer.frame.width, layer.frame.height))
                    let adjust = Int(min(50_000, layer.cornerRadius / short * 100_000))
                    geometry = "<a:prstGeom prst=\"roundRect\"><a:avLst><a:gd name=\"adj\" fmla=\"val \(adjust)\"/></a:avLst></a:prstGeom>"
                }
            case .ellipse: geometry = preset("ellipse")
            case .triangle: geometry = preset("triangle")
            case .star: geometry = preset("star5")
            case .line, .arrow:
                geometry = preset("line")
                shapeFill = "<a:noFill/>"
                let stroke = layer.stroke ?? layer.fill.firstColor ?? .black
                line = "<a:ln w=\"\(e(max(layer.strokeWidth, 2)))\" cap=\"rnd\"><a:solidFill>\(color(stroke))</a:solidFill>\(kind == .arrow ? "<a:tailEnd type=\"triangle\" w=\"med\" len=\"med\"/>" : "")</a:ln>"
            }
        case .text(let text, let style):
            body = textBody(text, style)
        default:
            break
        }
        let name = escape(layer.name)
        return "<p:sp><p:nvSpPr><p:cNvPr id=\"\(id)\" name=\"\(name)\"/><p:cNvSpPr\(layer.isText ? " txBox=\"1\"" : "")/><p:nvPr/></p:nvSpPr><p:spPr>\(transform(layer))\(geometry)\(shapeFill)\(line)</p:spPr>\(body)</p:sp>"
    }

    private static func textBody(_ text: String, _ style: TextStyle) -> String {
        let align = style.alignment == .left ? "l" : (style.alignment == .center ? "ctr" : "r")
        let size = Int((style.size * 0.75 * 100).rounded()) // points at 96 dpi to PowerPoint's hundredths of a point
        let bold = style.weight == .bold || style.weight == .heavy || style.weight == .semibold ? " b=\"1\"" : ""
        let italic = style.italic ? " i=\"1\"" : ""
        let spacing = style.tracking != 0 ? " spc=\"\(Int(style.tracking * 0.75 * 100))\"" : ""
        let caps = style.uppercase ? " cap=\"all\"" : ""
        let font = style.font == "System" ? "Helvetica Neue" : style.font
        let line = Int(style.lineHeight * 100_000 * 0.85)
        let paragraphs = text.components(separatedBy: "\n").map { paragraph -> String in
            let run = paragraph.isEmpty ? "" : "<a:r><a:rPr lang=\"en-AU\" sz=\"\(size)\"\(bold)\(italic)\(spacing)\(caps) dirty=\"0\"><a:solidFill>\(color(style.color))</a:solidFill><a:latin typeface=\"\(escape(font))\"/></a:rPr><a:t>\(escape(paragraph))</a:t></a:r>"
            return "<a:p><a:pPr algn=\"\(align)\"><a:lnSpc><a:spcPct val=\"\(line)\"/></a:lnSpc></a:pPr>\(run)<a:endParaRPr lang=\"en-AU\" sz=\"\(size)\" dirty=\"0\"/></a:p>"
        }
        return "<p:txBody><a:bodyPr wrap=\"square\" lIns=\"0\" tIns=\"0\" rIns=\"0\" bIns=\"0\" anchor=\"t\"><a:noAutofit/></a:bodyPr><a:lstStyle/>\(paragraphs.joined())</p:txBody>"
    }

    private static func picture(_ layer: CanvasLayer, id: Int, rid: String) -> String {
        "<p:pic><p:nvPicPr><p:cNvPr id=\"\(id)\" name=\"\(escape(layer.name))\"/><p:cNvPicPr><a:picLocks noChangeAspect=\"1\"/></p:cNvPicPr><p:nvPr/></p:nvPicPr><p:blipFill><a:blip r:embed=\"\(rid)\"/><a:stretch><a:fillRect/></a:stretch></p:blipFill><p:spPr>\(transform(layer))<a:prstGeom prst=\"rect\"><a:avLst/></a:prstGeom></p:spPr></p:pic>"
    }

    private static func theme(_ theme: DeckTheme) -> String {
        func hex(_ color: CanvasColor) -> String { String(color.hex.dropFirst().prefix(6)) }
        let heading = theme.headingFont == "System" ? "Helvetica Neue" : theme.headingFont
        let body = theme.bodyFont == "System" ? "Helvetica Neue" : theme.bodyFont
        let fills = "<a:solidFill><a:schemeClr val=\"phClr\"/></a:solidFill>"
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <a:theme xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" name="\(escape(theme.name))"><a:themeElements><a:clrScheme name="\(escape(theme.name))"><a:dk1><a:srgbClr val="\(hex(theme.ink))"/></a:dk1><a:lt1><a:srgbClr val="\(hex(theme.background))"/></a:lt1><a:dk2><a:srgbClr val="\(hex(theme.ink))"/></a:dk2><a:lt2><a:srgbClr val="\(hex(theme.soft))"/></a:lt2><a:accent1><a:srgbClr val="\(hex(theme.accent))"/></a:accent1><a:accent2><a:srgbClr val="\(hex(theme.soft))"/></a:accent2><a:accent3><a:srgbClr val="A5A5A5"/></a:accent3><a:accent4><a:srgbClr val="FFC000"/></a:accent4><a:accent5><a:srgbClr val="5B9BD5"/></a:accent5><a:accent6><a:srgbClr val="70AD47"/></a:accent6><a:hlink><a:srgbClr val="0563C1"/></a:hlink><a:folHlink><a:srgbClr val="954F72"/></a:folHlink></a:clrScheme><a:fontScheme name="\(escape(theme.name))"><a:majorFont><a:latin typeface="\(escape(heading))"/><a:ea typeface=""/><a:cs typeface=""/></a:majorFont><a:minorFont><a:latin typeface="\(escape(body))"/><a:ea typeface=""/><a:cs typeface=""/></a:minorFont></a:fontScheme><a:fmtScheme name="Office"><a:fillStyleLst>\(fills)\(fills)\(fills)</a:fillStyleLst><a:lnStyleLst><a:ln w="6350"><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:ln><a:ln w="12700"><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:ln><a:ln w="19050"><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:ln></a:lnStyleLst><a:effectStyleLst><a:effectStyle><a:effectLst/></a:effectStyle><a:effectStyle><a:effectLst/></a:effectStyle><a:effectStyle><a:effectLst/></a:effectStyle></a:effectStyleLst><a:bgFillStyleLst>\(fills)\(fills)\(fills)</a:bgFillStyleLst></a:fmtScheme></a:themeElements><a:objectDefaults/><a:extraClrSchemeLst/></a:theme>
        """
    }

    static func escape(_ text: String) -> String { DocxWriter.escape(text) }
}

extension ZipWriter {
    mutating func add(_ name: String, _ text: String) { add(name, Data(text.utf8)) }
}
