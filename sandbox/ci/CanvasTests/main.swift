import AppKit
import CoreImage
import Foundation
import PDFKit

// Checks Robert's canvas and Conner's decks: geometry, arranging, snapping, magic resize, rendering to PNG,
// PDF and SVG, QR codes, slide layouts, outlines and PowerPoint files.

var failures = 0
func check(_ condition: Bool, _ name: String) {
    print(condition ? "PASS" : "FAIL", name)
    if !condition { failures += 1 }
}

func rgba(_ image: CGImage, x: Int, y: Int) -> (Int, Int, Int, Int) {
    var pixel = [UInt8](repeating: 0, count: 4)
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let context = CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: space,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    // Move the wanted pixel (top-left origin) onto the 1×1 context.
    context.draw(image, in: CGRect(x: -x, y: -(image.height - 1 - y), width: image.width, height: image.height))
    return (Int(pixel[0]), Int(pixel[1]), Int(pixel[2]), Int(pixel[3]))
}

func near(_ a: Double, _ b: Double, _ tolerance: Double = 0.01) -> Bool { abs(a - b) <= tolerance }

// MARK: Colour

let orange = CanvasColor(hex: "#F26B3A")!
check(orange.hex == "#F26B3A" && CanvasColor(hex: "FFFFFF80")?.alpha.rounded(toPlaces: 2) == 0.5 && CanvasColor(hex: "zz") == nil, "Colours in and out of hex")
check(CanvasColor.white.luminance > 0.9 && CanvasColor.black.luminance < 0.01, "Luminance")

// MARK: Arranging

var document = CanvasDocument(name: "Test", size: CanvasSize(width: 1000, height: 800))
let a = CanvasLayer.shapeLayer(.rectangle, frame: CanvasRect(x: 100, y: 100, width: 100, height: 100), fill: .solid(.black))
let b = CanvasLayer.shapeLayer(.ellipse, frame: CanvasRect(x: 400, y: 300, width: 200, height: 100), fill: .solid(orange))
let c = CanvasLayer.shapeLayer(.star, frame: CanvasRect(x: 800, y: 500, width: 100, height: 100), fill: .solid(.black))
document.layers = [a, b, c]

var aligned = document
CanvasEdit.align(&aligned, [a.id, b.id], to: .left)
check(aligned.layer(b.id)?.frame.x == 100 && aligned.layer(a.id)?.frame.x == 100, "Align left lines two layers up with each other")
var centred = document
CanvasEdit.align(&centred, [b.id], to: .centerX)
CanvasEdit.align(&centred, [b.id], to: .centerY)
check(centred.layer(b.id)?.frame.midX == 500 && centred.layer(b.id)?.frame.midY == 400, "One layer aligns to the canvas")

var spread = document
spread.layers[1].frame.x = 250
CanvasEdit.distribute(&spread, [a.id, b.id, c.id], horizontally: true)
let gap1 = spread.layer(b.id)!.frame.minX - spread.layer(a.id)!.frame.maxX
let gap2 = spread.layer(c.id)!.frame.minX - spread.layer(b.id)!.frame.maxX
check(near(gap1, gap2) && near(gap1, 200), "Distribute leaves equal gaps (\(gap1), \(gap2))")

var ordered = document
CanvasEdit.reorder(&ordered, [a.id], .front)
check(ordered.layers.last?.id == a.id, "Bring to front")
CanvasEdit.reorder(&ordered, [a.id], .back)
check(ordered.layers.first?.id == a.id, "Send to back")
CanvasEdit.reorder(&ordered, [a.id], .forward)
check(ordered.layers.map(\.id) == [b.id, a.id, c.id], "Bring forward one step")
CanvasEdit.reorder(&ordered, [c.id], .backward)
check(ordered.layers.map(\.id) == [b.id, c.id, a.id], "Send backward one step")

