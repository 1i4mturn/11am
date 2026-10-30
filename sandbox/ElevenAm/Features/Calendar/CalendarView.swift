import AppKit
import SwiftUI

/// Leo's app: every calendar in one week, quick add in plain words, free time on tap and prep for each meeting.
struct CalendarView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var calendar: CalendarModel
    @EnvironmentObject private var mail: MailModel
    @EnvironmentObject private var brain: Brain
    @Environment(\.colorScheme) private var scheme
    @State private var quickText = ""
    @State private var findingTime = false
    @State private var choosingCalendars = false
    @State private var keyMonitor: Any?
    /// How far down the grid the hours start, so the event card sits below the day names and all-day events.
    @State private var gridTop: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "calendar", subtitle: subtitle) {
                HStack(spacing: 8) {
                    if calendar.isLoading {
                        ProgressView().controlSize(.small)
                    }
                    QuickAddField(text: $quickText) {
                        if calendar.quickAdd(quickText) { quickText = "" }
                    }
                    .frame(minWidth: 150, idealWidth: 240, maxWidth: 260)
                    Button {
                        findingTime = true
                    } label: {
                        Image(systemName: "clock.badge.checkmark")
                    }
                    .buttonStyle(.vellumSecondary)
                    .help("Find a time")
                    .popover(isPresented: $findingTime, arrowEdge: .bottom) {
                        FindTimeView { findingTime = false }
                            .withCalendarEnvironment(calendar, theme: theme)
                    }
                    Button {
                        choosingCalendars = true
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                    .buttonStyle(.vellumSecondary)
                    .help("Choose calendars")
                    .popover(isPresented: $choosingCalendars, arrowEdge: .bottom) {
                        CalendarsView()
                            .withCalendarEnvironment(calendar, theme: theme)
                    }
                    Button {
                        calendar.newEvent(at: CalendarView.suggestedStart(for: calendar))
                    } label: {
                        Label("New event", systemImage: "plus")
                    }
                    .buttonStyle(.vellumPrimary)
                    .keyboardShortcut("n", modifiers: [.command, .shift])
                }
            }

            CalendarToolbar()

            if calendar.isSample {
                ConnectBanner()
                    .transition(.rise(theme.rise))
            }
            ForEach(calendar.needsMicrosoftConsent) { account in
                CalendarBanner(text: "Leo needs your OK to read the Outlook calendar for \(account.address).", symbol: "lock", actions: {
                    Button("Allow") { Task { await calendar.connect(account) } }
                        .buttonStyle(.vellumPrimary)
                })
            }
            if let notice = calendar.notice {
                CalendarBanner(text: notice, symbol: "info.circle", dismiss: { calendar.notice = nil }, actions: { EmptyView() })
                    .transition(.rise(theme.rise))
            }

            ZStack(alignment: cardOnLeft ? .topLeading : .topTrailing) {
                grid
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background {
                        RoundedRectangle(cornerRadius: max(theme.radius - 4, 8), style: .continuous)
                            .fill(theme.well(scheme).opacity(0.45))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: max(theme.radius - 4, 8), style: .continuous)
                            .strokeBorder(theme.edge(scheme), lineWidth: 0.5)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: max(theme.radius - 4, 8), style: .continuous))
                if let event = calendar.selected {
                    EventCard(event: event)
                        .frame(width: 292)
                        .padding(.top, gridTop + 8)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 12)
                        .id(event.id)
                        .transition(.rise(theme.rise))
                }
            }
            .onPreferenceChange(GridTopKey.self) { gridTop = $0 }
        }
        .padding(24)
        .animation(theme.spring, value: calendar.notice)
        .animation(theme.spring, value: calendar.selectedID)
        .animation(theme.spring, value: calendar.isSample)
        .sheet(item: $calendar.editor) { draft in
            EventEditor(draft: draft)
                .withCalendarEnvironment(calendar, theme: theme)
        }
        .confirmationDialog(deleteTitle, isPresented: deleting, presenting: calendar.pendingDelete) { event in
            Button("Delete", role: .destructive) { calendar.delete(event) }
            Button("Cancel", role: .cancel) {}
        } message: { event in
            Text(event.attendees.isEmpty ? "It comes off every device that syncs this calendar." : "If you organised it, the people invited are told it's cancelled.")
        }
        // Notices clear themselves after a while.
        .task(id: calendar.notice) {
            guard calendar.notice != nil, (try? await Task.sleep(for: .seconds(9))) != nil else { return }
            calendar.notice = nil
        }
        // Picks up changes made elsewhere, such as an invitation accepted on your phone.
        .task {
            while (try? await Task.sleep(for: .seconds(300))) != nil {
                calendar.reload()
            }
        }
        .onAppear {
            calendar.reload()
            installKeys()
        }
        .onDisappear { removeKeys() }
    }

    @ViewBuilder private var grid: some View {
        switch calendar.mode {
        case .day, .threeDay, .week: TimeGrid(days: calendar.days)
        case .month: MonthGrid()
        case .agenda: AgendaList()
        }
    }

    /// The event card floats over the side of the week the event isn't on.
    private var cardOnLeft: Bool {
        guard let event = calendar.selected, [.week, .threeDay, .month].contains(calendar.mode) else { return false }
        let days = calendar.days
        guard let index = days.firstIndex(where: { Calendar.current.isDate($0, inSameDayAs: event.start) }) else { return false }
        let columns = calendar.mode == .month ? 7 : days.count
        return Double(index % columns) >= Double(columns) / 2
    }

    private var subtitle: String {
        if calendar.isSample { return "A sample week, until your calendars are connected" }
        let today = calendar.events(on: Date()).filter { !$0.isAllDay && $0.response != .declined }
        if let next = today.first(where: { $0.end > Date() }) {
            return "\(today.count) today · next, \(next.title) at \(CalText.time(next.start))"
        }
        return today.isEmpty ? "Nothing booked today" : "Today's done · \(today.count) \(today.count == 1 ? "event" : "events")"
    }

    private var deleting: Binding<Bool> {
        Binding(get: { calendar.pendingDelete != nil }, set: { if !$0 { calendar.pendingDelete = nil } })
    }

    private var deleteTitle: String {
        "Delete \u{201C}\(calendar.pendingDelete?.title ?? "event")\u{201D}?"
    }

    /// The next half hour if this week is showing, otherwise 9 am on the day you're looking at.
    static func suggestedStart(for calendar: CalendarModel) -> Date {
        if calendar.visibleRange.contains(Date()) { return FreeTime.roundUp(Date(), minutes: 30) }
        let day = Calendar.current.startOfDay(for: calendar.visibleRange.start)
        return Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: day) ?? day
    }

    /// t today, ← → move, d 3 w m a change the view, n new event, ↩ edit, ⌫ delete, esc closes the card.
    /// Only while Calendar is on screen in the main window, and never while you're typing.
    private func installKeys() {
        guard keyMonitor == nil else { return }
        let model = calendar
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let key = event.charactersIgnoringModifiers ?? ""
            let code = event.keyCode
            let plain = event.modifierFlags.intersection([.command, .control, .option]).isEmpty
            let handled = MainActor.assumeIsolated { () -> Bool in
                guard plain, let window = NSApp.keyWindow, window === NSApp.mainWindow, window.attachedSheet == nil,
                      !(window.firstResponder is NSText) else { return false }
                return CalendarView.handle(key: key, code: code, model: model)
            }
            return handled ? nil : event
        }
    }

    private static func handle(key: String, code: UInt16, model: CalendarModel) -> Bool {
        switch code {
        case 123:
            model.go(-1)
            return true
        case 124:
            model.go(1)
            return true
        case 53:
            guard model.selectedID != nil else { return false }
            model.selectedID = nil
            return true
        case 36:
            guard let event = model.selected, event.writable else { return false }
            model.edit(event)
            return true
        case 51, 117:
            guard let event = model.selected, event.writable else { return false }
            model.pendingDelete = event
            return true
        default:
            break
        }
        switch key {
        case "t": model.goToday()
        case "d": model.mode = .day
        case "3": model.mode = .threeDay
        case "w": model.mode = .week
        case "m": model.mode = .month
        case "a": model.mode = .agenda
        case "n": model.newEvent(at: suggestedStart(for: model))
        default: return false
        }
        return true
    }

    private func removeKeys() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }
}

