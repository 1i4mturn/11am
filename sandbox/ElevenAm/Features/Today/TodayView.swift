import AppKit
import SwiftUI

struct TodayView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var today: TodayModel
    @EnvironmentObject private var brain: Brain
    @EnvironmentObject private var phone: PhoneLinkModel
    @EnvironmentObject private var tasks: TasksModel
    @Environment(\.colorScheme) private var scheme
    @State private var width: CGFloat = 900
    @State private var scrolled: CGFloat = 0

    /// One square of the opener's grid: as large as the window allows, up to the size that keeps the day in view.
    private var square: CGFloat {
        min(112, max(64, (width - 230 - Opener.gap * 5) / 6))
    }

    private var openerText: TodayOpenerText {
        let events = today.shownEvents.map { TodayOpenerText.Event(title: $0.title, start: $0.start, end: $0.end, isAllDay: $0.isAllDay) }
        return TodayOpenerText.make(now: Date(), events: events, tasksDue: tasks.tasks(in: .today).count,
                                    overdue: tasks.overdueCount, briefReady: today.briefRun?.status == .done)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                // The overprint: the day's number, its word behind, and a note about the day, stepped across both.
                HStack(alignment: .top, spacing: 16) {
                    let text = openerText
                    Opener(numeral: text.numeral, word: text.word.rawValue, label: text.label, heading: text.heading, line: text.line,
                           square: square, scrolled: scrolled)
                        .background {
                            GeometryReader { proxy in
                                Color.clear.preference(key: OpenerScrollKey.self, value: proxy.frame(in: .named("today")).minY)
                            }
                        }
                    Spacer(minLength: 0)
                    VStack(alignment: .trailing, spacing: 12) {
                        Button {
                            phone.showsPairing = true
                        } label: {
                            Label(phone.isConnected ? "iPhone connected" : (phone.pairing == nil ? "Pair your iPhone" : "iPhone"), systemImage: "iphone")
                        }
                        .buttonStyle(.vellumSecondary)
                        .help("Energy from Apple Health, captures and your brief on the 11am iPhone app")
                        Toggle("11am check-in", isOn: $today.checkInEnabled)
                            .toggleStyle(.brandSwitch)
                            .controlSize(.small)
                            .help("A gentle notification at 11:00 every day")
                    }
                    .padding(.top, square + Opener.gap)
                }
                .onPreferenceChange(OpenerScrollKey.self) { minY in
                    scrolled = max(0, 24 - minY)
                }

                BriefCard()
                    .entrance()

                if !phone.energy.isEmpty {
                    EnergyCard()
                        .entrance(1)
                }

                TodayTasksCard()
                    .entrance(2)

                if !today.isLive {
                    Card {
                        HStack(alignment: .top, spacing: 12) {
                            Icon("calendar")
                                .font(.brand(size: 18))
                                .foregroundStyle(theme.inkSecondary(scheme))
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Showing a sample day")
                                    .font(.brand(size: 13, weight: .semibold))
                                    .foregroundStyle(theme.ink(scheme))
                                Text("Connect your calendars to see your real day. 11am reads every account you've added to macOS (iCloud, Google, Exchange) without any extra logins, and Outlook or Microsoft 365 through Calendar.")
                                    .font(.brand(size: 12.5))
                                    .foregroundStyle(theme.inkSecondary(scheme))
                                    .fixedSize(horizontal: false, vertical: true)
                                Button(today.access == .denied ? "Open Privacy Settings" : "Connect Calendars") {
                                    if today.access == .denied {
                                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
                                            NSWorkspace.shared.open(url)
                                        }
                                    } else {
                                        Task { await today.requestAccess() }
                                    }
                                }
                                .buttonStyle(.vellumSecondary)
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 0) {
                    SectionLabel(text: "Timeline")
                        .padding(.bottom, 8)
                    ForEach(Array(today.shownEvents.enumerated()), id: \.element.id) { index, event in
                        TimelineRow(event: event)
                            .entrance(index + 1)
                    }
                    if today.shownEvents.isEmpty {
                        Text("Nothing scheduled. A good day for deep work.")
                            .font(.brand(size: 13))
                            .foregroundStyle(theme.inkTertiary(scheme))
                            .padding(.vertical, 12)
                    }
                }
            }
            .padding(24)
            .background {
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { width = proxy.size.width - 48 }
                        .onChange(of: proxy.size.width) { _, value in width = value - 48 }
                }
            }
        }
        .coordinateSpace(name: "today")
        .scrollContentBackground(.hidden)
        .onAppear { today.loadEvents() }
        .sheet(isPresented: $phone.showsPairing) { PhonePairingSheet() }
    }
}

/// Where the opener sits in Today's scroll, for its drift.
private struct OpenerScrollKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

private struct BriefCard: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var today: TodayModel
    @EnvironmentObject private var brain: Brain
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionLabel(text: today.briefWasPreparedOvernight ? "Brief · prepared overnight" : "Brief")
                Spacer()
                Button(today.briefRun == nil ? "Write my brief" : "Rewrite") {
                    Task { await today.prepareBrief(overnight: false) }
                }
                .buttonStyle(.vellumPrimary)
                .disabled(brain.isBusy)
            }
            if let run = today.briefRun {
                BriefText(run: run)
            } else {
                Text("Your brief is written overnight while the Mac charges, so it's ready when you open the lid. You can also write it now.")
                    .font(theme.display(22))
                    .foregroundStyle(theme.inkSecondary(scheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .vellum(level: 3, radius: theme.radius)
    }
}

private struct BriefText: View {
    @EnvironmentObject private var theme: Theme
    @Environment(\.colorScheme) private var scheme
    @ObservedObject var run: BrainRun

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if run.text.isEmpty {
                RunView(run: run)
            } else {
                Text(run.text)
                    .font(theme.display(21))
                    .lineSpacing(4)
                    .foregroundStyle(theme.ink(scheme))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    ModelBadge(label: run.providerLabel, isLocal: run.isLocal)
                    if run.costUSD > 0 { Chip(text: Pricing.format(run.costUSD)) }
                    Chip(text: run.startedAt.formatted(date: .omitted, time: .shortened))
                }
            }
        }
    }
}

private struct TimelineRow: View {
    @EnvironmentObject private var theme: Theme
    @Environment(\.colorScheme) private var scheme
    var event: DayEvent

    var body: some View {
        let isPast = event.end < Date()
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(event.isAllDay ? "all day" : event.start.formatted(date: .omitted, time: .shortened))
                .font(.brand(size: 13).monospacedDigit())
                .foregroundStyle(theme.inkSecondary(scheme))
                .frame(width: 74, alignment: .leading)
            RoundedRectangle(cornerRadius: 0)
                .fill(theme.ink(scheme).opacity(isPast ? 0.2 : 0.85))
                .frame(width: 3, height: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .font(.brand(size: 14, weight: .medium))
                    .foregroundStyle(theme.ink(scheme).opacity(isPast ? 0.5 : 1))
                Text([event.location, event.calendar.isEmpty ? nil : event.calendar].compactMap { $0 }.joined(separator: " · "))
                    .font(.brand(size: 11.5))
                    .foregroundStyle(theme.inkTertiary(scheme))
            }
            Spacer()
        }
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            Rectangle().fill(theme.edge(scheme)).frame(height: 0.5)
        }
    }
}
