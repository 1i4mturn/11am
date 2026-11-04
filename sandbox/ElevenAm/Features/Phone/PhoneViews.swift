import Charts
import SwiftUI

/// Pair the iPhone: a QR code with the key, and what's connected.
struct PhonePairingSheet: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var phone: PhoneLinkModel
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss
    /// In Settings there's nothing to dismiss.
    var showsDone = true

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Your iPhone")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(theme.ink(scheme))
                    Text("Energy from Apple Health, things you capture, your brief on the go.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(theme.inkSecondary(scheme))
                }
                Spacer()
                if showsDone {
                    Button("Done") { dismiss() }
                        .buttonStyle(.vellumSecondary)
                        .keyboardShortcut(.cancelAction)
                }
            }
            if phone.pairing == nil {
                VStack(alignment: .leading, spacing: 10) {
                    Step(number: 1, text: "Put the 11am app on your iPhone (see “Your iPhone” in the README; Xcode installs it with your Apple ID).")
                    Step(number: 2, text: "Make a pairing code here, then scan it from the iPhone app's Mac tab.")
                    Button("Make a pairing code") { phone.makePairing() }
                        .buttonStyle(.vellumPrimary)
                }
            } else {
                HStack(alignment: .top, spacing: 18) {
                    if let image = phone.qrImage {
                        Image(nsImage: image)
                            .interpolation(.none)
                            .resizable()
                            .frame(width: 190, height: 190)
                            .padding(10)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color.white))
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        Text("On the iPhone, open 11am › Mac › Scan the code.")
                            .font(.system(size: 13))
                            .foregroundStyle(theme.ink(scheme))
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Or copy the link and paste it on the iPhone (Universal Clipboard carries it across).")
                            .font(.system(size: 12))
                            .foregroundStyle(theme.inkSecondary(scheme))
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Copy the pairing link") { phone.copyPairingLink() }
                            .buttonStyle(.vellumSecondary)
                        HStack(spacing: 6) {
                            Circle().fill(phone.isConnected ? Color.green : (phone.listening ? Color.orange : Color.gray)).frame(width: 7, height: 7)
                            Text(status)
                                .font(.system(size: 12))
                                .foregroundStyle(theme.inkSecondary(scheme))
                        }
                        if let problem = phone.problem {
                            Text(problem)
                                .font(.system(size: 11.5))
                                .foregroundStyle(.red)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                Text("The code holds a key made on this Mac. Everything between the two is sealed with it, and they talk directly on your network: no server, no account. Anyone who sees the code could pair, so make a new one if you've shared a screenshot.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(theme.inkTertiary(scheme))
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Make a new code") { phone.makePairing() }
                        .buttonStyle(.vellumSecondary)
                    Button("Unpair", role: .destructive) { phone.unpair() }
                        .buttonStyle(.vellumSecondary)
                }
            }
            if !phone.activity.isEmpty {
                SectionLabel(text: "Recently")
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(phone.activity, id: \.self) { line in
                            Text(line)
                                .font(.system(size: 11.5).monospacedDigit())
                                .foregroundStyle(theme.inkSecondary(scheme))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 110)
            }
        }
        .padding(22)
        .frame(width: 520)
        .onAppear { phone.start() }
    }

    private var status: String {
        if let first = phone.phones.first { return "\(first.name) is connected." }
        return phone.listening ? "Waiting for the iPhone on this network…" : "Not listening yet."
    }
}

private struct Step: View {
    @EnvironmentObject private var theme: Theme
    @Environment(\.colorScheme) private var scheme
    var number: Int
    var text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(number)")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(theme.paper(scheme))
                .frame(width: 18, height: 18)
                .background(Circle().fill(theme.ink(scheme)))
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(theme.ink(scheme))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Energy on Today: last night against your usual, and the last two weeks.
struct EnergyCard: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var phone: PhoneLinkModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let latest = phone.latest
        let reading = EnergyInsight.reading(today: latest.today, yesterday: latest.yesterday, baseline: latest.baseline)
        Card {
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        SectionLabel(text: "Energy")
                        if let reading {
                            Text(reading.headline)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(colour(reading.tone))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(colour(reading.tone).opacity(0.14)))
                        }
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(latest.today?.sleepMinutes.map(EnergyFormat.duration) ?? "–")
                            .font(.system(size: 26, weight: .bold).monospacedDigit())
                            .foregroundStyle(theme.ink(scheme))
                        if let usual = latest.baseline.sleepMinutes {
                            Text("asleep · usual \(EnergyFormat.duration(usual))")
                                .font(.system(size: 12))
                                .foregroundStyle(theme.inkTertiary(scheme))
                        }
                    }
                    if let reading {
                        Text(([reading.detail] + reading.suggestions.prefix(1)).filter { !$0.isEmpty }.joined(separator: " "))
                            .font(.system(size: 12.5))
                            .foregroundStyle(theme.inkSecondary(scheme))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    HStack(spacing: 16) {
                        figure("Steps yesterday", latest.yesterday?.steps.map(EnergyFormat.number))
                        figure("Resting HR", latest.today?.restingHeartRate.map { "\(Int($0))" })
                        figure("HRV", latest.today?.heartRateVariability.map { "\(Int($0)) ms" })
                    }
                    .padding(.top, 2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Chart {
                    ForEach(phone.energy.suffix(14)) { day in
                        if let minutes = day.sleepMinutes, let date = day.date {
                            BarMark(x: .value("Night", date, unit: .day), y: .value("Hours", minutes / 60))
                                .foregroundStyle(day.id == phone.energy.last?.id ? Color(red: 0.96, green: 0.42, blue: 0.24) : theme.ink(scheme).opacity(0.7))
                                .cornerRadius(3)
                        }
                    }
                    if let usual = latest.baseline.sleepMinutes {
                        RuleMark(y: .value("Usual", usual / 60))
                            .foregroundStyle(theme.inkTertiary(scheme))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    }
                }
                .chartYAxis { AxisMarks(position: .trailing, values: [0, 4, 8]) { value in
                    AxisGridLine()
                    AxisValueLabel { if let hours = value.as(Int.self) { Text("\(hours) h") } }
                } }
                .chartXAxis { AxisMarks(values: .stride(by: .day, count: 2)) { _ in AxisValueLabel(format: .dateTime.weekday(.narrow)) } }
                .frame(width: 260, height: 120)
            }
            Text("From Apple Health on your iPhone. Leo uses it to shape your day; it isn't medical advice and isn't sent to a cloud model unless you allow cloud help.")
                .font(.system(size: 10.5))
                .foregroundStyle(theme.inkTertiary(scheme))
        }
    }

    private func figure(_ title: String, _ value: String?) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value ?? "–")
                .font(.system(size: 14, weight: .semibold).monospacedDigit())
                .foregroundStyle(theme.ink(scheme))
            Text(title)
                .font(.system(size: 10.5))
                .foregroundStyle(theme.inkTertiary(scheme))
        }
    }

    private func colour(_ tone: EnergyInsight.Tone) -> Color {
        switch tone {
        case .good: return Color(red: 0.3, green: 0.62, blue: 0.4)
        case .usual: return theme.inkSecondary(scheme)
        case .easy: return Color(red: 0.9, green: 0.4, blue: 0.22)
        }
    }
}