extension View {
    /// Sheets and popovers don't inherit environment objects on every macOS version; pass the ones Calendar needs.
    func withCalendarEnvironment(_ calendar: CalendarModel, theme: Theme) -> some View {
        environmentObject(calendar).environmentObject(theme)
    }
}

extension Color {
    /// A calendar's own colour, from "#RRGGBB".
    init(calendarHex hex: String) {
        let digits = hex.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
        let value = UInt64(digits, radix: 16) ?? 0x7A7A7A
        self.init(red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255, blue: Double(value & 0xFF) / 255)
    }
}

enum CalText {
    static func time(_ date: Date) -> String { date.formatted(date: .omitted, time: .shortened) }

    /// "9 am", or "9:30 am".
    static func compact(_ date: Date) -> String {
        Calendar.current.component(.minute, from: date) == 0 ? date.formatted(.dateTime.hour()) : date.formatted(.dateTime.hour().minute())
    }

    static func range(_ event: CalEvent) -> String {
        event.isAllDay ? "All day" : "\(time(event.start)) – \(time(event.end))"
    }

    /// "Tue 3 Nov · 10:00 – 11:00 am" or "Fri 6 Nov · all day".
    static func when(_ event: CalEvent) -> String {
        let day = event.start.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        if event.isAllDay {
            let last = event.end.addingTimeInterval(-1)
            if Calendar.current.isDate(event.start, inSameDayAs: last) { return "\(day) · all day" }
            return "\(day) – \(last.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))"
        }
        if !Calendar.current.isDate(event.start, inSameDayAs: event.end) {
            return "\(day), \(time(event.start)) – \(event.end.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute()))"
        }
        let minutes = Int(event.duration / 60)
        let length = minutes < 60 ? "\(minutes) min" : (minutes % 60 == 0 ? "\(minutes / 60) h" : "\(minutes / 60) h \(minutes % 60) min")
        return "\(day) · \(time(event.start)) – \(time(event.end)) · \(length)"
    }
}

