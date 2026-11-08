import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Bolton's Preview parts: edits for an image (crop, rotate, flip, colour, resize), formats in and out, what a photo knows
// about itself (camera, place) and how to take the place out, batch conversion, and what a folder holds.
// Core Image and ImageIO only, so it's tested on its own.

// MARK: Edits

struct ImageEdits: Codable, Equatable, Sendable {
    /// What to keep, in 0–1 of the (turned) image, top-left origin.
    var crop: CGRect?
    /// Clockwise quarter turns.
    var quarterTurns = 0
    var flipHorizontal = false
    var flipVertical = false
    /// Stops, −2 to 2.
    var exposure = 0.0
    /// 0.5 to 1.5; 1 is unchanged.
    var contrast = 1.0
    /// 0 to 2; 1 is unchanged.
    var saturation = 1.0
    /// −1 cooler to 1 warmer.
    var warmth = 0.0
    /// −1 greener to 1 more magenta.
    var tint = 0.0
    /// 0 to 1.
    var sharpness = 0.0
    /// 0 to 1.
    var sepia = 0.0
    var blackAndWhite = false
    /// The final size in pixels, if it changes.
    var size: CGSize?

    var isEmpty: Bool { self == ImageEdits() }

    /// Turned a quarter: crops are turned with the picture.
    mutating func turn(clockwise: Bool) {
        quarterTurns = ((quarterTurns + (clockwise ? 1 : -1)) % 4 + 4) % 4
        if let crop {
            self.crop = clockwise ? CGRect(x: 1 - crop.maxY, y: crop.minX, width: crop.height, height: crop.width)
                                  : CGRect(x: crop.minY, y: 1 - crop.maxX, width: crop.height, height: crop.width)
        }
        if let size { self.size = CGSize(width: size.height, height: size.width) }
    }
}

enum ImageFormat: String, CaseIterable, Identifiable, Codable, Sendable {
    case jpeg, png, heic, tiff, pdf

    var id: String { rawValue }

    var title: String {
        switch self {
        case .jpeg: return "JPEG"
        case .png: return "PNG"
        case .heic: return "HEIC"
        case .tiff: return "TIFF"
        case .pdf: return "PDF"
        }
    }

    var fileExtension: String {
        switch self {
        case .jpeg: return "jpg"
        case .png: return "png"
        case .heic: return "heic"
        case .tiff: return "tiff"
        case .pdf: return "pdf"
        }
    }

    var type: UTType {
        switch self {
        case .jpeg: return .jpeg
        case .png: return .png
        case .heic: return .heic
        case .tiff: return .tiff
        case .pdf: return .pdf
        }
    }

    /// Formats that take a quality setting.
    var hasQuality: Bool { self == .jpeg || self == .heic }

    /// Formats that keep transparency (after removing a background).
    var keepsTransparency: Bool { self == .png || self == .tiff || self == .heic }

    static func of(_ url: URL) -> ImageFormat? {
        switch url.pathExtension.lowercased() {
        case "jpg", "jpeg": return .jpeg
        case "png": return .png
        case "heic", "heif": return .heic
        case "tif", "tiff": return .tiff
        case "pdf": return .pdf
        default: return nil
        }
    }
}

enum ImageKit {
    static let context = CIContext(options: [.cacheIntermediates: false])
    static let sRGB = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

    /// An image the right way up (as its orientation tag says).
    static func load(_ url: URL) -> CIImage? {
        CIImage(contentsOf: url, options: [.applyOrientationProperty: true])
    }

