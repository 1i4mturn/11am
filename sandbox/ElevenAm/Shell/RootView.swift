import SwiftUI

/// Layers, back to front: the desktop (blurred by the system) → a faint vellum wash →
/// the sidebar printed straight onto it → the main sheet → the agent sheet.
struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var theme: Theme
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            FrostedBackdrop(material: theme.values.backdrop.material, blending: .behindWindow)
                .ignoresSafeArea()
            theme.paper(scheme)
                .opacity(theme.frostOpacity(level: 0))
                .ignoresSafeArea()
            GrainOverlay()
                .ignoresSafeArea()

            HStack(spacing: 12) {
                Sidebar()
                    .frame(width: 214)

                SectionContent(section: model.section)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .vellum(level: 2)

                if model.showsPane {
                    AgentPane()
                        .frame(width: 292)
                        .vellum(level: 1)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .padding(.top, 40)
            .padding([.horizontal, .bottom], 12)
        }
        .background(WindowConfigurator())
        .preferredColorScheme(theme.values.appearance.colorScheme)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: model.showsPane)
    }
}

private struct SectionContent: View {
    var section: AppSection

    var body: some View {
        switch section {
        case .today: TodayView()
        case .files: FilesView()
        case .overnight: OvernightView()
        case .suite: SuiteView()
        case .lab: DesignLabView()
        }
    }
}
