import SwiftUI
import UniformTypeIdentifiers

/// Robert's Photo: grade, crop, straighten, clean up and cut out, without changing the original file.
struct PhotoView: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var photo: PhotoModel
    @Environment(\.colorScheme) private var scheme
    @State private var importing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "photo", subtitle: "Robert · \(photo.name)") {
                HStack(spacing: 6) {
                    Button { photo.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                        .buttonStyle(.vellumSecondary)
                        .disabled(!photo.canUndo)
                        .keyboardShortcut("z", modifiers: .command)
                        .help("Undo")
                    Button { photo.redo() } label: { Image(systemName: "arrow.uturn.forward") }
                        .buttonStyle(.vellumSecondary)
                        .disabled(!photo.canRedo)
                        .keyboardShortcut("z", modifiers: [.command, .shift])
                        .help("Redo")
                    Button(photo.showOriginal ? "After" : "Before") { photo.showOriginal.toggle() }
                        .buttonStyle(.vellumSecondary)
                        .help("Compare with the photo before any colour changes")
                    Menu {
                        ForEach(PhotoExportFormat.allCases) { format in
                            Button(format.title) { photo.export(as: format) }
                        }
                    } label: {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                    .menuStyle(.button)
                    .buttonStyle(.borderless)
                    .fixedSize()
                    .foregroundStyle(theme.inkSecondary(scheme))
                    Button {
                        importing = true
                    } label: {
                        Label("Open photo…", systemImage: "photo")
                    }
                    .buttonStyle(.vellumPrimary)
                }
            }

            PhotoToolBar()

            HStack(alignment: .top, spacing: 14) {
                PhotoCanvas()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        HistogramView(values: photo.histogram)
                            .frame(height: 64)
                        GradePanel(settings: $photo.settings, autoSource: { photo.autoSource })
                    }
                    .padding(14)
                }
                .scrollContentBackground(.hidden)
                .frame(width: 300)
                .frame(maxHeight: .infinity)
                .vellum(level: 3, radius: max(theme.radius - 2, 8))
            }
            .frame(maxHeight: .infinity)
        }
        .padding(24)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.image, .rawImage]) { result in
            if case .success(let url) = result { photo.open(url) }
        }
    }
}

// MARK: Tools

private struct PhotoToolBar: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var photo: PhotoModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 12) {
            Picker("Tool", selection: $photo.tool) {
                ForEach(PhotoTool.allCases) { tool in
                    Label(tool.title, systemImage: tool.symbol).tag(tool)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()

            options
                .font(.system(size: 12))
                .transition(.opacity)

            Spacer(minLength: 0)

            if photo.isBusy { ProgressView().controlSize(.small) }
            if let notice = photo.notice {
                HStack(spacing: 6) {
                    Text(notice)
                        .font(.system(size: 11.5))
                        .foregroundStyle(theme.inkSecondary(scheme))
                        .lineLimit(2)
                    Button { photo.notice = nil } label: { Image(systemName: "xmark").font(.system(size: 9, weight: .bold)) }
                        .buttonStyle(.plain)
                        .foregroundStyle(theme.inkTertiary(scheme))
                }
                .transition(.opacity)
            }
        }
        .animation(theme.spring, value: photo.tool)
        .animation(theme.spring, value: photo.notice)
    }

