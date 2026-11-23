import ActivityKit
import SwiftUI

/// The Live Activity: what's next and who it's from, counting down on the Lock Screen and in the Dynamic Island, and
/// the 11 with its halo while it listens.
struct ElevenActivity: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// The agent it's from, by brand code ("le").
        var agent: String
        /// The thing itself: "Acme pricing review".
        var line: String
        var place: String?
        /// When it starts, to count down to.
        var starts: Date?
        var listening: Bool
    }

    var name: String
}

/// The countdown, in Courier: minutes to go, or "now", or "listening".
struct ActivityCountdown: View {
    var state: ElevenActivity.ContentState
    var compact = false

    var body: some View {
        Group {
            if state.listening {
                Text(compact ? "…" : "listening")
            } else if let starts = state.starts, starts > Date() {
                Text(timerInterval: Date()...starts, countsDown: true, showsHours: false)
                    .monospacedDigit()
            } else {
                Text("now")
            }
        }
        .font(BrandFace.label(compact ? 13 : 15))
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .multilineTextAlignment(.trailing)
        .frame(maxWidth: compact ? 52 : 96, alignment: .trailing)
    }
}

/// The agent in the island: their circle in sheet-ink, or the 11 with its halo while it listens.
struct ActivityAgent: View {
    var state: ElevenActivity.ContentState
    var size: CGFloat

    var body: some View {
        if state.listening {
            PhoneAgentCircle(code: "11", size: size, style: .paper)
                .background {
                    Circle()
                        .fill(RadialGradient(colors: [Color.white.opacity(0.85), .clear], center: .center, startRadius: 0, endRadius: size))
                        .frame(width: size * 2, height: size * 2)
                        .blur(radius: size * 0.25)
                }
        } else {
            PhoneAgentCircle(code: state.agent, size: size, style: .sheetInk)
        }
    }
}

/// The Lock Screen: a note led by the agent's monogram, the thing in Schibsted, and the countdown.
struct ActivityLockNote: View {
    var state: ElevenActivity.ContentState

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            PhoneAgentCircle(code: state.listening ? "11" : state.agent, size: 44, style: .ink)
            VStack(alignment: .leading, spacing: 3) {
                Text("\(PhoneAgents.name(state.listening ? "11" : state.agent).lowercased()) · \(state.listening ? "listening" : "next")")
                    .font(BrandFace.label(12))
                Text(state.listening ? "Say what you need." : state.line)
                    .font(BrandFace.heading(19))
                    .lineLimit(2)
                if let place = state.place, !state.listening {
                    Text(place).font(.brand(size: 14)).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            ActivityCountdown(state: state)
        }
        .foregroundStyle(PhoneBrand.inkHex)
        .padding(16)
    }
}

/// The expanded island: agent on the left, the thing in the middle, the countdown on the right, a line under.
struct ActivityExpanded: View {
    var state: ElevenActivity.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                ActivityAgent(state: state, size: 40)
                Text(state.listening ? "Say what you need." : state.line)
                    .font(BrandFace.heading(18))
                    .lineLimit(2)
                Spacer(minLength: 6)
                ActivityCountdown(state: state)
            }
            Text(state.listening ? "listening · let go to send" : "hold the 11 to talk")
                .font(BrandFace.label(12))
        }
        .foregroundStyle(.white)
    }
}