var grouped = document
let group = CanvasEdit.group(&grouped, [a.id, c.id])
check(group != nil && grouped.expand([a.id]) == [a.id, c.id], "Picking one member of a group picks the group")
CanvasEdit.move(&grouped, grouped.expand([a.id]), dx: 10, dy: 0)
check(grouped.layer(c.id)?.frame.x == 810 && grouped.layer(b.id)?.frame.x == 400, "A group moves together")
CanvasEdit.ungroup(&grouped, [a.id])
check(grouped.expand([a.id]) == [a.id], "Ungroup")

var copied = document
let copies = CanvasEdit.duplicate(&copied, [b.id])
check(copies.count == 1 && copied.layers.count == 4 && copied.layers.last?.frame.x == 424 && !copies.contains(b.id), "Duplicate nudges a copy")
CanvasEdit.delete(&copied, copies)
check(copied.layers.count == 3, "Delete")

// MARK: Hit testing and snapping

var rotated = CanvasLayer.shapeLayer(.rectangle, frame: CanvasRect(x: 400, y: 100, width: 400, height: 40), fill: .solid(.black))
rotated.rotation = 90
var hitDocument = CanvasDocument(name: "Hit", size: CanvasSize(width: 1200, height: 800), layers: [rotated])
check(CanvasGeometry.hit(CGPoint(x: 600, y: 270), in: hitDocument) == rotated.id && CanvasGeometry.hit(CGPoint(x: 450, y: 120), in: hitDocument) == nil,
      "Hit testing follows rotation")
let box = CanvasGeometry.boundingBox(rotated)
check(near(box.width, 40) && near(box.height, 400), "A rotated layer's box")
hitDocument.layers.append(.shapeLayer(.rectangle, frame: CanvasRect(x: 0, y: 0, width: 50, height: 50), fill: .solid(.white)))
check(CanvasGeometry.inside(CanvasRect(x: -10, y: -10, width: 100, height: 100), in: hitDocument).count == 1, "Marquee selection")

let snapped = CanvasSnap.snap(CanvasRect(x: 447, y: 10, width: 100, height: 50), to: [CanvasRect(x: 0, y: 302, width: 10, height: 10)],
                              canvas: CanvasSize(width: 1000, height: 800), threshold: 6)
check(snapped.dx == 3 && snapped.guides.contains(SnapGuide(axis: .vertical, position: 500)), "Snaps the centre to the canvas centre")
let edge = CanvasSnap.snap(CanvasRect(x: 100, y: 248, width: 100, height: 50), to: [CanvasRect(x: 600, y: 302, width: 10, height: 10)],
                           canvas: CanvasSize(width: 1000, height: 800), threshold: 6)
check(edge.dy == 4 && edge.guides.contains(SnapGuide(axis: .horizontal, position: 302)), "Snaps an edge to another layer's edge")
let far = CanvasSnap.snap(CanvasRect(x: 120, y: 130, width: 100, height: 50), to: [], canvas: CanvasSize(width: 1000, height: 800), threshold: 6)
check(far.dx == 0 && far.dy == 0 && far.guides.isEmpty, "Nothing snaps when nothing is close")

// MARK: Magic resize

var post = CanvasDocument(name: "Post", size: CanvasSize(width: 1080, height: 1080))
let backdrop = CanvasLayer.shapeLayer(.rectangle, frame: CanvasRect(x: 0, y: 0, width: 1080, height: 1080), fill: .solid(orange), role: "background")
var headlineStyle = TextStyle()
headlineStyle.size = 96
headlineStyle.alignment = .center
let headline = CanvasLayer.textLayer("We closed our first pilot", headlineStyle, frame: CanvasRect(x: 140, y: 440, width: 800, height: 200), role: "title")
let logo = CanvasLayer.shapeLayer(.ellipse, frame: CanvasRect(x: 60, y: 940, width: 80, height: 80), fill: .solid(.white), role: "logo")
post.layers = [backdrop, headline, logo]
let story = CanvasEdit.resized(post, to: CanvasSize(width: 1080, height: 1920))
check(story.layers[0].frame == CanvasRect(x: 0, y: 0, width: 1080, height: 1920), "Magic resize: the background covers the new size")
check(near(story.layers[1].frame.midX, 540) && near(story.layers[1].frame.midY, 960) && story.layers[1].textStyle?.size == 96,
      "…the centred headline stays centred")
