import AppKit
import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers
import Vision

enum FilesMode: String, CaseIterable, Identifiable {
    case browse, search
    var id: String { rawValue }
    var title: String { self == .browse ? "Browse" : "Search" }
}

/// A place in the Files sidebar.
struct FilesPlace: Identifiable, Hashable {
    var name: String
    var url: URL
    var symbol: String
    var id: URL { url }
}

/// Bolton's Files as a browser: folders, quick view, and Preview's tools for pictures.
@MainActor
final class FileBrowser: ObservableObject {
    @Published var mode: FilesMode = .browse
    @Published private(set) var folder: URL?
    @Published private(set) var items: [FolderItem] = []
    @Published var selection: Set<URL> = []
    /// The item shown in the preview pane.
    @Published var focused: URL?
    /// The picture open in the editor.
    @Published var editing: URL?
    @Published var converting = false
    @Published var slideshow: [URL] = []
    @Published var slideIndex = 0
    @Published var notice: String?
    @Published var working = false
    @Published var thumbnailSize: Double = 120
    private var back: [URL] = []
    private var infoCache: [URL: ImageInfo] = [:]

    var places: [FilesPlace] {
        let manager = FileManager.default
        var list: [FilesPlace] = []
        for (directory, name, symbol) in [(FileManager.SearchPathDirectory.desktopDirectory, "Desktop", "menubar.dock.rectangle"),
                                          (.documentDirectory, "Documents", "doc"), (.downloadsDirectory, "Downloads", "arrow.down.circle"),
                                          (.picturesDirectory, "Pictures", "photo.on.rectangle")] {
            if let url = manager.urls(for: directory, in: .userDomainMask).first, manager.fileExists(atPath: url.path) {
                list.append(FilesPlace(name: name, url: url, symbol: symbol))
            }
        }
        if manager.fileExists(atPath: sampleFolder.path) { list.append(FilesPlace(name: "Sample photos", url: sampleFolder, symbol: "sparkles")) }
        return list
    }

    var sampleFolder: URL { JSONStore.folder.appendingPathComponent("Sample photos", isDirectory: true) }

    var canGoBack: Bool { !back.isEmpty }

    // MARK: Moving around

    func open(_ url: URL, remember: Bool = true) {
        if remember, let folder, folder != url { back.append(folder) }
        folder = url
        reload()
        selection = []
        focused = nil
        UserDefaults.standard.set(url.path, forKey: "files.browse.folder")
    }

    func goBack() {
        guard let previous = back.popLast() else { return }
        open(previous, remember: false)
    }

    func goUp() {
        guard let folder else { return }
        let parent = folder.deletingLastPathComponent()
        if parent != folder { open(parent) }
    }

    func reload() {
        items = folder.map { FolderListing.items(in: $0) } ?? []
        infoCache = [:]
    }

    /// The last folder, or Pictures.
    func start() {
        guard folder == nil else { return }
        if let saved = UserDefaults.standard.string(forKey: "files.browse.folder"), FileManager.default.fileExists(atPath: saved) {
            open(URL(fileURLWithPath: saved), remember: false)
        } else if let first = places.first(where: { $0.name == "Pictures" }) ?? places.first {
            open(first.url, remember: false)
        }
    }

    func select(_ item: FolderItem, extend: Bool) {
        if extend {
            if selection.contains(item.url) { selection.remove(item.url) } else { selection.insert(item.url) }
        } else {
            selection = [item.url]
        }
        focused = item.url
    }

    func activate(_ item: FolderItem) {
        if item.kind == .folder { open(item.url) } else { NSWorkspace.shared.open(item.url) }
    }

    var selectedItems: [FolderItem] { items.filter { selection.contains($0.url) } }

    var selectedImages: [URL] { selectedItems.filter { $0.kind == .image }.map(\.url) }

    // MARK: What a picture knows

    func info(_ url: URL) -> ImageInfo? {
        if let cached = infoCache[url] { return cached }
        let found = ImageInfo.read(url)
        infoCache[url] = found
        return found
    }

    /// Takes the place out of the picture itself (the pixels and everything else stay).
    func removeLocation(_ url: URL) {
        guard let data = try? Data(contentsOf: url), let cleaned = ImageMetadata.removingLocation(data) else {
            notice = "The location couldn't be taken out of \(url.lastPathComponent)."
            return
        }
        do {
            try cleaned.write(to: url, options: .atomic)
            infoCache[url] = nil
            objectWillChange.send()
            notice = "Took the location out of \(url.lastPathComponent). Safe to share."
        } catch {
            notice = "Couldn't save \(url.lastPathComponent): \(error.localizedDescription)"
        }
    }

    /// Live Text: the words in a picture, copied.
    func copyText(_ url: URL) {
        guard let image = ImageKit.load(url), let pixels = ImageKit.render(image) else { return }
        working = true
        Task { @MainActor in
            let text = await Self.recognise(pixels)
            working = false
            guard !text.isEmpty else {
                notice = "No words found in \(url.lastPathComponent)."
                return
            }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            let words = text.split(whereSeparator: \.isWhitespace).count
            notice = "Copied \(words) \(words == 1 ? "word" : "words") from \(url.lastPathComponent)."
        }
    }