    /// The edits, in order: turn and flip, crop, colour, size.
    static func apply(_ edits: ImageEdits, to source: CIImage) -> CIImage {
        var image = toOrigin(source)
        if edits.flipHorizontal || edits.flipVertical {
            image = toOrigin(image.transformed(by: CGAffineTransform(scaleX: edits.flipHorizontal ? -1 : 1, y: edits.flipVertical ? -1 : 1)))
        }
        let turns = ((edits.quarterTurns % 4) + 4) % 4
        if turns != 0 {
            // Core Image turns anticlockwise for positive angles.
            image = toOrigin(image.transformed(by: CGAffineTransform(rotationAngle: -CGFloat(turns) * .pi / 2)))
        }
        if let crop = edits.crop, crop.width > 0, crop.height > 0 {
            let width = image.extent.width, height = image.extent.height
            let rect = CGRect(x: crop.minX * width, y: (1 - crop.maxY) * height, width: crop.width * width, height: crop.height * height).integral
                .intersection(image.extent)
            if !rect.isNull, rect.width >= 1, rect.height >= 1 { image = toOrigin(image.cropped(to: rect)) }
        }
        image = colour(image, edits)
        if let size = edits.size, size.width >= 1, size.height >= 1, image.extent.width > 0, image.extent.height > 0 {
            let scale = size.height / image.extent.height
            let aspect = (size.width / image.extent.width) / scale
            let filter = CIFilter(name: "CILanczosScaleTransform")
            filter?.setValue(image, forKey: kCIInputImageKey)
            filter?.setValue(scale, forKey: kCIInputScaleKey)
            filter?.setValue(aspect, forKey: kCIInputAspectRatioKey)
            if let scaled = filter?.outputImage {
                image = toOrigin(scaled).cropped(to: CGRect(origin: .zero, size: CGSize(width: size.width.rounded(), height: size.height.rounded())))
            }
        }
        return image
    }

    /// Moved to the origin and snapped to whole pixels (a quarter turn can leave it a hair over).
    private static func toOrigin(_ image: CIImage) -> CIImage {
        let extent = image.extent
        guard extent.minX.isFinite, extent.minY.isFinite, extent.width.isFinite, extent.height.isFinite else { return image }
        let moved = extent.origin == .zero ? image : image.transformed(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY))
        return moved.cropped(to: CGRect(x: 0, y: 0, width: extent.width.rounded(), height: extent.height.rounded()))
    }

    private static func colour(_ input: CIImage, _ edits: ImageEdits) -> CIImage {
        var image = input
        let extent = input.extent
        if edits.exposure != 0 {
            image = image.applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: edits.exposure])
        }
        let saturation = edits.blackAndWhite ? 0 : edits.saturation
        if edits.contrast != 1 || saturation != 1 {
            image = image.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: saturation, kCIInputContrastKey: edits.contrast,
                                                                         kCIInputBrightnessKey: 0])
        }
        if edits.warmth != 0 || edits.tint != 0 {
            // Warmer lifts red and lowers blue; a magenta tint lowers green.
            let red = 1 + 0.12 * edits.warmth, blue = 1 - 0.12 * edits.warmth, green = 1 - 0.1 * edits.tint
            image = image.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: red, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: green, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: blue, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            ])
        }
        if edits.sepia > 0 {
            image = image.applyingFilter("CISepiaTone", parameters: [kCIInputIntensityKey: edits.sepia])
        }
        if edits.sharpness > 0 {
            image = image.applyingFilter("CISharpenLuminance", parameters: [kCIInputSharpnessKey: edits.sharpness * 2])
        }
        return image.cropped(to: extent)
    }

    /// Pixels, in sRGB with alpha.
    static func render(_ image: CIImage) -> CGImage? {
        let extent = image.extent.integral
        guard extent.width >= 1, extent.height >= 1, extent.width < 40_000, extent.height < 40_000 else { return nil }
        return context.createCGImage(image, from: extent, format: .RGBA8, colorSpace: sRGB)
    }

    /// The file's bytes in a format. Metadata (camera, place) goes along unless it's left out.
    static func encode(_ image: CGImage, as format: ImageFormat, quality: Double = 0.85, metadata: [CFString: Any]? = nil) -> Data? {
        if format == .pdf { return pdf([image]) }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, format.type.identifier as CFString, 1, nil) else { return nil }
        var properties: [CFString: Any] = metadata ?? [:]
        // The pixels are already the right way up.
        properties[kCGImagePropertyOrientation] = 1
        if format.hasQuality { properties[kCGImageDestinationLossyCompressionQuality] = max(0.05, min(1, quality)) }
        var pixels = image
        if !format.keepsTransparency, let flat = flatten(image) { pixels = flat }
        CGImageDestinationAddImage(destination, pixels, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    /// One page per image, each page the image's size.
    static func pdf(_ images: [CGImage]) -> Data? {
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData), let context = CGContext(consumer: consumer, mediaBox: nil, nil) else { return nil }
        for image in images {
            var box = CGRect(x: 0, y: 0, width: image.width, height: image.height)
            context.beginPage(mediaBox: &box)
            context.draw(image, in: box)
            context.endPage()
        }
        context.closePDF()
        return data as Data
    }

    /// On white, for formats without transparency.
    private static func flatten(_ image: CGImage) -> CGImage? {
        guard image.alphaInfo != .none, image.alphaInfo != .noneSkipLast, image.alphaInfo != .noneSkipFirst,
              let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0, space: sRGB,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return context.makeImage()
    }

    /// A size that fits inside a longest side, keeping proportions (never larger than it was).
    static func fitting(_ size: CGSize, longestSide: Double) -> CGSize {
        let longest = max(size.width, size.height)
        guard longest > longestSide, longest > 0 else { return size }
        let scale = longestSide / longest
        return CGSize(width: max(1, (size.width * scale).rounded()), height: max(1, (size.height * scale).rounded()))
    }

    /// A new width or height with the other kept in proportion.
    static func proportional(_ size: CGSize, width: Double? = nil, height: Double? = nil) -> CGSize {
        guard size.width > 0, size.height > 0 else { return size }
        if let width { return CGSize(width: width.rounded(), height: max(1, (width * size.height / size.width).rounded())) }
        if let height { return CGSize(width: max(1, (height * size.width / size.height).rounded()), height: height.rounded()) }
        return size
    }

    /// The pixel size the image shows at, the right way up.
    static func pixelSize(_ url: URL) -> CGSize? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int, let height = properties[kCGImagePropertyPixelHeight] as? Int else { return nil }
        let orientation = properties[kCGImagePropertyOrientation] as? Int ?? 1
        return orientation >= 5 ? CGSize(width: height, height: width) : CGSize(width: width, height: height)
    }
}

