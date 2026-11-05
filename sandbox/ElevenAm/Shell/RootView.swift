import SwiftUI

/// Layers, back to front: the desktop (partly as it is, partly blurred by the system) → a white vellum wash →
/// the sidebar printed straight onto it → the main sheet → the agent sheet. Sheets carry their own frost.
struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var theme: Theme
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            FrostedBackdrop(
                material: theme.values.backdrop.material,
                blending: .behindWindow,
                opacity: theme.backdropOpacity
            )
            .ignoresSafeArea()
            theme.paper(scheme)
                .opacity(theme.frostOpacity(level: 0))
                .ignoresSafeArea()
            GrainOverlay()
                .ignoresSafeArea()

            GeometryReader { proxy in
                // On smaller screens (or larger text) the agent pane steps aside so the app keeps its room.
                let roomForPane = proxy.size.width >= 1120
                HStack(spacing: 10) {
                    Sidebar()
                        .frame(width: 210)

                    ZStack {
                        SectionContent(section: model.section)
                            .id(model.section)
                            .transition(.rise(theme.rise))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    .vellum(level: 2)

                    if model.showsPane && roomForPane {
                        AgentPane()
                            .frame(width: 288)
                            .vellum(level: 1)
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
                // Sheets run nearly to the top; the sidebar clears the window buttons itself.
                .padding(.top, 10)
                .padding([.horizontal, .bottom], 10)
            }
            // The hidden title bar still reserves a safe area; reclaim it so there's no band at the top.
            .ignoresSafeArea(.container, edges: .top)
        }
        .background(WindowConfigurator())
        .preferredColorScheme(theme.values.appearance.colorScheme)
        .animation(theme.spring, value: model.showsPane)
    }
}

private struct SectionContent: View {
    var section: AppSection

    var body: some View {
        switch section {
        case .today: TodayView()
        case .calendar: CalendarView()
        case .tasks: TasksView()
        case .mail: MailView()
        case .notes: NotesView()
        case .write: WriteView()
        case .files: FilesView()
        case .pdf: PDFAppView()
        case .research: ResearchView()
        case .money: MoneyView()
        case .sheets: SheetsView()
        case .business: BusinessView()
        case .decks: DecksView()
        case .design: DesignView()
        case .photo: PhotoView()
        case .video: VideoView()
        case .audio: AudioView()
        case .learn: LearnView()
        case .build: BuildView()
        case .overnight: OvernightView()
        case .suite: SuiteView()
        case .lab: DesignLabView()
        }
    }
}
