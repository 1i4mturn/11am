import SwiftUI

/// Layers, back to front: the paper ground with the sidebar printed on it, then the main sheet and the agent sheet,
/// each lifted off the paper (brand v2).
struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var research: ResearchModel
    @EnvironmentObject private var theme: Theme
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            // Brand v2: the window is paper (ink in dark mode) carrying the tracing-paper tooth. No desktop showing
            // through any more; depth comes from paper lifting off paper.
            theme.paper(scheme)
                .ignoresSafeArea()
            Tooth()
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
                    // A look-up from another app still shows when the agent pane has stepped aside.
                    .overlay(alignment: .topTrailing) {
                        if let lookup = research.lookup, !(model.showsPane && roomForPane), model.section != .research {
                            ScrollView {
                                LookUpCard(lookup: lookup)
                            }
                            .scrollContentBackground(.hidden)
                            .frame(width: 340)
                            .frame(maxHeight: 520)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(8)
                            .vellum(level: 1, radius: theme.radius)
                            .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
                            .padding(18)
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                        }
                    }

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
        // elevenam://clip and elevenam://lookup from the browser button: handled in this window, not a new one.
        .onOpenURL { url in
            if let link = ClipLink.parse(url) { model.research.handle(link) }
        }
        .handlesExternalEvents(preferring: ["*"], allowing: ["*"])
        .preferredColorScheme(theme.values.appearance.colorScheme)
        // No accent colour: system controls (progress, pickers, links) take ink.
        .tint(theme.ink(scheme))
        .animation(theme.spring, value: model.showsPane)
        .animation(theme.spring, value: research.lookup?.id)
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
