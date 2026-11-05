import SwiftUI

/// Who wrote this email, from Conner's side: their company, open deals, what's coming up, and a way into Business.
struct MailPersonCard: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var business: BusinessModel
    @EnvironmentObject private var calendar: CalendarModel
    @EnvironmentObject private var theme: Theme
    @Environment(\.colorScheme) private var scheme
    var address: String
    var name: String

    var body: some View {
        let known = business.person(forAddress: address)
        let company = business.organisation(forAddress: address)
        let deals = business.openDeals(forAddress: address)
        let wanted = CRMMatch.address(address)
        let meetings = calendar.events
            .filter { event in event.end > Date() && event.attendees.contains { CRMMatch.address($0.email) == wanted } }
            .prefix(3)
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text(initials(known?.name ?? name))
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(theme.well(scheme)))
                    .overlay(Circle().strokeBorder(theme.edge(scheme), lineWidth: 0.5))
                VStack(alignment: .leading, spacing: 2) {
                    Text(known?.name ?? name)
                        .font(.system(size: 14, weight: .semibold))
                    let line = [known?.title ?? "", company?.name ?? ""].filter { !$0.isEmpty }.joined(separator: " · ")
                    Text(line.isEmpty ? wanted : line)
                        .font(.system(size: 11.5))
                        .foregroundStyle(theme.inkSecondary(scheme))
                }
            }
            .foregroundStyle(theme.ink(scheme))
            if !deals.isEmpty {
                SectionLabel(text: "Open deals")
                ForEach(deals) { deal in
                    Button {
                        business.selectedID = deal.id
                        business.tab = .pipeline
                        model.go(to: .business)
                    } label: {
                        HStack {
                            Text(deal.name).fontWeight(.medium)
                            Spacer()
                            Text("\(deal.stage.title) · \(Money.format(deal.value))")
                                .foregroundStyle(theme.inkSecondary(scheme))
                        }
                        .font(.system(size: 12))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(theme.ink(scheme))
                }
            }
            if !meetings.isEmpty {
                SectionLabel(text: "Coming up")
                ForEach(Array(meetings), id: \.id) { event in
                    Text(event.start.formatted(.dateTime.weekday(.abbreviated).day().hour().minute()) + " · " + event.title)
                        .font(.system(size: 12))
                        .foregroundStyle(theme.ink(scheme))
                        .lineLimit(1)
                }
            }
            if let known {
                Button("Open in Business") {
                    business.selectedPersonID = known.id
                    business.tab = .people
                    model.go(to: .business)
                }
                .buttonStyle(.vellumSecondary)
            } else {
                Button("Add to Business") { business.addPerson(name: name, email: address) }
                    .buttonStyle(.vellumPrimary)
            }
        }
        .padding(14)
        .frame(width: 290, alignment: .leading)
    }
}

/// The small person button beside a sender's address.
struct PersonCardButton: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var business: BusinessModel
    @EnvironmentObject private var calendar: CalendarModel
    @EnvironmentObject private var theme: Theme
    @Environment(\.colorScheme) private var scheme
    var address: String
    var name: String
    @State private var showing = false

    var body: some View {
        let deals = business.openDeals(forAddress: address).count
        Button {
            showing = true
        } label: {
            HStack(spacing: 3) {
                Image(systemName: business.person(forAddress: address) == nil ? "person.crop.circle.badge.plus" : "person.crop.circle")
                if deals > 0 { Text("\(deals)").font(.system(size: 10.5, weight: .semibold)) }
            }
            .font(.system(size: 12))
            .foregroundStyle(theme.inkSecondary(scheme))
        }
        .buttonStyle(.plain)
        .help(deals > 0 ? "\(deals) open deal\(deals == 1 ? "" : "s") with them" : "Who this is, from Business")
        .popover(isPresented: $showing, arrowEdge: .bottom) {
            MailPersonCard(address: address, name: name)
                .environmentObject(model)
                .environmentObject(business)
                .environmentObject(calendar)
                .environmentObject(theme)
        }
    }
}