check(near(story.layers[2].frame.minX, 60) && near(story.layers[2].frame.maxY, 1920 - 60), "…and the corner logo stays in its corner")
let banner = CanvasEdit.resized(post, to: CanvasSize(width: 1200, height: 627))
check(near(banner.layers[1].textStyle?.size ?? 0, 55.7, 0.2) && near(banner.layers[1].frame.midX, 600), "…text scales down for a wide banner")

// MARK: Rendering

let images: CanvasImages = { _ in nil }
let png = CanvasRenderer.cgImage(document, scale: 1, images: images)!
check(png.width == 1000 && png.height == 800, "Renders at the document's size")
let inside = rgba(png, x: 150, y: 150), outside = rgba(png, x: 20, y: 20), oval = rgba(png, x: 500, y: 350)
check(inside.0 < 10 && outside.0 > 245 && oval.0 > 230 && oval.1 > 90 && oval.1 < 125, "Shapes land where they should, in their colours (\(oval))")
let retina = CanvasRenderer.cgImage(document, scale: 2, images: images)!
check(retina.width == 2000 && rgba(retina, x: 300, y: 300).0 < 10, "Renders at 2×")

// An image drawn the right way up: red on top, blue below.
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let source = CGContext(data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
source.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1))
source.fill(CGRect(x: 0, y: 0, width: 2, height: 1))
source.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
source.fill(CGRect(x: 0, y: 1, width: 2, height: 1))
let picture = source.makeImage()!
var withPicture = CanvasDocument(name: "Picture", size: CanvasSize(width: 200, height: 200))
withPicture.layers = [CanvasLayer(name: "Photo", content: .image("p", .fill), frame: CanvasRect(x: 0, y: 0, width: 200, height: 200))]
let drawn = CanvasRenderer.cgImage(withPicture, images: { _ in picture })!
check(rgba(drawn, x: 100, y: 20).0 > 200 && rgba(drawn, x: 100, y: 180).2 > 200, "Pictures are drawn the right way up")

var textDocument = CanvasDocument(name: "Text", size: CanvasSize(width: 800, height: 400))
var bigText = TextStyle()
bigText.size = 120
bigText.weight = .heavy
textDocument.layers = [.textLayer("Hello", bigText, frame: CanvasRect(x: 40, y: 40, width: 720, height: 200))]
let textImage = CanvasRenderer.cgImage(textDocument, images: images)!
var dark = 0
for x in stride(from: 40, to: 500, by: 4) { for y in stride(from: 40, to: 200, by: 4) where rgba(textImage, x: x, y: y).0 < 80 { dark += 1 } }
check(dark > 100, "Text is drawn (\(dark) dark samples)")
let measured = CanvasRenderer.textSize("Hello world, this wraps onto more lines", bigText, width: 400)
check(measured.height > 250 && measured.width <= 401, "Text measures and wraps (\(measured))")
let fitted = CanvasRenderer.fittingSize("A very long headline that will not fit at this size", bigText, in: CanvasRect(x: 0, y: 0, width: 600, height: 200))
check(fitted < 120 && fitted >= 12, "Long text shrinks to fit its box (\(fitted))")

let pdfData = CanvasRenderer.pdf([textDocument, document, post], images: images)
let pdf = PDFDocument(data: pdfData)
check(pdf?.pageCount == 3 && pdf?.page(at: 0)?.bounds(for: .mediaBox).size == CGSize(width: 800, height: 400)
      && pdf?.page(at: 2)?.bounds(for: .mediaBox).size == CGSize(width: 1080, height: 1080), "PDF: one page per design, each its own size")
