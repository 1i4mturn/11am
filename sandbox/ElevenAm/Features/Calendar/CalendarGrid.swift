import AppKit
import SwiftUI

// MARK: Day, three days and week

/// Hours down the side, a column per day. Drag on empty time to book it, drag a block to move it (across days too),
/// drag its bottom edge to change the length. Everything snaps to a quarter hour.
struct TimeGrid: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var calendar: CalendarModel
    @Environment(\.colorScheme) private var scheme
    var days: [Date]

    static let hourHeight: CGFloat = 46
    static let gutter: CGFloat = 50

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    Color.clear.frame(width: TimeGrid.gutter, height: 1)
                    ForEach(days, id: \.self) { day in
                        DayHeader(day: day, wide: days.count == 1)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.vertical, 8)

                AllDayLane(days: days)
            }
            .reportGridTop()

            Rectangle().fill(theme.edge(scheme)).frame(height: 0.5)

            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 0) {
                        HourLabels()
                            .frame(width: TimeGrid.gutter)
                        ForEach(days, id: \.self) { day in
                            DayColumn(day: day)
                        }
                    }
                    .frame(height: TimeGrid.hourHeight * 24)
                    .background(alignment: .top) { HourLines() }
                }
                .onAppear {
                    // Just above the hour line, so its label isn't cut off.
                    let target = firstHour == 0 ? "hour-0" : "above-\(firstHour)"
                    DispatchQueue.main.async { proxy.scrollTo(target, anchor: .top) }
                }
            }
        }
    }

    /// Opens on the working day, or earlier if something starts earlier.
    private var firstHour: Int {
        let starts = days.flatMap { day in calendar.events(on: day).filter { !$0.isAllDay && Calendar.current.isDate($0.start, inSameDayAs: day) } }
            .map { Calendar.current.component(.hour, from: $0.start) }
        return max(0, min(8, starts.min() ?? 8))
    }
}

private struct DayHeader: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var calendar: CalendarModel
    @Environment(\.colorScheme) private var scheme
    var day: Date
    var wide: Bool

    var body: some View {
        let isToday = Calendar.current.isDateInToday(day)
        Button {
            calendar.show(day: day, as: .day)
        } label: {
            HStack(spacing: 5) {
                Text(day.formatted(.dateTime.weekday(wide ? .wide : .abbreviated)))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(theme.inkSecondary(scheme))
                Text(day.formatted(.dateTime.day()))
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .foregroundStyle(isToday ? theme.paper(scheme) : theme.ink(scheme))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background {
                        if isToday { Capsule().fill(theme.ink(scheme)) }
                    }
            }
            .lineLimit(1)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Show this day")
    }
}

private struct HourLabels: View {
    @EnvironmentObject private var theme: Theme
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<24, id: \.self) { hour in
                VStack(spacing: 0) {
                    Text(hour == 0 ? "" : HourLabels.label(hour))
                        .font(.system(size: 10.5).monospacedDigit())
                        .foregroundStyle(theme.inkTertiary(scheme))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.trailing, 8)
                        .offset(y: -7)
                        .frame(height: TimeGrid.hourHeight - 12, alignment: .top)
                    // A marker just above the next hour's line, to scroll to.
                    Color.clear
                        .frame(height: 12)
                        .id("above-\(hour + 1)")
                }
                .frame(height: TimeGrid.hourHeight)
                .id("hour-\(hour)")
            }
        }
    }

    static func label(_ hour: Int) -> String {
        let day = Calendar.current.startOfDay(for: Date())
        let date = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: day) ?? day
        return date.formatted(.dateTime.hour())
    }
}

private struct HourLines: View {
    @EnvironmentObject private var theme: Theme
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<24, id: \.self) { hour in
                VStack(spacing: 0) {
                    Rectangle().fill(hour == 0 ? Color.clear : theme.edge(scheme)).frame(height: 0.5)
                    Spacer(minLength: 0)
                }
                .frame(height: TimeGrid.hourHeight)
                // Outside working hours reads a shade quieter.
                .background((hour < 8 || hour >= 18) ? theme.ink(scheme).opacity(0.018) : Color.clear)
            }
        }
        .padding(.leading, TimeGrid.gutter)
        .allowsHitTesting(false)
    }
}