    nonisolated static func recognise(_ image: CGImage) async -> String {
        await Task.detached(priority: .userInitiated) { () -> String in
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            do {
                try VNImageRequestHandler(cgImage: image).perform([request])
            } catch {
                return ""
            }
            return (request.results ?? []).sorted { $0.boundingBox.maxY > $1.boundingBox.maxY }
                .compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
        }.value
    }

    /// The subject cut out of its background, the size of the original (Vision's subject lift).
    nonisolated static func liftSubject(_ image: CGImage) async -> CIImage? {
        await Task.detached(priority: .userInitiated) { () -> CIImage? in
            let request = VNGenerateForegroundInstanceMaskRequest()
            let handler = VNImageRequestHandler(cgImage: image)
            do {
                try handler.perform([request])
                guard let observation = request.results?.first else { return nil }
                let buffer = try observation.generateMaskedImage(ofInstances: observation.allInstances, from: handler, croppedToInstancesExtent: false)
                return CIImage(cvPixelBuffer: buffer)
            } catch {
                return nil
            }
        }.value
    }

    // MARK: Converting

    func convert(_ urls: [URL], to format: ImageFormat, quality: Double, longestSide: Double?, keepLocation: Bool, into destination: URL?) {
        guard !urls.isEmpty else { return }
        converting = false
        working = true
        notice = "Converting \(urls.count) \(urls.count == 1 ? "picture" : "pictures")…"
        Task { @MainActor in
            let result = await Task.detached(priority: .userInitiated) {
                BatchConvert.convert(urls, to: format, quality: quality, longestSide: longestSide, keepLocation: keepLocation, into: destination)
            }.value
            working = false
            reload()
            selection = Set(result.written)
            focused = result.written.first
            var parts: [String] = []
            if !result.written.isEmpty {
                parts.append(format == .pdf ? "Made \(result.written[0].lastPathComponent)." : "Made \(result.written.count) \(format.title) \(result.written.count == 1 ? "file" : "files").")
            }
            if !result.failed.isEmpty { parts.append("\(result.failed.count) couldn't be read as pictures.") }
            notice = parts.joined(separator: " ")
        }
    }

    // MARK: Saving edits

    /// Writes an edited picture: over the original, or as a copy beside it. A cut-out subject keeps its transparency
    /// (as a PNG if the original was a JPEG).
    func save(_ url: URL, edits: ImageEdits, cutout: CIImage?, asCopy: Bool) {
        guard let original = cutout ?? ImageKit.load(url), let pixels = ImageKit.render(ImageKit.apply(edits, to: original)) else {
            notice = "Couldn't save \(url.lastPathComponent)."
            return
        }
        var format = ImageFormat.of(url) ?? .png
        if format == .pdf { format = .png }
        var target = url
        if cutout != nil && !format.keepsTransparency {
            format = .png
            target = BatchConvert.target(for: url, format: .png, in: url.deletingLastPathComponent(), taken: [])
        } else if asCopy {
            let stem = url.deletingPathExtension().lastPathComponent + " edited"
            target = BatchConvert.target(for: url.deletingLastPathComponent().appendingPathComponent(stem + "." + format.fileExtension), format: format,
                                         in: url.deletingLastPathComponent(), taken: [])
        }
        let metadata = ImageMetadata.properties(of: url, keepLocation: true)
        guard let data = ImageKit.encode(pixels, as: format, quality: 0.92, metadata: metadata) else {
            notice = "Couldn't save \(url.lastPathComponent)."
            return
        }
        do {
            try data.write(to: target, options: .atomic)
            editing = nil
            reload()
            selection = [target]
            focused = target
            notice = target == url ? "Saved \(url.lastPathComponent)." : "Saved \(target.lastPathComponent) beside the original."
        } catch {
            notice = "Couldn't save: \(error.localizedDescription)"
        }
    }

    // MARK: Slideshow

    func startSlideshow() {
        let pictures = FolderListing.images(items)
        guard !pictures.isEmpty else {
            notice = "There are no pictures in this folder."
            return
        }
        slideIndex = focused.flatMap { pictures.firstIndex(of: $0) } ?? 0
        slideshow = pictures
    }

    func stepSlide(_ step: Int) {
        guard !slideshow.isEmpty else { return }
        slideIndex = (slideIndex + step + slideshow.count) % slideshow.count
    }

    // MARK: From iPhone

