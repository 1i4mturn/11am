import SwiftUI

/// For screenshots and checking by eye: the Live Activity's Lock Screen note and the Dynamic Island, compact and
/// expanded, at rest and listening, drawn with the same views the widget uses.
struct ActivityPreview: View {
    @EnvironmentObject private var model: PhoneModel

    private var next: ElevenActivity.ContentState {
        let event = model.brief?.events.first { $0.end > Date() }
        return ElevenActivity.ContentState(agent: "le", line: event?.title ?? "Acme pricing review", place: event?.location ?? "Acme, Level 4",
                                           starts: Date().addingTimeInterval(12 * 60 + 40), listening: false)
    }

    private var listening: ElevenActivity.ContentState {
        var state = next
        state.listening = true
        return state
    }

    var body: some View {
        ZStack {
            PhoneBrand.drop.ignoresSafeArea()
            PhoneTooth().ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text("lock screen").font(BrandFace.label(13))
                    ActivityLockNote(state: next)
                        .background(RoundedRectangle(cornerRadius: PhoneBrand.radiusNotification, style: .continuous).fill(PhoneBrand.note))
                    ActivityLockNote(state: listening)
                        .background(RoundedRectangle(cornerRadius: PhoneBrand.radiusNotification, style: .continuous).fill(PhoneBrand.note))

                    Text("dynamic island").font(BrandFace.label(13))
                    HStack(spacing: 12) {
                        compact(next)
                        compact(listening)
                    }
                    expanded(next)
                    expanded(listening)

                    Text("control center").font(BrandFace.label(13))
                    HStack(spacing: 12) {
                        VStack(spacing: 8) {
                            PhoneAgentCircle(code: "11", size: 56, style: .paper)
                            Text("Talk to 11am").font(.brand(size: 12, weight: .medium))
                        }
                        .frame(width: 120, height: 120)
                        .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(PhoneBrand.sheetInk))
                        Text("Add it in Control Center, or set the Action button to Shortcut › Talk to 11am.")
                            .font(.brand(size: 14))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Button("Done") { model.showsActivityPreview = false }
                        .buttonStyle(InkButtonStyle(secondary: true))
                        .environment(\.colorScheme, .dark)
                }
                .padding(20)
            }
        }
        .foregroundStyle(.white)
    }

    private func compact(_ state: ElevenActivity.ContentState) -> some View {
        HStack {
            ActivityAgent(state: state, size: 22)
            Spacer(minLength: 30)
            ActivityCountdown(state: state, compact: true)
        }
        .padding(.horizontal, 10)
        .frame(height: 36)
        .background(Capsule().fill(Color.black))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.2), lineWidth: 0.5))
    }

    private func expanded(_ state: ElevenActivity.ContentState) -> some View {
        ActivityExpanded(state: state)
            .padding(18)
            .background(RoundedRectangle(cornerRadius: 40, style: .continuous).fill(Color.black))
            .overlay(RoundedRectangle(cornerRadius: 40, style: .continuous).strokeBorder(Color.white.opacity(0.2), lineWidth: 0.5))
    }
}
