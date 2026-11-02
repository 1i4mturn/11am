import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Pictures used by designs and slides, kept as files next to them so documents stay small.
final class CanvasAssetStore {
    let folder: URL
    private var cache: [String: CGImage] = [:]

    init(folder: URL) {
        self.folder = folder
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    /// Saves a picture and returns its id.
    func add(_ data: Data) -> String {
        let id = UUID().uuidString
        try? data.write(to: folder.appendingPathComponent(id), options: .atomic)
        return id
    }

    func add(image: CGImage) -> String? {
        guard let data = CanvasRenderer.encode(image, as: .png) else { return nil }
        let id = add(data)
        cache[id] = image
        return id
    }

    func data(_ id: String) -> Data? {
        guard !id.isEmpty else { return nil }
        return try? Data(contentsOf: folder.appendingPathComponent(id))
    }

    func image(_ id: String) -> CGImage? {
        if let cached = cache[id] { return cached }
        guard let data = data(id), let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCache: true] as CFDictionary) else { return nil }
        cache[id] = image
        return image
    }

    func size(_ id: String) -> CGSize? { image(id).map { CGSize(width: $0.width, height: $0.height) } }
}

/// One canvas being edited: the document, the selection, and undo. Design and Decks each hold one.
@MainActor
final class CanvasController: ObservableObject {
    @Published private(set) var document: CanvasDocument
    @Published var selection: Set<UUID> = []
    @Published private(set) var revision = 0
    @Published var editingText: UUID?
    let assets: CanvasAssetStore
    /// Called after every finished change, to save.
    var onChange: ((CanvasDocument) -> Void)?

    private var undoStack: [CanvasDocument] = []
    private var redoStack: [CanvasDocument] = []
    private var gestureStart: CanvasDocument?

    init(document: CanvasDocument, assets: CanvasAssetStore) {
        self.document = document
        self.assets = assets
    }

    func load(_ document: CanvasDocument) {
        self.document = document
        selection = []
        editingText = nil
        undoStack.removeAll()
        redoStack.removeAll()
        revision += 1
    }

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    func change(_ edit: (inout CanvasDocument) -> Void) {
        var updated = document
        edit(&updated)
        guard updated != document else { return }
        updated.modified = Date()
        undoStack.append(document)
        if undoStack.count > 100 { undoStack.removeFirst() }
        redoStack.removeAll()
        document = updated
        selection = selection.filter { id in updated.layers.contains { $0.id == id } }
        revision += 1
        onChange?(updated)
    }

    // Drags change the document many times a second but are one undo step.
    func beginGesture() { gestureStart = document }

    func updateGesture(_ edit: (inout CanvasDocument) -> Void) {
        guard let start = gestureStart else { return }
        var updated = start
        edit(&updated)
        document = updated
        revision += 1
    }

