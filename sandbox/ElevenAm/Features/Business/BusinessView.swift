import SwiftUI

/// Conner's app: the pipeline as a board, every deal in a list, the people and companies you work with
/// (found from your mail), what's happened with each, and a forecast by month.
struct BusinessView: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var business: BusinessModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: "business", subtitle: subtitle) {
                HStack(spacing: 10) {
                    Button {
                        withAnimation(theme.spring) { business.refreshContacts() }
                    } label: {
                        Image(systemName: "person.crop.circle.badge.plus")
                    }
                    .buttonStyle(.vellumSecondary)
                    .help("Find the people you write to in your mail, and their companies")
                    Button {
                        withAnimation(theme.spring) { add() }
                    } label: {
                        Label(addTitle, systemImage: "plus")
                    }
                    .buttonStyle(.vellumPrimary)
                }
            }

            Picker("", selection: $business.tab) {
                ForEach(BusinessTab.allCases) { tab in Text(tab.title).tag(tab) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()

            if let notice = business.notice {
                Text(notice)
                    .font(.system(size: 12.5))
                    .foregroundStyle(theme.ink(scheme))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(theme.well(scheme)))
                    .onTapGesture { business.notice = nil }
                    .task(id: notice) {
                        try? await Task.sleep(nanoseconds: 6_000_000_000)
                        if business.notice == notice { business.notice = nil }
                    }
            }

            Group {
                switch business.tab {
                case .pipeline: PipelineBoard()
                case .deals: DealList()
                case .people: PeopleList()
                case .companies: CompanyList()
                case .forecast: ForecastView()
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .padding(24)
        .animation(theme.spring, value: business.selectedID)
        .animation(theme.spring, value: business.tab)
        .onAppear { business.refreshContacts() }
    }

    private var subtitle: String {
        var parts = ["Weighted pipeline \(Money.short(business.weightedPipeline))"]
        let quiet = business.staleCount
        if quiet > 0 { parts.append("\(quiet) going quiet") }
        return "Conner · " + parts.joined(separator: " · ")
    }

    private var addTitle: String {
        switch business.tab {
        case .people: return "New person"
        case .companies: return "New company"
        default: return "New deal"
        }
    }

    private func add() {
        switch business.tab {
        case .people: business.addPerson()
        case .companies: business.addOrganisation()
        default:
            if business.tab == .forecast { business.tab = .pipeline }
            business.addDeal()
        }
    }
}

// MARK: - Pipeline

private struct PipelineBoard: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var business: BusinessModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            QuietStrip()
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
                        .frame(width: 300)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }
}