    @ViewBuilder
    private var options: some View {
        switch photo.tool {
        case .adjust:
            Text("Colour and light are on the right. Drag the wheels and curve, or start from a look.")
                .foregroundStyle(theme.inkTertiary(scheme))
        case .crop:
            HStack(spacing: 8) {
                Picker("Shape", selection: $photo.cropAspect) {
                    ForEach(CropAspect.allCases) { aspect in Text(aspect.title).tag(aspect) }
                }
                .labelsHidden()
                .fixedSize()
                Button { photo.rotate() } label: { Image(systemName: "rotate.right") }
                    .buttonStyle(.vellumSecondary)
                    .help("Rotate 90°")
                Button { photo.flipHorizontal() } label: { Image(systemName: "arrow.left.and.right.righttriangle.left.righttriangle.right") }
                    .buttonStyle(.vellumSecondary)
                    .help("Flip horizontally")
                Button { photo.flipVertical() } label: { Image(systemName: "arrow.up.and.down.righttriangle.up.righttriangle.down") }
                    .buttonStyle(.vellumSecondary)
                    .help("Flip vertically")
                Text("Straighten")
                    .foregroundStyle(theme.inkSecondary(scheme))
                Slider(value: $photo.geometry.straighten, in: -45...45)
                    .controlSize(.small)
                    .frame(width: 130)
                Text(String(format: "%+.1f°", photo.geometry.straighten))
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(theme.inkTertiary(scheme))
                    .frame(width: 42, alignment: .leading)
                Button("Auto") { photo.autoStraighten() }
                    .buttonStyle(.vellumSecondary)
                    .help("Level the horizon")
                Button("Reset") { photo.resetCrop() }
                    .buttonStyle(.vellumSecondary)
            }
        case .heal:
            HStack(spacing: 8) {
                Text("Brush")
                    .foregroundStyle(theme.inkSecondary(scheme))
                Slider(value: $photo.brush, in: 0.006...0.08)
                    .controlSize(.small)
                    .frame(width: 130)
                Button("Clear") { photo.clearSpots() }
                    .buttonStyle(.vellumSecondary)
                    .disabled(photo.spots.isEmpty)
                Text(photo.spots.isEmpty ? "Paint over dust, spots or small distractions." : "\(photo.spots.count) cleaned")
                    .foregroundStyle(theme.inkTertiary(scheme))
            }
        case .cutout:
            HStack(spacing: 8) {
                Toggle("Remove background", isOn: $photo.cutout)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                Text("Finds the subject on this Mac. Export as PNG or HEIC to keep the transparency.")
                    .foregroundStyle(theme.inkTertiary(scheme))
            }
        }
    }
}

// MARK: Canvas

private struct PhotoCanvas: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var photo: PhotoModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                RoundedRectangle(cornerRadius: max(theme.radius - 2, 8), style: .continuous)
                    .fill(theme.well(scheme))
                if let image = photo.preview {
                    let area = CGSize(width: max(proxy.size.width - 32, 1), height: max(proxy.size.height - 32, 1))
                    let scale = min(area.width / CGFloat(image.width), area.height / CGFloat(image.height))
                    let size = CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
                    ZStack(alignment: .topLeading) {
                        if photo.cutout && photo.previewStage != .flat {
                            Checkerboard()
                        }
                        Image(decorative: image, scale: 1)
                            .resizable()
                            .interpolation(.high)
                        if photo.tool == .crop && photo.previewStage == .uncropped {
                            CropOverlay(rect: $photo.geometry.crop, ratio: photo.cropAspect.ratio(original: photo.uncroppedSize), size: size)
                        }
                        if photo.tool == .heal && photo.previewStage == .flat {
                            HealBrush(size: size, brush: photo.brush) { spots in photo.addSpots(spots) }
                        }
                    }
                    .frame(width: size.width, height: size.height)
                    .shadow(color: .black.opacity(0.12), radius: 14, y: 6)
                    .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                } else {
                    AgentLogo(code: "rt", size: 52, color: theme.inkTertiary(scheme))
                }
            }
        }
    }
}

/// Drag inside to move the crop, drag a corner (or anywhere outside) to resize. The shape stays locked unless it's Free.
private struct CropOverlay: View {
    @Binding var rect: CGRect
    /// Width over height in pixels; nil for free.
    var ratio: Double?
    var size: CGSize
    @State private var start: CGRect?
    @State private var handle: CropHandle?

