import AppKit
import SwiftUI

/// Real behind-window blur from the system: the frosted layer that lets the desktop show through.
/// Drawn at partial opacity, the rest of the window shows the desktop unblurred (Clarity in the Design Lab).
struct FrostedBackdrop: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blending: NSVisualEffectView.BlendingMode = .behindWindow
    var opacity: Double = 1
    /// Rounds the blur itself. AppKit views ignore SwiftUI clipping, so this uses a mask image.
    var cornerRadius: CGFloat = 0

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.state = .active
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = blending
        view.alphaValue = CGFloat(opacity)
        if view.maskImage?.size.width != cornerRadius * 2 + 1 {
            view.maskImage = cornerRadius > 0 ? FrostedBackdrop.mask(radius: cornerRadius) : nil
        }
    }

    /// A stretchable rounded-rect mask: only the corners are drawn, the middle stretches.
    private static func mask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}

/// Paper grain, generated once and tiled. Tiny, so it costs nothing on an 8 GB Mac.
enum GrainTexture {
    static let darkSpecks: NSImage = make(white: false)
    static let lightSpecks: NSImage = make(white: true)

    private static func make(white: Bool) -> NSImage {
        let size = 128
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        var generator = SystemRandomNumberGenerator()
        for index in 0..<(size * size) {
            let alpha = UInt8.random(in: 0...70, using: &generator)
            let value: UInt8 = white ? alpha : 0 // premultiplied alpha
            pixels[index * 4 + 0] = value
            pixels[index * 4 + 1] = value
            pixels[index * 4 + 2] = value
            pixels[index * 4 + 3] = alpha
        }
        let data = Data(pixels) as CFData
        guard let provider = CGDataProvider(data: data),
              let image = CGImage(
                width: size,
                height: size,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: size * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
              ) else {
            return NSImage(size: NSSize(width: 1, height: 1))
        }
        return NSImage(cgImage: image, size: NSSize(width: size, height: size))
    }
}

struct GrainOverlay: View {
    @EnvironmentObject private var theme: Theme
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Image(nsImage: scheme == .dark ? GrainTexture.lightSpecks : GrainTexture.darkSpecks)
            .resizable(resizingMode: .tile)
            .opacity(theme.values.grain * 0.5)
            .allowsHitTesting(false)
    }
}

/// A sheet of vellum: frosted, faintly tinted, grained, with a hairline edge and a lit top edge.
/// Sheets (levels 1-2) carry their own frosted backdrop, so they read as frosted paper over the clearer window.
/// Cards (level 3+) are paper laid on a sheet: a wash only.
struct VellumSheet: ViewModifier {
    @EnvironmentObject private var theme: Theme
    @Environment(\.colorScheme) private var scheme

    var level: Int
    var radius: CGFloat?
    var blending: NSVisualEffectView.BlendingMode

    func body(content: Content) -> some View {
        let corner = radius ?? theme.radius
        let shape = RoundedRectangle(cornerRadius: corner, style: .circular)
        content
            .background {
                ZStack {
                    OuterShadow(
                        shape: shape,
                        color: Color.black.opacity(theme.shadowOpacity(scheme)),
                        radius: 6 + 18 * theme.values.depth,
                        y: 2 + 8 * theme.values.depth
                    )
                    if level <= 2 {
                        FrostedBackdrop(
                            material: theme.values.backdrop.material,
                            blending: blending,
                            opacity: theme.sheetBackdropOpacity,
                            cornerRadius: corner
                        )
                    }
                    shape.fill(theme.paper(scheme).opacity(theme.frostOpacity(level: level)))
                    GrainOverlay().clipShape(shape)
                    shape.strokeBorder(
                        LinearGradient(
                            colors: [theme.highlight(scheme), theme.edge(scheme), theme.edge(scheme)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.75
                    )
                }
            }
    }
}

/// A shadow cast only outside the sheet. A plain shadow would show through the translucent paper and grey it.
private struct OuterShadow: View {
    var shape: RoundedRectangle
    var color: Color
    var radius: CGFloat
    var y: CGFloat

    var body: some View {
        shape.fill(Color.black)
            .shadow(color: color, radius: radius, x: 0, y: y)
            .mask {
                Rectangle()
                    .padding(-(radius * 2 + abs(y) + 8))
                    .overlay(shape.fill(Color.black).blendMode(.destinationOut))
                    .compositingGroup()
            }
            .allowsHitTesting(false)
    }
}

extension View {
    /// `blending: .withinWindow` frosts what's inside the window instead of the desktop (the Design Lab preview).
    func vellum(level: Int = 2, radius: CGFloat? = nil, blending: NSVisualEffectView.BlendingMode = .behindWindow) -> some View {
        modifier(VellumSheet(level: level, radius: radius, blending: blending))
    }
}

/// Makes the hosting window transparent so the behind-window blur reaches the desktop.
struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        Task { @MainActor in
            guard let window = view.window else { return }
            window.isOpaque = false
            window.backgroundColor = .clear
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.styleMask.insert(.fullSizeContentView)
            window.isMovableByWindowBackground = true
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
