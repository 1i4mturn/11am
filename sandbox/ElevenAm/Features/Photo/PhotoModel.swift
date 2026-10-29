import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import ImageIO
import UniformTypeIdentifiers
import Vision

enum PhotoTool: String, CaseIterable, Identifiable {
    case adjust, crop, heal, cutout

    var id: String { rawValue }

    var title: String {
        switch self {
        case .adjust: return "Adjust"
        case .crop: return "Crop"
        case .heal: return "Clean up"
        case .cutout: return "Cut out"
        }
    }

    var symbol: String {
        switch self {
        case .adjust: return "slider.horizontal.3"
        case .crop: return "crop"
        case .heal: return "bandage"
        case .cutout: return "person.crop.rectangle"
        }
    }
}

enum CropAspect: String, CaseIterable, Identifiable {
    case free, original, square, portrait, story, wide, classic

    var id: String { rawValue }

    var title: String {
        switch self {
        case .free: return "Free"
        case .original: return "Original"
        case .square: return "Square"
        case .portrait: return "4:5"
        case .story: return "9:16"
        case .wide: return "16:9"
        case .classic: return "3:2"
        }
    }

    /// Width over height; nil for free.
    func ratio(original size: CGSize) -> Double? {
        switch self {
        case .free: return nil
        case .original: return size.height > 0 ? size.width / size.height : nil
        case .square: return 1
        case .portrait: return 4.0 / 5
        case .story: return 9.0 / 16
        case .wide: return 16.0 / 9
        case .classic: return 3.0 / 2
        }
    }
}

struct PhotoGeometry: Codable, Equatable {
    /// Normalised to the rotated, straightened picture, from the top-left.
    var crop = CGRect(x: 0, y: 0, width: 1, height: 1)
    var straighten: Double = 0
    var quarterTurns = 0
    var flipH = false
    var flipV = false

    var isIdentity: Bool { self == PhotoGeometry() }
}

enum PhotoGeometryMath {
    static func apply(_ g: PhotoGeometry, to input: CIImage, crop: Bool) -> CIImage {
        var image = input.transformed(by: CGAffineTransform(translationX: -input.extent.minX, y: -input.extent.minY))
        for _ in 0..<((g.quarterTurns % 4 + 4) % 4) { image = image.oriented(.right) }
        if g.flipH { image = image.oriented(.upMirrored) }
        if g.flipV { image = image.oriented(.downMirrored) }
        image = image.transformed(by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY))
        let size = image.extent.size
        if abs(g.straighten) > 0.01 {
            let theta = g.straighten * .pi / 180
            // Scale up just enough that no empty corners show.
            let scale = abs(cos(theta)) + abs(sin(theta)) * max(size.width / size.height, size.height / size.width)
            let t = CGAffineTransform(translationX: size.width / 2, y: size.height / 2)
                .rotated(by: theta)
                .scaledBy(x: scale, y: scale)
                .translatedBy(x: -size.width / 2, y: -size.height / 2)
            image = image.transformed(by: t).cropped(to: CGRect(origin: .zero, size: size))
        }
        if crop, g.crop != CGRect(x: 0, y: 0, width: 1, height: 1) {
            let r = g.crop
            let rect = CGRect(x: r.minX * size.width, y: (1 - r.maxY) * size.height, width: r.width * size.width, height: r.height * size.height).integral
            image = image.cropped(to: rect).transformed(by: CGAffineTransform(translationX: -rect.minX, y: -rect.minY))
        }
        return image
    }

    /// Size of the picture the crop is drawn on (after rotation).
    static func orientedSize(_ size: CGSize, _ g: PhotoGeometry) -> CGSize {
        g.quarterTurns % 2 == 0 ? size : CGSize(width: size.height, height: size.width)
    }
}

/// What the canvas shows: the finished photo, the photo before cropping (while cropping), or flat (while cleaning up).
enum PhotoStage: Equatable {
    case final, uncropped, flat
}

private struct PhotoJob: @unchecked Sendable {
    let base: CIImage
    let renderer: GradeRenderer
    let geometry: PhotoGeometry
    let mask: CIImage?
    let stage: PhotoStage
    let original: Bool
    let context: CIContext
    let wantsHistogram: Bool

