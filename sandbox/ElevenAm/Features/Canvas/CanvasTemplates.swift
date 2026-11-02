import Foundation

/// Starting points for designs, laid out for any size from the brand kit.
enum CanvasTemplate: String, CaseIterable, Identifiable, Sendable {
    case blank, announcement, quote, bigNumber, event, hiring, launch, photo

    var id: String { rawValue }

    var title: String {
        switch self {
        case .blank: return "Blank"
        case .announcement: return "Announcement"
        case .quote: return "Quote"
        case .bigNumber: return "Big number"
        case .event: return "Event"
        case .hiring: return "Hiring"
        case .launch: return "Launch"
        case .photo: return "Photo and caption"
        }
    }

    /// What the template says before you change it.
    struct Copy: Sendable {
        var headline = "We closed our first enterprise pilot."
        var detail = "Acme is rolling 11am out to 40 people this month."
        var number = "40"
        var kicker = "News"
        var link = "https://11am.app"
    }

    func document(_ preset: CanvasPreset, brand: CanvasBrand, copy: Copy = Copy(), photo: String? = nil) -> CanvasDocument {
        let size = preset.size
        let w = size.width, h = size.height
        let unit = min(w, h)
        let tall = h > w * 1.2, wide = w > h * 1.6
        let margin = unit * 0.08
        var layers: [CanvasLayer] = []
        var background: CanvasFill = .solid(brand.paper)

        func style(_ size: Double, _ weight: TextWeight, _ color: CanvasColor, heading: Bool = true, alignment: TextAlignment = .left, lineHeight: Double = 1.1) -> TextStyle {
            var style = TextStyle()
            style.font = heading ? brand.headingFont : brand.bodyFont
            style.size = (size * 10).rounded() / 10
            style.weight = weight
            style.color = color
            style.alignment = alignment
            style.lineHeight = lineHeight
            style.tracking = heading && size > unit * 0.07 ? -size * 0.015 : 0
            return style
        }
        func text(_ value: String, _ style: TextStyle, _ frame: CanvasRect, role: String) {
            var fitted = style
            fitted.size = CanvasRenderer.fittingSize(value, style, in: frame, minimum: max(10, style.size * 0.4))
            layers.append(.textLayer(value, fitted, frame: frame, role: role))
        }
        func footer(_ color: CanvasColor) {
            guard !brand.footer.isEmpty else { return }
            var footer = style(unit * 0.03, .semibold, color.withAlpha(0.7), heading: false)
            footer.tracking = unit * 0.002
            text(brand.footer, footer, CanvasRect(x: margin, y: h - margin - unit * 0.04, width: w * 0.6, height: unit * 0.045), role: "footer")
            layers.append(.shapeLayer(.ellipse, frame: CanvasRect(x: w - margin - unit * 0.04, y: h - margin - unit * 0.04, width: unit * 0.04, height: unit * 0.04),
                                      fill: .solid(brand.accent), role: "logo"))
        }

        switch self {
        case .blank:
            background = .solid(.white)
        case .announcement:
            let ink = brand.primary
            layers.append(.shapeLayer(.rectangle, frame: CanvasRect(x: margin, y: margin, width: unit * 0.12, height: unit * 0.018), fill: .solid(brand.accent), role: "accent"))
            text(copy.kicker.uppercased(), style(unit * 0.035, .bold, brand.accent, heading: false), CanvasRect(x: margin, y: margin + unit * 0.05, width: w - margin * 2, height: unit * 0.05), role: "kicker")
            let top = tall ? h * 0.3 : (wide ? margin + unit * 0.14 : h * 0.24)
            let headlineHeight = tall ? h * 0.32 : (wide ? h * 0.5 : h * 0.4)
            text(copy.headline, style(unit * (wide ? 0.1 : 0.095), .bold, ink, lineHeight: 1.04), CanvasRect(x: margin, y: top, width: w - margin * 2, height: headlineHeight), role: "title")
            text(copy.detail, style(unit * 0.042, .regular, ink.withAlpha(0.72), heading: false, lineHeight: 1.3),
                 CanvasRect(x: margin, y: top + headlineHeight + unit * 0.03, width: (w - margin * 2) * (wide ? 0.7 : 1), height: unit * 0.16), role: "body")
            footer(ink)
        case .quote:
            background = .solid(brand.primary)
            let ink = brand.paper
            text("\u{201C}", style(unit * 0.32, .heavy, brand.accent, lineHeight: 1), CanvasRect(x: margin * 0.8, y: margin * 0.6, width: unit * 0.3, height: unit * 0.3), role: "mark")
            text(copy.headline, style(unit * 0.075, .semibold, ink, lineHeight: 1.16),
                 CanvasRect(x: margin, y: tall ? h * 0.32 : h * 0.3, width: w - margin * 2, height: tall ? h * 0.36 : h * 0.42), role: "quote")
            text("— " + copy.detail, style(unit * 0.036, .medium, ink.withAlpha(0.75), heading: false),
                 CanvasRect(x: margin, y: tall ? h * 0.7 : h * 0.76, width: w - margin * 2, height: unit * 0.06), role: "attribution")
            footer(ink)
        case .bigNumber:
            background = .solid(brand.paper)
            text(copy.number, style(unit * (wide ? 0.4 : 0.34), .heavy, brand.accent, lineHeight: 1),
                 CanvasRect(x: margin, y: tall ? h * 0.22 : margin * 1.4, width: w - margin * 2, height: unit * 0.4), role: "number")
            text(copy.headline, style(unit * 0.07, .bold, brand.primary, lineHeight: 1.08),
                 CanvasRect(x: margin, y: (tall ? h * 0.22 : margin * 1.4) + unit * 0.43, width: w - margin * 2, height: unit * 0.22), role: "title")
            footer(brand.primary)
        case .event:
            background = .linear(brand.primary, brand.primary.withAlpha(0.85), angle: 90)
            let ink = brand.paper
            text(copy.kicker.uppercased(), style(unit * 0.035, .bold, brand.accent, heading: false), CanvasRect(x: margin, y: margin, width: w - margin * 2, height: unit * 0.05), role: "kicker")
            text(copy.headline, style(unit * 0.09, .bold, ink, lineHeight: 1.05), CanvasRect(x: margin, y: margin + unit * 0.1, width: (w - margin * 2) * (wide ? 0.62 : 1), height: unit * 0.34), role: "title")
            text(copy.detail, style(unit * 0.04, .medium, ink.withAlpha(0.8), heading: false, lineHeight: 1.35),
                 CanvasRect(x: margin, y: margin + unit * 0.48, width: (w - margin * 2) * (wide ? 0.62 : 0.7), height: unit * 0.2), role: "body")
            let qr = unit * (wide ? 0.32 : 0.24)
            layers.append(CanvasLayer(name: "QR code", content: .qr(copy.link), frame: CanvasRect(x: w - margin - qr, y: h - margin - qr, width: qr, height: qr),
                                      fill: .solid(.white), cornerRadius: qr * 0.05, role: "qr"))
        case .hiring:
            background = .solid(brand.soft)
            let ink = brand.primary
            text("We're hiring", style(unit * 0.05, .bold, brand.accent, heading: false), CanvasRect(x: margin, y: margin, width: w - margin * 2, height: unit * 0.07), role: "kicker")
            text(copy.headline, style(unit * 0.11, .heavy, ink, lineHeight: 1.0), CanvasRect(x: margin, y: margin + unit * 0.12, width: w - margin * 2, height: unit * 0.36), role: "title")
            text(copy.detail, style(unit * 0.04, .regular, ink.withAlpha(0.75), heading: false, lineHeight: 1.35),
                 CanvasRect(x: margin, y: margin + unit * 0.52, width: w - margin * 2 - unit * 0.28, height: unit * 0.2), role: "body")
            let qr = unit * 0.2
            layers.append(CanvasLayer(name: "QR code", content: .qr(copy.link), frame: CanvasRect(x: w - margin - qr, y: h - margin - qr, width: qr, height: qr),
                                      fill: .solid(.white), cornerRadius: qr * 0.05, role: "qr"))
            footer(ink)
        case .launch:
            background = .linear(brand.accent, brand.primary, angle: 60)
            let ink = CanvasColor.white
            text(copy.kicker.uppercased(), style(unit * 0.04, .heavy, ink.withAlpha(0.85), heading: false), CanvasRect(x: margin, y: h * 0.3 - unit * 0.08, width: w - margin * 2, height: unit * 0.06), role: "kicker")
            text(copy.headline, style(unit * 0.12, .heavy, ink, alignment: .left, lineHeight: 1.0), CanvasRect(x: margin, y: h * 0.3, width: w - margin * 2, height: unit * 0.42), role: "title")
            text(copy.detail, style(unit * 0.042, .medium, ink.withAlpha(0.85), heading: false), CanvasRect(x: margin, y: h * 0.3 + unit * 0.46, width: w - margin * 2, height: unit * 0.12), role: "body")
            footer(ink)
        case .photo:
            let split = wide ? w * 0.5 : (tall ? h * 0.58 : h * 0.62)
            var picture = CanvasLayer(name: "Photo", content: .image(photo ?? "", .fill),
                                      frame: wide ? CanvasRect(x: w - split, y: 0, width: split, height: h) : CanvasRect(x: 0, y: 0, width: w, height: split), role: "photo")
            if photo == nil { picture.content = .shape(.rectangle); picture.fill = .solid(brand.soft); picture.name = "Photo frame" }
            layers.append(picture)
            let box = wide ? CanvasRect(x: margin, y: margin, width: w - split - margin * 2, height: h - margin * 2)
                           : CanvasRect(x: margin, y: split + margin * 0.6, width: w - margin * 2, height: h - split - margin * 1.6)
            text(copy.headline, style(unit * 0.07, .bold, brand.primary, lineHeight: 1.06), CanvasRect(x: box.x, y: box.y, width: box.width, height: box.height * 0.62), role: "title")
            text(copy.detail, style(unit * 0.036, .regular, brand.primary.withAlpha(0.7), heading: false, lineHeight: 1.3),
                 CanvasRect(x: box.x, y: box.y + box.height * 0.66, width: box.width, height: box.height * 0.34), role: "body")
        }
        return CanvasDocument(name: "\(title) · \(preset.name)", size: size, background: background, layers: layers)
    }
}