/// Deals going quiet, with a follow-up a click away.
private struct QuietStrip: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var business: BusinessModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let quiet = business.quietDeals
        if !quiet.isEmpty {
            HStack(spacing: 8) {
                AgentLogo(code: "cr", size: 16, color: theme.inkSecondary(scheme))
                Text("Going quiet")
                    .font(.system(size: 12, weight: .semibold))
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(quiet) { deal in
                            Button {
                                withAnimation(theme.spring) { business.selectedID = deal.id }
                                business.draftFollowUp(deal)
                            } label: {
                                Text("\(deal.name) · \(CRMNudge.text(lastTouch: business.lastTouch(deal), now: Date(), calendar: .current).lowercased())")
                                    .font(.system(size: 11.5))
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 4)
                                    .background(Capsule().fill(theme.well(scheme)))
                                    .overlay(Capsule().strokeBorder(theme.edge(scheme), lineWidth: 0.5))
                            }
                            .buttonStyle(.plain)
                            .help("Open it and draft a follow-up")
                        }
                    }
                }
            }
            .foregroundStyle(theme.ink(scheme))
        }
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
                if business.isQuiet(deal) {
                    Text("quiet")
                        .font(.system(size: 9.5, weight: .semibold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(Capsule().strokeBorder(theme.ink(scheme).opacity(0.4), lineWidth: 0.75))
                        .help(CRMNudge.text(lastTouch: business.lastTouch(deal), now: Date(), calendar: .current))
                }
            }
            HStack(spacing: 6) {
                Text(Money.format(deal.value))
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(theme.inkSecondary(scheme))
                if let close = deal.closeDate, deal.stage.isOpen {
                    Text("· closes " + close.formatted(.dateTime.day().month(.abbreviated)))
                        .font(.system(size: 11))
                        .foregroundStyle(theme.inkTertiary(scheme))
                }
            }
            if let person = business.findPerson(deal.personID) {
                Text(person.name)
                    .font(.system(size: 11))
                    .foregroundStyle(theme.inkTertiary(scheme))
            }
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

// MARK: - Deal

private struct DealDetail: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var business: BusinessModel
    @EnvironmentObject private var brain: Brain
    @Environment(\.colorScheme) private var scheme
    @State private var draft: Deal
    @State private var call = ""

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
                VStack(alignment: .leading, spacing: 3) {
                    SectionLabel(text: "Company")
                    Picker("", selection: Binding(get: { draft.organisationID }, set: { id in
                        draft.organisationID = id
                        if let company = business.findOrganisation(id) { draft.company = company.name }
                    })) {
                        Text(draft.company.isEmpty ? "None" : draft.company + " (not in Companies)").tag(UUID?.none)
                        ForEach(business.organisations) { company in Text(company.name).tag(Optional(company.id)) }
                    }
                    .labelsHidden()
                }
                VStack(alignment: .leading, spacing: 3) {
                    SectionLabel(text: "Person")
                    Picker("", selection: Binding(get: { draft.personID }, set: { id in
                        draft.personID = id
                        if let person = business.findPerson(id), !person.email.isEmpty { draft.contact = person.email }
                    })) {
                        Text(draft.contact.isEmpty ? "None" : draft.contact).tag(UUID?.none)
                        ForEach(candidates) { person in Text(person.name).tag(Optional(person.id)) }
                    }
                    .labelsHidden()
                }
                HStack(alignment: .bottom, spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        SectionLabel(text: "Value")
                        TextField("Value", value: $draft.value, format: .currency(code: Money.currencyCode).precision(.fractionLength(0)))
                            .textFieldStyle(.roundedBorder)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        SectionLabel(text: "Stage")
                        Picker("", selection: $draft.stage) {
                            ForEach(DealStage.allCases) { stage in Text(stage.title).tag(stage) }
                        }
                        .labelsHidden()
                    }
                }
                VStack(alignment: .leading, spacing: 3) {
                    SectionLabel(text: "Expected to close")
                    HStack {
                        Toggle("", isOn: Binding(get: { draft.closeDate != nil }, set: { on in
                            draft.closeDate = on ? Calendar.current.date(byAdding: .day, value: 30, to: Date()) : nil
                        }))
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .labelsHidden()
                        if let close = draft.closeDate {
                            DatePicker("", selection: Binding(get: { close }, set: { draft.closeDate = $0 }), displayedComponents: .date)
                                .labelsHidden()
                                .datePickerStyle(.compact)
                        }
                    }
                }
                field("Next step", text: $draft.nextStep)
                VStack(alignment: .leading, spacing: 3) {
                    SectionLabel(text: "Notes")
                    TextEditor(text: $draft.notes)
                        .font(.system(size: 12.5))
                        .scrollContentBackground(.hidden)
                        .padding(4)
                        .frame(height: 56)
                        .background(RoundedRectangle(cornerRadius: 6).fill(theme.well(scheme)))
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(theme.edge(scheme), lineWidth: 0.5))
                }
                Text(CRMNudge.text(lastTouch: business.lastTouch(draft), now: Date(), calendar: .current))
                    .font(.system(size: 11))
                    .foregroundStyle(theme.inkTertiary(scheme))

                FlowLayout(spacing: 6) {
                    Button("Draft follow-up") { business.draftFollowUp(draft) }
                        .buttonStyle(.vellumPrimary)
                        .disabled(brain.isBusy)
                    Button("Next step?") { business.adviseNextStep(draft) }
                        .buttonStyle(.vellumSecondary)
                        .disabled(brain.isBusy)
                    Button("Write a proposal") { business.writeProposal(draft) }
                        .buttonStyle(.vellumSecondary)
                    Button("Next step to Tasks") { business.nextStepAsTask(draft) }
                        .buttonStyle(.vellumSecondary)
                        .disabled(draft.nextStep.isEmpty)
                    Button("Delete") { withAnimation(theme.spring) { business.delete(draft.id) } }
                        .buttonStyle(.vellumSecondary)
                }

                if let run = business.advice[draft.id] {
                    Card { RunView(run: run) }
                }
                if let run = business.drafts[draft.id] {
                    FollowUp(run: run, deal: draft)
                }

                SectionLabel(text: "What's happened")
                    .padding(.top, 6)
                HStack(spacing: 6) {
                    TextField("Log a call or a note", text: $call)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(logCall)
                    Button("Log", action: logCall)
                        .buttonStyle(.vellumSecondary)
                        .disabled(call.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                ActivityList(activities: business.activities(for: business.deals.first(where: { $0.id == draft.id }) ?? draft), limit: 12)
            }
            .padding(14)
        }
        .scrollContentBackground(.hidden)
        .vellum(level: 3, radius: max(theme.radius - 2, 8))
        .onChange(of: draft) { _, newValue in business.update(newValue) }
    }

    /// People at the deal's company first, then everyone.
    private var candidates: [CRMPerson] {
        guard let company = draft.organisationID else { return business.people.sorted { $0.name < $1.name } }
        let here = business.people(at: company)
        return here + business.people.filter { $0.organisationID != company }.sorted { $0.name < $1.name }
    }

    private func logCall() {
        business.log(call, on: draft.id)
        call = ""
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

/// Emails, meetings and calls, newest first.
private struct ActivityList: View {
    @EnvironmentObject private var theme: Theme
    @Environment(\.colorScheme) private var scheme
    var activities: [CRMActivity]
    var limit: Int

    var body: some View {
        if activities.isEmpty {
            Text("Nothing yet. Emails with them and meetings they're invited to show here, from Mail and Calendar.")
                .font(.system(size: 11.5))
                .foregroundStyle(theme.inkTertiary(scheme))
                .fixedSize(horizontal: false, vertical: true)
        }
        ForEach(activities.prefix(limit)) { activity in
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: activity.kind.symbol)
                    .font(.system(size: 11))
                    .frame(width: 16)
                    .foregroundStyle(theme.inkSecondary(scheme))
                VStack(alignment: .leading, spacing: 2) {
                    Text(activity.title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(theme.ink(scheme))
                        .lineLimit(2)
                    if !activity.detail.isEmpty {
                        Text(activity.detail)
                            .font(.system(size: 11))
                            .foregroundStyle(theme.inkTertiary(scheme))
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 4)
                Text(activity.date.formatted(.relative(presentation: .named)))
                    .font(.system(size: 10.5))
                    .foregroundStyle(theme.inkTertiary(scheme))
                    .lineLimit(1)
                    .fixedSize()
            }
        }
    }
}

// MARK: - Deals as a list

private struct DealList: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var business: BusinessModel
    @Environment(\.colorScheme) private var scheme
    @State private var openOnly = true

    var body: some View {
        let shown = business.deals
            .filter { !openOnly || $0.stage.isOpen }
            .sorted { ($0.closeDate ?? .distantFuture, -$0.value) < ($1.closeDate ?? .distantFuture, -$1.value) }
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Toggle("Open deals only", isOn: $openOnly)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 12))
                HStack(spacing: 10) {
                    Text("Deal").frame(maxWidth: .infinity, alignment: .leading)
                    Text("Stage").frame(width: 70, alignment: .leading)
                    Text("Value").frame(width: 80, alignment: .trailing)
                    Text("Closes").frame(width: 70, alignment: .leading)
                    Text("Last touch").frame(width: 90, alignment: .leading)
                }
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(theme.inkTertiary(scheme))
                .padding(.horizontal, 10)
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(shown) { deal in
                            row(deal)
                        }
                    }
                }
            }
            if let deal = business.selected {
                DealDetail(deal: deal)
                    .id(deal.id)
                    .frame(width: 300)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
    }

    private func row(_ deal: Deal) -> some View {
        let selected = business.selectedID == deal.id
        let quiet = business.isQuiet(deal)
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(deal.name).font(.system(size: 12.5, weight: .medium)).lineLimit(1)
                Text(business.findOrganisation(deal.organisationID)?.name ?? deal.company)
                    .font(.system(size: 11))
                    .foregroundStyle(theme.inkTertiary(scheme))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(deal.stage.title).frame(width: 70, alignment: .leading)
            Text(Money.format(deal.value)).monospacedDigit().frame(width: 80, alignment: .trailing)
            Text(deal.closeDate.map { $0.formatted(.dateTime.day().month(.abbreviated)) } ?? "—").frame(width: 70, alignment: .leading)
            Text(CRMNudge.text(lastTouch: business.lastTouch(deal), now: Date(), calendar: .current).replacingOccurrences(of: "Last touch ", with: ""))
                .fontWeight(quiet ? .semibold : .regular)
                .lineLimit(1)
                .frame(width: 90, alignment: .leading)
        }
        .font(.system(size: 12))
        .foregroundStyle(theme.ink(scheme))
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(selected ? theme.raised(scheme) : Color.clear))
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(theme.spring) { business.selectedID = selected ? nil : deal.id } }
    }
}