    func image() -> CIImage {
        var image = base
        if !original { image = renderer.apply(to: image, frame: base.extent).cropped(to: base.extent) }
        if let mask {
            image = image.applyingFilter("CIBlendWithMask", parameters: [
                kCIInputBackgroundImageKey: CIImage.empty(),
                kCIInputMaskImageKey: mask,
            ])
        }
        switch stage {
        case .final: image = PhotoGeometryMath.apply(geometry, to: image, crop: true)
        case .uncropped: image = PhotoGeometryMath.apply(geometry, to: image, crop: false)
        case .flat: break
        }
        return image
    }

    func run() -> (CGImage?, [Float]) {
        let output = image()
        let cg = context.createCGImage(output, from: output.extent)
        let histogram = wantsHistogram ? Histogram.luminance(of: output, context: context) : []
        return (cg, histogram)
    }
}

private struct PhotoSnapshot: Equatable {
    var settings: GradeSettings
    var geometry: PhotoGeometry
    var spots: [HealSpot]
    var cutout: Bool
}

enum PhotoExportFormat: String, CaseIterable, Identifiable {
    case jpeg, heic, png, tiff

    var id: String { rawValue }
    var title: String { rawValue.uppercased() }

    var type: UTType {
        switch self {
        case .jpeg: return .jpeg
        case .heic: return .heic
        case .png: return .png
        case .tiff: return .tiff
        }
    }

    var keepsTransparency: Bool { self == .png || self == .heic || self == .tiff }
}

/// Robert's Photo: non-destructive colour, crop and straighten, spot clean-up and cut-outs. The original file is never changed.
@MainActor
final class PhotoModel: ObservableObject {
    @Published private(set) var name = "Sample · dusk"
    @Published var settings = GradeSettings() { didSet { changed() } }
    @Published var geometry = PhotoGeometry() { didSet { changed() } }
    @Published private(set) var spots: [HealSpot] = []
    @Published var cutout = false { didSet { if cutout != oldValue { cutoutChanged() } } }
    @Published var tool: PhotoTool = .adjust { didSet { schedulePreview() } }
    @Published var showOriginal = false { didSet { schedulePreview() } }
    @Published var cropAspect: CropAspect = .free { didSet { applyAspect() } }
    @Published var brush: Double = 0.025
    @Published private(set) var preview: CGImage?
    /// Which stage the preview shows, so overlays only draw over the picture they belong to.
    @Published private(set) var previewStage: PhotoStage = .final
    @Published private(set) var histogram: [Float] = []
    @Published private(set) var isBusy = false
    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false
    @Published var notice: String?

    private let looks: LookLibrary
    private let context = CIContext(options: [.cacheIntermediates: false])
    private var original: CIImage
    private var proxy: CGImage?
    private var healed: CGImage?
    private var mask: CIImage?
    private var rendering = false
    private var dirty = false
    private var history: [PhotoSnapshot] = []
    private var future: [PhotoSnapshot] = []
    private var restoring = false
    private var historyTask: Task<Void, Never>?

    init(looks: LookLibrary) {
        self.looks = looks
        let scene = SampleMedia.scene()
        original = scene.map { CIImage(cgImage: $0) } ?? CIImage.empty()
        proxy = scene.flatMap { PhotoModel.makeProxy(CIImage(cgImage: $0), context: context) }
        history = [snapshot]
        schedulePreview()
    }

    var stage: PhotoStage {
        switch tool {
        case .adjust, .cutout: return .final
        case .crop: return .uncropped
        case .heal: return .flat
        }
    }

    /// The picture Auto analyses: the current photo before any grade.
    var autoSource: CIImage? { (healed ?? proxy).map { CIImage(cgImage: $0) } }

    /// Size of the picture the crop overlay is drawn over.
    var uncroppedSize: CGSize {
        guard let proxy else { return CGSize(width: 1, height: 1) }
        return PhotoGeometryMath.orientedSize(CGSize(width: proxy.width, height: proxy.height), geometry)
    }

    private var snapshot: PhotoSnapshot {
        PhotoSnapshot(settings: settings, geometry: geometry, spots: spots, cutout: cutout)
    }

    // MARK: Opening