check(pdf?.string?.contains("Hello") == true && pdf?.string?.contains("pilot") == true, "PDF: text stays text")

let svg = CanvasRenderer.svg(post, imageData: { _ in nil })
let svgXML = try? XMLDocument(xmlString: svg)
check(svgXML != nil && svg.contains("<ellipse") && svg.contains("pilot") && svg.contains("text-anchor=\"middle\""), "SVG is valid XML with shapes and text")

let qr = CanvasRenderer.qrImage("https://11am.app/pilot")
let detector = CIDetector(ofType: CIDetectorTypeQRCode, context: nil, options: [CIDetectorAccuracy: CIDetectorAccuracyHigh])
var qrDocument = CanvasDocument(name: "QR", size: CanvasSize(width: 400, height: 400))
qrDocument.layers = [CanvasLayer(name: "QR", content: .qr("https://11am.app/pilot"), frame: CanvasRect(x: 50, y: 50, width: 300, height: 300))]
let qrRender = CanvasRenderer.cgImage(qrDocument, images: images)!
let decoded = detector?.features(in: CIImage(cgImage: qrRender)).compactMap { ($0 as? CIQRCodeFeature)?.messageString }.first
check(qr != nil && decoded == "https://11am.app/pilot", "QR codes scan (\(decoded ?? "nothing"))")

let pngData = CanvasRenderer.png(post, images: images)
let jpegData = CanvasRenderer.jpeg(post, images: images)
check(pngData.map { $0.starts(with: [0x89, 0x50, 0x4E, 0x47]) } == true && jpegData.map { $0.starts(with: [0xFF, 0xD8]) } == true, "PNG and JPEG files")

let codable = try? JSONDecoder().decode(CanvasDocument.self, from: JSONEncoder().encode(post))
check(codable == post, "Designs save and load as JSON")

// MARK: Decks

let theme = DeckTheme.paper
for layout in SlideLayout.allCases {
    var content = SlideContent()
    content.title = "Revenue doubled in a quarter"
    content.subtitle = "Q3 2026"
    content.bullets = ["Acme — Head of ops", "Bluegum — CFO", "Kestrel — Founder"]
    content.secondary = ["One", "Two"]
    content.number = "$1.2m"
    content.quote = "It saved us a day a week"
    content.attribution = "Priya, Acme"
    content.chart = [ChartPoint(label: "Q1", value: 120), ChartPoint(label: "Q2", value: 180), ChartPoint(label: "Q3", value: 340)]
    content.table = [["Plan", "Price"], ["Solo", "$12"], ["Team", "$40"]]
    let slide = Slide(layout: layout, content: content, theme: theme)
    let inBounds = slide.canvas.layers.allSatisfy { $0.frame.minX >= -1 && $0.frame.maxX <= 1921 && $0.frame.minY >= -1 && $0.frame.maxY <= 1081 }
    check(!slide.canvas.layers.isEmpty && inBounds && slide.canvas.size == SlideDeck.size, "Layout: \(layout.title) (\(slide.canvas.layers.count) layers, on the slide)")
}
let chartSlide = Slide(layout: .chart, content: SlideContent(title: "Growth", chart: [ChartPoint(label: "Jan", value: 10), ChartPoint(label: "Feb", value: 20)]), theme: theme)
let bars = chartSlide.canvas.layers.filter { $0.role == "bar" }
check(bars.count == 2 && near(bars[1].frame.height, bars[0].frame.height * 2, 1), "Chart bars are to scale")
check(ChartPoint.format(1_200_000) == "1.2m" && ChartPoint.format(48_000) == "48k" && ChartPoint.format(3.5) == "3.5" && ChartPoint.format(120) == "120", "Chart labels")