// MARK: Header pieces

private struct QuickAddField: View {
    @EnvironmentObject private var theme: Theme
    @Environment(\.colorScheme) private var scheme
    @Binding var text: String
    var onSubmit: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "calendar.badge.plus")
                .font(.system(size: 11.5))
                .foregroundStyle(theme.inkTertiary(scheme))
            TextField("Lunch Fri 1pm at Lune", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .onSubmit(onSubmit)
            if !text.isEmpty {
                Button(action: onSubmit) { Image(systemName: "return") }
                    .buttonStyle(.plain)
                    .foregroundStyle(theme.inkSecondary(scheme))
                    .help("Add it")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background { Capsule().fill(theme.well(scheme)) }
        .overlay { Capsule().strokeBorder(theme.edge(scheme), lineWidth: 0.5) }
        .help("Type an event in plain words: \"Dentist tomorrow 9:30 for 45 min\", \"Mum's birthday 12 Dec\".")
    }
}

private struct CalendarToolbar: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var calendar: CalendarModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 8) {
            Button("Today") { withAnimation(theme.spring) { calendar.goToday() } }
                .buttonStyle(.vellumSecondary)
                .help("Go to today · T")
            HStack(spacing: 4) {
                Button { calendar.go(-1) } label: { Image(systemName: "chevron.left") }
                    .help("Back · ←")
                Button { calendar.go(1) } label: { Image(systemName: "chevron.right") }
                    .help("Forward · →")
            }
            .buttonStyle(.vellumSecondary)
            Text(calendar.title)
                .font(theme.display(19))
                .foregroundStyle(theme.ink(scheme))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .padding(.leading, 4)
            Spacer(minLength: 8)
            ModeBar()
        }
    }
}

