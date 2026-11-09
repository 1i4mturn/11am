import CoreGraphics
import Foundation

/// Robert's canvas: designs and slides as layers of text, shapes, images and QR codes. Plain data, so it can be
/// tested, saved as JSON, rendered to PNG, PDF and SVG, and written into PowerPoint files.

// MARK: Geometry and colour

struct CanvasRect: Codable, Hashable, Sendable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    init(_ rect: CGRect) {
        self.init(x: Double(rect.minX), y: Double(rect.minY), width: Double(rect.width), height: Double(rect.height))
    }

    var cg: CGRect { CGRect(x: x, y: y, width: width, height: height) }
    var minX: Double { x }
    var midX: Double { x + width / 2 }
    var maxX: Double { x + width }
    var minY: Double { y }
    var midY: Double { y + height / 2 }
    var maxY: Double { y + height }
    var center: CGPoint { CGPoint(x: midX, y: midY) }

    func union(_ other: CanvasRect) -> CanvasRect {
        let left = min(minX, other.minX), top = min(minY, other.minY)
        return CanvasRect(x: left, y: top, width: max(maxX, other.maxX) - left, height: max(maxY, other.maxY) - top)
    }

    func offset(_ dx: Double, _ dy: Double) -> CanvasRect { CanvasRect(x: x + dx, y: y + dy, width: width, height: height) }

    /// Keeps the width and height positive whichever way a corner was dragged.
    var standardised: CanvasRect {
        CanvasRect(x: min(x, x + width), y: min(y, y + height), width: abs(width), height: abs(height))
    }
}

struct CanvasSize: Codable, Hashable, Sendable {
    var width: Double
    var height: Double

    var rect: CanvasRect { CanvasRect(x: 0, y: 0, width: width, height: height) }
    var aspect: Double { height == 0 ? 1 : width / height }
}

struct CanvasColor: Codable, Hashable, Sendable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double = 1

    init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    /// "#RRGGBB" or "#RRGGBBAA".
    init?(hex: String) {
        var text = hex.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6 || text.count == 8, let value = UInt64(text, radix: 16) else { return nil }
        if text.count == 8 {
            self.init(red: Double((value >> 24) & 0xFF) / 255, green: Double((value >> 16) & 0xFF) / 255,
                      blue: Double((value >> 8) & 0xFF) / 255, alpha: Double(value & 0xFF) / 255)
        } else {
            self.init(red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255, blue: Double(value & 0xFF) / 255)
        }
    }

    var hex: String {
        func byte(_ value: Double) -> String {
            let number = max(0, min(255, Int((value * 255).rounded())))
            return String(format: "%02X", number)
        }
        return "#" + byte(red) + byte(green) + byte(blue) + (alpha < 1 ? byte(alpha) : "")
    }

    var cg: CGColor { CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha) }

    /// Relative luminance, for picking readable text on a colour.
    var luminance: Double {
        func channel(_ value: Double) -> Double { value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4) }
        return 0.2126 * channel(red) + 0.7152 * channel(green) + 0.0722 * channel(blue)
    }

    static let black = CanvasColor(red: 0, green: 0, blue: 0)
    static let white = CanvasColor(red: 1, green: 1, blue: 1)
    static let clear = CanvasColor(red: 0, green: 0, blue: 0, alpha: 0)
}

enum CanvasFill: Codable, Hashable, Sendable {
    case none
    case solid(CanvasColor)
    /// From `from` to `to`, at an angle in degrees (0 is left to right, 90 top to bottom).
    case linear(CanvasColor, CanvasColor, angle: Double)

    var firstColor: CanvasColor? {
        switch self {
        case .none: return nil
        case .solid(let color): return color
        case .linear(let from, _, _): return from
        }
    }
}

// MARK: Layers

