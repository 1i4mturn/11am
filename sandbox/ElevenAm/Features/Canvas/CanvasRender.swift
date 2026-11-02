import AppKit
import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Finds the picture for an image layer's asset id.
typealias CanvasImages = (String) -> CGImage?

/// Draws canvas documents with Core Graphics: into the editor, a PNG or JPEG, a PDF (one page per design or
/// slide, with real text) or SVG.
enum CanvasRenderer {
    // MARK: Drawing

    /// Draws a document into a context already set up with a top-left origin in document units.
    static func draw(_ document: CanvasDocument, in context: CGContext, images: CanvasImages, skipping: Set<UUID> = []) {
        context.saveGState()
        let canvas = document.size.rect.cg
        fill(document.background, path: CGPath(rect: canvas, transform: nil), rect: canvas, context: context)
        for layer in document.layers where !layer.hidden && !skipping.contains(layer.id) {
            draw(layer, in: context, images: images)
        }
        context.restoreGState()
    }

    static func draw(_ layer: CanvasLayer, in context: CGContext, images: CanvasImages) {
        let frame = layer.frame.cg
        guard frame.width > 0.5 || frame.height > 0.5 else { return }
        context.saveGState()
        context.translateBy(x: frame.midX, y: frame.midY)
        if layer.rotation != 0 { context.rotate(by: CGFloat(layer.rotation * .pi / 180)) }
        context.translateBy(x: -frame.width / 2, y: -frame.height / 2)
        let local = CGRect(origin: .zero, size: frame.size)
        context.setAlpha(CGFloat(max(0, min(1, layer.opacity))))
        if layer.shadow {
            let lift = max(3, min(frame.width, frame.height) * 0.025)
            context.setShadow(offset: CGSize(width: 0, height: -lift), blur: lift * 3, color: CGColor(gray: 0, alpha: 0.28))
        }
        switch layer.content {
        case .shape(let kind):
            drawShape(kind, layer: layer, rect: local, context: context)
        case .text(let text, let style):
            if case .solid = layer.fill { fill(layer.fill, path: roundedPath(local, layer.cornerRadius), rect: local, context: context) }
            if case .linear = layer.fill { fill(layer.fill, path: roundedPath(local, layer.cornerRadius), rect: local, context: context) }
            drawText(text, style: style, in: local, context: context)
        case .image(let asset, let fit):
            if let image = images(asset) {
                drawImage(image, fit: fit, in: local, radius: layer.cornerRadius, context: context)
            } else {
                drawPlaceholder(in: local, radius: layer.cornerRadius, context: context)
            }
            strokeIfNeeded(layer, path: roundedPath(local, layer.cornerRadius), context: context)
        case .qr(let message):
            if let code = qrImage(message) {
                if case .solid = layer.fill { fill(layer.fill, path: roundedPath(local, layer.cornerRadius), rect: local, context: context) }
                context.interpolationQuality = .none
                let side = min(local.width, local.height)
                drawImage(code, fit: .fit, in: CGRect(x: (local.width - side) / 2, y: (local.height - side) / 2, width: side, height: side), radius: 0, context: context)
            }
        }
        context.restoreGState()
    }

    static func roundedPath(_ rect: CGRect, _ radius: Double) -> CGPath {
        let r = CGFloat(max(0, min(radius, Double(min(rect.width, rect.height)) / 2)))
        return r > 0 ? CGPath(roundedRect: rect, cornerWidth: r, cornerHeight: r, transform: nil) : CGPath(rect: rect, transform: nil)
    }