    /// A photo or scan from Continuity Camera, kept in the folder you're in.
    func imported(_ data: Data, type: UTType) {
        guard let folder else { return }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let kind = type == .pdf ? "Scan" : "iPhone photo"
        let ext = type == .pdf ? "pdf" : (type.preferredFilenameExtension ?? "jpg")
        let url = folder.appendingPathComponent("\(kind) \(formatter.string(from: Date())).\(ext)")
        do {
            try data.write(to: url, options: .atomic)
            reload()
            selection = [url]
            focused = url
            notice = "\(kind) saved to \(folder.lastPathComponent)."
        } catch {
            notice = "Couldn't save it: \(error.localizedDescription)"
        }
    }

    // MARK: Sample photos

    /// A folder of pictures to try things on: made on this Mac, with camera details and places like real photos.
    func makeSampleFolder() {
        let folder = sampleFolder
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let pictures: [(name: String, top: (Double, Double, Double), bottom: (Double, Double, Double), sun: Bool, place: (Double, Double)?, format: ImageFormat)] = [
            ("Lake Eildon.jpg", (0.36, 0.55, 0.78), (0.86, 0.72, 0.52), true, (-37.2310, 145.9120), .jpeg),
            ("Fitzroy laneway.jpg", (0.22, 0.24, 0.30), (0.62, 0.48, 0.40), false, (-37.7983, 144.9784), .jpeg),
            ("Bells Beach.heic", (0.55, 0.72, 0.86), (0.18, 0.36, 0.48), true, (-38.3717, 144.2810), .heic),
            ("Studio desk.png", (0.92, 0.90, 0.86), (0.55, 0.50, 0.45), false, nil, .png),
        ]
        for picture in pictures {
            let url = folder.appendingPathComponent(picture.name)
            guard !FileManager.default.fileExists(atPath: url.path),
                  let image = Self.scene(top: picture.top, bottom: picture.bottom, sun: picture.sun) else { continue }
            var metadata: [CFString: Any] = [
                kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFMake: "Apple", kCGImagePropertyTIFFModel: "iPhone 15 Pro"] as [CFString: Any],
                kCGImagePropertyExifDictionary: [kCGImagePropertyExifDateTimeOriginal: "2026:10:18 07:42:10", kCGImagePropertyExifExposureTime: 1.0 / 250,
                                                 kCGImagePropertyExifFNumber: 1.78, kCGImagePropertyExifISOSpeedRatings: [64],
                                                 kCGImagePropertyExifFocalLength: 6.86] as [CFString: Any],
            ]
            if let place = picture.place {
                metadata[kCGImagePropertyGPSDictionary] = [kCGImagePropertyGPSLatitude: abs(place.0), kCGImagePropertyGPSLatitudeRef: place.0 < 0 ? "S" : "N",
                                                           kCGImagePropertyGPSLongitude: abs(place.1), kCGImagePropertyGPSLongitudeRef: place.1 < 0 ? "W" : "E"] as [CFString: Any]
            }
            if let data = ImageKit.encode(image, as: picture.format, quality: 0.88, metadata: metadata) { try? data.write(to: url, options: .atomic) }
        }
        let note = folder.appendingPathComponent("Shot list.md")
        if !FileManager.default.fileExists(atPath: note.path) {
            try? "# Shot list\n\n- Lake Eildon at sunrise\n- Fitzroy laneway, the mural\n- Bells Beach from the lookout\n".write(to: note, atomically: true, encoding: .utf8)
        }
        open(folder)
    }

    /// A simple landscape: a sky, a sun, hills.
    nonisolated static func scene(top: (Double, Double, Double), bottom: (Double, Double, Double), sun: Bool) -> CGImage? {
        let width = 1_600, height = 1_066
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: ImageKit.sRGB,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let gradient = CGGradient(colorsSpace: ImageKit.sRGB, colors: [CGColor(red: top.0, green: top.1, blue: top.2, alpha: 1),
                                                                             CGColor(red: bottom.0, green: bottom.1, blue: bottom.2, alpha: 1)] as CFArray,
                                        locations: [0, 1]) else { return nil }
        context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: height), end: CGPoint(x: 0, y: 0), options: [])
        if sun {
            context.setFillColor(CGColor(red: 1, green: 0.93, blue: 0.75, alpha: 0.9))
            context.fillEllipse(in: CGRect(x: 1_050, y: 640, width: 190, height: 190))
        }
        for (index, shade) in [0.35, 0.22, 0.12].enumerated() {
            let base = Double(index) * 120 + 120
            let path = CGMutablePath()
            path.move(to: CGPoint(x: 0, y: 0))
            path.addLine(to: CGPoint(x: 0, y: base + 160))
            path.addCurve(to: CGPoint(x: Double(width), y: base + 90), control1: CGPoint(x: 500, y: base + 330), control2: CGPoint(x: 1_000, y: base - 40))
            path.addLine(to: CGPoint(x: Double(width), y: 0))
            path.closeSubpath()
            context.addPath(path)
            context.setFillColor(CGColor(red: bottom.0 * shade * 2, green: bottom.1 * shade * 2.2, blue: bottom.2 * shade * 1.8, alpha: 1))
            context.fillPath()
        }
        return context.makeImage()
    }
}