enum ShapeKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case rectangle, ellipse, triangle, star, line, arrow

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum TextWeight: String, Codable, CaseIterable, Identifiable, Sendable {
    case regular, medium, semibold, bold, heavy

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum TextAlignment: String, Codable, CaseIterable, Sendable {
    case left, center, right
}

struct TextStyle: Codable, Hashable, Sendable {
    /// A font family, or "System" for San Francisco.
    var font = "System"
    var size: Double = 48
    var weight: TextWeight = .regular
    var italic = false
    var color = CanvasColor.black
    var alignment: TextAlignment = .left
    /// Line height as a multiple of the size.
    var lineHeight: Double = 1.15
    /// Extra space between letters, in points.
    var tracking: Double = 0
    var uppercase = false
    var outline: CanvasColor?
}

enum ImageFit: String, Codable, Sendable {
    /// Fills the frame, cropping what doesn't fit.
    case fill
    /// Shows the whole picture inside the frame.
    case fit
}

struct CanvasLayer: Codable, Identifiable, Hashable, Sendable {
    enum Content: Codable, Hashable, Sendable {
        case text(String, TextStyle)
        case shape(ShapeKind)
        /// An image by its asset id.
        case image(String, ImageFit)
        case qr(String)
    }

    var id = UUID()
    var name: String
    var content: Content
    var frame: CanvasRect
    /// Degrees, clockwise.
    var rotation: Double = 0
    var opacity: Double = 1
    var fill: CanvasFill = .none
    var stroke: CanvasColor?
    var strokeWidth: Double = 0
    var cornerRadius: Double = 0
    var shadow = false
    var locked = false
    var hidden = false
    var group: UUID?
    /// What the layer is for in a template or slide layout ("title", "body", "photo", "logo", "background"), so
    /// layouts, themes and magic resize know how to treat it.
    var role: String?
    /// On a chart's frame layer: what it shows and, when linked, where in Sheets the numbers come from.
    var chart: CanvasChart?

    var isText: Bool { if case .text = content { return true } else { return false } }

    var text: String? {
        if case .text(let text, _) = content { return text }
        return nil
    }

    var textStyle: TextStyle? {
        if case .text(_, let style) = content { return style }
        return nil
    }

    var kindTitle: String {
        switch content {
        case .text: return "Text"
        case .shape(let kind): return kind.title
        case .image: return "Image"
        case .qr: return "QR code"
        }
    }

    static func textLayer(_ text: String, _ style: TextStyle, frame: CanvasRect, role: String? = nil) -> CanvasLayer {
        CanvasLayer(name: String(text.prefix(24)), content: .text(text, style), frame: frame, role: role)
    }

    static func shapeLayer(_ kind: ShapeKind, frame: CanvasRect, fill: CanvasFill, radius: Double = 0, role: String? = nil) -> CanvasLayer {
        CanvasLayer(name: kind.title, content: .shape(kind), frame: frame, fill: fill, cornerRadius: radius, role: role)
    }
}

struct CanvasDocument: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var name: String
    var size: CanvasSize
    var background: CanvasFill = .solid(.white)
    /// Bottom to top.
    var layers: [CanvasLayer] = []
    var modified = Date()

    func layer(_ id: UUID) -> CanvasLayer? { layers.first { $0.id == id } }

    func index(of id: UUID) -> Int? { layers.firstIndex { $0.id == id } }

    /// The layers a selection really covers: picking one member of a group picks the group.
    func expand(_ ids: Set<UUID>) -> Set<UUID> {
        var result = ids
        let groups = Set(layers.filter { ids.contains($0.id) }.compactMap(\.group))
        for layer in layers where layer.group.map({ groups.contains($0) }) == true { result.insert(layer.id) }
        return result
    }

    func bounds(of ids: Set<UUID>) -> CanvasRect? {
        let frames = layers.filter { ids.contains($0.id) }.map { CanvasGeometry.boundingBox($0) }
        guard var result = frames.first else { return nil }
        for frame in frames.dropFirst() { result = result.union(frame) }
        return result
    }
}

// MARK: Geometry helpers

enum CanvasGeometry {
    /// The axis-aligned box around a rotated layer.
    static func boundingBox(_ layer: CanvasLayer) -> CanvasRect {
        guard layer.rotation.truncatingRemainder(dividingBy: 360) != 0 else { return layer.frame }
        let angle = layer.rotation * .pi / 180
        let w = layer.frame.width, h = layer.frame.height
        let width = abs(w * cos(angle)) + abs(h * sin(angle))
        let height = abs(w * sin(angle)) + abs(h * cos(angle))
        return CanvasRect(x: layer.frame.midX - width / 2, y: layer.frame.midY - height / 2, width: width, height: height)
    }

    /// A point in the canvas, in the layer's own unrotated frame.
    static func local(_ point: CGPoint, in layer: CanvasLayer) -> CGPoint {
        let angle = -layer.rotation * .pi / 180
        let dx = Double(point.x) - layer.frame.midX, dy = Double(point.y) - layer.frame.midY
        return CGPoint(x: layer.frame.midX + dx * cos(angle) - dy * sin(angle), y: layer.frame.midY + dx * sin(angle) + dy * cos(angle))
    }