    func open(_ url: URL) {
        isBusy = true
        notice = nil
        let context = self.context
        Task {
            let loaded = await Task.detached(priority: .userInitiated) { () -> (CIImage, CGImage)? in
                var image: CIImage?
                if UTType(filenameExtension: url.pathExtension)?.conforms(to: .rawImage) == true, let raw = CIRAWFilter(imageURL: url) {
                    image = raw.outputImage
                }
                if image == nil { image = CIImage(contentsOf: url, options: [.applyOrientationProperty: true]) }
                guard let image, let proxy = PhotoModel.makeProxy(image, context: context) else { return nil }
                return (image, proxy)
            }.value
            isBusy = false
            guard let loaded else {
                notice = "That file couldn't be opened as a photo."
                return
            }
            original = loaded.0
            proxy = loaded.1
            healed = nil
            mask = nil
            name = url.lastPathComponent
            restoring = true
            settings = GradeSettings()
            geometry = PhotoGeometry()
            spots = []
            cutout = false
            restoring = false
            cropAspect = .free
            history = [snapshot]
            future = []
            updateUndoState()
            schedulePreview()
        }
    }

    nonisolated private static func makeProxy(_ image: CIImage, context: CIContext) -> CGImage? {
        let longest = max(image.extent.width, image.extent.height)
        guard longest > 0 else { return nil }
        let scale = min(1, 1800 / longest)
        var output = image
        if scale < 1 {
            let f = CIFilter.lanczosScaleTransform()
            f.inputImage = image
            f.scale = Float(scale)
            f.aspectRatio = 1
            output = f.outputImage ?? image
        }
        return context.createCGImage(output, from: output.extent.integral)
    }

    // MARK: Rendering

    private func changed() {
        guard !restoring else { return }
        schedulePreview()
        scheduleHistory()
    }

    private var lastKey: String?

    private func schedulePreview() {
        dirty = true
        guard !rendering else { return }
        renderNext()
    }

    private func renderNext() {
        guard dirty, let base = healed ?? proxy else { return }
        dirty = false
        // While cropping, moving the crop box doesn't change the picture under it.
        var keyGeometry = geometry
        if stage == .uncropped { keyGeometry.crop = .zero }
        if stage == .flat { keyGeometry = PhotoGeometry() }
        let key = "\(settings.hashValueString)|\(keyGeometry)|\(stage)|\(showOriginal)|\(cutout && mask != nil)|\(ObjectIdentifier(base).hashValue)"
        if key == lastKey { return }
        lastKey = key
        rendering = true
        let job = PhotoJob(
            base: CIImage(cgImage: base),
            renderer: looks.renderer(for: settings),
            geometry: geometry,
            mask: cutout ? mask : nil,
            stage: stage,
            original: showOriginal,
            context: context,
            wantsHistogram: stage == .final
        )
        Task {
            let result = await Task.detached(priority: .userInitiated) { job.run() }.value
            preview = result.0
            previewStage = job.stage
            if !result.1.isEmpty { histogram = result.1 }
            rendering = false
            renderNext()
        }
    }

    // MARK: History

