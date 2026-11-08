import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers

// Checks Bolton's Preview parts: edits (turn, flip, crop, colour, size), formats out, what a photo knows and taking its
// place out, batch conversion, orientation, and what a folder holds. Run from an empty folder.

var failures = 0
func check(_ condition: Bool, _ name: String) {
    print(condition ? "PASS" : "FAIL", name)
    if !condition { failures += 1 }
}

let folder = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("images", isDirectory: true)
try? FileManager.default.removeItem(at: folder)
try! FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

func makeImage(_ width: Int, _ height: Int, _ draw: (CGContext) -> Void) -> CGImage {
    let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: sRGB,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    draw(context)
    return context.makeImage()!
}

/// Red on the left, blue on the right.
func halves(_ width: Int = 400, _ height: Int = 300) -> CGImage {
    makeImage(width, height) { context in
        context.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width / 2, height: height))
        context.setFillColor(red: 0, green: 0, blue: 1, alpha: 1)
        context.fill(CGRect(x: width / 2, y: 0, width: width - width / 2, height: height))
    }
}

/// Top-left origin.
func pixel(_ image: CGImage, _ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int) {
    let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4, space: sRGB,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    let data = context.data!.assumingMemoryBound(to: UInt8.self)
    let offset = (y * image.width + x) * 4
    return (Int(data[offset]), Int(data[offset + 1]), Int(data[offset + 2]))
}

func isRed(_ p: (r: Int, g: Int, b: Int)) -> Bool { p.r > 200 && p.g < 60 && p.b < 60 }
func isBlue(_ p: (r: Int, g: Int, b: Int)) -> Bool { p.b > 200 && p.r < 60 && p.g < 60 }

func write(_ image: CGImage, _ name: String, _ type: UTType, _ properties: [CFString: Any] = [:]) -> URL {
    let url = folder.appendingPathComponent(name)
    let destination = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, properties as CFDictionary)
    CGImageDestinationFinalize(destination)
    return url
}

let photo: [CFString: Any] = [
    kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFMake: "Apple", kCGImagePropertyTIFFModel: "iPhone 15 Pro"] as [CFString: Any],
    kCGImagePropertyExifDictionary: [kCGImagePropertyExifDateTimeOriginal: "2026:11:03 10:15:00", kCGImagePropertyExifExposureTime: 1.0 / 120,
                                     kCGImagePropertyExifFNumber: 1.8, kCGImagePropertyExifISOSpeedRatings: [100], kCGImagePropertyExifFocalLength: 6.86,
                                     kCGImagePropertyExifLensModel: "iPhone 15 Pro back camera"] as [CFString: Any],
    kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 37.8136, kCGImagePropertyGPSLatitudeRef: "S",
                                    kCGImagePropertyGPSLongitude: 144.9631, kCGImagePropertyGPSLongitudeRef: "E"] as [CFString: Any],
]

// MARK: What a photo knows

let jpegURL = write(halves(), "Fitzroy.jpg", .jpeg, photo)
let info = ImageInfo.read(jpegURL)
check(info?.dimensions == "400 × 300" && info?.format == "JPEG" && info?.camera == "Apple iPhone 15 Pro" && info?.lens == "iPhone 15 Pro back camera",
      "Info: size, format, camera and lens (\(String(describing: info)))")
check(info?.exposure == "1/120 s · f/1.8 · ISO 100 · 6.86 mm", "Info: exposure in a line (\(info?.exposure ?? "none"))")
let takenParts = info?.taken.map { Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: $0) }
check(takenParts?.year == 2026 && takenParts?.month == 11 && takenParts?.day == 3 && takenParts?.hour == 10 && takenParts?.minute == 15, "Info: when it was taken")
check(info.map { $0.hasLocation && abs(($0.latitude ?? 0) + 37.8136) < 0.0001 && abs(($0.longitude ?? 0) - 144.9631) < 0.0001 } == true,
      "Info: where, south of the equator")