    func endGesture() {
        guard let start = gestureStart else { return }
        gestureStart = nil
        guard start != document else { return }
        document.modified = Date()
        undoStack.append(start)
        redoStack.removeAll()
        onChange?(document)
    }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(document)
        document = previous
        selection = selection.filter { id in previous.layers.contains { $0.id == id } }
        revision += 1
        onChange?(previous)
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(document)
        document = next
        revision += 1
        onChange?(next)
    }

    // MARK: Selection

    var selectedLayers: [CanvasLayer] { document.layers.filter { selection.contains($0.id) } }
    var single: CanvasLayer? { selectedLayers.count == 1 ? selectedLayers.first : nil }

    func select(_ id: UUID?, adding: Bool = false) {
        guard let id else {
            if !adding { selection = [] }
            return
        }
        let group = document.expand([id])
        if adding {
            if selection.isSuperset(of: group) { selection.subtract(group) } else { selection.formUnion(group) }
        } else {
            selection = group
        }
    }

    func selectAll() { selection = Set(document.layers.filter { !$0.locked && !$0.hidden }.map(\.id)) }

    // MARK: Adding

    private var centre: CGPoint { CGPoint(x: document.size.width / 2, y: document.size.height / 2) }
    private var unit: Double { min(document.size.width, document.size.height) }

    func addText(_ text: String = "Your text here", heading: Bool = true, brand: CanvasBrand = CanvasBrand()) {
        var style = TextStyle()
        style.font = heading ? brand.headingFont : brand.bodyFont
        style.size = (unit * (heading ? 0.08 : 0.04)).rounded()
        style.weight = heading ? .bold : .regular
        style.color = brand.ink(on: document.background.firstColor ?? .white)
        style.alignment = .center
        let width = document.size.width * 0.7
        let height = Double(CanvasRenderer.textSize(text, style, width: width).height) + 8
        let layer = CanvasLayer.textLayer(text, style, frame: CanvasRect(x: Double(centre.x) - width / 2, y: Double(centre.y) - height / 2, width: width, height: height))
        insert(layer)
    }

    func addShape(_ kind: ShapeKind, brand: CanvasBrand = CanvasBrand()) {
        let side = unit * 0.3
        var frame = CanvasRect(x: Double(centre.x) - side / 2, y: Double(centre.y) - side / 2, width: side, height: side)
        if kind == .line || kind == .arrow { frame = CanvasRect(x: Double(centre.x) - side, y: Double(centre.y) - 10, width: side * 2, height: 20) }
        var layer = CanvasLayer.shapeLayer(kind, frame: frame, fill: .solid(brand.accent))
        if kind == .line || kind == .arrow {
            layer.stroke = brand.primary
            layer.strokeWidth = max(4, unit * 0.006)
            layer.fill = .none
        }
        insert(layer)
    }

    func addImage(_ data: Data, at point: CGPoint? = nil) {
        let id = assets.add(data)
        guard let size = assets.size(id), size.width > 0, size.height > 0 else { return }
        let fit = min(document.size.width * 0.6 / size.width, document.size.height * 0.6 / size.height, 1)
        let width = Double(size.width * fit), height = Double(size.height * fit)
        let target = point ?? centre
        insert(CanvasLayer(name: "Picture", content: .image(id, .fill), frame: CanvasRect(x: Double(target.x) - width / 2, y: Double(target.y) - height / 2, width: width, height: height)))
    }

    func addQR(_ message: String) {
        let side = unit * 0.3
        insert(CanvasLayer(name: "QR code", content: .qr(message), frame: CanvasRect(x: Double(centre.x) - side / 2, y: Double(centre.y) - side / 2, width: side, height: side),
                           fill: .solid(.white), cornerRadius: side * 0.04))
    }

    func insert(_ layer: CanvasLayer) {
        change { $0.layers.append(layer) }
        selection = [layer.id]
    }

    // MARK: Editing

    func update(_ ids: Set<UUID>? = nil, _ transform: (inout CanvasLayer) -> Void) {
        let targets = ids ?? selection
        change { document in
            for index in document.layers.indices where targets.contains(document.layers[index].id) { transform(&document.layers[index]) }
        }
    }

    func updateText(_ transform: (inout TextStyle) -> Void) {
        update { layer in
            if case .text(let text, var style) = layer.content {
                transform(&style)
                layer.content = .text(text, style)
            }
        }
    }

    func setText(_ id: UUID, _ text: String) {
        update([id]) { layer in
            if case .text(_, let style) = layer.content {
                layer.content = .text(text, style)
                layer.name = String(text.prefix(24))
                // Grow the box to fit what was typed.
                let height = Double(CanvasRenderer.textSize(text, style, width: layer.frame.width).height) + 8
                if height > layer.frame.height { layer.frame.height = height }
            }
        }
    }

    func setBackground(_ fill: CanvasFill) { change { $0.background = fill } }
    func delete() { change { CanvasEdit.delete(&$0, selection) } }

    func duplicate() {
        var copies: Set<UUID> = []
        change { copies = CanvasEdit.duplicate(&$0, selection) }
        selection = copies
    }

    func group() { change { _ = CanvasEdit.group(&$0, selection) } }
    func ungroup() { change { CanvasEdit.ungroup(&$0, selection) } }
    func align(_ edge: AlignEdge) { change { CanvasEdit.align(&$0, selection, to: edge) } }
    func distribute(horizontally: Bool) { change { CanvasEdit.distribute(&$0, selection, horizontally: horizontally) } }
    func reorder(_ order: LayerOrder) { change { CanvasEdit.reorder(&$0, selection, order) } }
    func nudge(_ dx: Double, _ dy: Double) {
        let ids = document.expand(selection)
        change { CanvasEdit.move(&$0, ids, dx: dx, dy: dy) }
    }

    func toggleLock() {
        let lock = !(selectedLayers.allSatisfy(\.locked))
        update { $0.locked = lock }
    }

    // MARK: Clipboard

    static let pasteboardType = NSPasteboard.PasteboardType("app.11am.canvas.layers")

    func copy() {
        let layers = selectedLayers
        guard !layers.isEmpty, let data = try? JSONEncoder().encode(layers) else { return }
        let board = NSPasteboard.general
        board.clearContents()
        board.setData(data, forType: Self.pasteboardType)
    }

    func cut() {
        copy()
        delete()
    }

    func paste() {
        let board = NSPasteboard.general
        if let data = board.data(forType: Self.pasteboardType), let layers = try? JSONDecoder().decode([CanvasLayer].self, from: data) {
            var fresh: [CanvasLayer] = []
            var groups: [UUID: UUID] = [:]
            for var layer in layers {
                layer.id = UUID()
                layer.frame = layer.frame.offset(24, 24)
                if let group = layer.group { layer.group = groups[group] ?? { let id = UUID(); groups[group] = id; return id }() }
                fresh.append(layer)
            }
            change { $0.layers += fresh }
            selection = Set(fresh.map(\.id))
        } else if let image = NSImage(pasteboard: board), let tiff = image.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiff), let png = bitmap.representation(using: .png, properties: [:]) {
            addImage(png)
        } else if let text = board.string(forType: .string), !text.isEmpty {
            addText(text, heading: text.count < 60)
        }
    }

    func image(_ id: String) -> CGImage? { assets.image(id) }
}

