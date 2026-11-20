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

/// The tracing-paper tooth (kept under the old name so every surface picks it up).
struct GrainOverlay: View {
    var body: some View { Tooth() }
}

/// A surface in brand v2. Paper lifts off paper with a soft shadow, square, no outline; in the ink theme it's a
/// sheet-ink layer over the ink ground. Every surface carries the tracing-paper tooth.
/// Levels keep their old meaning: 0 the window, 1 a side sheet, 2 the main sheet, 3 a card laid on a sheet.
struct VellumSheet: ViewModifier {
    @EnvironmentObject private var theme: Theme
    @Environment(\.colorScheme) private var scheme

    var level: Int
    var radius: CGFloat?
    var blending: NSVisualEffectView.BlendingMode

    func body(content: Content) -> some View {
        let shape = Rectangle()
        let corner = radius ?? BrandTokens.radius
        content
            .background {
                if corner > 0 {
                    surface(RoundedRectangle(cornerRadius: corner, style: .continuous))
                } else {
                    surface(shape)
                }
            }
    }

    @ViewBuilder
    private func surface<S: Shape>(_ shape: S) -> some View {
        if scheme == .dark {
            ZStack {
                shape.fill(BrandTokens.inkHex)
                shape.fill(BrandTokens.sheetInk.opacity(level >= 3 ? 1 : (level == 2 ? 0.5 : 0.75)))
                Tooth().clipShape(shape)
            }
        } else {
            ZStack {
                shape.fill(BrandTokens.paperHex)
                    .lift(hi: level == 1)
                Tooth().clipShape(shape)
            }
        }
    }
}

extension View {
    /// Kept for every screen that asks for vellum; brand v2 draws it as lifted paper (see `VellumSheet`).
    func vellum(level: Int = 2, radius: CGFloat? = nil, blending: NSVisualEffectView.BlendingMode = .behindWindow) -> some View {
        modifier(VellumSheet(level: level, radius: radius, blending: blending))
    }

    /// A vellum note: paper at 82% with the tooth, the post-it that carries text over anything, ink included.
    func noteSurface() -> some View {
        background {
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                Rectangle().fill(BrandTokens.note)
                Tooth()
            }
        }
    }

    /// A solid ink panel with the tooth, paper text on it.
    func inkPanel() -> some View {
        background {
            ZStack {
                Rectangle().fill(BrandTokens.inkHex)
                Tooth()
            }
        }
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