private struct DayColumn: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var calendar: CalendarModel
    @Environment(\.colorScheme) private var scheme
    var day: Date
    @State private var creating: ClosedRange<CGFloat>?

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let placed = EventLayout.place(calendar.events(on: day).filter { !$0.isAllDay })
            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .gesture(createGesture)
                    .onTapGesture(count: 2) { point in
                        calendar.newEvent(at: time(at: point.y, snap: 30, rounding: .down))
                    }
                    .onTapGesture { calendar.selectedID = nil }

                if let creating {
                    CreatingPreview(day: day, range: creating, top: time(at: creating.lowerBound, snap: 15), bottom: time(at: creating.upperBound, snap: 15))
                        .frame(width: max(width - 4, 8))
                        .offset(x: 2)
                }

                ForEach(placed, id: \.event.id) { item in
                    let slot = (width - 4) / CGFloat(max(item.columns, 1))
                    let top = y(for: max(item.event.start, day))
                    let bottom = y(for: min(item.event.end, nextDay))
                    EventBlock(event: item.event, columnWidth: width, height: max(bottom - top - 1, 17))
                        .frame(width: max(slot - 2, 8))
                        .offset(x: 2 + CGFloat(item.column) * slot, y: top)
                        .zIndex(calendar.selectedID == item.event.id ? 1 : 0)
                }

                if Calendar.current.isDateInToday(day) {
                    NowLine(day: day, width: width)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .overlay(alignment: .leading) {
            Rectangle().fill(theme.edge(scheme)).frame(width: 0.5).allowsHitTesting(false)
        }
    }

    private var nextDay: Date { Calendar.current.date(byAdding: .day, value: 1, to: day) ?? day.addingTimeInterval(86_400) }

    private func y(for date: Date) -> CGFloat {
        CGFloat(date.timeIntervalSince(day) / 3_600) * TimeGrid.hourHeight
    }

    private func time(at y: CGFloat, snap: Int, rounding: FloatingPointRoundingRule = .toNearestOrAwayFromZero) -> Date {
        let minutes = Double(max(0, y)) / Double(TimeGrid.hourHeight) * 60
        let snapped = min(24 * 60 - snap, Int((minutes / Double(snap)).rounded(rounding)) * snap)
        return Calendar.current.date(byAdding: .minute, value: max(0, snapped), to: day) ?? day
    }

    private var createGesture: some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .local)
            .onChanged { value in
                creating = min(value.startLocation.y, value.location.y)...max(value.startLocation.y, value.location.y)
            }
            .onEnded { value in
                let start = time(at: min(value.startLocation.y, value.location.y), snap: 15)
                let end = time(at: max(value.startLocation.y, value.location.y), snap: 15)
                creating = nil
                calendar.newEvent(at: start, minutes: max(15, Int(end.timeIntervalSince(start) / 60)))
            }
    }
}

private struct CreatingPreview: View {
    @EnvironmentObject private var theme: Theme
    @Environment(\.colorScheme) private var scheme
    var day: Date
    var range: ClosedRange<CGFloat>
    var top: Date
    var bottom: Date

    var body: some View {
        let height = max(range.upperBound - range.lowerBound, 12)
        Text("\(CalText.time(top)) – \(CalText.time(max(bottom, top.addingTimeInterval(900))))")
            .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
            .foregroundStyle(theme.ink(scheme))
            .padding(4)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .frame(height: height, alignment: .top)
            .background {
                RoundedRectangle(cornerRadius: 5, style: .continuous).fill(theme.ink(scheme).opacity(0.08))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(theme.ink(scheme).opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }
            .offset(y: range.lowerBound)
            .allowsHitTesting(false)
    }
}

/// A time block. Its calendar's colour is a quiet wash and an edge, so the week stays black and white.
private struct EventBlock: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var calendar: CalendarModel
    @Environment(\.colorScheme) private var scheme
    var event: CalEvent
    var columnWidth: CGFloat
    var height: CGFloat
    @State private var drag: CGSize = .zero
    @State private var stretch: CGFloat = 0
    @State private var resizeHover = false

