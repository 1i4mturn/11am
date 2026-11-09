import Foundation

// Robert's design extras: charts drawn as layers (and drawn again when their numbers change), photo frames and
// grids you drop pictures into, and print sizes in millimetres or inches.

// MARK: - Charts

enum CanvasCharts {
    static let roles: Set<String> = ["chart-bar", "chart-label", "chart-value"]

    /// A chart's frame and the layers that draw it, grouped. The frame remembers the chart.
    static func layers(_ chart: CanvasChart, in rect: CanvasRect, group: UUID = UUID()) -> [CanvasLayer] {
        var frame = CanvasLayer.shapeLayer(.rectangle, frame: rect, fill: .none, role: "chart")
        frame.name = "Chart"
        frame.chart = chart
        frame.group = group
        return [frame] + drawing(chart, in: rect, group: group)
    }

    /// Just the bars and labels, for a frame that's already there, in the chart's own colours.
    static func drawing(_ chart: CanvasChart, in rect: CanvasRect, group: UUID) -> [CanvasLayer] {
        let color = chart.color, accent = chart.accent, ink = chart.ink, font = chart.font
        let points = chart.points
        guard !points.isEmpty, rect.width > 0, rect.height > 0 else { return [] }
        let top = max(points.map(\.value).max() ?? 0, 0)
        let biggest = points.indices.max { points[$0].value < points[$1].value }
        var layers: [CanvasLayer] = []
        func style(_ size: Double, _ weight: TextWeight, _ color: CanvasColor, _ alignment: TextAlignment) -> TextStyle {
            var style = TextStyle()
            style.font = font
            style.size = (max(8, size) * 10).rounded() / 10
            style.weight = weight
            style.color = color
            style.alignment = alignment
            style.lineHeight = 1.05
            return style
        }
        func add(_ layer: CanvasLayer) {
            var copy = layer
            copy.group = group
            layers.append(copy)
        }
        let count = Double(points.count)
        switch chart.kind {
        case .columns:
            let labelBand = rect.height * 0.12
            let valueBand = rect.height * 0.09
            let plot = CanvasRect(x: rect.x, y: rect.y + valueBand, width: rect.width, height: rect.height - labelBand - valueBand)
            let slot = rect.width / count
            let width = slot * 0.62
            let text = min(rect.height * 0.055, slot * 0.2)
            for (index, point) in points.enumerated() {
                let share = top > 0 ? max(0, point.value) / top : 0
                let height = max(plot.height * share, point.value > 0 ? 2 : 0)
                let x = rect.x + slot * Double(index) + (slot - width) / 2
                let bar = CanvasRect(x: x, y: plot.maxY - height, width: width, height: height)
                var shape = CanvasLayer.shapeLayer(.rectangle, frame: bar, fill: .solid(index == biggest ? accent : color),
                                                   radius: min(width * 0.12, 8), role: "chart-bar")
                shape.name = point.label
                add(shape)
                add(.textLayer(ChartPoint.format(point.value), style(text, .semibold, ink, .center),
                               frame: CanvasRect(x: rect.x + slot * Double(index), y: bar.minY - valueBand, width: slot, height: valueBand), role: "chart-value"))
                add(.textLayer(point.label, style(text * 0.95, .regular, ink.withAlpha(0.7), .center),
                               frame: CanvasRect(x: rect.x + slot * Double(index), y: plot.maxY + labelBand * 0.12, width: slot, height: labelBand * 0.88), role: "chart-label"))
            }
        case .bars:
            let labels = rect.width * 0.3
            let values = rect.width * 0.14
            let plot = CanvasRect(x: rect.x + labels, y: rect.y, width: rect.width - labels - values, height: rect.height)
            let slot = rect.height / count
            let height = slot * 0.62
            let text = min(slot * 0.36, rect.width * 0.045)
            for (index, point) in points.enumerated() {
                let share = top > 0 ? max(0, point.value) / top : 0
                let width = max(plot.width * share, point.value > 0 ? 2 : 0)
                let y = rect.y + slot * Double(index) + (slot - height) / 2
                var shape = CanvasLayer.shapeLayer(.rectangle, frame: CanvasRect(x: plot.x, y: y, width: width, height: height),
                                                   fill: .solid(index == biggest ? accent : color), radius: min(height * 0.12, 8), role: "chart-bar")
                shape.name = point.label
                add(shape)
                add(.textLayer(point.label, style(text, .regular, ink.withAlpha(0.75), .right),
                               frame: CanvasRect(x: rect.x, y: rect.y + slot * Double(index), width: labels - 12, height: slot), role: "chart-label"))
                add(.textLayer(ChartPoint.format(point.value), style(text, .semibold, ink, .left),
                               frame: CanvasRect(x: plot.x + width + 10, y: rect.y + slot * Double(index), width: values + plot.width - width - 10, height: slot), role: "chart-value"))
            }
        }
        return layers
    }
}

extension CanvasDocument {
    /// The chart frames on the design.
    var chartFrames: [CanvasLayer] { layers.filter { $0.role == "chart" && $0.chart != nil } }