let outline = """
# 11am
Software you own, on the Mac you have

## The problem
- Eleven subscriptions
- None of them talk to each other
- Your data is everywhere
Notes: Start with the bill.

## $1.2m ARR
Up from $400k a year ago

> It saved us a day a week — Priya, Acme

## Revenue by quarter
- Q1: 120
- Q2: 180
- Q3: 340

## Pricing
| Plan | Price |
| --- | --- |
| Solo | $12 |
| Team | $40 |

## The plan
- Nov: Mail and Calendar
- Dec: Documents and Sheets
- Jan: Design and Decks

## Thank you
"""
let slides = DeckOutline.slides(from: outline, theme: theme)
check(slides.map(\.layout) == [.title, .bullets, .bigNumber, .quote, .chart, .table, .timeline, .closing],
      "Outline to slides (\(slides.map(\.layout.rawValue)))")
check(slides[1].notes == "Start with the bill." && slides[2].content.number == "$1.2m" && slides[2].content.title == "ARR" && slides[3].content.attribution == "Priya, Acme"
      && slides[4].content.chart.count == 3 && slides[5].content.table.count == 3, "…with notes, numbers, quotes, charts and tables")

var deck = SlideDeck(name: "Pitch", theme: theme, slides: slides)
deck.slides[1].customised = true
deck.slides[1].canvas.layers[0].frame.x = 300
deck.apply(.ink)
check(deck.slides[0].canvas.background == .solid(DeckTheme.ink.background) && deck.slides[1].canvas.layers[0].frame.x == 300
      && deck.slides[1].canvas.background == .solid(DeckTheme.ink.background), "A new theme relays untouched slides and recolours edited ones")

// MARK: PowerPoint

deck.slides[3].hidden = true
let pptx = PPTXWriter.data(deck, imageData: { _ in nil })
let folder = FileManager.default.temporaryDirectory.appendingPathComponent("canvas-tests-\(UUID().uuidString)")
try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
let file = folder.appendingPathComponent("deck.pptx")
try? pptx.write(to: file)
func part(_ name: String) -> Data? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
    process.arguments = ["-p", file.path, name]
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = Pipe()
    try? process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return process.terminationStatus == 0 ? data : nil
}
let listing: String = {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
    process.arguments = ["-l", file.path]
    let pipe = Pipe()
    process.standardOutput = pipe
    try? process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return String(decoding: data, as: UTF8.self)
}()
check(listing.contains("ppt/slides/slide7.xml") && !listing.contains("ppt/slides/slide8.xml"), "PowerPoint: one slide per visible slide")
var wellFormed = true
for name in ["[Content_Types].xml", "_rels/.rels", "ppt/presentation.xml", "ppt/_rels/presentation.xml.rels", "ppt/slideMasters/slideMaster1.xml",
             "ppt/slideLayouts/slideLayout1.xml", "ppt/theme/theme1.xml", "ppt/slides/slide1.xml", "ppt/slides/slide4.xml", "ppt/slides/_rels/slide1.xml.rels",
             "docProps/core.xml", "docProps/app.xml"] {
    guard let data = part(name), (try? XMLDocument(data: data)) != nil else {
        print("  not well-formed: \(name)")
        wellFormed = false
        continue
    }
}
check(wellFormed, "PowerPoint: every part is well-formed XML")
let slideXML = part("ppt/slides/slide1.xml").map { String(decoding: $0, as: UTF8.self) } ?? ""
check(slideXML.contains("<a:t>11am</a:t>") && slideXML.contains("sldSz") == false && part("ppt/presentation.xml").map { String(decoding: $0, as: UTF8.self).contains("cx=\"12192000\" cy=\"6858000\"") } == true,
      "PowerPoint: widescreen, with the slide's text as text")
let chartXML = part("ppt/slides/slide4.xml").map { String(decoding: $0, as: UTF8.self) } ?? ""
check(chartXML.contains("prst=\"roundRect\"") && chartXML.contains("<a:t>Q3</a:t>"), "PowerPoint: chart bars as shapes")

print(failures == 0 ? "ALL PASSED" : "\(failures) FAILED")
exit(failures == 0 ? 0 : 1)

extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let factor = pow(10, Double(places))
        return (self * factor).rounded() / factor
    }
}