    var body: some View {
        let frame = CGRect(x: rect.minX * size.width, y: rect.minY * size.height, width: rect.width * size.width, height: rect.height * size.height)
        ZStack(alignment: .topLeading) {
            Path { path in
                path.addRect(CGRect(origin: .zero, size: size))
                path.addRect(frame)
            }
            .fill(Color.black.opacity(0.5), style: FillStyle(eoFill: true))
            Path { path in
                for i in 1...2 {
                    let x = frame.minX + frame.width * CGFloat(i) / 3
                    let y = frame.minY + frame.height * CGFloat(i) / 3
                    path.move(to: CGPoint(x: x, y: frame.minY))
                    path.addLine(to: CGPoint(x: x, y: frame.maxY))
                    path.move(to: CGPoint(x: frame.minX, y: y))
                    path.addLine(to: CGPoint(x: frame.maxX, y: y))
                }
            }
            .stroke(Color.white.opacity(handle == nil ? 0.35 : 0.6), lineWidth: 0.5)
            Path { path in path.addRect(frame) }
                .stroke(Color.white, lineWidth: 1)
            Path { path in
                let arm: CGFloat = min(18, frame.width / 3, frame.height / 3)
                for corner in [CGPoint(x: frame.minX, y: frame.minY), CGPoint(x: frame.maxX, y: frame.minY),
                               CGPoint(x: frame.minX, y: frame.maxY), CGPoint(x: frame.maxX, y: frame.maxY)] {
                    let sx: CGFloat = corner.x == frame.minX ? 1 : -1
                    let sy: CGFloat = corner.y == frame.minY ? 1 : -1
                    path.move(to: CGPoint(x: corner.x + sx * arm, y: corner.y))
                    path.addLine(to: corner)
                    path.addLine(to: CGPoint(x: corner.x, y: corner.y + sy * arm))
                }
            }
            .stroke(Color.white, style: StrokeStyle(lineWidth: 3, lineCap: .square))
        }
        .frame(width: size.width, height: size.height)
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 1)
            .onChanged { drag in
                if start == nil {
                    start = rect
                    handle = CropMath.handle(at: drag.startLocation, frame: frame)
                }
                guard let start, let handle else { return }
                let relative = ratio.map { CGFloat($0) * size.height / size.width }
                rect = CropMath.adjust(start, handle: handle, dx: drag.translation.width / size.width,
                                       dy: drag.translation.height / size.height, ratio: relative)
            }
            .onEnded { _ in
                start = nil
                handle = nil
            }
        )
    }
}

enum CropHandle {
    case move, topLeft, topRight, bottomLeft, bottomRight
}

enum CropMath {
    static func handle(at point: CGPoint, frame: CGRect) -> CropHandle {
        let corners: [(CropHandle, CGPoint)] = [
            (.topLeft, CGPoint(x: frame.minX, y: frame.minY)), (.topRight, CGPoint(x: frame.maxX, y: frame.minY)),
            (.bottomLeft, CGPoint(x: frame.minX, y: frame.maxY)), (.bottomRight, CGPoint(x: frame.maxX, y: frame.maxY)),
        ]
        let nearest = corners.min { hypot($0.1.x - point.x, $0.1.y - point.y) < hypot($1.1.x - point.x, $1.1.y - point.y) }!
        if hypot(nearest.1.x - point.x, nearest.1.y - point.y) < 22 || !frame.contains(point) { return nearest.0 }
        return .move
    }

