import AppKit
import SwiftUI

/// What's in the selected event, floating over the week: join, who's coming, your answer, clashes and Leo's prep.
struct EventCard: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var calendar: CalendarModel
    @Environment(\.colorScheme) private var scheme
    var event: CalEvent

    var body: some View {
        ViewThatFits(in: .vertical) {
            content
            ScrollView(showsIndicators: false) { content }
        }
        .vellum(level: 1, radius: max(theme.radius - 2, 8), blending: .withinWindow)
    }

    private var content: some View {
        let tint = Color(calendarHex: event.color)
        let owner = calendar.calendar(for: event)
        let clashes = event.isAllDay ? [] : calendar.conflicts(for: event)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(tint)
                    .frame(width: 3, height: 36)
                VStack(alignment: .leading, spacing: 3) {
                    Text(event.title)
                        .font(theme.display(19))
                        .foregroundStyle(theme.ink(scheme))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(CalText.when(event))
                        .font(.system(size: 12))
                        .foregroundStyle(theme.inkSecondary(scheme))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                Button {
                    calendar.selectedID = nil
                } label: {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(theme.inkTertiary(scheme))
                .help("Close · esc")
            }

            HStack(spacing: 6) {
                Circle().fill(tint).frame(width: 7, height: 7)
                Text([owner?.title, owner?.account].compactMap { $0 }.joined(separator: " · "))
                    .lineLimit(1)
                if event.isRecurring {
                    Image(systemName: "repeat").help("Repeats")
                }
                if !event.writable && !event.isHoliday {
                    Image(systemName: "lock").help("Read-only")
                }
            }
            .font(.system(size: 11.5))
            .foregroundStyle(theme.inkTertiary(scheme))

            if let join = event.joinURL {
                Button {
                    NSWorkspace.shared.open(join)
                } label: {
                    Label("Join \(JoinLinks.service(join))", systemImage: "video.fill")
                }
                .buttonStyle(.vellumPrimary)
            }

            if let place = place {
                Button {
                    if let url = URL(string: "http://maps.apple.com/?q=\(place.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? place)") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Label(place, systemImage: "mappin.and.ellipse")
                        .font(.system(size: 12.5))
                        .lineLimit(2)
                }
                .buttonStyle(.plain)
                .foregroundStyle(theme.ink(scheme))
                .help("Open in Maps")
            }

            if !clashes.isEmpty {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle")
                    Text("Clashes with \(clashes.map { "\($0.title) (\(CalText.time($0.start)))" }.joined(separator: ", "))")
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.system(size: 12))
                .foregroundStyle(theme.ink(scheme))
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    RoundedRectangle(cornerRadius: 7, style: .continuous).fill(theme.ink(scheme).opacity(0.06))
                }
            }

            if !event.attendees.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    SectionLabel(text: event.attendees.count == 1 ? "With" : "\(event.attendees.count) people")
                    ForEach(Array(event.attendees.prefix(8)), id: \.email) { person in
                        HStack(spacing: 6) {
                            Image(systemName: EventCard.symbol(person.response))
                                .font(.system(size: 10.5))
                                .foregroundStyle(theme.inkSecondary(scheme))
                                .frame(width: 14)
                            Text(person.name)
                                .font(.system(size: 12.5))
                                .foregroundStyle(theme.ink(scheme))
                                .lineLimit(1)
                            if person.email == event.organizer {
                                Text("organiser").font(.system(size: 11)).foregroundStyle(theme.inkTertiary(scheme))
                            }
                        }
                        .help(person.email)
                    }
                    if event.attendees.count > 8 {
                        Text("and \(event.attendees.count - 8) more")
                            .font(.system(size: 11.5))
                            .foregroundStyle(theme.inkTertiary(scheme))
                    }
                }
            }

            if event.response != .organizer && !event.attendees.isEmpty && !event.isHoliday {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text("Going?")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(theme.inkSecondary(scheme))
                        ForEach([CalResponse.accepted, .tentative, .declined], id: \.self) { answer in
                            Button(EventCard.word(answer)) { calendar.respond(event, answer) }
                                .buttonStyle(VellumButtonStyle(kind: event.response == answer ? .primary : .secondary))
                        }
                    }
                    if event.isOnThisMac {
                        Text("Opens in Calendar, which answers the organiser for you.")
                            .font(.system(size: 11))
                            .foregroundStyle(theme.inkTertiary(scheme))
                    }
                }
            }

            if let notes = notes {
                Text(notes)
                    .font(.system(size: 12))
                    .foregroundStyle(theme.inkSecondary(scheme))
                    .lineLimit(6)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !event.attendees.isEmpty || event.notes != nil {
                PrepSection(event: event)
            }

            HStack(spacing: 8) {
                if event.writable {
                    Button("Edit") { calendar.edit(event) }
                        .buttonStyle(.vellumSecondary)
                        .help("Edit · ↩")
                    Button {
                        calendar.pendingDelete = event
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.vellumSecondary)
                    .help("Delete · ⌫")
                }
                if event.isOnThisMac {
                    Button("Open in Calendar") { calendar.openInCalendar(event) }
                        .buttonStyle(.vellumSecondary)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The location, unless it's only the video link.
    private var place: String? {
        guard let location = event.location?.trimmingCharacters(in: .whitespacesAndNewlines), !location.isEmpty else { return nil }
        if JoinLinks.find(in: location) != nil, !location.contains(" ") { return nil }
        return location
    }

    private var notes: String? {
        guard let notes = event.notes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty else { return nil }
        return notes
    }

    static func symbol(_ response: CalResponse) -> String {
        switch response {
        case .accepted, .organizer: return "checkmark.circle.fill"
        case .tentative: return "questionmark.circle"
        case .declined: return "xmark.circle"
        case .none: return "circle"
        }
    }

    static func word(_ response: CalResponse) -> String {
        switch response {
        case .accepted: return "Yes"
        case .tentative: return "Maybe"
        case .declined: return "No"
        default: return ""
        }
    }
}

/// Your recent mail with the people coming (from Marc), and a short prep note from Leo.
private struct PrepSection: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var calendar: CalendarModel
    @Environment(\.colorScheme) private var scheme
    var event: CalEvent

    var body: some View {
        let mails = calendar.recentMail(for: event)
        let run = calendar.prepRuns[event.id]
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                SectionLabel(text: "Prep")
                Spacer()
                Button(run == nil ? "Prep me" : "Again") { calendar.prep(event) }
                    .buttonStyle(.vellumSecondary)
                    .help("Leo writes a few lines: who it's with, what they last said, what to bring")
            }
            ForEach(Array(mails.prefix(3))) { message in
                HStack(spacing: 6) {
                    AgentLogo(code: "mc", size: 13, color: theme.inkTertiary(scheme))
                    Text("\(message.fromName): \(message.subject)")
                        .font(.system(size: 11.5))
                        .foregroundStyle(theme.inkSecondary(scheme))
                        .lineLimit(1)
                }
                .help(message.date.formatted(date: .abbreviated, time: .shortened))
            }
            if let run {
                RunView(run: run)
            } else if mails.isEmpty {
                Text("No recent mail with them. Leo can still pull the details together.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(theme.inkTertiary(scheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous).fill(theme.well(scheme))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(theme.edge(scheme), lineWidth: 0.5)
        }
    }
}

/// New or edited event. All-day events show their last day; they're stored ending at the next midnight.
struct EventEditor: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var calendar: CalendarModel
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss
    @State private var draft: EventDraft
    @State private var lastDay: Date

    init(draft: EventDraft) {
        _draft = State(initialValue: draft)
        let last = draft.isAllDay ? (Calendar.current.date(byAdding: .day, value: -1, to: draft.end) ?? draft.start) : draft.start
        _lastDay = State(initialValue: max(last, draft.start))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(draft.eventID == nil ? "New event" : "Edit event")
                .font(theme.display(24))
                .foregroundStyle(theme.ink(scheme))

            TextField("Title", text: $draft.title)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 14))

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    Text("All day").gridColumnAlignment(.trailing)
                    Toggle("", isOn: allDay).labelsHidden().toggleStyle(.switch).controlSize(.small)
                }
                if draft.isAllDay {
                    GridRow {
                        Text("From")
                        DatePicker("", selection: $draft.start, displayedComponents: .date).labelsHidden()
                    }
                    GridRow {
                        Text("To")
                        DatePicker("", selection: $lastDay, in: draft.start..., displayedComponents: .date).labelsHidden()
                    }
                } else {
                    GridRow {
                        Text("Starts")
                        DatePicker("", selection: start, displayedComponents: [.date, .hourAndMinute]).labelsHidden()
                    }
                    GridRow {
                        Text("Ends")
                        DatePicker("", selection: $draft.end, in: draft.start..., displayedComponents: [.date, .hourAndMinute]).labelsHidden()
                    }
                }
                GridRow {
                    Text("Calendar")
                    Picker("", selection: $draft.calendarID) {
                        ForEach(choices) { item in
                            Text(item.account.isEmpty ? item.title : "\(item.title) · \(item.account)").tag(item.id)
                        }
                    }
                    .labelsHidden()
                    .disabled(draft.eventID != nil && draft.calendarID.hasPrefix("ms:"))
                }
                GridRow {
                    Text("Where")
                    TextField("A place or a video link", text: $draft.location).textFieldStyle(.roundedBorder)
                }
                GridRow(alignment: .top) {
                    Text("Notes").padding(.top, 4)
                    TextEditor(text: $draft.notes)
                        .font(.system(size: 12.5))
                        .scrollContentBackground(.hidden)
                        .padding(4)
                        .frame(height: 74)
                        .background {
                            RoundedRectangle(cornerRadius: 6, style: .continuous).fill(theme.well(scheme))
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(theme.edge(scheme), lineWidth: 0.5)
                        }
                }
            }
            .font(.system(size: 12.5))
            .foregroundStyle(theme.ink(scheme))

            HStack(spacing: 8) {
                Spacer()
                Button("Cancel") { close() }
                    .buttonStyle(.vellumSecondary)
                    .keyboardShortcut(.cancelAction)
                Button(draft.eventID == nil ? "Add" : "Save") { save() }
                    .buttonStyle(.vellumPrimary)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 440)
    }

    private var choices: [CalCalendar] {
        calendar.calendars.filter { $0.writable && (!calendar.hidden.contains($0.id) || $0.id == draft.calendarID) }
    }

    /// Moving the start keeps the length.
    private var start: Binding<Date> {
        Binding(get: { draft.start }, set: { value in
            let length = max(draft.end.timeIntervalSince(draft.start), 900)
            draft.start = value
            draft.end = value.addingTimeInterval(length)
        })
    }

    private var allDay: Binding<Bool> {
        Binding(get: { draft.isAllDay }, set: { value in
            let day = Calendar.current.startOfDay(for: draft.start)
            draft.isAllDay = value
            if value {
                draft.start = day
                lastDay = day
            } else {
                draft.start = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: day) ?? day
                draft.end = draft.start.addingTimeInterval(3_600)
            }
        })
    }

    private func save() {
        var saved = draft
        if saved.isAllDay {
            let first = Calendar.current.startOfDay(for: saved.start)
            let last = Calendar.current.startOfDay(for: max(lastDay, first))
            saved.start = first
            saved.end = Calendar.current.date(byAdding: .day, value: 1, to: last) ?? last.addingTimeInterval(86_400)
        }
        saved.title = saved.title.trimmingCharacters(in: .whitespacesAndNewlines)
        calendar.save(saved)
        close()
    }

    private func close() {
        calendar.editor = nil
        dismiss()
    }
}