    var body: some View {
        let selected = calendar.selectedID == event.id
        let tint = Color(calendarHex: event.color)
        let shown = max(17, height + stretch)
        let shape = RoundedRectangle(cornerRadius: 5, style: .continuous)
        VStack(alignment: .leading, spacing: 1) {
            Text(event.title)
                .font(.system(size: 11.5, weight: .semibold))
                .lineLimit(shown > 40 ? 2 : 1)
                .strikethrough(event.response == .declined)
            if shown > 32 {
                Text(timeText)
                    .font(.system(size: 10.5).monospacedDigit())
                    .foregroundStyle(theme.inkSecondary(scheme))
                    .lineLimit(1)
            }
            if shown > 62, let detail {
                Text(detail)
                    .font(.system(size: 10.5))
                    .foregroundStyle(theme.inkTertiary(scheme))
                    .lineLimit(1)
            }
        }
        .foregroundStyle(theme.ink(scheme))
        .padding(.leading, 8)
        .padding(.trailing, 4)
        .padding(.vertical, shown > 24 ? 4 : 1)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: shown, alignment: .top)
        .background {
            ZStack {
                shape.fill(theme.raised(scheme))
                shape.fill(tint.opacity(scheme == .dark ? 0.30 : 0.17))
            }
        }
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 1.5).fill(tint).frame(width: 3).padding(.vertical, 3).padding(.leading, 2.5)
        }
        .overlay {
            if selected {
                shape.strokeBorder(theme.ink(scheme), lineWidth: 1.25)
            } else if event.awaitsAnswer {
                shape.strokeBorder(theme.ink(scheme).opacity(0.45), style: StrokeStyle(lineWidth: 0.9, dash: [3, 2]))
            } else {
                shape.strokeBorder(theme.edge(scheme), lineWidth: 0.5)
            }
        }
        .overlay(alignment: .bottom) {
            if event.writable {
                Color.clear
                    .frame(height: 7)
                    .contentShape(Rectangle())
                    .onHover { inside in
                        guard inside != resizeHover else { return }
                        resizeHover = inside
                        if inside { NSCursor.resizeUpDown.push() } else { NSCursor.pop() }
                    }
                    .gesture(resizeGesture)
            }
        }
        .opacity(event.response == .declined ? 0.5 : 1)
        .shadow(color: .black.opacity(drag == .zero ? 0 : 0.18), radius: 6, y: 3)
        .contentShape(Rectangle())
        .offset(drag)
        .gesture(moveGesture)
        .onTapGesture(count: 2) {
            if event.writable { calendar.edit(event) }
        }
        .onTapGesture {
            calendar.selectedID = event.id
        }
        .onDisappear {
            if resizeHover { NSCursor.pop() }
        }
        .help(event.writable ? "\(event.title) · drag to move, drag the bottom edge to change the length" : event.title)
    }

    private var timeText: String {
        if drag != .zero {
            let start = movedStart
            return "\(CalText.time(start)) – \(CalText.time(start.addingTimeInterval(event.duration)))"
        }
        if stretch != 0 { return "\(CalText.time(event.start)) – \(CalText.time(stretchedEnd))" }
        return "\(CalText.time(event.start)) – \(CalText.time(event.end))"
    }

    private var detail: String? {
        if let join = event.joinURL { return JoinLinks.service(join) }
        return event.location
    }

    private var dayShift: Int { columnWidth > 0 ? Int((drag.width / columnWidth).rounded()) : 0 }
    private var minuteShift: Int { Int((drag.height / TimeGrid.hourHeight * 60).rounded()) }

    private var movedStart: Date {
        let moved = Calendar.current.date(byAdding: .day, value: dayShift, to: event.start) ?? event.start
        return moved.addingTimeInterval(Double(minuteShift) * 60)
    }

    private var stretchedEnd: Date {
        event.end.addingTimeInterval(Double(Int((stretch / TimeGrid.hourHeight * 60).rounded())) * 60)
    }

    /// Whole days sideways, quarter hours up and down.
    private func snapped(_ translation: CGSize) -> CGSize {
        let days = columnWidth > 0 ? (translation.width / columnWidth).rounded() : 0
        let quarters = (translation.height / TimeGrid.hourHeight * 4).rounded()
        return CGSize(width: days * columnWidth, height: quarters * TimeGrid.hourHeight / 4)
    }

    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .global)
            .onChanged { value in
                guard event.writable else { return }
                if calendar.selectedID != event.id { calendar.selectedID = event.id }
                drag = snapped(value.translation)
            }
            .onEnded { value in
                guard event.writable else { return }
                drag = snapped(value.translation)
                let start = movedStart
                drag = .zero
                calendar.move(event, to: start)
            }
    }

    private var resizeGesture: some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .global)
            .onChanged { value in
                let quarters = (value.translation.height / TimeGrid.hourHeight * 4).rounded()
                stretch = max(quarters * TimeGrid.hourHeight / 4, -(height - TimeGrid.hourHeight / 4))
            }
            .onEnded { _ in
                let end = stretchedEnd
                stretch = 0
                calendar.resize(event, to: end)
            }
    }
}

