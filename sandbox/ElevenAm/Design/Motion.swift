import SwiftUI

/// Content rises into place the first time it appears, a beat after the item before it.
private struct Entrance: ViewModifier {
    @EnvironmentObject private var theme: Theme
    var index: Int
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : theme.rise)
            .onAppear {
                guard !shown else { return }
                guard let spring = theme.spring else {
                    shown = true
                    return
                }
                withAnimation(spring.delay(Double(min(index, 10)) * 0.035)) { shown = true }
            }
    }
}

/// A tile lifts a touch under the pointer.
private struct HoverLift: ViewModifier {
    @EnvironmentObject private var theme: Theme
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .offset(y: hovering ? -theme.lift : 0)
            .onHover { inside in
                withAnimation(theme.spring) { hovering = inside }
            }
    }
}

extension View {
    func entrance(_ index: Int = 0) -> some View {
        modifier(Entrance(index: index))
    }

    func hoverLift() -> some View {
        modifier(HoverLift())
    }
}

/// Used for content swapping in place (a new app, a new page): fades and rises in, fades out.
extension AnyTransition {
    static func rise(_ distance: CGFloat) -> AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .offset(y: distance)),
            removal: .opacity
        )
    }
}

/// Reports a view's height, for containers that size to their content (the notch, suggestion cards).
struct HeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

extension View {
    func readHeight(_ onChange: @escaping (CGFloat) -> Void) -> some View {
        background {
            GeometryReader { proxy in
                Color.clear.preference(key: HeightKey.self, value: proxy.size.height)
            }
        }
        .onPreferenceChange(HeightKey.self, perform: onChange)
    }
}

/// Lays chips and small buttons out in rows, wrapping when the row is full.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            widest = max(widest, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: widest, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