    /// The outline of a shape in a box.
    static func path(_ kind: ShapeKind, in rect: CGRect, radius: Double) -> CGPath {
        switch kind {
        case .rectangle:
            return roundedPath(rect, radius)
        case .ellipse:
            return CGPath(ellipseIn: rect, transform: nil)
        case .triangle:
            let path = CGMutablePath()
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.closeSubpath()
            return path
        case .star:
            let path = CGMutablePath()
            let centre = CGPoint(x: rect.midX, y: rect.midY)
            for point in 0..<10 {
                let outer = point % 2 == 0
                let angle = -Double.pi / 2 + Double(point) * Double.pi / 5
                let rx = Double(rect.width) / 2 * (outer ? 1 : 0.42), ry = Double(rect.height) / 2 * (outer ? 1 : 0.42)
                let p = CGPoint(x: Double(centre.x) + cos(angle) * rx, y: Double(centre.y) + sin(angle) * ry)
                if point == 0 { path.move(to: p) } else { path.addLine(to: p) }
            }
            path.closeSubpath()
            return path
        case .line, .arrow:
            let path = CGMutablePath()
            path.move(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            return path
        }
    }

    private static func drawShape(_ kind: ShapeKind, layer: CanvasLayer, rect: CGRect, context: CGContext) {
        if kind == .line || kind == .arrow {
            let color = (layer.stroke ?? layer.fill.firstColor ?? .black).cg
            let width = CGFloat(max(layer.strokeWidth, 2))
            context.setStrokeColor(color)
            context.setLineWidth(width)
            context.setLineCap(.round)
            let head = kind == .arrow ? min(rect.width * 0.4, width * 4 + 8) : 0
            context.move(to: CGPoint(x: rect.minX, y: rect.midY))
            context.addLine(to: CGPoint(x: rect.maxX - head * 0.6, y: rect.midY))
            context.strokePath()
            if kind == .arrow {
                context.setFillColor(color)
                context.move(to: CGPoint(x: rect.maxX, y: rect.midY))
                context.addLine(to: CGPoint(x: rect.maxX - head, y: rect.midY - head * 0.55))
                context.addLine(to: CGPoint(x: rect.maxX - head, y: rect.midY + head * 0.55))
                context.closePath()
                context.fillPath()
            }
            return
        }
        let outline = path(kind, in: rect, radius: layer.cornerRadius)
        fill(layer.fill, path: outline, rect: rect, context: context)
        strokeIfNeeded(layer, path: outline, context: context)
    }

    private static func strokeIfNeeded(_ layer: CanvasLayer, path: CGPath, context: CGContext) {
        guard let stroke = layer.stroke, layer.strokeWidth > 0 else { return }
        context.saveGState()
        context.setShadow(offset: .zero, blur: 0, color: nil)
        context.addPath(path)
        context.setStrokeColor(stroke.cg)
        context.setLineWidth(CGFloat(layer.strokeWidth))
        context.strokePath()
        context.restoreGState()
    }

    static func fill(_ fill: CanvasFill, path: CGPath, rect: CGRect, context: CGContext) {
        switch fill {
        case .none:
            return
        case .solid(let color):
            context.addPath(path)
            context.setFillColor(color.cg)
            context.fillPath()
        case .linear(let from, let to, let angle):
            context.saveGState()
            context.addPath(path)
            context.clip()
            let radians = angle * .pi / 180
            let half = (abs(cos(radians)) * Double(rect.width) + abs(sin(radians)) * Double(rect.height)) / 2
            let centre = CGPoint(x: rect.midX, y: rect.midY)
            let start = CGPoint(x: Double(centre.x) - cos(radians) * half, y: Double(centre.y) - sin(radians) * half)
            let end = CGPoint(x: Double(centre.x) + cos(radians) * half, y: Double(centre.y) + sin(radians) * half)
            if let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [from.cg, to.cg] as CFArray, locations: [0, 1]) {
                context.drawLinearGradient(gradient, start: start, end: end, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
            }
            context.restoreGState()
        }
    }

    // MARK: Text

    static func font(_ style: TextStyle, scale: Double = 1) -> NSFont {
        let size = CGFloat(max(1, style.size * scale))
        let weight: NSFont.Weight
        let managerWeight: Int
        switch style.weight {
        case .regular: weight = .regular; managerWeight = 5
        case .medium: weight = .medium; managerWeight = 6
        case .semibold: weight = .semibold; managerWeight = 8
        case .bold: weight = .bold; managerWeight = 9
        case .heavy: weight = .heavy; managerWeight = 11
        }
        var font: NSFont
        if style.font == "System" || style.font.isEmpty {
            font = NSFont.systemFont(ofSize: size, weight: weight)
        } else {
            let traits: NSFontTraitMask = managerWeight >= 9 ? .boldFontMask : []
            font = NSFontManager.shared.font(withFamily: style.font, traits: traits, weight: managerWeight, size: size)
                ?? NSFont(name: style.font, size: size)
                ?? NSFont.systemFont(ofSize: size, weight: weight)
        }
        if style.italic { font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask) }
        return font
    }