// MARK: What a photo knows

struct ImageInfo: Equatable, Sendable {
    var pixelWidth: Int
    var pixelHeight: Int
    var format: String
    var colourProfile: String?
    var dpi: Double?
    var camera: String?
    var lens: String?
    /// "1/120 s · f/1.8 · ISO 100 · 6.9 mm"
    var exposure: String?
    var taken: Date?
    var latitude: Double?
    var longitude: Double?
    var hasTransparency = false

    var hasLocation: Bool { latitude != nil && longitude != nil }

    var dimensions: String { "\(pixelWidth) × \(pixelHeight)" }

    var megapixels: Double { Double(pixelWidth * pixelHeight) / 1_000_000 }

    static func read(_ url: URL) -> ImageInfo? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return read(source)
    }

    static func read(data: Data) -> ImageInfo? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return read(source)
    }

    private static func read(_ source: CGImageSource) -> ImageInfo? {
        guard CGImageSourceGetCount(source) > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              var width = properties[kCGImagePropertyPixelWidth] as? Int, var height = properties[kCGImagePropertyPixelHeight] as? Int else { return nil }
        if (properties[kCGImagePropertyOrientation] as? Int ?? 1) >= 5 { swap(&width, &height) }
        let type = CGImageSourceGetType(source).map { UTType($0 as String)?.preferredFilenameExtension?.uppercased() ?? ($0 as String) } ?? ""
        var info = ImageInfo(pixelWidth: width, pixelHeight: height, format: type == "JPEG" ? "JPEG" : type)
        info.colourProfile = properties[kCGImagePropertyProfileName] as? String
        info.dpi = properties[kCGImagePropertyDPIWidth] as? Double
        info.hasTransparency = properties[kCGImagePropertyHasAlpha] as? Bool ?? false
        let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        let make = (tiff[kCGImagePropertyTIFFMake] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
        let model = (tiff[kCGImagePropertyTIFFModel] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
        let camera = model.lowercased().hasPrefix(make.lowercased()) ? model : [make, model].filter { !$0.isEmpty }.joined(separator: " ")
        info.camera = camera.isEmpty ? nil : camera
        info.lens = exif[kCGImagePropertyExifLensModel] as? String
        var parts: [String] = []
        if let time = exif[kCGImagePropertyExifExposureTime] as? Double, time > 0 {
            parts.append(time >= 1 ? "\(GridlessNumber.text(time)) s" : "1/\(Int((1 / time).rounded())) s")
        }
        if let aperture = exif[kCGImagePropertyExifFNumber] as? Double { parts.append("f/\(GridlessNumber.text(aperture))") }
        if let iso = (exif[kCGImagePropertyExifISOSpeedRatings] as? [Int])?.first { parts.append("ISO \(iso)") }
        if let focal = exif[kCGImagePropertyExifFocalLength] as? Double { parts.append("\(GridlessNumber.text(focal)) mm") }
        info.exposure = parts.isEmpty ? nil : parts.joined(separator: " · ")
        if let original = (exif[kCGImagePropertyExifDateTimeOriginal] as? String) ?? (tiff[kCGImagePropertyTIFFDateTime] as? String) {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
            info.taken = formatter.date(from: original)
        }
        if let gps = properties[kCGImagePropertyGPSDictionary] as? [CFString: Any],
           let latitude = gps[kCGImagePropertyGPSLatitude] as? Double, let longitude = gps[kCGImagePropertyGPSLongitude] as? Double {
            info.latitude = (gps[kCGImagePropertyGPSLatitudeRef] as? String)?.uppercased() == "S" ? -latitude : latitude
            info.longitude = (gps[kCGImagePropertyGPSLongitudeRef] as? String)?.uppercased() == "W" ? -longitude : longitude
        }
        return info
    }
}

/// Numbers without trailing zeros: 1.8, 2, 6.86.
enum GridlessNumber {
    static func text(_ value: Double) -> String {
        if value == value.rounded() { return String(Int(value)) }
        var text = String(format: "%.2f", value)
        while text.hasSuffix("0") { text.removeLast() }
        return text
    }
}

enum ImageMetadata {
    /// The same image with its location taken out (and nothing else changed: pixels, camera and dates stay).
    static func removingLocation(_ data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil), let type = CGImageSourceGetType(source) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, type, 1, nil) else { return nil }
        var error: Unmanaged<CFError>?
        let options: [CFString: Any] = [kCGImageMetadataShouldExcludeGPS: true]
        if CGImageDestinationCopyImageSource(destination, source, options as CFDictionary, &error) {
            return output as Data
        }
        // Formats that can't be copied without re-encoding: write the pixels again, with the other metadata.
        let rewritten = NSMutableData()
        guard let fresh = CGImageDestinationCreateWithData(rewritten, type, 1, nil),
              var properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { return nil }
        properties.removeValue(forKey: kCGImagePropertyGPSDictionary)
        CGImageDestinationAddImageFromSource(fresh, source, 0, properties as CFDictionary)
        return CGImageDestinationFinalize(fresh) ? rewritten as Data : nil
    }

    /// The metadata to carry into a converted copy: everything, or everything but the place.
    static func properties(of url: URL, keepLocation: Bool) -> [CFString: Any] {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              var properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { return [:] }
        if !keepLocation { properties.removeValue(forKey: kCGImagePropertyGPSDictionary) }
        for key in [kCGImagePropertyPixelWidth, kCGImagePropertyPixelHeight, kCGImagePropertyOrientation, kCGImagePropertyProfileName,
                    kCGImagePropertyColorModel, kCGImagePropertyDepth, kCGImagePropertyHasAlpha] { properties.removeValue(forKey: key) }
        if var tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
            tiff.removeValue(forKey: kCGImagePropertyTIFFOrientation)
            properties[kCGImagePropertyTIFFDictionary] = tiff
        }
        if var exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] {
            exif.removeValue(forKey: kCGImagePropertyExifPixelXDimension)
            exif.removeValue(forKey: kCGImagePropertyExifPixelYDimension)
            properties[kCGImagePropertyExifDictionary] = exif
        }
        return properties
    }
}