    /// The topmost visible layer under a point, allowing for rotation; lines get a few points of slack.
    static func hit(_ point: CGPoint, in document: CanvasDocument, tolerance: Double = 4) -> UUID? {
        for layer in document.layers.reversed() where !layer.hidden {
            let local = local(point, in: layer)
            var frame = layer.frame.cg
            if case .shape(let kind) = layer.content, kind == .line || kind == .arrow { frame = frame.insetBy(dx: 0, dy: -max(tolerance, 8)) }
            if frame.insetBy(dx: -tolerance / 2, dy: -tolerance / 2).contains(local) { return layer.id }
        }
        return nil
    }

    /// Layers whose boxes fall inside a dragged marquee.
    static func inside(_ marquee: CanvasRect, in document: CanvasDocument) -> Set<UUID> {
        let area = marquee.standardised.cg
        return Set(document.layers.filter { !$0.hidden && !$0.locked && area.intersects(boundingBox($0).cg) }.map(\.id))
    }
}

// MARK: Snapping

struct SnapGuide: Hashable, Sendable {
    enum Axis: Hashable, Sendable { case vertical, horizontal }
    var axis: Axis
    /// x for a vertical guide, y for a horizontal one.
    var position: Double
}

enum CanvasSnap {
    /// Nudges a moving box so its edges or centre line up with the canvas or other layers, within `threshold`.
    static func snap(_ moving: CanvasRect, to others: [CanvasRect], canvas: CanvasSize, threshold: Double) -> (dx: Double, dy: Double, guides: [SnapGuide]) {
        var targetsX: [Double] = [0, canvas.width / 2, canvas.width]
        var targetsY: [Double] = [0, canvas.height / 2, canvas.height]
        for other in others {
            targetsX += [other.minX, other.midX, other.maxX]
            targetsY += [other.minY, other.midY, other.maxY]
        }
        func best(_ edges: [Double], _ targets: [Double]) -> (delta: Double, position: Double)? {
            var found: (delta: Double, position: Double)?
            for edge in edges {
                for target in targets {
                    let delta = target - edge
                    if abs(delta) <= threshold && (found.map { abs(delta) < abs($0.delta) } ?? true) { found = (delta, target) }
                }
            }
            return found
        }
        var guides: [SnapGuide] = []
        let x = best([moving.minX, moving.midX, moving.maxX], targetsX)
        let y = best([moving.minY, moving.midY, moving.maxY], targetsY)
        if let x { guides.append(SnapGuide(axis: .vertical, position: x.position)) }
        if let y { guides.append(SnapGuide(axis: .horizontal, position: y.position)) }
        return (x?.delta ?? 0, y?.delta ?? 0, guides)
    }
}

// MARK: Arranging

enum AlignEdge: String, CaseIterable, Identifiable, Sendable {
    case left, centerX, right, top, centerY, bottom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .left: return "Left"
        case .centerX: return "Centre"
        case .right: return "Right"
        case .top: return "Top"
        case .centerY: return "Middle"
        case .bottom: return "Bottom"
        }
    }
}

enum LayerOrder: Sendable { case front, forward, backward, back }

enum CanvasEdit {
    /// Lines layers up with each other, or with the canvas when only one is selected.
    static func align(_ document: inout CanvasDocument, _ ids: Set<UUID>, to edge: AlignEdge) {
        let ids = document.expand(ids)
        let groups = units(document, ids)
        guard !groups.isEmpty else { return }
        let target: CanvasRect = groups.count == 1 ? document.size.rect : (document.bounds(of: ids) ?? document.size.rect)
        for unit in groups {
            guard let box = document.bounds(of: unit) else { continue }
            var dx = 0.0, dy = 0.0
            switch edge {
            case .left: dx = target.minX - box.minX
            case .centerX: dx = target.midX - box.midX
            case .right: dx = target.maxX - box.maxX
            case .top: dy = target.minY - box.minY
            case .centerY: dy = target.midY - box.midY
            case .bottom: dy = target.maxY - box.maxY
            }
            move(&document, unit, dx: dx, dy: dy)
        }
    }