    /// Draws a chart again in its frame: new numbers, a new kind, or a frame that was resized.
    mutating func redrawChart(_ frameID: UUID, chart: CanvasChart) {
        guard let position = self.index(of: frameID) else { return }
        let group = layers[position].group ?? UUID()
        layers[position].group = group
        layers[position].chart = chart
        let rect = layers[position].frame
        layers.removeAll { $0.group == group && CanvasCharts.roles.contains($0.role ?? "") }
        guard let at = self.index(of: frameID) else { return }
        layers.insert(contentsOf: CanvasCharts.drawing(chart, in: rect, group: group), at: at + 1)
    }
}

// MARK: - Photo frames and grids

enum PhotoGrid: String, CaseIterable, Identifiable, Sendable {
    case one, two, three, four, six

    var id: String { rawValue }

    var title: String {
        switch self {
        case .one: return "One frame"
        case .two: return "Two side by side"
        case .three: return "One large, two small"
        case .four: return "Four in a grid"
        case .six: return "Six in a grid"
        }
    }

    /// Where each frame goes inside a rectangle, with a gap between.
    func rects(in rect: CanvasRect, gap: Double) -> [CanvasRect] {
        func grid(_ columns: Int, _ rows: Int) -> [CanvasRect] {
            let width = (rect.width - gap * Double(columns - 1)) / Double(columns)
            let height = (rect.height - gap * Double(rows - 1)) / Double(rows)
            return (0..<rows).flatMap { row in
                (0..<columns).map { column in
                    CanvasRect(x: rect.x + Double(column) * (width + gap), y: rect.y + Double(row) * (height + gap), width: width, height: height)
                }
            }
        }
        switch self {
        case .one: return [rect]
        case .two: return rect.width >= rect.height ? grid(2, 1) : grid(1, 2)
        case .three:
            let big = (rect.width - gap) * 0.6
            let small = rect.width - gap - big
            let half = (rect.height - gap) / 2
            return [CanvasRect(x: rect.x, y: rect.y, width: big, height: rect.height),
                    CanvasRect(x: rect.x + big + gap, y: rect.y, width: small, height: half),
                    CanvasRect(x: rect.x + big + gap, y: rect.y + half + gap, width: small, height: half)]
        case .four: return grid(2, 2)
        case .six: return rect.width >= rect.height ? grid(3, 2) : grid(2, 3)
        }
    }
}

enum CanvasFrames {
    /// Empty picture frames, grouped: drop a picture on one to fill it.
    static func layers(_ grid: PhotoGrid, in rect: CanvasRect, gap: Double, radius: Double, fill: CanvasColor, group: UUID = UUID()) -> [CanvasLayer] {
        grid.rects(in: rect, gap: gap).enumerated().map { index, frame in
            var layer = CanvasLayer(name: "Frame \(index + 1)", content: .image("", .fill), frame: frame, fill: .solid(fill), cornerRadius: radius, role: "frame")
            layer.group = grid == .one ? nil : group
            return layer
        }
    }

    static func isEmptyFrame(_ layer: CanvasLayer, hasImage: (String) -> Bool) -> Bool {
        guard case .image(let asset, _) = layer.content else { return false }
        return layer.role == "frame" || asset.isEmpty || !hasImage(asset)
    }

    /// The picture frame under a point (the top one), for a dropped picture.
    static func frame(at x: Double, _ y: Double, in document: CanvasDocument, hasImage: (String) -> Bool) -> UUID? {
        // Only the top layer under the pointer counts: a picture over a frame keeps the drop for itself.
        guard let top = document.layers.reversed().first(where: { layer in
            !layer.hidden && x >= layer.frame.minX && x <= layer.frame.maxX && y >= layer.frame.minY && y <= layer.frame.maxY
        }) else { return nil }
        return !top.locked && isEmptyFrame(top, hasImage: hasImage) ? top.id : nil
    }
}

// MARK: - Print sizes

enum PrintUnit: String, CaseIterable, Identifiable, Sendable {
    case pixels = "px", millimetres = "mm", inches = "in"

    var id: String { rawValue }
    var title: String {
        switch self {
        case .pixels: return "Pixels"
        case .millimetres: return "Millimetres"
        case .inches: return "Inches"
        }
    }

    /// Pixels at the print resolution (300 dots an inch unless you say otherwise).
    func pixels(_ value: Double, dpi: Double = 300) -> Double {
        switch self {
        case .pixels: return value.rounded()
        case .millimetres: return (value / 25.4 * dpi).rounded()
        case .inches: return (value * dpi).rounded()
        }
    }

    /// Back from pixels, for showing a size in this unit.
    func value(_ pixels: Double, dpi: Double = 300) -> Double {
        switch self {
        case .pixels: return pixels
        case .millimetres: return (pixels / dpi * 25.4 * 10).rounded() / 10
        case .inches: return (pixels / dpi * 100).rounded() / 100
        }
    }

    /// Common print sizes, in millimetres.
    static let paper: [(name: String, width: Double, height: Double)] = [
        ("A4", 210, 297), ("A5", 148, 210), ("A3", 297, 420), ("DL invitation", 99, 210), ("Square invitation", 140, 140),
        ("Business card (AU)", 90, 55), ("Postcard", 148, 105), ("Letter (US)", 215.9, 279.4),
    ]
}