// MARK: Converting many

enum BatchConvert {
    /// A free name in the folder for a converted copy: "Beach.png", then "Beach 2.png".
    static func target(for source: URL, format: ImageFormat, in folder: URL, taken: Set<String>) -> URL {
        let stem = source.deletingPathExtension().lastPathComponent
        var name = "\(stem).\(format.fileExtension)"
        var number = 2
        while taken.contains(name.lowercased()) || FileManager.default.fileExists(atPath: folder.appendingPathComponent(name).path)
                || folder.appendingPathComponent(name).standardizedFileURL == source.standardizedFileURL {
            name = "\(stem) \(number).\(format.fileExtension)"
            number += 1
        }
        return folder.appendingPathComponent(name)
    }

    struct Result: Equatable {
        var written: [URL] = []
        var failed: [URL] = []
    }

    /// Converts each image (next to the original unless a folder is given), shrinking to a longest side if asked.
    /// PDF puts every image in one document, a page each.
    static func convert(_ sources: [URL], to format: ImageFormat, quality: Double = 0.85, longestSide: Double? = nil,
                        keepLocation: Bool = true, into folder: URL? = nil) -> Result {
        var result = Result()
        var taken = Set<String>()
        var pages: [CGImage] = []
        for source in sources {
            guard let image = ImageKit.load(source) else {
                result.failed.append(source)
                continue
            }
            var edits = ImageEdits()
            if let longestSide {
                let fitted = ImageKit.fitting(image.extent.size, longestSide: longestSide)
                if fitted != image.extent.size { edits.size = fitted }
            }
            guard let pixels = ImageKit.render(ImageKit.apply(edits, to: image)) else {
                result.failed.append(source)
                continue
            }
            if format == .pdf {
                pages.append(pixels)
                continue
            }
            let destination = folder ?? source.deletingLastPathComponent()
            let output = Self.target(for: source, format: format, in: destination, taken: taken)
            let metadata = ImageMetadata.properties(of: source, keepLocation: keepLocation)
            guard let data = ImageKit.encode(pixels, as: format, quality: quality, metadata: metadata), (try? data.write(to: output, options: .atomic)) != nil else {
                result.failed.append(source)
                continue
            }
            taken.insert(output.lastPathComponent.lowercased())
            result.written.append(output)
        }
        if format == .pdf, !pages.isEmpty, let first = sources.first {
            let destination = folder ?? first.deletingLastPathComponent()
            let name = sources.count == 1 ? first : first.deletingLastPathComponent().appendingPathComponent("Images.pdf")
            let output = Self.target(for: name, format: .pdf, in: destination, taken: taken)
            if let data = ImageKit.pdf(pages), (try? data.write(to: output, options: .atomic)) != nil {
                result.written.append(output)
            } else {
                result.failed += sources
            }
        }
        return result
    }
}

