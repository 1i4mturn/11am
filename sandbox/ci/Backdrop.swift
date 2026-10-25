// A busy desktop for CI screenshots: colour, shapes and a document, sitting just above the wallpaper,
// so the screenshots show how much of what's behind 11am reads through the vellum.
// Build and run: swiftc -O ci/Backdrop.swift -o backdrop && ./backdrop &
import AppKit

final class BusyView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let gradient = NSGradient(colors: [
            NSColor(red: 0.10, green: 0.22, blue: 0.52, alpha: 1),
            NSColor(red: 0.55, green: 0.20, blue: 0.45, alpha: 1),
            NSColor(red: 0.96, green: 0.55, blue: 0.22, alpha: 1),
        ])
        gradient?.draw(in: bounds, angle: -35)

        let blobs: [(CGFloat, CGFloat, CGFloat, NSColor)] = [
            (0.18, 0.70, 260, .systemTeal), (0.62, 0.30, 340, .systemYellow), (0.82, 0.78, 220, .systemPink),
            (0.40, 0.18, 180, .systemGreen), (0.50, 0.62, 200, .systemBlue),
        ]
        for (x, y, d, color) in blobs {
            color.withAlphaComponent(0.85).setFill()
            NSBezierPath(ovalIn: NSRect(x: bounds.width * x - d / 2, y: bounds.height * y - d / 2, width: d, height: d)).fill()
        }

        // A document window behind, with real text to read through the glass.
        let page = NSRect(x: bounds.width * 0.08, y: bounds.height * 0.12, width: bounds.width * 0.42, height: bounds.height * 0.7)
        NSColor.white.setFill()
        NSBezierPath(roundedRect: page, xRadius: 12, yRadius: 12).fill()
        let headline: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 44, weight: .heavy), .foregroundColor: NSColor.black]
        let body: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 20), .foregroundColor: NSColor.darkGray]
        ("Behind the window" as NSString).draw(at: NSPoint(x: page.minX + 32, y: page.maxY - 80), withAttributes: headline)
        let text = String(repeating: "The quick brown fox jumps over the lazy dog. Pack my box with five dozen liquor jugs. ", count: 14)
        (text as NSString).draw(in: page.insetBy(dx: 32, dy: 32).offsetBy(dx: 0, dy: -70), withAttributes: body)

        let big: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 140, weight: .black), .foregroundColor: NSColor.white.withAlphaComponent(0.9)]
        ("11am" as NSString).draw(at: NSPoint(x: bounds.width * 0.55, y: bounds.height * 0.08), withAttributes: big)
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let frame = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1920, height: 1080)
let window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
window.collectionBehavior = [.canJoinAllSpaces, .stationary]
window.contentView = BusyView(frame: NSRect(origin: .zero, size: frame.size))
window.orderFrontRegardless()
app.run()