private struct ModeBar: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var calendar: CalendarModel
    @Environment(\.colorScheme) private var scheme
    @Namespace private var highlight

    var body: some View {
        HStack(spacing: 2) {
            ForEach(CalendarMode.allCases) { mode in
                let selected = calendar.mode == mode
                Button {
                    withAnimation(theme.spring) { calendar.mode = mode }
                } label: {
                    Text(mode.title)
                        .font(.system(size: 12, weight: .semibold))
                        .fixedSize()
                        .foregroundStyle(selected ? theme.paper(scheme) : theme.ink(scheme))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4.5)
                        .background {
                            if selected {
                                Capsule()
                                    .fill(theme.ink(scheme))
                                    .matchedGeometryEffect(id: "mode", in: highlight)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help("\(mode.title) · \(ModeBar.key(mode))")
            }
        }
        .padding(3)
        .background { Capsule().fill(theme.well(scheme)) }
        .overlay { Capsule().strokeBorder(theme.edge(scheme), lineWidth: 0.5) }
        .fixedSize()
    }

    static func key(_ mode: CalendarMode) -> String {
        switch mode {
        case .day: return "D"
        case .threeDay: return "3"
        case .week: return "W"
        case .month: return "M"
        case .agenda: return "A"
        }
    }
}

struct CalendarBanner<Actions: View>: View {
    @EnvironmentObject private var theme: Theme
    @Environment(\.colorScheme) private var scheme
    var text: String
    var symbol: String
    var dismiss: (() -> Void)?
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(theme.inkSecondary(scheme))
            Text(text)
                .font(.system(size: 12.5))
                .foregroundStyle(theme.ink(scheme))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            actions()
            if let dismiss {
                Button { dismiss() } label: { Image(systemName: "xmark").font(.system(size: 10, weight: .bold)) }
                    .buttonStyle(.plain)
                    .foregroundStyle(theme.inkTertiary(scheme))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background {
            RoundedRectangle(cornerRadius: max(theme.radius - 4, 8), style: .continuous).fill(theme.well(scheme))
        }
        .overlay {
            RoundedRectangle(cornerRadius: max(theme.radius - 4, 8), style: .continuous).strokeBorder(theme.edge(scheme), lineWidth: 0.5)
        }
    }
}

/// Until something real is connected: the calendars macOS already syncs, or Outlook and Microsoft 365.
private struct ConnectBanner: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var calendar: CalendarModel
    @EnvironmentObject private var mail: MailModel

    var body: some View {
        CalendarBanner(text: calendar.access == .denied
                       ? "Calendar access is off for 11am. Turn it on in Privacy settings, or sign in to Outlook or Microsoft 365."
                       : "Sample week. Connect the calendars on this Mac (iCloud, Google, Exchange), or sign in to Outlook or Microsoft 365.",
                       symbol: "calendar", actions: {
            HStack(spacing: 6) {
                Button(calendar.access == .denied ? "Privacy Settings" : "Connect") {
                    if calendar.access == .denied {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
                            NSWorkspace.shared.open(url)
                        }
                    } else {
                        Task { await calendar.requestAccess() }
                    }
                }
                .buttonStyle(.vellumPrimary)
                Button("Microsoft 365") {
                    mail.addAccountRequest = .outlook
                    model.go(to: .mail)
                }
                .buttonStyle(.vellumSecondary)
                .help("Sign in with Microsoft in Mail. Leo reads the same account's calendar.")
            }
        })
    }
}

// MARK: Popovers

