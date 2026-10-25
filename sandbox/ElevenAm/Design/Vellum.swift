import AppKit
import SwiftUI

/// Real behind-window blur from the system: the frosted layer that lets the desktop show through.
struct FrostedBackdrop: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blending: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blending
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = blending
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
/// Higher levels sit "on top" and are more opaque, like paper laid over paper.
struct VellumSheet: ViewModifier {
    @EnvironmentObject private var theme: Theme
    @Environment(\.colorScheme) private var scheme

    var level: Int
    var radius: CGFloat?

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius ?? theme.radius, style: .continuous)
        content
            .background {
                shape
                    .fill(theme.paper(scheme).opacity(theme.frostOpacity(level: level)))
                    .background(.ultraThinMaterial, in: shape)
                    .overlay { GrainOverlay().clipShape(shape) }
                    .overlay {
                        shape.strokeBorder(
                            LinearGradient(
                                colors: [theme.highlight(scheme), theme.edge(scheme), theme.edge(scheme)],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 0.75
                        )
                    }
                    .shadow(
                        color: Color.black.opacity(theme.shadowOpacity(scheme)),
                        radius: 6 + 18 * theme.values.depth,
                        x: 0,
                        y: 2 + 8 * theme.values.depth
                    )
            }
    }
}

extension View {
    func vellum(level: Int = 2, radius: CGFloat? = nil) -> some View {
        modifier(VellumSheet(level: level, radius: radius))
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
