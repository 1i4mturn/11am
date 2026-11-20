import SwiftUI

struct Sidebar: View {
    static let groups: [(title: String, sections: [AppSection])] = [
        ("Every day", [.today, .calendar, .tasks, .mail, .notes, .write, .files, .overnight]),
        ("Work", [.pdf, .research, .money, .sheets, .business, .decks]),
        ("Make", [.design, .photo, .video, .audio, .learn, .build]),
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
                Text(machine.summary.lowercased())
                    .font(BrandFont.label(12))
                    .foregroundStyle(theme.ink(scheme))
                HStack(spacing: 6) {
                    ModelBadge(label: brain.mode.title, isLocal: brain.mode == .onDevice || !brain.hasClaudeKey)
                }
                if brain.hasClaudeKey {
                    Text("Claude this month: \(Pricing.format(brain.spentThisMonthUSD)) of \(Pricing.format(brain.monthlyBudgetUSD))")
                        .font(.brand(size: 11))
                        .foregroundStyle(theme.inkTertiary(scheme))
                        .contentTransition(.numericText())
                }
                SettingsLink {
                    Text("Brain and settings")
                        .font(BrandFont.body(12.5, weight: .medium))
                        .underline()
                        .foregroundStyle(theme.ink(scheme))
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
        let ink = theme.ink(scheme), paper = theme.paper(scheme)
        Button {
            model.go(to: section)
        } label: {
            HStack(spacing: 10) {
                AppGlyph(section: section, size: 16, color: selected ? paper : ink)
                Text(section.title)
                    .font(BrandFont.body(13.5, weight: selected ? .semibold : nil))
                Spacer()
                AgentCircle(code: section.monogram, size: 20, style: selected ? .paper : .ring)
            }
            .foregroundStyle(selected ? paper : ink)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background {
                if selected {
                    // The active app is a solid ink row that slides between rows.
                    Rectangle()
                        .fill(ink)
                        .matchedGeometryEffect(id: "selection", in: selection)
                } else if hovering {
                    Rectangle().fill(theme.well(scheme)).lift(row: true)
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