    static func attributed(_ text: String, _ style: TextStyle, scale: Double = 1) -> NSAttributedString {
        let face = font(style, scale: scale)
        let paragraph = NSMutableParagraphStyle()
        switch style.alignment {
        case .left: paragraph.alignment = .left
        case .center: paragraph.alignment = .center
        case .right: paragraph.alignment = .right
        }
        let line = face.pointSize * CGFloat(style.lineHeight)
        paragraph.minimumLineHeight = line
        paragraph.maximumLineHeight = line
        var attributes: [NSAttributedString.Key: Any] = [
            .font: face,
            .foregroundColor: NSColor(cgColor: style.color.cg) ?? NSColor.black,
            .paragraphStyle: paragraph,
        ]
        if style.tracking != 0 { attributes[.kern] = CGFloat(style.tracking * scale) }
        if let outline = style.outline {
            attributes[.strokeColor] = NSColor(cgColor: outline.cg) ?? NSColor.black
            attributes[.strokeWidth] = -3.0
        }
        return NSAttributedString(string: style.uppercase ? text.uppercased() : text, attributes: attributes)
    }

    /// How tall text runs at a width, for laying out slides and growing text boxes.
    static func textSize(_ text: String, _ style: TextStyle, width: Double) -> CGSize {
        let string = attributed(text.isEmpty ? " " : text, style)
        let bounds = string.boundingRect(with: CGSize(width: CGFloat(max(1, width)), height: .greatestFiniteMagnitude),
                                         options: [.usesLineFragmentOrigin, .usesFontLeading])
        return CGSize(width: ceil(bounds.width), height: ceil(bounds.height))
    }

    /// The largest size (down to `minimum`) at which text fits a box.
    static func fittingSize(_ text: String, _ style: TextStyle, in box: CanvasRect, minimum: Double = 12) -> Double {
        var trial = style
        while trial.size > minimum {
            let size = textSize(text, trial, width: box.width)
            if Double(size.height) <= box.height && Double(size.width) <= box.width + 1 { break }
            trial.size = max(minimum, (trial.size * 0.92).rounded())
        }
        return trial.size
    }

