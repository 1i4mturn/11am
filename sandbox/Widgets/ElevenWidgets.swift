import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

/// The widget extension: the Live Activity (Lock Screen and Dynamic Island) and, from iOS 18, the Control Center
/// control that opens 11am listening, the puck in place of the torch.
@main
struct ElevenWidgets: WidgetBundle {
    init() {
        PhoneBrand.registerFonts()
    }

    var body: some Widget {
        ElevenLiveActivity()
        if #available(iOS 18.0, *) {
            TalkControl()
        }
    }
}

struct ElevenLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ElevenActivity.self) { context in
            ActivityLockNote(state: context.state)
                .activityBackgroundTint(Color.white.opacity(0.82))
                .activitySystemActionForegroundColor(PhoneBrand.inkHex)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    ActivityAgent(state: context.state, size: 40)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ActivityCountdown(state: context.state)
                        .foregroundStyle(.white)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.listening ? "Say what you need." : context.state.line)
                        .font(BrandFace.heading(17))
                        .lineLimit(2)
                        .foregroundStyle(.white)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.state.listening ? "listening · let go to send" : "hold the 11 to talk")
                        .font(BrandFace.label(12))
                        .foregroundStyle(.white)
                }
            } compactLeading: {
                ActivityAgent(state: context.state, size: 22)
            } compactTrailing: {
                ActivityCountdown(state: context.state, compact: true)
                    .foregroundStyle(.white)
            } minimal: {
                ActivityAgent(state: context.state, size: 20)
            }
            .keylineTint(.white)
        }
    }
}

/// Control Center (and the Lock Screen's controls): "Talk to 11am" opens the app listening.
@available(iOS 18.0, *)
struct TalkControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "au.elevenam.sandbox.phone.talk") {
            ControlWidgetButton(action: OpenURLIntent(URL(string: "elevenam://talk")!)) {
                Label("Talk to 11am", systemImage: "waveform")
            }
        }
        .displayName("Talk to 11am")
        .description("Opens 11am listening, the same as holding the 11.")
    }
}