    /// Equal gaps between three or more layers, left to right or top to bottom.
    static func distribute(_ document: inout CanvasDocument, _ ids: Set<UUID>, horizontally: Bool) {
        let groups = units(document, document.expand(ids)).compactMap { unit in document.bounds(of: unit).map { (unit, $0) } }
        guard groups.count >= 3 else { return }
        let sorted = groups.sorted { horizontally ? $0.1.minX < $1.1.minX : $0.1.minY < $1.1.minY }
        let first = sorted[0].1, last = sorted[sorted.count - 1].1
        let span = horizontally ? last.maxX - first.minX : last.maxY - first.minY
        let used = sorted.reduce(0.0) { $0 + (horizontally ? $1.1.width : $1.1.height) }
        let gap = (span - used) / Double(sorted.count - 1)
        var cursor = horizontally ? first.maxX + gap : first.maxY + gap
        for item in sorted.dropFirst().dropLast() {
            let box = item.1
            if horizontally {
                move(&document, item.0, dx: cursor - box.minX, dy: 0)
                cursor += box.width + gap
            } else {
                move(&document, item.0, dx: 0, dy: cursor - box.minY)
                cursor += box.height + gap
            }
        }
    }

    /// Selected layers grouped by their group, each group moving as one.
    private static func units(_ document: CanvasDocument, _ ids: Set<UUID>) -> [Set<UUID>] {
        var result: [Set<UUID>] = []
        var seenGroups: Set<UUID> = []
        for layer in document.layers where ids.contains(layer.id) {
            if let group = layer.group {
                guard !seenGroups.contains(group) else { continue }
                seenGroups.insert(group)
                result.append(Set(document.layers.filter { $0.group == group && ids.contains($0.id) }.map(\.id)))
            } else {
                result.append([layer.id])
            }
        }
        return result
    }

    static func move(_ document: inout CanvasDocument, _ ids: Set<UUID>, dx: Double, dy: Double) {
        for index in document.layers.indices where ids.contains(document.layers[index].id) && !document.layers[index].locked {
            document.layers[index].frame = document.layers[index].frame.offset(dx, dy)
        }
    }

    /// Scales a set of layers from one box to another (resizing a group or a multiple selection).
    static func resize(_ document: inout CanvasDocument, _ ids: Set<UUID>, from old: CanvasRect, to new: CanvasRect) {
        guard old.width > 0, old.height > 0 else { return }
        let sx = new.width / old.width, sy = new.height / old.height
        for index in document.layers.indices where ids.contains(document.layers[index].id) && !document.layers[index].locked {
            let frame = document.layers[index].frame
            document.layers[index].frame = CanvasRect(x: new.minX + (frame.minX - old.minX) * sx, y: new.minY + (frame.minY - old.minY) * sy,
                                                      width: frame.width * sx, height: frame.height * sy)
            if case .text(let text, var style) = document.layers[index].content, ids.count > 1 {
                style.size *= min(sx, sy)
                document.layers[index].content = .text(text, style)
            }
        }
    }

    static func reorder(_ document: inout CanvasDocument, _ ids: Set<UUID>, _ order: LayerOrder) {
        let ids = document.expand(ids)
        let chosen = document.layers.filter { ids.contains($0.id) }
        let rest = document.layers.filter { !ids.contains($0.id) }
        switch order {
        case .front:
            document.layers = rest + chosen
        case .back:
            document.layers = chosen + rest
        case .forward, .backward:
            guard let first = document.layers.firstIndex(where: { ids.contains($0.id) }),
                  let last = document.layers.lastIndex(where: { ids.contains($0.id) }) else { return }
            var layers = rest
            // Find the neighbour just above (or below) the selection and step past it.
            if order == .forward {
                let above = document.layers[(last + 1)...].first { !ids.contains($0.id) }
                let insertAt = above.flatMap { neighbour in layers.firstIndex { $0.id == neighbour.id }.map { $0 + 1 } } ?? layers.count
                layers.insert(contentsOf: chosen, at: insertAt)
            } else {
                let below = document.layers[..<first].last { !ids.contains($0.id) }
                let insertAt = below.flatMap { neighbour in layers.firstIndex { $0.id == neighbour.id } } ?? 0
                layers.insert(contentsOf: chosen, at: insertAt)
            }
            document.layers = layers
        }
    }

