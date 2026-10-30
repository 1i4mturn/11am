import AppKit
import SwiftUI

struct TodayView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var today: TodayModel
    @EnvironmentObject private var brain: Brain
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                SectionHeader(title: "today", subtitle: Date().formatted(date: .complete, time: .omitted)) {
                    Toggle("11am check-in", isOn: $today.checkInEnabled)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .help("A gentle notification at 11:00 every day")
                }

                BriefCard()
                    .entrance()

                if !today.isLive {
                    Card {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "calendar")
                                .font(.system(size: 18))
                                .foregroundStyle(theme.inkSecondary(scheme))
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Showing a sample day")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(theme.ink(scheme))
                                Text("Connect your calendars to see your real day. 11am reads every account you've added to macOS (iCloud, Google, Exchange) without any extra logins, and Outlook or Microsoft 365 through Calendar.")
                                    .font(.system(size: 12.5))
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
                            .font(.system(size: 13))
                            .foregroundStyle(theme.inkTertiary(scheme))
                            .padding(.vertical, 12)
                    }
                }
            }
            .padding(24)
        }
        .scrollContentBackground(.hidden)
        .onAppear { today.loadEvents() }
    }
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
        .vellum(level: 3, radius: max(theme.radius - 4, 8))
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
                .font(.system(size: 13).monospacedDigit())
                .foregroundStyle(theme.inkSecondary(scheme))
                .frame(width: 74, alignment: .leading)
            RoundedRectangle(cornerRadius: 1.5)
                .fill(theme.ink(scheme).opacity(isPast ? 0.2 : 0.85))
                .frame(width: 3, height: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(theme.ink(scheme).opacity(isPast ? 0.5 : 1))
                Text([event.location, event.calendar.isEmpty ? nil : event.calendar].compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 11.5))
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
