import SwiftUI

struct Sidebar: View {
    static let groups: [(title: String, sections: [AppSection])] = [
        ("Every day", [.today, .calendar, .mail, .write, .files, .overnight]),
        ("Work", [.research, .money, .business]),
        ("Make", [.design, .photo, .video, .learn, .build]),
        ("Sandbox", [.suite, .lab]),
    ]

    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var machine: MachineProfile
    @EnvironmentObject private var brain: Brain
    @Environment(\.colorScheme) private var scheme
    @Namespace private var selection

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Shares a row with the window buttons, so the list starts high.
            HStack {
                Spacer()
                Wordmark(height: 16)
                    .padding(.trailing, 8)
            }
            .frame(height: 14)
            .padding(.bottom, 22)

            // Scrolls on short screens so the footer always fits.
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(Sidebar.groups.enumerated()), id: \.offset) { index, group in
                        SectionLabel(text: group.title)
                            .padding(.horizontal, 10)
                            .padding(.top, index == 0 ? 0 : 14)
                            .padding(.bottom, 3)
                        ForEach(group.sections) { section in
                            SidebarRow(section: section, selection: selection)
                        }
                    }
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .leading, spacing: 6) {
                SectionLabel(text: "This Mac")
                Text(machine.summary)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(theme.inkSecondary(scheme))
                HStack(spacing: 6) {
                    ModelBadge(label: brain.mode.title, isLocal: brain.mode == .onDevice || !brain.hasClaudeKey)
                }
                if brain.hasClaudeKey {
                    Text("Claude this month: \(Pricing.format(brain.spentThisMonthUSD)) of \(Pricing.format(brain.monthlyBudgetUSD))")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.inkTertiary(scheme))
                        .contentTransition(.numericText())
                }
                SettingsLink {
                    Text("Brain & settings…")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(theme.inkSecondary(scheme))
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }
            .padding(10)
        }
        .padding(.top, 0)
        .padding(.bottom, 4)
    }
}

private struct SidebarRow: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var theme: Theme
    @Environment(\.colorScheme) private var scheme
    var section: AppSection
    var selection: Namespace.ID
    @State private var hovering = false

    var body: some View {
        let selected = model.section == section
        Button {
            model.go(to: section)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: section.symbol)
                    .font(.system(size: 13, weight: .regular))
                    .frame(width: 18)
                Text(section.title)
                    .font(.system(size: 13, weight: selected ? .semibold : .regular))
                Spacer()
                AgentLogo(code: section.monogram, size: 20, color: theme.ink(scheme).opacity(selected ? 0.9 : 0.55))
            }
            .foregroundStyle(theme.ink(scheme))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background {
                if selected {
                    // One highlight that slides between rows.
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(theme.raised(scheme))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(theme.edge(scheme), lineWidth: 0.5)
                        }
                        .shadow(color: .black.opacity(scheme == .dark ? 0.25 : 0.06), radius: 3, y: 1)
                        .matchedGeometryEffect(id: "selection", in: selection)
                } else if hovering {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(theme.well(scheme).opacity(0.6))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { inside in
            withAnimation(theme.motionEnabled ? .easeOut(duration: 0.12) : nil) { hovering = inside }
        }
        .help(section.shortcutNumber.map { "\(section.subtitle) · ⌘\($0)" } ?? section.subtitle)
    }
}