private struct NowLine: View {
    @EnvironmentObject private var theme: Theme
    @Environment(\.colorScheme) private var scheme
    var day: Date
    var width: CGFloat

    var body: some View {
        TimelineView(.everyMinute) { context in
            let y = CGFloat(context.date.timeIntervalSince(day) / 3_600) * TimeGrid.hourHeight
            ZStack(alignment: .leading) {
                Rectangle().fill(theme.ink(scheme)).frame(height: 1.25)
                Circle().fill(theme.ink(scheme)).frame(width: 7, height: 7).offset(x: -3.5)
            }
            .frame(width: width, height: 7)
            .offset(y: y - 3.5)
        }
        .allowsHitTesting(false)
    }
}

/// All-day events, holidays and reminders that are due, above the hours.
private struct AllDayLane: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var calendar: CalendarModel
    @Environment(\.colorScheme) private var scheme
    var days: [Date]

    var body: some View {
        let events = days.map { day in calendar.events(on: day).filter(\.isAllDay) }
        let reminders = days.map { day in calendar.reminders(on: day) }
        let busiest = zip(events, reminders).map { $0.0.count + $0.1.count }.max() ?? 0
        if busiest > 0 {
            HStack(alignment: .top, spacing: 0) {
                Text("all-day")
                    .font(.system(size: 10))
                    .foregroundStyle(theme.inkTertiary(scheme))
                    .frame(width: TimeGrid.gutter - 8, alignment: .trailing)
                    .padding(.trailing, 8)
                    .padding(.top, 4)
                ForEach(Array(days.enumerated()), id: \.offset) { index, _ in
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(events[index].prefix(3))) { event in
                            AllDayChip(event: event)
                        }
                        ForEach(Array(reminders[index].prefix(3))) { reminder in
                            ReminderChip(reminder: reminder)
                        }
                        let extra = events[index].count + reminders[index].count - min(events[index].count, 3) - min(reminders[index].count, 3)
                        if extra > 0 {
                            Text("+\(extra) more")
                                .font(.system(size: 10.5))
                                .foregroundStyle(theme.inkTertiary(scheme))
                                .padding(.leading, 4)
                        }
                    }
                    .padding(.horizontal, 2)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
            .padding(.bottom, 6)
        }
    }
}

struct AllDayChip: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var calendar: CalendarModel
    @Environment(\.colorScheme) private var scheme
    var event: CalEvent

    var body: some View {
        let selected = calendar.selectedID == event.id
        let tint = Color(calendarHex: event.color)
        let shape = RoundedRectangle(cornerRadius: 4, style: .continuous)
        HStack(spacing: 4) {
            if event.isHoliday {
                Image(systemName: "flag").font(.system(size: 8.5))
            }
            Text(event.title)
                .font(.system(size: 11, weight: event.isHoliday ? .regular : .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(event.isHoliday ? theme.inkSecondary(scheme) : theme.ink(scheme))
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if event.isHoliday {
                shape.fill(theme.well(scheme))
            } else {
                ZStack {
                    shape.fill(theme.raised(scheme))
                    shape.fill(tint.opacity(scheme == .dark ? 0.32 : 0.2))
                }
            }
        }
        .overlay { shape.strokeBorder(selected ? theme.ink(scheme) : theme.edge(scheme), lineWidth: selected ? 1.2 : 0.5) }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            if event.writable { calendar.edit(event) }
        }
        .onTapGesture { calendar.selectedID = event.id }
        .help(event.title)
    }
}