// MARK: - People

private struct PeopleList: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var business: BusinessModel
    @Environment(\.colorScheme) private var scheme
    @State private var search = ""

    var body: some View {
        let shown = business.people
            .filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || $0.email.localizedCaseInsensitiveContains(search) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                TextField("Search people", text: $search)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 260)
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(shown) { person in
                            let selected = business.selectedPersonID == person.id
                            HStack(spacing: 10) {
                                Text(initials(person.name))
                                    .font(.system(size: 10.5, weight: .semibold))
                                    .frame(width: 26, height: 26)
                                    .background(Circle().fill(theme.well(scheme)))
                                    .overlay(Circle().strokeBorder(theme.edge(scheme), lineWidth: 0.5))
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(person.name).font(.system(size: 12.5, weight: .medium))
                                    Text([person.title, business.findOrganisation(person.organisationID)?.name ?? ""].filter { !$0.isEmpty }.joined(separator: " · "))
                                        .font(.system(size: 11))
                                        .foregroundStyle(theme.inkTertiary(scheme))
                                }
                                Spacer()
                                Text(person.email)
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(theme.inkSecondary(scheme))
                                    .lineLimit(1)
                            }
                            .foregroundStyle(theme.ink(scheme))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(selected ? theme.raised(scheme) : Color.clear))
                            .contentShape(Rectangle())
                            .onTapGesture { withAnimation(theme.spring) { business.selectedPersonID = selected ? nil : person.id } }
                        }
                        if shown.isEmpty {
                            Text(business.people.isEmpty ? "No one yet. The button with the person and plus finds the people you write to in your mail." : "No one matches that.")
                                .font(.system(size: 12.5))
                                .foregroundStyle(theme.inkTertiary(scheme))
                                .padding(10)
                        }
                    }
                }
            }
            if let person = business.findPerson(business.selectedPersonID) {
                PersonDetail(person: person)
                    .id(person.id)
                    .frame(width: 300)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
    }
}