    @discardableResult
    static func group(_ document: inout CanvasDocument, _ ids: Set<UUID>) -> UUID? {
        guard ids.count > 1 else { return nil }
        let group = UUID()
        for index in document.layers.indices where ids.contains(document.layers[index].id) { document.layers[index].group = group }
        // Keep the group together in the stack, where its top layer was.
        let chosen = document.layers.filter { ids.contains($0.id) }
        guard let top = document.layers.lastIndex(where: { ids.contains($0.id) }) else { return group }
        var rest = document.layers.enumerated().filter { !ids.contains($0.element.id) }
        let insertAt = rest.firstIndex { $0.offset > top } ?? rest.count
        rest.insert(contentsOf: chosen.map { (offset: -1, element: $0) }, at: insertAt)
        document.layers = rest.map { $0.element }
        return group
    }

    static func ungroup(_ document: inout CanvasDocument, _ ids: Set<UUID>) {
        let groups = Set(document.layers.filter { ids.contains($0.id) }.compactMap(\.group))
        for index in document.layers.indices where document.layers[index].group.map({ groups.contains($0) }) == true { document.layers[index].group = nil }
    }

    /// Copies, nudged down and right, placed above the originals. Returns the copies' ids.
    @discardableResult
    static func duplicate(_ document: inout CanvasDocument, _ ids: Set<UUID>, offset: Double = 24) -> Set<UUID> {
        let ids = document.expand(ids)
        var groupMap: [UUID: UUID] = [:]
        var copies: [CanvasLayer] = []
        for layer in document.layers where ids.contains(layer.id) {
            var copy = layer
            copy.id = UUID()
            copy.frame = layer.frame.offset(offset, offset)
            copy.locked = false
            if let group = layer.group {
                let fresh = groupMap[group] ?? UUID()
                groupMap[group] = fresh
                copy.group = fresh
            }
            copies.append(copy)
        }
        document.layers += copies
        return Set(copies.map(\.id))
    }

    static func delete(_ document: inout CanvasDocument, _ ids: Set<UUID>) {
        let ids = document.expand(ids)
        document.layers.removeAll { ids.contains($0.id) && !$0.locked }
    }

    // MARK: Magic resize

    /// The same design at another size: full-bleed layers stretch to the new edges, everything else keeps its
    /// proportions and its place relative to the canvas, and text scales with the design.
    static func resized(_ document: CanvasDocument, to size: CanvasSize, name: String? = nil) -> CanvasDocument {
        var result = document
        result.id = UUID()
        result.name = name ?? document.name
        result.size = size
        let old = document.size
        guard old.width > 0, old.height > 0 else { return result }
        let scale = min(size.width / old.width, size.height / old.height)
        let fillScale = max(size.width / old.width, size.height / old.height)
        for index in result.layers.indices {
            let layer = document.layers[index]
            let frame = layer.frame
            let bleedsX = frame.minX <= old.width * 0.03 && frame.maxX >= old.width * 0.97
            let bleedsY = frame.minY <= old.height * 0.03 && frame.maxY >= old.height * 0.97
            var updated: CanvasRect
            if bleedsX && bleedsY {
                // Backgrounds: cover the new canvas.
                updated = CanvasRect(x: 0, y: 0, width: size.width, height: size.height)
            } else if bleedsX {
                // Bands across the full width: stretch across, keep their height share.
                updated = CanvasRect(x: 0, y: frame.minY / old.height * size.height, width: size.width, height: frame.height * scale)
            } else if bleedsY {
                updated = CanvasRect(x: frame.minX / old.width * size.width, y: 0, width: frame.width * scale, height: size.height)
            } else {
                let width = frame.width * scale, height = frame.height * scale
                // Anchor to the nearest edge or the centre, so a logo in a corner stays in that corner.
                func place(_ start: Double, _ length: Double, _ oldTotal: Double, _ newLength: Double, _ newTotal: Double) -> Double {
                    let before = start, after = oldTotal - (start + length)
                    let centre = start + length / 2
                    if abs(centre - oldTotal / 2) < oldTotal * 0.08 { return newTotal / 2 - newLength / 2 }
                    if before <= after { return before * scale }
                    return newTotal - after * scale - newLength
                }
                updated = CanvasRect(x: place(frame.minX, frame.width, old.width, width, size.width),
                                     y: place(frame.minY, frame.height, old.height, height, size.height), width: width, height: height)
            }
            result.layers[index].frame = updated
            result.layers[index].strokeWidth = layer.strokeWidth * scale
            result.layers[index].cornerRadius = layer.cornerRadius * (bleedsX && bleedsY ? fillScale : scale)
            if case .text(let text, var style) = layer.content {
                style.size = (style.size * scale * 10).rounded() / 10
                style.tracking *= scale
                result.layers[index].content = .text(text, style)
            }
        }
        result.modified = Date()
        return result
    }
}