let jpegData = try! Data(contentsOf: jpegURL)
let placeless = ImageMetadata.removingLocation(jpegData)
let placelessInfo = placeless.flatMap { ImageInfo.read(data: $0) }
check(placelessInfo?.hasLocation == false && placelessInfo?.camera == "Apple iPhone 15 Pro" && placelessInfo?.dimensions == "400 × 300"
      && placelessInfo?.taken == info?.taken, "Remove location: the place goes, the camera and date stay")
check(GridlessNumber.text(1.8) == "1.8" && GridlessNumber.text(2) == "2" && GridlessNumber.text(6.86) == "6.86", "Numbers without trailing zeros")

// MARK: Edits

let pngURL = write(halves(), "Halves.png", .png)
let source = ImageKit.load(pngURL)!
func rendered(_ edits: ImageEdits, _ image: CIImage = source) -> CGImage { ImageKit.render(ImageKit.apply(edits, to: image))! }
var turned = ImageEdits()
turned.turn(clockwise: true)
let turnedImage = rendered(turned)
check(turnedImage.width == 300 && turnedImage.height == 400 && isRed(pixel(turnedImage, 150, 20)) && isBlue(pixel(turnedImage, 150, 380)),
      "Turn right: the left side is on top (\(turnedImage.width)×\(turnedImage.height), \(pixel(turnedImage, 150, 20)))")
var anticlockwise = ImageEdits()
anticlockwise.turn(clockwise: false)
let leftImage = rendered(anticlockwise)
check(leftImage.width == 300 && isBlue(pixel(leftImage, 150, 20)) && isRed(pixel(leftImage, 150, 380)), "Turn left: the right side is on top")
var flipped = ImageEdits()
flipped.flipHorizontal = true
let flippedImage = rendered(flipped)
check(isBlue(pixel(flippedImage, 20, 150)) && isRed(pixel(flippedImage, 380, 150)), "Flip: left and right swap")
var cropped = ImageEdits()
cropped.crop = CGRect(x: 0, y: 0, width: 0.5, height: 1)
let croppedImage = rendered(cropped)
check(croppedImage.width == 200 && croppedImage.height == 300 && isRed(pixel(croppedImage, 5, 5)) && isRed(pixel(croppedImage, 194, 294)), "Crop: the left half")
cropped.turn(clockwise: true)
let croppedTurned = rendered(cropped)
check(cropped.crop == CGRect(x: 0, y: 0, width: 1, height: 0.5) && croppedTurned.width == 300 && croppedTurned.height == 200 && isRed(pixel(croppedTurned, 150, 100)),
      "A crop turns with the picture (\(String(describing: cropped.crop)))")
var resized = ImageEdits()
resized.size = ImageKit.proportional(CGSize(width: 400, height: 300), width: 200)
let resizedImage = rendered(resized)
check(resized.size == CGSize(width: 200, height: 150) && resizedImage.width == 200 && resizedImage.height == 150 && isRed(pixel(resizedImage, 20, 75)),
      "Resize keeping proportions")
check(ImageKit.fitting(CGSize(width: 4000, height: 3000), longestSide: 1000) == CGSize(width: 1000, height: 750)
      && ImageKit.fitting(CGSize(width: 400, height: 300), longestSide: 1000) == CGSize(width: 400, height: 300)
      && ImageKit.proportional(CGSize(width: 400, height: 300), height: 600) == CGSize(width: 800, height: 600), "Fitting and proportions")