private struct FindTimeView: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var calendar: CalendarModel
    @Environment(\.colorScheme) private var scheme
    @State private var minutes = UserDefaults.standard.object(forKey: "calendar.find.minutes") as? Int ?? 60
    @State private var days = 7
    var close: () -> Void

    var body: some View {
        let slots = calendar.freeSlots(minutes: minutes, days: days)
        VStack(alignment: .leading, spacing: 12) {
            Text("Find a time")
                .font(theme.display(19))
                .foregroundStyle(theme.ink(scheme))
            Picker("Length", selection: $minutes) {
                ForEach([30, 45, 60, 90], id: \.self) { value in Text("\(value) min").tag(value) }
            }
            .pickerStyle(.segmented)
            .onChange(of: minutes) { _, value in UserDefaults.standard.set(value, forKey: "calendar.find.minutes") }
            Picker("Within", selection: $days) {
                Text("3 days").tag(3)
                Text("A week").tag(7)
                Text("Two weeks").tag(14)
            }
            .pickerStyle(.segmented)
            Text("Weekdays, 9 to 5, around everything you haven't declined.")
                .font(.system(size: 11.5))
                .foregroundStyle(theme.inkTertiary(scheme))

            VStack(alignment: .leading, spacing: 2) {
                if slots.isEmpty {
                    Text("No gaps that long. Try a shorter meeting or a longer window.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(theme.inkSecondary(scheme))
                        .padding(.vertical, 6)
                }
                ForEach(Array(slots.prefix(6).enumerated()), id: \.offset) { _, slot in
                    SlotRow(slot: slot) {
                        close()
                        calendar.newEvent(at: slot.start, minutes: minutes)
                    }
                }
                if slots.count > 6 {
                    Text("and \(slots.count - 6) more")
                        .font(.system(size: 11.5))
                        .foregroundStyle(theme.inkTertiary(scheme))
                        .padding(.horizontal, 8)
                        .padding(.top, 2)
                }
            }

            HStack(spacing: 8) {
                Button("Copy for an email") {
                    if calendar.copyFreeTime(minutes: minutes, days: days) > 0 { close() }
                }
                .buttonStyle(.vellumPrimary)
                .disabled(slots.isEmpty)
                Button("Hold 2 h for focus") {
                    close()
                    calendar.blockFocus()
                }
                .buttonStyle(.vellumSecondary)
            }
        }
        .padding(16)
        .frame(width: 330)
    }
}

private struct SlotRow: View {
    @EnvironmentObject private var theme: Theme
    @Environment(\.colorScheme) private var scheme
    var slot: DateInterval
    var pick: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: pick) {
            HStack {
                Text(slot.start.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                    .font(.system(size: 12.5, weight: .medium))
                Spacer()
                Text("\(CalText.time(slot.start)) – \(CalText.time(slot.end))")
                    .font(.system(size: 12.5).monospacedDigit())
                    .foregroundStyle(theme.inkSecondary(scheme))
            }
            .foregroundStyle(theme.ink(scheme))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous).fill(hovering ? theme.raised(scheme) : Color.clear)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Book it")
    }
}

private struct CalendarsView: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var calendar: CalendarModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let own = calendar.calendars.filter { !$0.isHolidays }
        let accounts = Array(Set(own.map(\.account))).sorted()
        VStack(alignment: .leading, spacing: 10) {
            Text("Calendars")
                .font(theme.display(19))
                .foregroundStyle(theme.ink(scheme))
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(accounts, id: \.self) { account in
                        SectionLabel(text: account)
                            .padding(.top, 4)
                        ForEach(own.filter { $0.account == account }) { item in
                            Toggle(isOn: Binding(get: { !calendar.hidden.contains(item.id) }, set: { _ in calendar.toggle(item) })) {
                                HStack(spacing: 6) {
                                    Circle().fill(Color(calendarHex: item.color)).frame(width: 8, height: 8)
                                    Text(item.title).font(.system(size: 12.5))
                                    if !item.writable {
                                        Image(systemName: "lock").font(.system(size: 9)).foregroundStyle(theme.inkTertiary(scheme))
                                    }
                                }
                            }
                            .toggleStyle(.checkbox)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 320)
            .fixedSize(horizontal: false, vertical: true)
            Divider()
            Toggle("Australian public holidays", isOn: $calendar.showHolidays)
                .toggleStyle(.checkbox)
                .font(.system(size: 12.5))
            if calendar.access == .granted && calendar.reminderAccess != .granted {
                Button("Show reminders that are due") { Task { await calendar.requestReminders() } }
                    .buttonStyle(.vellumSecondary)
            }
            Text("New events go to your default calendar. Outlook calendars come from accounts signed in with Microsoft in Mail.")
                .font(.system(size: 11))
                .foregroundStyle(theme.inkTertiary(scheme))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(width: 290)
    }
}

private extension CalCalendar {
    var isHolidays: Bool { source == .holidays }
}