func initials(_ name: String) -> String {
    let parts = name.split(separator: " ").prefix(2)
    return parts.compactMap { $0.first.map(String.init) }.joined().uppercased()
}

private struct PersonDetail: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var business: BusinessModel
    @Environment(\.colorScheme) private var scheme
    @State private var draft: CRMPerson

    init(person: CRMPerson) {
        _draft = State(initialValue: person)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(draft.name).font(.system(size: 16, weight: .semibold))
                    Spacer()
                    Button { withAnimation(theme.spring) { business.selectedPersonID = nil } } label: {
                        Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(theme.inkTertiary(scheme))
                }
                .foregroundStyle(theme.ink(scheme))
                field("Name", $draft.name)
                field("Email", $draft.email)
                field("Title", $draft.title)
                field("Phone", $draft.phone)
                VStack(alignment: .leading, spacing: 3) {
                    SectionLabel(text: "Company")
                    Picker("", selection: $draft.organisationID) {
                        Text("None").tag(UUID?.none)
                        ForEach(business.organisations) { company in Text(company.name).tag(Optional(company.id)) }
                    }
                    .labelsHidden()
                }
                field("Notes", $draft.notes)
                let deals = business.deals(with: draft.id)
                if !deals.isEmpty {
                    SectionLabel(text: "Deals")
                    ForEach(deals) { deal in
                        Button("\(deal.name) · \(deal.stage.title) · \(Money.format(deal.value))") {
                            business.selectedID = deal.id
                            business.tab = .pipeline
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 12))
                        .foregroundStyle(theme.ink(scheme))
                    }
                }
                SectionLabel(text: "What's happened").padding(.top, 4)
                ActivityList(activities: business.activities(forPerson: draft), limit: 10)
                Button("Delete \(draft.name)", role: .destructive) { business.deletePerson(draft.id) }
                    .buttonStyle(.vellumSecondary)
                    .padding(.top, 6)
            }
            .padding(14)
        }
        .vellum(level: 3, radius: max(theme.radius - 2, 8))
        .onChange(of: draft) { _, newValue in business.updatePerson(newValue) }
    }

    private func field(_ label: String, _ text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            SectionLabel(text: label)
            TextField(label, text: text).textFieldStyle(.roundedBorder)
        }
    }
}

