import ActivityKit
import Foundation

/// Starts and updates the Live Activity: the next thing on the day, counting down, and the 11 while it listens.
@MainActor
enum LiveActivities {
    private static var current: Activity<ElevenActivity>? { Activity<ElevenActivity>.activities.first }

    static var allowed: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    /// The next event from the brief, on the Lock Screen and in the island until it starts.
    @discardableResult
    static func nextEvent(_ brief: LinkBrief, now: Date = Date()) -> Bool {
        guard allowed, let next = brief.events.first(where: { $0.end > now }) else { return false }
        let state = ElevenActivity.ContentState(agent: "le", line: next.title, place: next.location, starts: next.start, listening: false)
        show(state, staleDate: next.end)
        return true
    }

    /// The 11 with its halo while the talk note listens; back to what it was after.
    static func listening(_ on: Bool) {
        guard allowed else { return }
        if let current {
            var state = current.content.state
            state.listening = on
            Task { await current.update(ActivityContent(state: state, staleDate: nil)) }
        } else if on {
            show(ElevenActivity.ContentState(agent: "11", line: "Listening", place: nil, starts: nil, listening: true), staleDate: nil)
        }
    }

    static func end() {
        guard let current else { return }
        Task { await current.end(nil, dismissalPolicy: .immediate) }
    }

    private static func show(_ state: ElevenActivity.ContentState, staleDate: Date?) {
        let content = ActivityContent(state: state, staleDate: staleDate)
        if let current {
            Task { await current.update(content) }
        } else {
            _ = try? Activity.request(attributes: ElevenActivity(name: "11am"), content: content, pushType: nil)
        }
    }
}
