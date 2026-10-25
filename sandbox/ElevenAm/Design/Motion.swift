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
