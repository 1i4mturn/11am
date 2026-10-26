import SwiftUI

/// Conner's app: the pipeline as a board. Drag a deal to move it; pick one to work on it.
struct BusinessView: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var business: BusinessModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: "business", subtitle: subtitle) {
                Button {
                    withAnimation(theme.spring) { business.addDeal() }
                } label: {
                    Label("New deal", systemImage: "plus")
                }
                .buttonStyle(.vellumPrimary)
            }

            HStack(alignment: .top, spacing: 12) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 10) {
                        ForEach(DealStage.allCases) { stage in
                            StageColumn(stage: stage)
                        }
                    }
                    .padding(.bottom, 4)
                }
                if let deal = business.selected {
                    DealDetail(deal: deal)
                        .id(deal.id)
                        .frame(width: 280)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .padding(24)
        .animation(theme.spring, value: business.selectedID)
    }

    private var subtitle: String {
        var parts = ["Weighted pipeline \(Money.short(business.weightedPipeline))"]
        if business.staleCount > 0 { parts.append("\(business.staleCount) going quiet") }
        return "Conner · " + parts.joined(separator: " · ")
    }
}

private struct StageColumn: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var business: BusinessModel
    @Environment(\.colorScheme) private var scheme
    var stage: DealStage
    @State private var targeted = false

    var body: some View {
        let deals = business.deals(in: stage)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(stage.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.ink(scheme))
                Text("\(deals.count)")
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(theme.inkTertiary(scheme))
                Spacer()
                Text(Money.short(business.total(stage)))
                    .font(.system(size: 11.5, weight: .medium).monospacedDigit())
                    .foregroundStyle(theme.inkSecondary(scheme))
                    .contentTransition(.numericText())
            }
            .padding(.horizontal, 4)

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(Array(deals.enumerated()), id: \.element.id) { index, deal in
                        DealCard(deal: deal, selected: business.selectedID == deal.id)
                            .entrance(index)
                    }
                    if deals.isEmpty {
                        Text("Drop a deal here")
                            .font(.system(size: 11.5))
                            .foregroundStyle(theme.inkTertiary(scheme))
                            .frame(maxWidth: .infinity, minHeight: 60)
                    }
                }
                .padding(2)
            }
            .scrollContentBackground(.hidden)
        }
        .padding(10)
        .frame(width: 200)
        .frame(maxHeight: .infinity, alignment: .top)
        .background {
            RoundedRectangle(cornerRadius: max(theme.radius - 2, 8), style: .continuous)
                .fill(targeted ? theme.raised(scheme) : theme.well(scheme).opacity(0.45))
        }
        .overlay {
            RoundedRectangle(cornerRadius: max(theme.radius - 2, 8), style: .continuous)
                .strokeBorder(targeted ? theme.ink(scheme).opacity(0.35) : theme.edge(scheme), lineWidth: targeted ? 1 : 0.5)
        }
        .dropDestination(for: String.self) { items, _ in
            guard let first = items.first, let id = UUID(uuidString: first) else { return false }
            withAnimation(theme.spring) { business.move(id, to: stage) }
            return true
        } isTargeted: { inside in
            withAnimation(theme.motionEnabled ? .easeOut(duration: 0.15) : nil) { targeted = inside }
        }
    }
}