// MARK: - Companies

private struct CompanyList: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var business: BusinessModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let shown = business.organisations.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        HStack(alignment: .top, spacing: 12) {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 10)], spacing: 10) {
                    ForEach(shown) { company in
                        let selected = business.selectedOrganisationID == company.id
                        let open = business.deals(for: company.id).filter { $0.stage.isOpen }
                        VStack(alignment: .leading, spacing: 5) {
                            Text(company.name).font(.system(size: 14, weight: .semibold))
                            Text(company.domain ?? "No domain")
                                .font(.system(size: 11.5))
                                .foregroundStyle(theme.inkTertiary(scheme))
                            HStack(spacing: 10) {
                                Label("\(business.people(at: company.id).count)", systemImage: "person.2")
                                Label(open.isEmpty ? "No open deals" : Money.short(open.reduce(0) { $0 + $1.value }), systemImage: "briefcase")
                            }
                            .font(.system(size: 11.5))
                            .foregroundStyle(theme.inkSecondary(scheme))
                        }
                        .foregroundStyle(theme.ink(scheme))
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(selected ? theme.raised(scheme) : theme.well(scheme)))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(selected ? theme.ink(scheme).opacity(0.4) : theme.edge(scheme), lineWidth: selected ? 1 : 0.5))
                        .contentShape(Rectangle())
                        .onTapGesture { withAnimation(theme.spring) { business.selectedOrganisationID = selected ? nil : company.id } }
                    }
                }
            }
            if let company = business.findOrganisation(business.selectedOrganisationID) {
                CompanyDetail(company: company)
                    .id(company.id)
                    .frame(width: 300)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
    }
}