// MARK: What a folder holds

enum FileKind: String, Sendable {
    case folder, image, pdf, video, audio, text, document, spreadsheet, presentation, archive, other

    var symbol: String {
        switch self {
        case .folder: return "folder"
        case .image: return "photo"
        case .pdf: return "doc.richtext"
        case .video: return "film"
        case .audio: return "waveform"
        case .text: return "doc.plaintext"
        case .document: return "doc.text"
        case .spreadsheet: return "tablecells"
        case .presentation: return "rectangle.on.rectangle"
        case .archive: return "doc.zipper"
        case .other: return "doc"
        }
    }

    static func of(_ url: URL, isDirectory: Bool = false) -> FileKind {
        if isDirectory { return .folder }
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "docx", "doc", "pages", "rtf", "odt": return .document
        case "xlsx", "xls", "numbers", "csv", "ods": return .spreadsheet
        case "pptx", "ppt", "key", "odp": return .presentation
        case "md", "markdown", "txt", "json", "swift", "py", "js", "html", "css", "yml", "yaml", "xml", "log": return .text
        default: break
        }
        guard let type = UTType(filenameExtension: ext) else { return .other }
        if type.conforms(to: .pdf) { return .pdf }
        if type.conforms(to: .image) { return .image }
        if type.conforms(to: .movie) || type.conforms(to: .video) { return .video }
        if type.conforms(to: .audio) { return .audio }
        if type.conforms(to: .archive) { return .archive }
        if type.conforms(to: .text) { return .text }
        return .other
    }
}

struct FolderItem: Identifiable, Hashable, Sendable {
    var url: URL
    var name: String
    var kind: FileKind
    var size: Int
    var modified: Date
    var id: URL { url }
}

enum FolderListing {
    /// What's in a folder: folders first, then files, in Finder's order; hidden files left out.
    static func items(in folder: URL) -> [FolderItem] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey, .isHiddenKey, .isPackageKey]
        guard let urls = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) else { return [] }
        let items = urls.compactMap { url -> FolderItem? in
            let values = try? url.resourceValues(forKeys: Set(keys))
            if values?.isHidden == true { return nil }
            let isFolder = values?.isDirectory == true && values?.isPackage != true
            return FolderItem(url: url, name: url.lastPathComponent, kind: FileKind.of(url, isDirectory: isFolder), size: values?.fileSize ?? 0,
                              modified: values?.contentModificationDate ?? .distantPast)
        }
        return items.sorted { a, b in
            if (a.kind == .folder) != (b.kind == .folder) { return a.kind == .folder }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }

    /// The images in a listing, for a slideshow.
    static func images(_ items: [FolderItem]) -> [URL] {
        items.filter { $0.kind == .image }.map(\.url)
    }
}