private struct DealCard: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var business: BusinessModel
    @Environment(\.colorScheme) private var scheme
    var deal: Deal
    var selected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(deal.name)
                    .font(.system(size: 12.5, weight: .semibold))
                    .lineLimit(2)
                Spacer(minLength: 4)
                if deal.isStale {
                    Text("quiet")
                        .font(.system(size: 9.5, weight: .semibold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(Capsule().strokeBorder(theme.ink(scheme).opacity(0.4), lineWidth: 0.75))
                        .help("No contact for over a week")
                }
            }
            Text(Money.format(deal.value))
                .font(.system(size: 12).monospacedDigit())
                .foregroundStyle(theme.inkSecondary(scheme))
            if !deal.nextStep.isEmpty {
                Text(deal.nextStep)
                    .font(.system(size: 11))
                    .foregroundStyle(theme.inkTertiary(scheme))
                    .lineLimit(2)
            }
        }
        .foregroundStyle(theme.ink(scheme))
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: max(theme.radius - 4, 7), style: .continuous)
                .fill(theme.raised(scheme))
        }
        .overlay {
            RoundedRectangle(cornerRadius: max(theme.radius - 4, 7), style: .continuous)
                .strokeBorder(selected ? theme.ink(scheme).opacity(0.5) : theme.edge(scheme), lineWidth: selected ? 1 : 0.5)
        }
        .shadow(color: .black.opacity(scheme == .dark ? 0.2 : 0.04), radius: 2, y: 1)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(theme.spring) { business.selectedID = selected ? nil : deal.id }
        }
        .draggable(deal.id.uuidString) {
            Text(deal.name)
                .font(.system(size: 12.5, weight: .semibold))
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8).fill(theme.raised(scheme)))
        }
        .hoverLift()
    }
}

private struct DealDetail: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var business: BusinessModel
    @EnvironmentObject private var brain: Brain
    @Environment(\.colorScheme) private var scheme
    @State private var draft: Deal

    init(deal: Deal) {
        _draft = State(initialValue: deal)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    AgentLogo(code: "cr", size: 24)
                    Spacer()
                    Button { withAnimation(theme.spring) { business.selectedID = nil } } label: {
                        Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(theme.inkTertiary(scheme))
                    .help("Close")
                }
                field("Deal", text: $draft.name)
                field("Company", text: $draft.company)
                field("Contact email", text: $draft.contact)
                VStack(alignment: .leading, spacing: 3) {
                    SectionLabel(text: "Value")
                    TextField("Value", value: $draft.value, format: .currency(code: Money.currencyCode).precision(.fractionLength(0)))
                        .textFieldStyle(.roundedBorder)
                }
                Picker("Stage", selection: $draft.stage) {
                    ForEach(DealStage.allCases) { stage in Text(stage.title).tag(stage) }
                }
                field("Next step", text: $draft.nextStep)
                VStack(alignment: .leading, spacing: 3) {
                    SectionLabel(text: "Notes")
                    TextEditor(text: $draft.notes)
                        .font(.system(size: 12.5))
                        .scrollContentBackground(.hidden)
                        .padding(4)
                        .frame(height: 64)
                        .background(RoundedRectangle(cornerRadius: 6).fill(theme.well(scheme)))
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(theme.edge(scheme), lineWidth: 0.5))
                }
                Text("Last contact \(draft.lastTouch.formatted(.relative(presentation: .named)))")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.inkTertiary(scheme))

                FlowLayout(spacing: 6) {
                    Button("Draft follow-up") { business.draftFollowUp(draft) }
                        .buttonStyle(.vellumPrimary)
                    Button("Next step?") { business.adviseNextStep(draft) }
                        .buttonStyle(.vellumSecondary)
                    Button("Delete") { withAnimation(theme.spring) { business.delete(draft.id) } }
                        .buttonStyle(.vellumSecondary)
                }
                .disabled(brain.isBusy)

                if let run = business.advice[draft.id] {
                    Card { RunView(run: run) }
                }
                if let run = business.drafts[draft.id] {
                    FollowUp(run: run, deal: draft)
                }
            }
            .padding(14)
        }
        .scrollContentBackground(.hidden)
        .vellum(level: 3, radius: max(theme.radius - 2, 8))
        .onChange(of: draft) { _, newValue in business.update(newValue) }
    }

    private func field(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            SectionLabel(text: label)
            TextField(label, text: text)
                .textFieldStyle(.roundedBorder)
        }
    }
}

private struct FollowUp: View {
    @EnvironmentObject private var business: BusinessModel
    @ObservedObject var run: BrainRun
    var deal: Deal

    var body: some View {
        Card {
            RunView(run: run)
            if run.status == .done, !deal.contact.isEmpty {
                Button("Open in Mail") { business.openInMail(deal, body: run.text) }
                    .buttonStyle(.vellumPrimary)
            }
        }
    }
}