private struct ReminderChip: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var calendar: CalendarModel
    @Environment(\.colorScheme) private var scheme
    var reminder: CalReminder

    var body: some View {
        HStack(spacing: 4) {
            Button {
                withAnimation(theme.spring) { calendar.complete(reminder) }
            } label: {
                Image(systemName: "circle").font(.system(size: 10))
            }
            .buttonStyle(.plain)
            .help("Done")
            Text(reminder.title)
                .font(.system(size: 11))
                .lineLimit(1)
        }
        .foregroundStyle(theme.inkSecondary(scheme))
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .help("\(reminder.title) · \(reminder.list)")
    }
}

// MARK: Month

struct MonthGrid: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var calendar: CalendarModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let days = calendar.days
        let month = Calendar.current.component(.month, from: calendar.anchor)
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(Array(days.prefix(7)), id: \.self) { day in
                    Text(day.formatted(.dateTime.weekday(.abbreviated)))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(theme.inkTertiary(scheme))
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.vertical, 8)
            .reportGridTop()
            ForEach(0..<(days.count / 7), id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<7, id: \.self) { column in
                        let day = days[row * 7 + column]
                        MonthCell(day: day, inMonth: Calendar.current.component(.month, from: day) == month)
                    }
                }
                .frame(maxHeight: .infinity)
            }
        }
    }
}

private struct MonthCell: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var calendar: CalendarModel
    @Environment(\.colorScheme) private var scheme
    var day: Date
    var inMonth: Bool

    var body: some View {
        let events = calendar.events(on: day)
        let isToday = Calendar.current.isDateInToday(day)
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Spacer()
                Button {
                    calendar.show(day: day, as: .day)
                } label: {
                    Text(day.formatted(.dateTime.day()))
                        .font(.system(size: 12, weight: .semibold).monospacedDigit())
                        .foregroundStyle(isToday ? theme.paper(scheme) : theme.ink(scheme).opacity(inMonth ? 1 : 0.35))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background {
                            if isToday { Capsule().fill(theme.ink(scheme)) }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help("Show this day")
            }
            ForEach(Array(events.prefix(3))) { event in
                MonthEventLine(event: event)
            }
            if events.count > 3 {
                Text("+\(events.count - 3) more")
                    .font(.system(size: 10.5))
                    .foregroundStyle(theme.inkTertiary(scheme))
                    .padding(.leading, 4)
            }
            Spacer(minLength: 0)
        }
        .padding(4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(inMonth ? Color.clear : theme.ink(scheme).opacity(0.025))
        // A full point, so the lines survive cells that start between pixels.
        .overlay(alignment: .top) { Rectangle().fill(theme.edge(scheme)).frame(height: 1) }
        .overlay(alignment: .leading) { Rectangle().fill(theme.edge(scheme)).frame(width: 1) }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            let start = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: day) ?? day
            calendar.newEvent(at: start)
        }
        .onTapGesture { calendar.selectedID = nil }
    }
}

private struct MonthEventLine: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var calendar: CalendarModel
    @Environment(\.colorScheme) private var scheme
    var event: CalEvent

    var body: some View {
        if event.isAllDay {
            AllDayChip(event: event)
        } else {
            let selected = calendar.selectedID == event.id
            HStack(spacing: 4) {
                Circle().fill(Color(calendarHex: event.color)).frame(width: 6, height: 6)
                Text(CalText.compact(event.start))
                    .font(.system(size: 10.5).monospacedDigit())
                    .foregroundStyle(theme.inkTertiary(scheme))
                Text(event.title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(theme.ink(scheme))
                    .strikethrough(event.response == .declined)
            }
            .lineLimit(1)
            .padding(.horizontal, 4)
            .padding(.vertical, 1.5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 4, style: .continuous).fill(selected ? theme.raised(scheme) : Color.clear)
            }
            .contentShape(Rectangle())
            .onTapGesture(count: 2) {
                if event.writable { calendar.edit(event) }
            }
            .onTapGesture { calendar.selectedID = event.id }
            .help("\(CalText.range(event)) · \(event.title)")
        }
    }
}