    private static func drawText(_ text: String, style: TextStyle, in rect: CGRect, context: CGContext) {
        let graphics = NSGraphicsContext(cgContext: context, flipped: true)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphics
        attributed(text, style).draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading])
        NSGraphicsContext.restoreGraphicsState()
    }

    /// Where each wrapped line of text breaks, for SVG.
    static func lines(_ text: String, _ style: TextStyle, width: Double) -> [String] {
        let string = attributed(text, style)
        let setter = CTFramesetterCreateWithAttributedString(string)
        let path = CGPath(rect: CGRect(x: 0, y: 0, width: max(1, width), height: 100_000), transform: nil)
        let frame = CTFramesetterCreateFrame(setter, CFRange(location: 0, length: 0), path, nil)
        let source = string.string as NSString
        guard let lines = CTFrameGetLines(frame) as? [CTLine] else { return [string.string] }
        return lines.map { line in
            let range = CTLineGetStringRange(line)
            return source.substring(with: NSRange(location: range.location, length: range.length)).trimmingCharacters(in: .newlines)
        }
    }

    // MARK: Images

    static func drawImage(_ image: CGImage, fit: ImageFit, in rect: CGRect, radius: Double, context: CGContext) {
        let width = CGFloat(image.width), height = CGFloat(image.height)
        guard width > 0, height > 0 else { return }
        let scale = fit == .fill ? max(rect.width / width, rect.height / height) : min(rect.width / width, rect.height / height)
        let size = CGSize(width: width * scale, height: height * scale)
        let target = CGRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2, width: size.width, height: size.height)
        context.saveGState()
        context.addPath(roundedPath(rect, radius))
        context.clip()
        // Core Graphics draws images bottom-up; flip around the target so the picture is the right way up.
        context.translateBy(x: 0, y: target.maxY)
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: CGRect(x: target.minX, y: 0, width: target.width, height: target.height))
        context.restoreGState()
    }

    private static func drawPlaceholder(in rect: CGRect, radius: Double, context: CGContext) {
        let path = roundedPath(rect, radius)
        context.addPath(path)
        context.setFillColor(CGColor(gray: 0.86, alpha: 1))
        context.fillPath()
        context.setStrokeColor(CGColor(gray: 0.7, alpha: 1))
        context.setLineWidth(max(1, min(rect.width, rect.height) / 200))
        context.move(to: CGPoint(x: rect.minX, y: rect.minY))
        context.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        context.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        context.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        context.strokePath()
    }

    private static var qrCache: [String: CGImage] = [:]
    private static let lock = NSLock()

    static func qrImage(_ message: String) -> CGImage? {
        lock.lock()
        defer { lock.unlock() }
        if let cached = qrCache[message] { return cached }
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(message.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage, let image = CIContext().createCGImage(output, from: output.extent) else { return nil }
        qrCache[message] = image
        return image
    }

    // MARK: Files

    static func cgImage(_ document: CanvasDocument, scale: Double = 1, images: CanvasImages) -> CGImage? {
        let width = max(1, Int((document.size.width * scale).rounded())), height = max(1, Int((document.size.height * scale).rounded()))
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .high
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: CGFloat(scale), y: CGFloat(-scale))
        draw(document, in: context, images: images)
        return context.makeImage()
    }

    static func encode(_ image: CGImage, as type: UTType, quality: Double = 0.9) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    static func png(_ document: CanvasDocument, scale: Double = 1, images: CanvasImages) -> Data? {
        cgImage(document, scale: scale, images: images).flatMap { encode($0, as: .png) }
    }

    static func jpeg(_ document: CanvasDocument, scale: Double = 1, quality: Double = 0.9, images: CanvasImages) -> Data? {
        var flat = document
        // JPEG has no transparency: put a white sheet behind a transparent design.
        if case .none = flat.background { flat.background = .solid(.white) }
        return cgImage(flat, scale: scale, images: images).flatMap { encode($0, as: .jpeg, quality: quality) }
    }

    /// One page per document, each its own size.
    static func pdf(_ documents: [CanvasDocument], images: CanvasImages) -> Data {
        let data = NSMutableData()
        var box = documents.first?.size.rect.cg ?? CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let consumer = CGDataConsumer(data: data), let context = CGContext(consumer: consumer, mediaBox: &box, nil) else { return Data() }
        for document in documents {
            var media = document.size.rect.cg
            context.beginPage(mediaBox: &media)
            context.saveGState()
            context.translateBy(x: 0, y: media.height)
            context.scaleBy(x: 1, y: -1)
            draw(document, in: context, images: images)
            context.restoreGState()
            context.endPage()
        }
        context.closePDF()
        return data as Data
    }

    // MARK: SVG

    /// SVG with text kept as text (wrapped where the canvas wraps it) and pictures embedded.
    static func svg(_ document: CanvasDocument, imageData: (String) -> Data?) -> String {
        var defs: [String] = []
        var body: [String] = []
        var gradientCount = 0
        func number(_ value: Double) -> String {
            let rounded = (value * 100).rounded() / 100
            return rounded == rounded.rounded() ? String(Int(rounded)) : String(rounded)
        }
        func paint(_ fill: CanvasFill, _ rect: CanvasRect) -> String {
            switch fill {
            case .none: return "none"
            case .solid(let color): return color.alpha < 1 ? "\(color.hex.prefix(7))\" fill-opacity=\"\(number(color.alpha))" : color.hex
            case .linear(let from, let to, let angle):
                gradientCount += 1
                let id = "g\(gradientCount)"
                let radians = angle * .pi / 180
                let x1 = 50 - cos(radians) * 50, y1 = 50 - sin(radians) * 50, x2 = 50 + cos(radians) * 50, y2 = 50 + sin(radians) * 50
                defs.append("<linearGradient id=\"\(id)\" x1=\"\(number(x1))%\" y1=\"\(number(y1))%\" x2=\"\(number(x2))%\" y2=\"\(number(y2))%\"><stop offset=\"0\" stop-color=\"\(from.hex.prefix(7))\"/><stop offset=\"1\" stop-color=\"\(to.hex.prefix(7))\"/></linearGradient>")
                return "url(#\(id))"
            }
        }
        let size = document.size
        body.append("<rect width=\"\(number(size.width))\" height=\"\(number(size.height))\" fill=\"\(paint(document.background, size.rect))\"/>")
        for (index, layer) in document.layers.enumerated() where !layer.hidden {
            let f = layer.frame
            var attributes = ""
            if layer.rotation != 0 { attributes += " transform=\"rotate(\(number(layer.rotation)) \(number(f.midX)) \(number(f.midY)))\"" }
            if layer.opacity < 1 { attributes += " opacity=\"\(number(layer.opacity))\"" }
            var stroke = ""
            if let color = layer.stroke, layer.strokeWidth > 0 { stroke = " stroke=\"\(color.hex.prefix(7))\" stroke-width=\"\(number(layer.strokeWidth))\"" }
            var element = ""
            switch layer.content {
            case .shape(let kind):
                switch kind {
                case .rectangle:
                    let radius = min(layer.cornerRadius, min(f.width, f.height) / 2)
                    element = "<rect x=\"\(number(f.x))\" y=\"\(number(f.y))\" width=\"\(number(f.width))\" height=\"\(number(f.height))\"\(radius > 0 ? " rx=\"\(number(radius))\"" : "") fill=\"\(paint(layer.fill, f))\"\(stroke)/>"
                case .ellipse:
                    element = "<ellipse cx=\"\(number(f.midX))\" cy=\"\(number(f.midY))\" rx=\"\(number(f.width / 2))\" ry=\"\(number(f.height / 2))\" fill=\"\(paint(layer.fill, f))\"\(stroke)/>"
                case .triangle, .star:
                    let outline = path(kind, in: f.cg, radius: 0)
                    var points: [String] = []
                    outline.applyWithBlock { element in
                        if element.pointee.type != .closeSubpath {
                            let p = element.pointee.points[0]
                            points.append("\(number(Double(p.x))),\(number(Double(p.y)))")
                        }
                    }
                    element = "<polygon points=\"\(points.joined(separator: " "))\" fill=\"\(paint(layer.fill, f))\"\(stroke)/>"
                case .line, .arrow:
                    let color = (layer.stroke ?? layer.fill.firstColor ?? .black).hex.prefix(7)
                    let width = max(layer.strokeWidth, 2)
                    element = "<line x1=\"\(number(f.minX))\" y1=\"\(number(f.midY))\" x2=\"\(number(f.maxX))\" y2=\"\(number(f.midY))\" stroke=\"\(color)\" stroke-width=\"\(number(width))\" stroke-linecap=\"round\"/>"
                    if kind == .arrow {
                        let head = min(f.width * 0.4, width * 4 + 8)
                        element += "<polygon points=\"\(number(f.maxX)),\(number(f.midY)) \(number(f.maxX - head)),\(number(f.midY - head * 0.55)) \(number(f.maxX - head)),\(number(f.midY + head * 0.55))\" fill=\"\(color)\"/>"
                    }
                }
            case .text(let text, let style):
                let face = font(style)
                let anchor = style.alignment == .left ? "start" : (style.alignment == .center ? "middle" : "end")
                let x = style.alignment == .left ? f.minX : (style.alignment == .center ? f.midX : f.maxX)
                let lineHeight = Double(face.pointSize) * style.lineHeight
                let family = style.font == "System" ? "-apple-system, 'SF Pro Display', 'Helvetica Neue', Arial, sans-serif" : "'\(style.font)', sans-serif"
                let weights: [TextWeight: Int] = [.regular: 400, .medium: 500, .semibold: 600, .bold: 700, .heavy: 800]
                var spans: [String] = []
                for (row, line) in lines(text, style, width: f.width).enumerated() {
                    let y = f.minY + lineHeight * Double(row) + (lineHeight + Double(face.ascender + face.descender)) / 2
                    spans.append("<tspan x=\"\(number(x))\" y=\"\(number(y))\">\(escape(style.uppercase ? line.uppercased() : line))</tspan>")
                }
                var textAttributes = "font-family=\"\(family)\" font-size=\"\(number(style.size))\" font-weight=\"\(weights[style.weight] ?? 400)\" fill=\"\(style.color.hex.prefix(7))\" text-anchor=\"\(anchor)\""
                if style.italic { textAttributes += " font-style=\"italic\"" }
                if style.tracking != 0 { textAttributes += " letter-spacing=\"\(number(style.tracking))\"" }
                if style.color.alpha < 1 { textAttributes += " fill-opacity=\"\(number(style.color.alpha))\"" }
                if let outline = style.outline { textAttributes += " stroke=\"\(outline.hex.prefix(7))\" stroke-width=\"\(number(style.size / 24))\" paint-order=\"stroke\"" }
                var background = ""
                if layer.fill != .none {
                    background = "<rect x=\"\(number(f.x))\" y=\"\(number(f.y))\" width=\"\(number(f.width))\" height=\"\(number(f.height))\" rx=\"\(number(layer.cornerRadius))\" fill=\"\(paint(layer.fill, f))\"/>"
                }
                element = background + "<text \(textAttributes)>\(spans.joined())</text>"
            case .image(let asset, let fit):
                guard let data = imageData(asset) else { continue }
                let type = data.starts(with: [0xFF, 0xD8]) ? "jpeg" : "png"
                let clip = "c\(index)"
                defs.append("<clipPath id=\"\(clip)\"><rect x=\"\(number(f.x))\" y=\"\(number(f.y))\" width=\"\(number(f.width))\" height=\"\(number(f.height))\" rx=\"\(number(layer.cornerRadius))\"/></clipPath>")
                element = "<image x=\"\(number(f.x))\" y=\"\(number(f.y))\" width=\"\(number(f.width))\" height=\"\(number(f.height))\" preserveAspectRatio=\"xMidYMid \(fit == .fill ? "slice" : "meet")\" clip-path=\"url(#\(clip))\" href=\"data:image/\(type);base64,\(data.base64EncodedString())\"/>"
            case .qr(let message):
                guard let code = qrImage(message), let data = encode(code, as: .png) else { continue }
                let side = min(f.width, f.height)
                element = "<image x=\"\(number(f.midX - side / 2))\" y=\"\(number(f.midY - side / 2))\" width=\"\(number(side))\" height=\"\(number(side))\" style=\"image-rendering:pixelated\" href=\"data:image/png;base64,\(data.base64EncodedString())\"/>"
            }
            body.append(attributes.isEmpty ? element : "<g\(attributes)>\(element)</g>")
        }
        return """
        <svg xmlns="http://www.w3.org/2000/svg" width="\(number(size.width))" height="\(number(size.height))" viewBox="0 0 \(number(size.width)) \(number(size.height))">
        \(defs.isEmpty ? "" : "<defs>\(defs.joined())</defs>\n")\(body.joined(separator: "\n"))
        </svg>

        """
    }

    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }
}