let grey = ImageKit.load(write(makeImage(64, 64) { context in
    context.setFillColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
}, "Grey.png", .png))!
let plainGrey = pixel(rendered(ImageEdits(), grey), 32, 32)
var brighter = ImageEdits()
brighter.exposure = 1
var warmer = ImageEdits()
warmer.warmth = 1
var mono = ImageEdits()
mono.blackAndWhite = true
let brightPixel = pixel(rendered(brighter, grey), 32, 32), warmPixel = pixel(rendered(warmer, grey), 32, 32), monoPixel = pixel(rendered(mono), 20, 150)
check(brightPixel.r > plainGrey.r + 30, "Exposure: a stop brighter (\(plainGrey.r) → \(brightPixel.r))")
check(warmPixel.r > warmPixel.b + 10, "Warmth: more red than blue (\(warmPixel))")
check(abs(monoPixel.r - monoPixel.g) < 4 && abs(monoPixel.g - monoPixel.b) < 4 && monoPixel.r > 20, "Black and white: red becomes a grey (\(monoPixel))")
check(ImageEdits().isEmpty && !brighter.isEmpty, "No edits is no edits")

// MARK: Formats

let halvesImage = halves()
func header(_ data: Data?, _ count: Int = 4) -> [UInt8] { data.map { Array($0.prefix(count)) } ?? [] }
let tiffHeaders: [[UInt8]] = [[0x49, 0x49, 0x2A, 0x00], [0x4D, 0x4D, 0x00, 0x2A]]
check(header(ImageKit.encode(halvesImage, as: .jpeg), 2) == [0xFF, 0xD8] && header(ImageKit.encode(halvesImage, as: .png)) == [0x89, 0x50, 0x4E, 0x47]
      && tiffHeaders.contains(header(ImageKit.encode(halvesImage, as: .tiff)))
      && header(ImageKit.encode(halvesImage, as: .pdf)) == Array("%PDF".utf8), "Formats: JPEG, PNG, TIFF and PDF")
let heic = ImageKit.encode(halvesImage, as: .heic)
let heicType = heic.flatMap { CGImageSourceCreateWithData($0 as CFData, nil) }.flatMap { CGImageSourceGetType($0) }.map { $0 as String }
check(heicType == "public.heic", "Formats: HEIC (\(heicType ?? "none"))")
var seed: UInt64 = 42
let noisy = makeImage(300, 300) { context in
    for x in stride(from: 0, to: 300, by: 6) {
        for y in stride(from: 0, to: 300, by: 6) {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            let value = Double(seed >> 40 & 0xFF) / 255
            context.setFillColor(red: value, green: 1 - value, blue: value * 0.5, alpha: 1)
            context.fill(CGRect(x: x, y: y, width: 6, height: 6))
        }
    }
}
let small = ImageKit.encode(noisy, as: .jpeg, quality: 0.1)?.count ?? 0, large = ImageKit.encode(noisy, as: .jpeg, quality: 0.95)?.count ?? 0
check(small > 0 && small < large, "Quality: lower is smaller (\(small) < \(large))")
let seeThrough = makeImage(100, 100) { context in
    context.setFillColor(red: 0, green: 0, blue: 0, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: 50, height: 100))
}
let flatJPEG = ImageKit.encode(seeThrough, as: .jpeg).flatMap { CGImageSourceCreateWithData($0 as CFData, nil) }.flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) }
check(flatJPEG.map { pixel($0, 80, 50).r > 240 && pixel($0, 20, 50).r < 20 } == true, "JPEG: see-through parts go white")

// MARK: Orientation

let sideways = write(halves(), "Sideways.jpg", .jpeg, [kCGImagePropertyOrientation: 6])
check(ImageInfo.read(sideways)?.dimensions == "300 × 400" && ImageKit.pixelSize(sideways) == CGSize(width: 300, height: 400)
      && ImageKit.load(sideways)?.extent.size == CGSize(width: 300, height: 400), "Orientation: a sideways photo shows upright")

// MARK: Converting many