private struct CompanyDetail: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var business: BusinessModel
    @Environment(\.colorScheme) private var scheme
    @State private var draft: CRMOrganisation

    init(company: CRMOrganisation) {
        _draft = State(initialValue: company)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(draft.name).font(.system(size: 16, weight: .semibold))
                    Spacer()
                    Button { withAnimation(theme.spring) { business.selectedOrganisationID = nil } } label: {
                        Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(theme.inkTertiary(scheme))
                }
                .foregroundStyle(theme.ink(scheme))
                VStack(alignment: .leading, spacing: 3) {
                    SectionLabel(text: "Name")
                    TextField("Name", text: $draft.name).textFieldStyle(.roundedBorder)
                }
                VStack(alignment: .leading, spacing: 3) {
                    SectionLabel(text: "Domain")
                    TextField("acme.com", text: Binding(get: { draft.domain ?? "" }, set: { draft.domain = $0.isEmpty ? nil : $0.lowercased() }))
                        .textFieldStyle(.roundedBorder)
                }
                VStack(alignment: .leading, spacing: 3) {
                    SectionLabel(text: "Notes")
                    TextField("Notes", text: $draft.notes, axis: .vertical).textFieldStyle(.roundedBorder).lineLimit(2...5)
                }
                let people = business.people(at: draft.id)
                SectionLabel(text: "People · \(people.count)")
                ForEach(people) { person in
                    Button("\(person.name)\(person.title.isEmpty ? "" : " · " + person.title)") {
                        business.selectedPersonID = person.id
                        business.tab = .people
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(theme.ink(scheme))
                }
                let deals = business.deals(for: draft.id)
                HStack {
                    SectionLabel(text: "Deals · \(deals.count)")
                    Spacer()
                    Button("New deal") { business.newDeal(for: draft.id) }
                        .buttonStyle(.borderless)
                        .font(.system(size: 11.5, weight: .medium))
                }
                ForEach(deals) { deal in
                    Button("\(deal.name) · \(deal.stage.title) · \(Money.format(deal.value))") {
                        business.selectedID = deal.id
                        business.tab = .pipeline
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(theme.ink(scheme))
                }
                SectionLabel(text: "What's happened").padding(.top, 4)
                ActivityList(activities: business.activities(forOrganisation: draft), limit: 12)
                Button("Delete \(draft.name)", role: .destructive) { business.deleteOrganisation(draft.id) }
                    .buttonStyle(.vellumSecondary)
                    .padding(.top, 6)
            }
            .padding(14)
        }
        .vellum(level: 3, radius: max(theme.radius - 2, 8))
        .onChange(of: draft) { _, newValue in business.updateOrganisation(newValue) }
    }
}

// MARK: - Forecast

private struct ForecastView: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var business: BusinessModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let months = business.forecast
        let largest = max(months.map(\.total).max() ?? 1, 1)
        let undated = business.deals.filter { $0.stage.isOpen && $0.closeDate == nil }
        VStack(alignment: .leading, spacing: 14) {
            Text("Open deals by the month they're expected to close. The dark bar is weighted by stage (a lead counts 10%, talking 30%, a proposal 60%); the outline is the full value.")
                .font(.system(size: 12.5))
                .foregroundStyle(theme.inkSecondary(scheme))
                .fixedSize(horizontal: false, vertical: true)
            if months.isEmpty {
                Text("No open deals have a close date yet. Set one in a deal's details.")
                    .font(.system(size: 13))
                    .foregroundStyle(theme.inkTertiary(scheme))
            }
            HStack(alignment: .bottom, spacing: 18) {
                ForEach(months, id: \.month) { month in
                    VStack(spacing: 6) {
                        Text(Money.short(month.weighted))
                            .font(.system(size: 12, weight: .semibold).monospacedDigit())
                        ZStack(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(theme.ink(scheme).opacity(0.35), lineWidth: 1)
                                .frame(height: 200 * month.total / largest)
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(theme.ink(scheme).opacity(0.85))
                                .frame(height: max(2, 200 * month.weighted / largest))
                        }
                        .frame(width: 54, height: 200, alignment: .bottom)
                        Text(month.month.formatted(.dateTime.month(.abbreviated).year()))
                            .font(.system(size: 11.5, weight: .medium))
                        Text("\(month.count) deal\(month.count == 1 ? "" : "s") · \(Money.short(month.total))")
                            .font(.system(size: 10.5))
                            .foregroundStyle(theme.inkTertiary(scheme))
                    }
                    .foregroundStyle(theme.ink(scheme))
                }
            }
            .padding(.vertical, 8)
            if !undated.isEmpty {
                Text("Not dated: " + undated.map(\.name).joined(separator: ", "))
                    .font(.system(size: 12))
                    .foregroundStyle(theme.inkTertiary(scheme))
            }
            Spacer()
        }
    }
}
