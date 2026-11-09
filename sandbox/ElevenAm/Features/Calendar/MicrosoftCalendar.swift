import Foundation

/// Outlook and Microsoft 365 calendars through Microsoft Graph, with the same Microsoft sign-in as Mail.
/// Times are asked for in UTC, so nothing depends on Windows time-zone names.
enum MicrosoftCalendar {
    static let scope = MicrosoftAuth.calendarScope

    struct CalendarInfo: Sendable {
        var id: String
        var name: String
        var color: String
        var canEdit: Bool
    }

    static func calendars(token: String) async throws -> [CalendarInfo] {
        let json = try await request("GET", "/me/calendars?$select=id,name,hexColor,color,canEdit&$top=50", token: token)
        let values = json["value"] as? [[String: Any]] ?? []
        return values.enumerated().compactMap { index, item in
            guard let id = item["id"] as? String else { return nil }
            let hex = (item["hexColor"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? palette[index % palette.count]
            return CalendarInfo(id: id, name: item["name"] as? String ?? "Calendar", color: hex, canEdit: item["canEdit"] as? Bool ?? true)
        }
    }

    /// Every event and recurring instance between two dates, following Graph's paging.
    static func events(calendarID: String, from start: Date, to end: Date, token: String, accountID: String, color: String, writable: Bool) async throws -> [CalEvent] {
        var path: String? = "/me/calendars/\(escape(calendarID))/calendarView?startDateTime=\(iso(start))&endDateTime=\(iso(end))&$top=250"
            + "&$select=id,subject,start,end,isAllDay,location,bodyPreview,onlineMeeting,attendees,organizer,responseStatus,isOrganizer,type,webLink"
        var events: [CalEvent] = []
        var pages = 0
        while let next = path, pages < 10 {
            let json = try await request("GET", next, token: token)
            for item in json["value"] as? [[String: Any]] ?? [] {
                if let event = event(from: item, calendarID: calendarID, accountID: accountID, color: color, writable: writable) {
                    events.append(event)
                }
            }
            path = json["@odata.nextLink"] as? String
            pages += 1
        }
        return events
    }

    static func event(from item: [String: Any], calendarID: String, accountID: String, color: String, writable: Bool) -> CalEvent? {
        guard let id = item["id"] as? String,
              let startInfo = item["start"] as? [String: Any], let endInfo = item["end"] as? [String: Any],
              let startText = startInfo["dateTime"] as? String, let endText = endInfo["dateTime"] as? String else { return nil }
        let allDay = item["isAllDay"] as? Bool ?? false
        guard let start = allDay ? allDayDate(startText) : utc(startText), let end = allDay ? allDayDate(endText) : utc(endText) else { return nil }
        let isOrganizer = item["isOrganizer"] as? Bool ?? false
        let responseText = (item["responseStatus"] as? [String: Any])?["response"] as? String ?? "none"
        let attendees: [CalAttendee] = (item["attendees"] as? [[String: Any]] ?? []).compactMap { entry in
            guard let address = entry["emailAddress"] as? [String: Any], let email = address["address"] as? String else { return nil }
            let status = (entry["status"] as? [String: Any])?["response"] as? String ?? "none"
            return CalAttendee(name: address["name"] as? String ?? email, email: email.lowercased(), response: response(status))
        }
        let organizer = ((item["organizer"] as? [String: Any])?["emailAddress"] as? [String: Any])?["address"] as? String
        let join = ((item["onlineMeeting"] as? [String: Any])?["joinUrl"] as? String).flatMap(URL.init(string:))
        let location = ((item["location"] as? [String: Any])?["displayName"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        return CalEvent(
            id: "ms:\(accountID):\(id)", calendarID: "ms:\(accountID):\(calendarID)", source: .microsoft(accountID: accountID),
            title: (item["subject"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "(No title)",
            start: start, end: end, isAllDay: allDay, location: location,
            notes: (item["bodyPreview"] as? String).flatMap { $0.isEmpty ? nil : $0 }, url: join,
            attendees: attendees, organizer: organizer?.lowercased(),
            response: isOrganizer ? .organizer : response(responseText),
            isRecurring: (item["type"] as? String).map { $0 != "singleInstance" } ?? false,
            color: color, writable: writable, externalID: id
        )
    }

    // MARK: Changes

    static func create(_ draft: EventFields, calendarID: String, token: String) async throws -> String {
        let json = try await request("POST", "/me/calendars/\(escape(calendarID))/events", token: token, body: body(for: draft))
        guard let id = json["id"] as? String else { throw MailError("Outlook didn't create the event.") }
        return id
    }

    static func update(_ draft: EventFields, eventID: String, token: String) async throws {
        _ = try await request("PATCH", "/me/events/\(escape(eventID))", token: token, body: body(for: draft))
    }

    static func delete(eventID: String, token: String) async throws {
        _ = try await request("DELETE", "/me/events/\(escape(eventID))", token: token)
    }

    /// Accept, maybe or decline, and tell the organiser.
    static func respond(_ answer: CalResponse, eventID: String, token: String) async throws {
        let action: String
        switch answer {
        case .accepted: action = "accept"
        case .tentative: action = "tentativelyAccept"
        case .declined: action = "decline"
        default: return
        }
        _ = try await request("POST", "/me/events/\(escape(eventID))/\(action)", token: token, body: ["sendResponse": true])
    }

    /// The parts of an event 11am edits.
    struct EventFields: Sendable {
        var title: String
        var start: Date
        var end: Date
        var isAllDay: Bool
        var location: String?
        var notes: String?
        /// Only sent for a new event: changing a series from one of its days is left to Outlook.
        var repeats: EventRepeat = .never
        var repeatUntil: Date?
        /// Minutes before; nil leaves the reminder as it is.
        var alert: Int?
    }

    static func body(for fields: EventFields, calendar: Calendar = .current) -> [String: Any] {
        var body: [String: Any] = ["subject": fields.title, "isAllDay": fields.isAllDay]
        if fields.isAllDay {
            // All-day events start and end at midnight in a named zone.
            let zone = TimeZone.current.identifier
            body["start"] = ["dateTime": localMidnight(fields.start), "timeZone": zone]
            body["end"] = ["dateTime": localMidnight(fields.end), "timeZone": zone]
        } else {
            body["start"] = ["dateTime": utcText(fields.start), "timeZone": "UTC"]
            body["end"] = ["dateTime": utcText(fields.end), "timeZone": "UTC"]
        }
        body["location"] = ["displayName": fields.location ?? ""]
        if let notes = fields.notes { body["body"] = ["contentType": "text", "content": notes] }
        if let recurrence = fields.repeats.graph(start: fields.start, until: fields.repeatUntil, calendar: calendar) { body["recurrence"] = recurrence }
        if let alert = fields.alert {
            body["isReminderOn"] = true
            body["reminderMinutesBeforeStart"] = alert
        }
        return body
    }

    // MARK: Plumbing

    @discardableResult
    static func request(_ method: String, _ path: String, token: String, body: [String: Any]? = nil) async throws -> [String: Any] {
        let address = path.hasPrefix("http") ? path : MicrosoftGraph.baseURL + path
        guard let url = URL(string: address) else { throw MailError("Couldn't reach Outlook.") }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("outlook.timezone=\"UTC\"", forHTTPHeaderField: "Prefer")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any]) ?? [:]
        guard (200..<300).contains(status) else {
            let message = ((json["error"] as? [String: Any])?["message"] as? String) ?? "HTTP \(status)"
            throw MailError("Outlook calendar: \(message)")
        }
        return json
    }

    private static let palette = ["#4F7FD6", "#C2703D", "#5E9C6A", "#9A6BC2", "#C24F6B", "#3D9AA8"]

    private static func escape(_ id: String) -> String {
        id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))) ?? id
    }

    static func iso(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: date)
    }

    /// "2026-10-30T09:00:00.0000000" in UTC.
    static func utc(_ text: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return formatter.date(from: String(text.prefix(19)))
    }

    /// All-day events are whole days wherever you are. Graph sends them either as midnight, or converted to UTC from
    /// the zone they were made in ("2026-11-02T13:00:00" for 3 November in Sydney); both land on the right day.
    static func allDayDate(_ text: String) -> Date? {
        if text.dropFirst(11).hasPrefix("00:00:00") { return localDay(text) }
        guard let instant = utc(text) else { return localDay(text) }
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: instant)
        return calendar.component(.hour, from: instant) >= 12 ? calendar.date(byAdding: .day, value: 1, to: day) : day
    }

    static func localDay(_ text: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: String(text.prefix(10)))
    }

    static func utcText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return formatter.string(from: date)
    }

    private static func localMidnight(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd'T'00:00:00"
        return formatter.string(from: date)
    }

    private static func response(_ text: String) -> CalResponse {
        switch text.lowercased() {
        case "accepted": return .accepted
        case "tentativelyaccepted": return .tentative
        case "declined": return .declined
        case "organizer": return .organizer
        default: return .none
        }
    }
}