    private func scheduleHistory() {
        historyTask?.cancel()
        historyTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard !Task.isCancelled else { return }
            self.commitHistory()
        }
    }

    private func commitHistory() {
        let current = snapshot
        guard history.last != current else { return }
        history.append(current)
        if history.count > 80 { history.removeFirst() }
        future = []
        updateUndoState()
    }

    func undo() {
        historyTask?.cancel()
        commitHistory()
        guard history.count > 1, let last = history.popLast() else { return }
        future.append(last)
        restore(history[history.count - 1])
    }

    func redo() {
        guard let next = future.popLast() else { return }
        history.append(next)
        restore(next)
    }

    private func restore(_ state: PhotoSnapshot) {
        restoring = true
        let spotsChanged = state.spots != spots
        settings = state.settings
        geometry = state.geometry
        spots = state.spots
        cutout = state.cutout
        restoring = false
        updateUndoState()
        if spotsChanged { rebuildHealed() } else { schedulePreview() }
    }

    private func updateUndoState() {
        canUndo = history.count > 1
        canRedo = !future.isEmpty
    }

    // MARK: Crop and straighten

    func rotate() { geometry.quarterTurns = (geometry.quarterTurns + 1) % 4; geometry.crop = CGRect(x: 0, y: 0, width: 1, height: 1); applyAspect() }
    func flipHorizontal() { geometry.flipH.toggle() }
    func flipVertical() { geometry.flipV.toggle() }

    func resetCrop() {
        cropAspect = .free
        geometry.crop = CGRect(x: 0, y: 0, width: 1, height: 1)
        geometry.straighten = 0
    }

    /// The largest centred crop with the chosen shape.
    private func applyAspect() {
        guard let ratio = cropAspect.ratio(original: uncroppedSize) else { return }
        let size = uncroppedSize
        let relative = ratio * size.height / size.width
        var rect = CGRect(x: 0, y: 0, width: 1, height: 1)
        if relative <= 1 { rect.size.width = relative } else { rect.size.height = 1 / relative }
        rect.origin = CGPoint(x: (1 - rect.width) / 2, y: (1 - rect.height) / 2)
        geometry.crop = rect
    }

    func autoStraighten() {
        guard let proxy else { return }
        let request = VNDetectHorizonRequest()
        try? VNImageRequestHandler(cgImage: proxy, options: [:]).perform([request])
        guard let angle = request.results?.first?.angle else {
            notice = "No clear horizon to level."
            return
        }
        geometry.straighten = min(max(-Double(angle) * 180 / .pi, -45), 45)
    }

    // MARK: Clean up

    func addSpots(_ newSpots: [HealSpot]) {
        guard !newSpots.isEmpty, let base = healed ?? proxy else { return }
        spots.append(contentsOf: newSpots)
        isBusy = true
        Task {
            let result = await Task.detached(priority: .userInitiated) { PhotoHeal.apply(newSpots, to: base) }.value
            isBusy = false
            healed = result ?? healed
            mask = nil
            if cutout { cutoutChanged() }
            schedulePreview()
            scheduleHistory()
        }
    }

    func clearSpots() {
        spots = []
        rebuildHealed()
        scheduleHistory()
    }

    private func rebuildHealed() {
        guard let proxy else { return }
        let all = spots
        Task {
            healed = all.isEmpty ? nil : await Task.detached(priority: .userInitiated) { PhotoHeal.apply(all, to: proxy) }.value
            mask = nil
            if cutout { cutoutChanged() }
            schedulePreview()
        }
    }

    // MARK: Cut out

    private func cutoutChanged() {
        defer { if !restoring { scheduleHistory() } }
        guard cutout else {
            schedulePreview()
            return
        }
        guard mask == nil, let base = healed ?? proxy else {
            schedulePreview()
            return
        }
        isBusy = true
        Task {
            let result = await Task.detached(priority: .userInitiated) { PhotoModel.subjectMask(for: base) }.value
            isBusy = false
            if let result {
                mask = result
            } else {
                notice = "Robert couldn't find a clear subject to cut out."
                cutout = false
            }
            schedulePreview()
        }
    }

    nonisolated private static func subjectMask(for image: CGImage) -> CIImage? {
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        guard (try? handler.perform([request])) != nil,
              let observation = request.results?.first,
              let buffer = try? observation.generateScaledMaskForImage(forInstances: observation.allInstances, from: handler) else { return nil }
        return CIImage(cvPixelBuffer: buffer)
    }

    // MARK: Export

    func export(as format: PhotoExportFormat, quality: Double = 0.9) {
        if cutout && !format.keepsTransparency {
            notice = "JPEG can't keep the transparent background. Export as PNG or HEIC instead."
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [format.type]
        panel.nameFieldStringValue = (name as NSString).deletingPathExtension + " (edited)." + (format.type.preferredFilenameExtension ?? format.rawValue)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        isBusy = true
        let original = self.original
        let spots = self.spots
        let cutout = self.cutout
        let renderer = looks.renderer(for: settings)
        let geometry = self.geometry
        let context = self.context
        Task {
            let ok = await Task.detached(priority: .userInitiated) { () -> Bool in
                // Full resolution: clean-ups and the cut-out are redone on the original pixels.
                guard var base = context.createCGImage(original, from: original.extent.integral) else { return false }
                if !spots.isEmpty, let cleaned = PhotoHeal.apply(spots, to: base) { base = cleaned }
                let mask = cutout ? PhotoModel.subjectMask(for: base) : nil
                let job = PhotoJob(base: CIImage(cgImage: base), renderer: renderer, geometry: geometry, mask: mask,
                                   stage: .final, original: false, context: context, wantsHistogram: false)
                let image = job.image()
                guard let output = context.createCGImage(image, from: image.extent, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)),
                      let destination = CGImageDestinationCreateWithURL(url as CFURL, format.type.identifier as CFString, 1, nil) else { return false }
                CGImageDestinationAddImage(destination, output, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
                return CGImageDestinationFinalize(destination)
            }.value
            isBusy = false
            notice = ok ? "Saved \(url.lastPathComponent)." : "The photo couldn't be saved."
        }
    }
}

private extension GradeSettings {
    /// A cheap, stable key for "has the grade changed since the last render".
    var hashValueString: String {
        (try? JSONEncoder().encode(self)).map { String(decoding: $0, as: UTF8.self) } ?? UUID().uuidString
    }
}
