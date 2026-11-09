import Foundation

/// Starting points for designs, laid out for any size from the brand kit.
enum CanvasTemplate: String, CaseIterable, Identifiable, Sendable {
    case blank, announcement, quote, bigNumber, event, hiring, launch, photo, invitation, certificate, menu, resume

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
        case .invitation: return "Invitation"
        case .certificate: return "Certificate"
        case .menu: return "Menu"
        case .resume: return "Résumé"
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
        case .invitation:
            background = .solid(brand.paper)
            let ink = brand.primary
            var border = CanvasLayer.shapeLayer(.rectangle, frame: CanvasRect(x: margin * 0.5, y: margin * 0.5, width: w - margin, height: h - margin), fill: .none, role: "border")
            border.stroke = brand.accent
            border.strokeWidth = max(2, unit * 0.004)
            layers.append(border)
            text("YOU'RE INVITED", style(unit * 0.034, .bold, brand.accent, heading: false, alignment: .center), CanvasRect(x: margin, y: h * 0.16, width: w - margin * 2, height: unit * 0.05), role: "kicker")
            text("The 11am launch party", style(unit * 0.1, .bold, ink, alignment: .center, lineHeight: 1.04), CanvasRect(x: margin, y: h * 0.24, width: w - margin * 2, height: h * 0.26), role: "title")
            layers.append(.shapeLayer(.rectangle, frame: CanvasRect(x: w / 2 - unit * 0.06, y: h * 0.53, width: unit * 0.12, height: max(2, unit * 0.004)), fill: .solid(brand.accent), role: "accent"))
            text("Friday 20 March, 6 pm\nFitzroy Cowork, 12 Smith Street", style(unit * 0.042, .medium, ink.withAlpha(0.8), heading: false, alignment: .center, lineHeight: 1.4),
                 CanvasRect(x: margin, y: h * 0.57, width: w - margin * 2, height: unit * 0.14), role: "body")
            text("RSVP by 13 March · hello@11am.app", style(unit * 0.03, .regular, ink.withAlpha(0.6), heading: false, alignment: .center),
                 CanvasRect(x: margin, y: h - margin * 1.6 - unit * 0.05, width: w - margin * 2, height: unit * 0.05), role: "footer")
        case .certificate:
            background = .solid(brand.paper)
            let ink = brand.primary
            for inset in [0.4, 0.62] {
                var border = CanvasLayer.shapeLayer(.rectangle, frame: CanvasRect(x: margin * inset, y: margin * inset, width: w - margin * inset * 2, height: h - margin * inset * 2), fill: .none, role: "border")
                border.stroke = inset < 0.5 ? ink : brand.accent
                border.strokeWidth = max(1.5, unit * (inset < 0.5 ? 0.006 : 0.002))
                layers.append(border)
            }
            text("CERTIFICATE OF COMPLETION", style(unit * 0.04, .bold, brand.accent, heading: false, alignment: .center), CanvasRect(x: margin, y: h * 0.18, width: w - margin * 2, height: unit * 0.06), role: "kicker")
            text("This is to certify that", style(unit * 0.036, .regular, ink.withAlpha(0.7), heading: false, alignment: .center), CanvasRect(x: margin, y: h * 0.3, width: w - margin * 2, height: unit * 0.05), role: "body")
            text("Priya Nair", style(unit * 0.11, .bold, ink, alignment: .center, lineHeight: 1), CanvasRect(x: margin, y: h * 0.37, width: w - margin * 2, height: unit * 0.14), role: "title")
            text("has completed Bookkeeping for Small Business, 12 hours", style(unit * 0.036, .regular, ink.withAlpha(0.75), heading: false, alignment: .center),
                 CanvasRect(x: margin * 1.5, y: h * 0.56, width: w - margin * 3, height: unit * 0.1), role: "detail")
            for (index, label) in ["Date", "Signed"].enumerated() {
                let x = index == 0 ? margin * 1.5 : w / 2 + margin * 0.5
                let lineWidth = w / 2 - margin * 2
                layers.append(.shapeLayer(.rectangle, frame: CanvasRect(x: x, y: h * 0.8, width: lineWidth, height: max(1.5, unit * 0.002)), fill: .solid(ink.withAlpha(0.6)), role: "line"))
                text(label, style(unit * 0.026, .medium, ink.withAlpha(0.6), heading: false, alignment: .center), CanvasRect(x: x, y: h * 0.8 + unit * 0.015, width: lineWidth, height: unit * 0.04), role: "label")
            }
        case .menu:
            background = .solid(brand.paper)
            let ink = brand.primary
            text("Lunch", style(unit * 0.12, .bold, ink, alignment: .center, lineHeight: 1), CanvasRect(x: margin, y: margin, width: w - margin * 2, height: unit * 0.14), role: "title")
            text("Served noon to three", style(unit * 0.03, .medium, brand.accent, heading: false, alignment: .center), CanvasRect(x: margin, y: margin + unit * 0.15, width: w - margin * 2, height: unit * 0.045), role: "kicker")
            let sections: [(String, String)] = [
                ("Small", "Sourdough, cultured butter · 9\nCharred broccolini, almonds · 14\nKingfish crudo, finger lime · 22"),
                ("Large", "Pumpkin risotto, sage · 28\nMarket fish, brown butter · 36\nSlow lamb shoulder, salsa verde · 38"),
                ("Sweet", "Burnt honey custard · 14\nDark chocolate, olive oil · 15"),
            ]
            let columns = wide ? 3 : 1
            let top = margin + unit * 0.26
            let columnWidth = (w - margin * 2 - Double(columns - 1) * margin) / Double(columns)
            let blockHeight = wide ? h - top - margin : (h - top - margin) / Double(sections.count)
            for (index, section) in sections.enumerated() {
                let x = margin + Double(index % columns) * (columnWidth + margin)
                let y = top + (wide ? 0 : Double(index) * blockHeight)
                text(section.0.uppercased(), style(unit * 0.034, .bold, brand.accent, heading: false, alignment: wide ? .left : .center),
                     CanvasRect(x: x, y: y, width: columnWidth, height: unit * 0.05), role: "heading")
                text(section.1, style(unit * 0.036, .regular, ink, heading: false, alignment: wide ? .left : .center, lineHeight: 1.5),
                     CanvasRect(x: x, y: y + unit * 0.06, width: columnWidth, height: blockHeight - unit * 0.08), role: "body")
            }
        case .resume:
            background = .solid(.white)
            let ink = brand.primary
            text("Sam Lee", style(unit * 0.08, .bold, ink, lineHeight: 1), CanvasRect(x: margin, y: margin, width: w - margin * 2, height: unit * 0.1), role: "title")
            text("Product designer · Melbourne · sam@example.com · 0400 000 000", style(unit * 0.028, .medium, brand.accent, heading: false),
                 CanvasRect(x: margin, y: margin + unit * 0.11, width: w - margin * 2, height: unit * 0.04), role: "kicker")
            layers.append(.shapeLayer(.rectangle, frame: CanvasRect(x: margin, y: margin + unit * 0.17, width: w - margin * 2, height: max(1.5, unit * 0.002)), fill: .solid(ink.withAlpha(0.3)), role: "line"))
            let blocks: [(String, String)] = [
                ("Experience", "Lead designer, 11am · 2024 to now\nDesigned the Mac suite's look and its eleven agents' apps.\n\nProduct designer, Kestrel Labs · 2020 to 2024\nLed onboarding and billing for 40,000 small businesses."),
                ("Skills", "Interaction and visual design · Prototyping · Research · Design systems · SwiftUI"),
                ("Education", "Bachelor of Design, RMIT University · 2019"),
            ]
            var y = margin + unit * 0.21
            let left = (w - margin * 2) * 0.24
            for block in blocks {
                let lines = Double(block.1.components(separatedBy: "\n").count)
                let height = unit * 0.035 * 1.45 * max(1, lines) + unit * 0.02
                text(block.0.uppercased(), style(unit * 0.026, .bold, brand.accent, heading: false), CanvasRect(x: margin, y: y, width: left - 12, height: unit * 0.04), role: "heading")
                text(block.1, style(unit * 0.03, .regular, ink, heading: false, lineHeight: 1.45), CanvasRect(x: margin + left, y: y, width: w - margin * 2 - left, height: height), role: "body")
                y += height + unit * 0.04
            }
        }
        return CanvasDocument(name: "\(title) · \(preset.name)", size: size, background: background, layers: layers)
    }
}