let beach = write(halves(1200, 800), "Beach.png", .png)
let forest = write(halves(800, 1200), "Forest.png", .png)
let notes = folder.appendingPathComponent("notes.txt")
try? "not a picture".write(to: notes, atomically: true, encoding: .utf8)
let out = folder.appendingPathComponent("out", isDirectory: true)
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
let first = BatchConvert.convert([beach, forest, notes], to: .jpeg, longestSide: 600, into: out)
check(first.written.map(\.lastPathComponent) == ["Beach.jpg", "Forest.jpg"] && first.failed == [notes]
      && ImageInfo.read(first.written[0])?.dimensions == "600 × 400" && ImageInfo.read(first.written[1])?.dimensions == "400 × 600",
      "Convert: two JPEGs, shrunk to fit 600, and the text file left alone (\(first.written.map(\.lastPathComponent)))")
let second = BatchConvert.convert([beach], to: .jpeg, into: out)
check(second.written.map(\.lastPathComponent) == ["Beach 2.jpg"] && ImageInfo.read(second.written[0])?.dimensions == "1200 × 800", "Convert: never over the top of a file")
let kept = BatchConvert.convert([jpegURL], to: .jpeg, keepLocation: true, into: out).written.first.flatMap(ImageInfo.read)
let dropped = BatchConvert.convert([jpegURL], to: .heic, keepLocation: false, into: out).written.first.flatMap(ImageInfo.read)
check(kept?.hasLocation == true && kept?.camera == "Apple iPhone 15 Pro" && dropped?.hasLocation == false && dropped?.dimensions == "400 × 300",
      "Convert: the place kept, or taken out")
let upright = BatchConvert.convert([sideways], to: .png, into: out).written.first
let uprightImage = upright.flatMap { ImageKit.load($0) }.flatMap { ImageKit.render($0) }
check(upright.flatMap(ImageInfo.read)?.dimensions == "300 × 400" && uprightImage.map { isRed(pixel($0, 150, 20)) } == true, "Convert: a sideways photo comes out upright")
let combined = BatchConvert.convert([beach, forest], to: .pdf, into: out)
check(combined.written.map(\.lastPathComponent) == ["Images.pdf"] && combined.written.first.flatMap { PDFDocument(url: $0) }?.pageCount == 2,
      "Convert: several pictures into one PDF, a page each")
check(BatchConvert.convert([beach], to: .pdf, into: out).written.map(\.lastPathComponent) == ["Beach.pdf"], "Convert: one picture is one PDF named for it")

// MARK: What a folder holds

let listing = folder.appendingPathComponent("listing", isDirectory: true)
try? FileManager.default.createDirectory(at: listing.appendingPathComponent("Albums", isDirectory: true), withIntermediateDirectories: true)
for name in ["b.png", "a.md", "C.pdf", ".hidden", "report.docx", "song.mp3", "clip.mov", "data.xlsx"] {
    FileManager.default.createFile(atPath: listing.appendingPathComponent(name).path, contents: Data("x".utf8))
}
let items = FolderListing.items(in: listing)
check(items.map(\.name) == ["Albums", "a.md", "b.png", "C.pdf", "clip.mov", "data.xlsx", "report.docx", "song.mp3"], "Listing: folders first, then by name (\(items.map(\.name)))")
check(items.map(\.kind) == [.folder, .text, .image, .pdf, .video, .spreadsheet, .document, .audio], "Listing: what each one is (\(items.map(\.kind.rawValue)))")
check(FolderListing.images(items).map(\.lastPathComponent) == ["b.png"] && FileKind.of(URL(fileURLWithPath: "/x/Photo.HEIC")) == .image
      && FileKind.of(URL(fileURLWithPath: "/x/a.zip")) == .archive, "Kinds: pictures for a slideshow, HEIC, archives")
check(ImageFormat.of(URL(fileURLWithPath: "a.JPEG")) == .jpeg && ImageFormat.of(URL(fileURLWithPath: "a.tif")) == .tiff && ImageFormat.of(URL(fileURLWithPath: "a.gif")) == nil,
      "Formats by name")

print(failures == 0 ? "ALL PASSED" : "\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
