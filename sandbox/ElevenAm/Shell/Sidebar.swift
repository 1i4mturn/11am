import SwiftUI

struct Sidebar: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var machine: MachineProfile
    @EnvironmentObject private var brain: Brain
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("11am")
                .font(theme.display(30))
                .tracking(-0.8)
                .foregroundStyle(theme.ink(scheme))
                .padding(.horizontal, 10)
                .padding(.bottom, 14)

            SectionLabel(text: "Apps")
                .padding(.horizontal, 10)
                .padding(.bottom, 2)
            ForEach([AppSection.today, .files, .overnight]) { section in
                SidebarRow(section: section)
            }

            SectionLabel(text: "Sandbox")
                .padding(.horizontal, 10)
                .padding(.top, 14)
                .padding(.bottom, 2)
            ForEach([AppSection.suite, .lab]) { section in
                SidebarRow(section: section)
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
        .padding(.vertical, 4)
    }
}

private struct SidebarRow: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var theme: Theme
    @Environment(\.colorScheme) private var scheme
    var section: AppSection

    var body: some View {
        let selected = model.section == section
        Button {
            model.section = section
        } label: {
            HStack(spacing: 10) {
                Image(systemName: section.symbol)
                    .font(.system(size: 13, weight: .regular))
                    .frame(width: 18)
                Text(section.title)
                    .font(.system(size: 13, weight: selected ? .semibold : .regular))
                Spacer()
                Text(section.monogram)
                    .font(theme.monogramFont(10.5))
                    .foregroundStyle(theme.inkTertiary(scheme))
            }
            .foregroundStyle(theme.ink(scheme))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(selected ? theme.well(scheme).opacity(2.2) : Color.clear)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
