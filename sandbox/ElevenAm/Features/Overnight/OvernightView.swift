import SwiftUI

/// Makes the "works with your Mac, not against it" promise visible.
struct OvernightView: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var nightShift: NightShift
    @EnvironmentObject private var machine: MachineProfile
    @EnvironmentObject private var brain: Brain
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let decision = nightShift.conditions()
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                SectionHeader(title: "overnight", subtitle: "Heavy work waits until your Mac is free, so it never slows you down.") {
                    Button(nightShift.isRunning ? "Running…" : "Run Now") {
                        Task { await nightShift.runNow() }
                    }
                    .buttonStyle(.vellumPrimary)
                    .disabled(nightShift.isRunning)
                }

                HStack(alignment: .top, spacing: 14) {
                    StatusTile(label: "Right now", value: decision.ok ? "Good time" : "Waiting", detail: decision.reason)
                    StatusTile(label: "Power", value: machine.onACPower ? "Charging" : "Battery", detail: machine.lowPowerMode ? "Low Power Mode on" : "Normal power")
                    StatusTile(label: "Temperature", value: machine.thermalTitle, detail: "Pauses if the Mac gets warm")
                    StatusTile(label: "Memory", value: machine.memoryPressure.rawValue.capitalized, detail: "\(machine.memoryGB) GB · \(machine.tier.title) mode")
                }

                Card {
                    SectionLabel(text: "Rules")
                    HStack(spacing: 14) {
                        Stepper("Window starts \(nightShift.windowStartHour):00", value: $nightShift.windowStartHour, in: 0...23)
                        Stepper("ends \(nightShift.windowEndHour):00", value: $nightShift.windowEndHour, in: 0...23)
                    }
                    .font(.system(size: 12.5))
                    Toggle("Only when plugged in", isOn: $nightShift.requiresPower)
                        .font(.system(size: 12.5))
                    Stepper("Or when idle for \(nightShift.idleMinutes) minutes", value: $nightShift.idleMinutes, in: 5...120, step: 5)
                        .font(.system(size: 12.5))
                    Toggle("Allow Claude for overnight work", isOn: $brain.allowCloudOvernight)
                        .font(.system(size: 12.5))
                        .help("Off: overnight work only uses the brain on this Mac, so it costs nothing.")
                    Text(machine.tier.guidance)
                        .font(.system(size: 12))
                        .foregroundStyle(theme.inkTertiary(scheme))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(theme.ink(scheme))

                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel(text: "Tonight's jobs")
                    ForEach(nightShift.jobs) { job in
                        HStack(alignment: .top, spacing: 12) {
                            Monogram(text: job.monogram, size: 26)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(job.title)
                                    .font(.system(size: 13.5, weight: .semibold))
                                    .foregroundStyle(theme.ink(scheme))
                                Text(job.detail)
                                    .font(.system(size: 12))
                                    .foregroundStyle(theme.inkSecondary(scheme))
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 0) {
                    SectionLabel(text: "Log").padding(.bottom, 6)
                    if nightShift.log.isEmpty {
                        Text("Nothing has run yet. Press Run Now to try tonight's jobs immediately.")
                            .font(.system(size: 12.5))
                            .foregroundStyle(theme.inkTertiary(scheme))
                    }
                    ForEach(nightShift.log) { entry in
                        HStack(alignment: .firstTextBaseline, spacing: 14) {
                            Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                                .font(.system(size: 11.5).monospacedDigit())
                                .foregroundStyle(theme.inkTertiary(scheme))
                                .frame(width: 130, alignment: .leading)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.title)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(theme.ink(scheme))
                                Text(entry.detail)
                                    .font(.system(size: 12))
                                    .foregroundStyle(theme.inkSecondary(scheme))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }

                if let last = nightShift.lastCheck {
                    Text("Last checked \(last.formatted(date: .omitted, time: .shortened)): \(nightShift.lastDecision)")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.inkTertiary(scheme))
                }
            }
            .padding(28)
        }
        .scrollContentBackground(.hidden)
    }
}

private struct StatusTile: View {
    @EnvironmentObject private var theme: Theme
    @Environment(\.colorScheme) private var scheme
    var label: String
    var value: String
    var detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(text: label)
            Text(value)
                .font(theme.display(24))
                .foregroundStyle(theme.ink(scheme))
            Text(detail)
                .font(.system(size: 11.5))
                .foregroundStyle(theme.inkTertiary(scheme))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .vellum(level: 3, radius: max(theme.radius - 6, 8))
    }
}