    /// A new crop from where the drag started. Everything is normalised; ratio is width over height in those units.
    static func adjust(_ start: CGRect, handle: CropHandle, dx: CGFloat, dy: CGFloat, ratio: CGFloat?) -> CGRect {
        if handle == .move {
            var moved = start
            moved.origin.x = min(max(start.minX + dx, 0), 1 - start.width)
            moved.origin.y = min(max(start.minY + dy, 0), 1 - start.height)
            return moved
        }
        let minSide: CGFloat = 0.05
        let left = handle == .topLeft || handle == .bottomLeft
        let top = handle == .topLeft || handle == .topRight
        let anchorX = left ? start.maxX : start.minX
        let anchorY = top ? start.maxY : start.minY
        let cornerX = (left ? start.minX : start.maxX) + dx
        let cornerY = (top ? start.minY : start.maxY) + dy
        let roomX = left ? anchorX : 1 - anchorX
        let roomY = top ? anchorY : 1 - anchorY
        var w = min(max(left ? anchorX - cornerX : cornerX - anchorX, minSide), roomX)
        var h = min(max(top ? anchorY - cornerY : cornerY - anchorY, minSide), roomY)
        if let ratio, ratio > 0 {
            // Follow whichever side moved further, then shrink to fit inside the picture.
            if w / ratio > h { h = w / ratio } else { w = h * ratio }
            if w > roomX {
                w = roomX
                h = w / ratio
            }
            if h > roomY {
                h = roomY
                w = h * ratio
            }
        }
        return CGRect(x: left ? anchorX - w : anchorX, y: top ? anchorY - h : anchorY, width: w, height: h)
    }
}

/// Paint over what should go; each stroke is cleaned when you let go.
private struct HealBrush: View {
    var size: CGSize
    var brush: Double
    var onStroke: ([HealSpot]) -> Void
    @State private var hover: CGPoint?
    @State private var stroke: [CGPoint] = []

    var body: some View {
        let radius = CGFloat(brush) * min(size.width, size.height)
        ZStack(alignment: .topLeading) {
            Path { path in
                for point in stroke {
                    path.addEllipse(in: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2))
                }
            }
            .fill(Color.white.opacity(0.45))
            if let hover {
                Circle()
                    .strokeBorder(Color.white, lineWidth: 1.25)
                    .background(Circle().strokeBorder(Color.black.opacity(0.4), lineWidth: 2.5))
                    .frame(width: radius * 2, height: radius * 2)
                    .position(hover)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: size.width, height: size.height)
        .contentShape(Rectangle())
        .onContinuousHover { phase in
            switch phase {
            case .active(let point): hover = point
            case .ended: hover = nil
            }
        }
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { drag in
                hover = drag.location
                // Keep dabs a little closer together than the brush is wide, so the stroke has no gaps.
                if let last = stroke.last, hypot(last.x - drag.location.x, last.y - drag.location.y) < radius * 0.7 { return }
                stroke.append(drag.location)
            }
            .onEnded { _ in
                let spots = stroke
                    .filter { $0.x >= 0 && $0.y >= 0 && $0.x <= size.width && $0.y <= size.height }
                    .map { HealSpot(x: Double($0.x / size.width), y: Double($0.y / size.height), radius: brush) }
                stroke = []
                onStroke(spots)
            }
        )
    }
}

private struct Checkerboard: View {
    var body: some View {
        Canvas { context, size in
            let square: CGFloat = 10
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(white: 0.92)))
            var y: CGFloat = 0
            var row = 0
            while y < size.height {
                var x: CGFloat = row % 2 == 0 ? 0 : square
                while x < size.width {
                    context.fill(Path(CGRect(x: x, y: y, width: square, height: square)), with: .color(Color(white: 0.8)))
                    x += square * 2
                }
                y += square
                row += 1
            }
        }
    }
}

/// Brightness spread of the finished photo: shadows on the left, highlights on the right.
struct HistogramView: View {
    @EnvironmentObject private var theme: Theme
    @Environment(\.colorScheme) private var scheme
    var values: [Float]

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            ZStack {
                RoundedRectangle(cornerRadius: 6).fill(theme.well(scheme))
                if values.count > 1 {
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: h))
                        for (index, value) in values.enumerated() {
                            let x = w * CGFloat(index) / CGFloat(values.count - 1)
                            path.addLine(to: CGPoint(x: x, y: h - h * 0.92 * CGFloat(sqrt(max(value, 0)))))
                        }
                        path.addLine(to: CGPoint(x: w, y: h))
                        path.closeSubpath()
                    }
                    .fill(theme.ink(scheme).opacity(0.28))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .accessibilityLabel("Histogram")
    }
}