// MARK: Agenda

/// The next two weeks as a list, with join links and clashes at a glance.
struct AgendaList: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var calendar: CalendarModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let days = calendar.days.filter { !calendar.events(on: $0).isEmpty || Calendar.current.isDateInToday($0) }
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                ForEach(days, id: \.self) { day in
                    let events = calendar.events(on: day)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(day.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                                .font(theme.display(16))
                                .foregroundStyle(theme.ink(scheme))
                            if Calendar.current.isDateInToday(day) {
                                Chip(text: "Today", filled: true)
                            } else if Calendar.current.isDateInTomorrow(day) {
                                Chip(text: "Tomorrow")
                            }
                            Spacer()
                        }
                        .padding(.bottom, 4)
                        if events.isEmpty {
                            Text("Nothing booked.")
                                .font(.system(size: 12.5))
                                .foregroundStyle(theme.inkTertiary(scheme))
                                .padding(.vertical, 6)
                        }
                        ForEach(events) { event in
                            AgendaRow(event: event)
                        }
                    }
                }
                if days.isEmpty {
                    Text("Nothing in the next two weeks.")
                        .font(.system(size: 13))
                        .foregroundStyle(theme.inkTertiary(scheme))
                }
            }
            .padding(18)
        }
        .scrollContentBackground(.hidden)
    }
}

private struct AgendaRow: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var calendar: CalendarModel
    @Environment(\.colorScheme) private var scheme
    var event: CalEvent
    @State private var hovering = false

    var body: some View {
        let selected = calendar.selectedID == event.id
        let clashes = event.isAllDay ? [] : calendar.conflicts(for: event)
        HStack(alignment: .center, spacing: 12) {
            Text(CalText.range(event))
                .font(.system(size: 12).monospacedDigit())
                .foregroundStyle(theme.inkSecondary(scheme))
                .frame(width: 128, alignment: .leading)
            RoundedRectangle(cornerRadius: 1.5)
                .fill(Color(calendarHex: event.color))
                .frame(width: 3, height: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(theme.ink(scheme))
                    .strikethrough(event.response == .declined)
                    .lineLimit(1)
                Text(detail)
                    .font(.system(size: 11.5))
                    .foregroundStyle(theme.inkTertiary(scheme))
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if !clashes.isEmpty {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.inkSecondary(scheme))
                    .help("Clashes with \(clashes.map(\.title).joined(separator: ", "))")
            }
            if event.awaitsAnswer {
                Chip(text: "Reply")
            }
            if let join = event.joinURL {
                Button {
                    NSWorkspace.shared.open(join)
                } label: {
                    Label(JoinLinks.service(join), systemImage: "video")
                }
                .buttonStyle(.vellumSecondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(selected ? theme.raised(scheme) : (hovering ? theme.well(scheme) : Color.clear))
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(count: 2) {
            if event.writable { calendar.edit(event) }
        }
        .onTapGesture { calendar.selectedID = event.id }
    }

    private var detail: String {
        var parts: [String] = []
        if let location = event.location, event.joinURL?.absoluteString != location { parts.append(location) }
        if let name = calendar.calendar(for: event)?.title { parts.append(name) }
        if !event.attendees.isEmpty { parts.append(event.attendees.count == 1 ? "with \(event.attendees[0].name)" : "\(event.attendees.count) people") }
        return parts.joined(separator: " · ")
    }
}

/// The height of a grid's headings (day names, all-day events), for placing the event card below them.
struct GridTopKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private extension View {
    func reportGridTop() -> some View {
        background {
            GeometryReader { proxy in
                Color.clear.preference(key: GridTopKey.self, value: proxy.size.height)
            }
        }
    }
}