// MARK: The editor view

struct CanvasEditorView: NSViewRepresentable {
    @ObservedObject var controller: CanvasController
    var backdrop: NSColor
    var accent: NSColor

    func makeNSView(context: Context) -> CanvasNSView {
        let view = CanvasNSView()
        view.controller = controller
        view.backdrop = backdrop
        view.accent = accent
        return view
    }

    func updateNSView(_ view: CanvasNSView, context: Context) {
        view.controller = controller
        view.backdrop = backdrop
        view.accent = accent
        view.sync()
    }
}

final class CanvasNSView: NSView, NSTextViewDelegate {
    weak var controller: CanvasController?
    var backdrop: NSColor = .clear
    var accent: NSColor = .controlAccentColor

    private var seenRevision = -1
    private var seenSelection: Set<UUID> = []
    private var guides: [SnapGuide] = []
    private var marquee: CanvasRect?
    private var textEditor: NSTextView?
    private var editingID: UUID?

    private enum Mode {
        case none
        case move(start: CGPoint, bounds: CanvasRect)
        case resize(handle: CGPoint, start: CGPoint, layer: CanvasLayer)
        case resizeGroup(handle: CGPoint, start: CGPoint, bounds: CanvasRect)
        case rotate(layer: CanvasLayer)
        case marquee(start: CGPoint, base: Set<UUID>)
    }
    private var mode: Mode = .none

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL, .png, .tiff])
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        registerForDraggedTypes([.fileURL, .png, .tiff])
    }

    func sync() {
        guard let controller else { return }
        if controller.revision != seenRevision || controller.selection != seenSelection {
            seenRevision = controller.revision
            seenSelection = controller.selection
            needsDisplay = true
        }
        if controller.editingText != editingID {
            if let id = controller.editingText { beginTextEditing(id) } else { endTextEditing(commit: true) }
        }
    }

    // MARK: Geometry

    private var document: CanvasDocument? { controller?.document }

    private var scale: CGFloat {
        guard let size = document?.size, size.width > 0, size.height > 0 else { return 1 }
        let pad: CGFloat = 28
        return max(0.01, min((bounds.width - pad * 2) / CGFloat(size.width), (bounds.height - pad * 2) / CGFloat(size.height)))
    }

    private var origin: CGPoint {
        guard let size = document?.size else { return .zero }
        return CGPoint(x: (bounds.width - CGFloat(size.width) * scale) / 2, y: (bounds.height - CGFloat(size.height) * scale) / 2)
    }

    private func toDocument(_ point: CGPoint) -> CGPoint {
        CGPoint(x: (point.x - origin.x) / scale, y: (point.y - origin.y) / scale)
    }

    private func toView(_ point: CGPoint) -> CGPoint {
        CGPoint(x: origin.x + point.x * scale, y: origin.y + point.y * scale)
    }

    private func toView(_ rect: CanvasRect) -> CGRect {
        CGRect(x: origin.x + CGFloat(rect.x) * scale, y: origin.y + CGFloat(rect.y) * scale, width: CGFloat(rect.width) * scale, height: CGFloat(rect.height) * scale)
    }

    /// The eight resize handles of a layer, in document space, as (-1…1, -1…1) positions and points.
    private func handles(_ layer: CanvasLayer) -> [(position: CGPoint, point: CGPoint)] {
        let positions: [CGPoint] = [CGPoint(x: -1, y: -1), CGPoint(x: 0, y: -1), CGPoint(x: 1, y: -1), CGPoint(x: 1, y: 0),
                                    CGPoint(x: 1, y: 1), CGPoint(x: 0, y: 1), CGPoint(x: -1, y: 1), CGPoint(x: -1, y: 0)]
        let lineLike: Bool = { if case .shape(let kind) = layer.content { return kind == .line || kind == .arrow }; return false }()
        return positions.filter { !lineLike || $0.y == 0 }.map { position in
            (position, rotated(CGPoint(x: position.x * CGFloat(layer.frame.width) / 2, y: position.y * CGFloat(layer.frame.height) / 2), layer))
        }
    }

    /// A point given relative to a layer's centre, rotated with it, in document space.
    private func rotated(_ offset: CGPoint, _ layer: CanvasLayer) -> CGPoint {
        let angle = CGFloat(layer.rotation * .pi / 180)
        return CGPoint(x: CGFloat(layer.frame.midX) + offset.x * cos(angle) - offset.y * sin(angle),
                       y: CGFloat(layer.frame.midY) + offset.x * sin(angle) + offset.y * cos(angle))
    }

    private func rotationHandle(_ layer: CanvasLayer) -> CGPoint {
        rotated(CGPoint(x: 0, y: -CGFloat(layer.frame.height) / 2 - 28 / scale), layer)
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext, let controller, let document else { return }
        backdrop.setFill()
        bounds.fill()
        let page = toView(document.size.rect)
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -6), blur: 24, color: NSColor.black.withAlphaComponent(0.18).cgColor)
        NSColor.white.setFill()
        page.fill()
        context.restoreGState()

        context.saveGState()
        context.clip(to: page)
        context.translateBy(x: origin.x, y: origin.y)
        context.scaleBy(x: scale, y: scale)
        let skipping: Set<UUID> = editingID.map { [$0] } ?? []
        CanvasRenderer.draw(document, in: context, images: { [weak controller] id in controller?.image(id) }, skipping: skipping)
        context.restoreGState()

        // Guides
        accent.withAlphaComponent(0.9).setStroke()
        for guide in guides {
            let path = NSBezierPath()
            path.lineWidth = 1
            if guide.axis == .vertical {
                let x = origin.x + CGFloat(guide.position) * scale
                path.move(to: CGPoint(x: x, y: page.minY))
                path.line(to: CGPoint(x: x, y: page.maxY))
            } else {
                let y = origin.y + CGFloat(guide.position) * scale
                path.move(to: CGPoint(x: page.minX, y: y))
                path.line(to: CGPoint(x: page.maxX, y: y))
            }
            path.stroke()
        }

        // Selection
        let selected = controller.selectedLayers
        if selected.count == 1, let layer = selected.first, editingID == nil {
            drawOutline(layer, thick: true)
            if !layer.locked {
                for handle in handles(layer) {
                    let point = toView(handle.point)
                    let box = CGRect(x: point.x - 4.5, y: point.y - 4.5, width: 9, height: 9)
                    NSColor.white.setFill()
                    box.fill()
                    accent.setStroke()
                    let outline = NSBezierPath(rect: box)
                    outline.lineWidth = 1.5
                    outline.stroke()
                }
                let knob = toView(rotationHandle(layer))
                let top = toView(rotated(CGPoint(x: 0, y: -CGFloat(layer.frame.height) / 2), layer))
                let stem = NSBezierPath()
                stem.move(to: top)
                stem.line(to: knob)
                stem.lineWidth = 1
                stem.stroke()
                let circle = NSBezierPath(ovalIn: CGRect(x: knob.x - 6, y: knob.y - 6, width: 12, height: 12))
                NSColor.white.setFill()
                circle.fill()
                circle.lineWidth = 1.5
                circle.stroke()
            } else {
                let point = toView(CGPoint(x: layer.frame.maxX, y: layer.frame.minY))
                ("🔒" as NSString).draw(at: CGPoint(x: point.x + 4, y: point.y - 18), withAttributes: [.font: NSFont.systemFont(ofSize: 12)])
            }
        } else if selected.count > 1 {
            for layer in selected { drawOutline(layer, thick: false) }
            if let box = document.bounds(of: controller.selection) {
                let rect = toView(box)
                accent.setStroke()
                let path = NSBezierPath(rect: rect)
                path.lineWidth = 1.5
                path.setLineDash([5, 3], count: 2, phase: 0)
                path.stroke()
                for corner in [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY)] {
                    let handle = CGRect(x: corner.x - 4.5, y: corner.y - 4.5, width: 9, height: 9)
                    NSColor.white.setFill()
                    handle.fill()
                    NSBezierPath(rect: handle).stroke()
                }
            }
        }
        if let marquee {
            let rect = toView(marquee.standardised)
            accent.withAlphaComponent(0.08).setFill()
            rect.fill()
            accent.setStroke()
            let path = NSBezierPath(rect: rect)
            path.lineWidth = 1
            path.stroke()
        }
    }

    private func drawOutline(_ layer: CanvasLayer, thick: Bool) {
        let corners = [CGPoint(x: -1, y: -1), CGPoint(x: 1, y: -1), CGPoint(x: 1, y: 1), CGPoint(x: -1, y: 1)].map {
            toView(rotated(CGPoint(x: $0.x * CGFloat(layer.frame.width) / 2, y: $0.y * CGFloat(layer.frame.height) / 2), layer))
        }
        let path = NSBezierPath()
        path.move(to: corners[0])
        for corner in corners.dropFirst() { path.line(to: corner) }
        path.close()
        path.lineWidth = thick ? 1.5 : 1
        accent.setStroke()
        path.stroke()
    }

    // MARK: Mouse

    override func mouseDown(with event: NSEvent) {
        guard let controller, let document else { return }
        if editingID != nil { controller.editingText = nil }
        window?.makeFirstResponder(self)
        let point = toDocument(convert(event.locationInWindow, from: nil))
        let tolerance = 7 / scale
        let shift = event.modifierFlags.contains(.shift)

        // Handles on a single selection.
        if let layer = controller.single, !layer.locked {
            let knob = rotationHandle(layer)
            if hypot(point.x - knob.x, point.y - knob.y) <= tolerance + 2 {
                controller.beginGesture()
                mode = .rotate(layer: layer)
                return
            }
            for handle in handles(layer) where hypot(point.x - handle.point.x, point.y - handle.point.y) <= tolerance {
                controller.beginGesture()
                mode = .resize(handle: handle.position, start: point, layer: layer)
                return
            }
        } else if controller.selection.count > 1, let box = document.bounds(of: controller.selection) {
            for (x, y) in [(-1.0, -1.0), (1.0, -1.0), (1.0, 1.0), (-1.0, 1.0)] {
                let corner = CGPoint(x: x < 0 ? box.minX : box.maxX, y: y < 0 ? box.minY : box.maxY)
                if hypot(point.x - corner.x, point.y - corner.y) <= tolerance {
                    controller.beginGesture()
                    mode = .resizeGroup(handle: CGPoint(x: x, y: y), start: point, bounds: box)
                    return
                }
            }
        }

        if let hit = CanvasGeometry.hit(point, in: document, tolerance: Double(tolerance)) {
            if event.clickCount == 2, let layer = document.layer(hit), layer.isText, !layer.locked {
                controller.select(hit)
                controller.editingText = hit
                return
            }
            if shift {
                controller.select(hit, adding: true)
            } else if !controller.selection.contains(hit) {
                controller.select(hit)
            }
            let movable = controller.selectedLayers.contains { !$0.locked }
            if movable, let box = document.bounds(of: controller.selection) {
                controller.beginGesture()
                mode = .move(start: point, bounds: box)
            }
        } else {
            if !shift { controller.select(nil) }
            mode = .marquee(start: point, base: shift ? controller.selection : [])
        }
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let controller, let document else { return }
        let point = toDocument(convert(event.locationInWindow, from: nil))
        let shift = event.modifierFlags.contains(.shift)
        switch mode {
        case .none:
            break
        case .move(let start, let bounds):
            var dx = Double(point.x - start.x), dy = Double(point.y - start.y)
            if shift { if abs(dx) > abs(dy) { dy = 0 } else { dx = 0 } }
            let others = document.layers.filter { !controller.selection.contains($0.id) && !$0.hidden }.map { CanvasGeometry.boundingBox($0) }
            let snap = event.modifierFlags.contains(.command)
                ? (dx: 0.0, dy: 0.0, guides: [SnapGuide]())
                : CanvasSnap.snap(bounds.offset(dx, dy), to: others, canvas: document.size, threshold: Double(6 / scale))
            dx += snap.dx
            dy += snap.dy
            guides = snap.guides
            let ids = controller.selection
            controller.updateGesture { CanvasEdit.move(&$0, ids, dx: dx, dy: dy) }
        case .resize(let handle, let start, let layer):
            let updated = resized(layer, handle: handle, from: start, to: point, keepAspect: shift || keepsAspect(layer), corner: handle.x != 0 && handle.y != 0)
            controller.updateGesture { document in
                if let index = document.index(of: layer.id) { document.layers[index] = updated }
            }
        case .resizeGroup(let handle, let start, let bounds):
            var dx = Double(point.x - start.x) * Double(handle.x), dy = Double(point.y - start.y) * Double(handle.y)
            let factor = max((bounds.width + dx) / max(bounds.width, 1), (bounds.height + dy) / max(bounds.height, 1), 0.05)
            dx = bounds.width * (factor - 1)
            dy = bounds.height * (factor - 1)
            let new = CanvasRect(x: handle.x < 0 ? bounds.minX - dx : bounds.minX, y: handle.y < 0 ? bounds.minY - dy : bounds.minY,
                                 width: bounds.width + dx, height: bounds.height + dy)
            let ids = controller.selection
            controller.updateGesture { CanvasEdit.resize(&$0, ids, from: bounds, to: new) }
        case .rotate(let layer):
            var angle = atan2(Double(point.y) - layer.frame.midY, Double(point.x) - layer.frame.midX) * 180 / .pi + 90
            if shift { angle = (angle / 15).rounded() * 15 }
            if abs(angle.truncatingRemainder(dividingBy: 90)) < 2 { angle = (angle / 90).rounded() * 90 }
            angle = angle.truncatingRemainder(dividingBy: 360)
            controller.updateGesture { document in
                if let index = document.index(of: layer.id) { document.layers[index].rotation = angle }
            }
        case .marquee(let start, let base):
            let rect = CanvasRect(x: Double(start.x), y: Double(start.y), width: Double(point.x - start.x), height: Double(point.y - start.y))
            marquee = rect
            controller.selection = base.union(CanvasGeometry.inside(rect, in: document))
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        switch mode {
        case .move, .resize, .resizeGroup, .rotate: controller?.endGesture()
        default: break
        }
        mode = .none
        guides = []
        marquee = nil
        needsDisplay = true
    }

    private func keepsAspect(_ layer: CanvasLayer) -> Bool {
        switch layer.content {
        case .image, .qr: return true
        default: return false
        }
    }

    /// Resizes from a handle, keeping the opposite side where it was even when rotated. Corner handles on text
    /// scale the type with the box.
    private func resized(_ layer: CanvasLayer, handle: CGPoint, from start: CGPoint, to point: CGPoint, keepAspect: Bool, corner: Bool) -> CanvasLayer {
        let angle = layer.rotation * .pi / 180
        let dx = Double(point.x - start.x), dy = Double(point.y - start.y)
        let lx = dx * cos(-angle) - dy * sin(-angle), ly = dx * sin(-angle) + dy * cos(-angle)
        let hx = Double(handle.x), hy = Double(handle.y)
        let w = layer.frame.width, h = layer.frame.height
        var newW = max(4, w + hx * lx), newH = max(4, h + hy * ly)
        if hx == 0 { newW = w }
        if hy == 0 { newH = h }
        if keepAspect && corner {
            let factor = max(newW / max(w, 1), newH / max(h, 1))
            newW = max(4, w * factor)
            newH = max(4, h * factor)
        }
        // The opposite anchor stays put.
        let ax = -hx * w / 2, ay = -hy * h / 2
        let bx = -hx * newW / 2, by = -hy * newH / 2
        let rax = ax * cos(angle) - ay * sin(angle), ray = ax * sin(angle) + ay * cos(angle)
        let rbx = bx * cos(angle) - by * sin(angle), rby = bx * sin(angle) + by * cos(angle)
        let cx = layer.frame.midX + rax - rbx, cy = layer.frame.midY + ray - rby
        var result = layer
        result.frame = CanvasRect(x: cx - newW / 2, y: cy - newH / 2, width: newW, height: newH)
        if case .text(let text, var style) = layer.content, corner {
            style.size = max(4, (style.size * newW / max(w, 1) * 10).rounded() / 10)
            result.content = .text(text, style)
        }
        return result
    }

    // MARK: Keys

    override func keyDown(with event: NSEvent) {
        guard let controller else { return }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let step = flags.contains(.shift) ? 10.0 : 1.0
        if let special = event.specialKey {
            switch special {
            case .leftArrow: controller.nudge(-step, 0)
            case .rightArrow: controller.nudge(step, 0)
            case .upArrow: controller.nudge(0, -step)
            case .downArrow: controller.nudge(0, step)
            case .delete, .deleteForward, .backspace: controller.delete()
            case .carriageReturn, .enter:
                if let layer = controller.single, layer.isText { controller.editingText = layer.id }
            default: super.keyDown(with: event)
            }
            return
        }
        if event.keyCode == 53 {
            controller.select(nil)
            return
        }
        if flags.contains(.command) {
            switch event.charactersIgnoringModifiers?.lowercased() ?? "" {
            case "d": controller.duplicate()
            case "g": if flags.contains(.shift) { controller.ungroup() } else { controller.group() }
            case "]": controller.reorder(flags.contains(.option) ? .front : .forward)
            case "[": controller.reorder(flags.contains(.option) ? .back : .backward)
            case "a": controller.selectAll()
            case "c": controller.copy()
            case "x": controller.cut()
            case "v": controller.paste()
            case "z": if flags.contains(.shift) { controller.redo() } else { controller.undo() }
            case "l": controller.toggleLock()
            default: super.keyDown(with: event)
            }
            return
        }
        // Typing with a text layer selected starts editing it.
        if let layer = controller.single, layer.isText, let characters = event.characters, let scalar = characters.unicodeScalars.first,
           !CharacterSet.controlCharacters.contains(scalar) {
            controller.editingText = layer.id
            beginTextEditing(layer.id)
            textEditor?.string = characters
            return
        }
        super.keyDown(with: event)
    }

    @objc(copy:) func copyLayers(_ sender: Any?) { controller?.copy() }
    @objc(cut:) func cutLayers(_ sender: Any?) { controller?.cut() }
    @objc(paste:) func pasteLayers(_ sender: Any?) { controller?.paste() }
    @objc(undo:) func undoChange(_ sender: Any?) { controller?.undo() }
    @objc(redo:) func redoChange(_ sender: Any?) { controller?.redo() }
    @objc(selectAll:) func selectEverything(_ sender: Any?) { controller?.selectAll() }

    // MARK: Text editing

    private func beginTextEditing(_ id: UUID) {
        endTextEditing(commit: true)
        guard let layer = document?.layer(id), case .text(let text, let style) = layer.content else { return }
        editingID = id
        let frame = toView(layer.frame)
        let editor = NSTextView(frame: frame.insetBy(dx: -2, dy: -2))
        editor.drawsBackground = false
        editor.isRichText = false
        editor.allowsUndo = true
        editor.textContainerInset = NSSize(width: 0, height: 0)
        editor.textContainer?.lineFragmentPadding = 0
        editor.isVerticallyResizable = true
        editor.textContainer?.widthTracksTextView = true
        let attributed = CanvasRenderer.attributed(text, style, scale: Double(scale))
        editor.textStorage?.setAttributedString(attributed)
        editor.typingAttributes = attributed.attributes(at: 0, effectiveRange: nil)
        editor.insertionPointColor = accent
        editor.delegate = self
        editor.wantsLayer = true
        editor.layer?.borderColor = accent.cgColor
        editor.layer?.borderWidth = 1
        addSubview(editor)
        textEditor = editor
        window?.makeFirstResponder(editor)
        editor.selectAll(nil)
        needsDisplay = true
    }

    private func endTextEditing(commit: Bool) {
        guard let editor = textEditor, let id = editingID else { return }
        let text = editor.string
        textEditor = nil
        editingID = nil
        editor.delegate = nil
        editor.removeFromSuperview()
        if commit { controller?.setText(id, text) }
        if controller?.editingText != nil { controller?.editingText = nil }
        window?.makeFirstResponder(self)
        needsDisplay = true
    }

    func textDidEndEditing(_ notification: Notification) {
        guard editingID != nil else { return }
        DispatchQueue.main.async { [weak self] in
            self?.controller?.editingText = nil
            self?.endTextEditing(commit: true)
        }
    }

    func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.cancelOperation(_:)) {
            controller?.editingText = nil
            endTextEditing(commit: true)
            return true
        }
        return false
    }

    // MARK: Dropping pictures

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let controller else { return false }
        let point = toDocument(convert(sender.draggingLocation, from: nil))
        let board = sender.draggingPasteboard
        if let urls = board.readObjects(forClasses: [NSURL.self], options: [.urlReadingContentsConformToTypes: [UTType.image.identifier]]) as? [URL], !urls.isEmpty {
            for (index, url) in urls.enumerated() {
                if let data = try? Data(contentsOf: url) { controller.addImage(data, at: CGPoint(x: point.x + CGFloat(index) * 30, y: point.y + CGFloat(index) * 30)) }
            }
            return true
        }
        if let image = NSImage(pasteboard: board), let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
           let png = bitmap.representation(using: .png, properties: [:]) {
            controller.addImage(png, at: point)
            return true
        }
        return false
    }

    override func layout() {
        super.layout()
        if let id = editingID, let layer = document?.layer(id) { textEditor?.frame = toView(layer.frame).insetBy(dx: -2, dy: -2) }
        needsDisplay = true
    }
}

/// A small, live picture of a canvas (slide thumbnails, design cards).
struct CanvasThumbnail: View {
    var document: CanvasDocument
    var images: CanvasImages
    var height: CGFloat

    var body: some View {
        let width = height * CGFloat(document.size.aspect)
        Canvas { context, size in
            context.withCGContext { cg in
                let scale = size.height / CGFloat(max(document.size.height, 1))
                cg.scaleBy(x: scale, y: scale)
                CanvasRenderer.draw(document, in: cg, images: images)
            }
        }
        .frame(width: width, height: height)
    }
}