// MARK: Sizes and brand

struct CanvasPreset: Identifiable, Hashable, Sendable {
    var id: String
    var name: String
    var size: CanvasSize
    var group: String

    static let all: [CanvasPreset] = [
        CanvasPreset(id: "instagram", name: "Instagram post", size: CanvasSize(width: 1080, height: 1080), group: "Social"),
        CanvasPreset(id: "portrait", name: "Instagram portrait", size: CanvasSize(width: 1080, height: 1350), group: "Social"),
        CanvasPreset(id: "story", name: "Story or reel", size: CanvasSize(width: 1080, height: 1920), group: "Social"),
        CanvasPreset(id: "linkedin", name: "LinkedIn post", size: CanvasSize(width: 1200, height: 627), group: "Social"),
        CanvasPreset(id: "twitter", name: "X post", size: CanvasSize(width: 1600, height: 900), group: "Social"),
        CanvasPreset(id: "youtube", name: "YouTube thumbnail", size: CanvasSize(width: 1280, height: 720), group: "Social"),
        CanvasPreset(id: "banner", name: "LinkedIn banner", size: CanvasSize(width: 1584, height: 396), group: "Social"),
        CanvasPreset(id: "email", name: "Email header", size: CanvasSize(width: 1200, height: 400), group: "Web"),
        CanvasPreset(id: "og", name: "Link preview", size: CanvasSize(width: 1200, height: 630), group: "Web"),
        CanvasPreset(id: "slide", name: "Presentation 16:9", size: CanvasSize(width: 1920, height: 1080), group: "Documents"),
        CanvasPreset(id: "a4", name: "A4 page", size: CanvasSize(width: 1240, height: 1754), group: "Print"),
        CanvasPreset(id: "poster", name: "Poster A3", size: CanvasSize(width: 1754, height: 2480), group: "Print"),
        CanvasPreset(id: "flyer", name: "Flyer A5", size: CanvasSize(width: 874, height: 1240), group: "Print"),
        CanvasPreset(id: "card", name: "Business card", size: CanvasSize(width: 1050, height: 600), group: "Print"),
        CanvasPreset(id: "logo", name: "Logo", size: CanvasSize(width: 1000, height: 1000), group: "Brand"),
    ]

    static func named(_ id: String) -> CanvasPreset? { all.first { $0.id == id } }
}

/// Robert's brand kit as the canvas needs it.
struct CanvasBrand: Codable, Hashable, Sendable {
    var name = "11am"
    var primary = CanvasColor(red: 0.08, green: 0.08, blue: 0.09)
    var accent = CanvasColor(red: 0.96, green: 0.42, blue: 0.24)
    var paper = CanvasColor(red: 0.98, green: 0.97, blue: 0.95)
    var soft = CanvasColor(red: 0.91, green: 0.89, blue: 0.86)
    var headingFont = "System"
    var bodyFont = "System"
    var footer = "11am.app"

    /// Ink that reads on a background.
    func ink(on background: CanvasColor) -> CanvasColor { background.luminance > 0.4 ? primary : paper }
}

// MARK: Charts on a design

enum CanvasChartKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case columns, bars

    var id: String { rawValue }
    var title: String { self == .columns ? "Columns" : "Bars" }
}

/// A chart drawn as ordinary layers (so it exports anywhere), remembered on its frame layer so it can be drawn again.
struct CanvasChart: Codable, Hashable, Sendable {
    var kind: CanvasChartKind
    var points: [ChartPoint]
    var link: ChartLink?
    var color: CanvasColor
    var accent: CanvasColor
    var ink: CanvasColor
    var font: String

    init(kind: CanvasChartKind, points: [ChartPoint], link: ChartLink? = nil, color: CanvasColor = .black, accent: CanvasColor = .black,
         ink: CanvasColor = .black, font: String = "System") {
        self.kind = kind
        self.points = points
        self.link = link
        self.color = color
        self.accent = accent
        self.ink = ink
        self.font = font
    }
}
