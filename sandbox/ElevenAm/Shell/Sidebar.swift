import SwiftUI

struct Sidebar: View {
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
                Wordmark(height: 17)
                    .padding(.trailing, 8)
            }
            .frame(height: 22)
            .padding(.bottom, 16)

            SectionLabel(text: "Apps")
                .padding(.horizontal, 10)
                .padding(.bottom, 3)
            ForEach([AppSection.today, .mail, .write, .files, .overnight]) { section in
                SidebarRow(section: section, selection: selection)
            }

            SectionLabel(text: "Sandbox")
                .padding(.horizontal, 10)
                .padding(.top, 16)
                .padding(.bottom, 3)
            ForEach([AppSection.suite, .lab]) { section in
                SidebarRow(section: section, selection: selection)
            }

            Spacer()

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
                AgentLogo(code: section.monogram, size: 20, color: theme.ink(scheme).opacity(selected ? 0.9 : 0.42))
            }
            .foregroundStyle(theme.ink(scheme))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
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
        .help("\(section.subtitle) · ⌘\(section.shortcutNumber)")
    }
}
