import AppKit
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            BrainSettings()
                .tabItem { Label("Brain", systemImage: "cpu") }
            MacSettings()
                .tabItem { Label("This Mac", systemImage: "laptopcomputer") }
        }
        .frame(width: 560, height: 560)
    }
}

private struct BrainSettings: View {
    @EnvironmentObject private var brain: Brain
    @State private var keyDraft = ""
    @State private var testResult = ""
    @State private var testing = false
    @State private var localResult = ""

    var body: some View {
        Form {
            Section("How 11am thinks") {
                Picker("Mode", selection: $brain.mode) {
                    ForEach(BrainMode.allCases) { mode in Text(mode.title).tag(mode) }
                }
                Text(brain.mode.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                LabeledContent("Apple on-device model", value: brain.appleStatus.detail)
            }

            Section {
                if brain.hasClaudeKey {
                    LabeledContent("API key", value: "Saved in Keychain")
                    HStack {
                        Button(testing ? "Testing…" : "Test Connection") { test(key: nil) }
                            .disabled(testing)
                        Button("Remove Key", role: .destructive) { brain.removeClaudeKey() }
                    }
                } else {
                    SecureField("sk-ant-…", text: $keyDraft)
                    HStack {
                        Button("Save Key") {
                            brain.saveClaudeKey(keyDraft)
                            keyDraft = ""
                        }
                        .disabled(keyDraft.isEmpty)
                        Button(testing ? "Testing…" : "Test") { test(key: keyDraft) }
                            .disabled(keyDraft.isEmpty || testing)
                    }
                }
                if !testResult.isEmpty {
                    Text(testResult).font(.caption).foregroundStyle(.secondary)
                }
                Picker("Model", selection: $brain.claudeModel) {
                    ForEach(ClaudeModel.all) { model in
                        Text("\(model.name) · \(model.note) · $\(price(model.inputPerMillion)) in / $\(price(model.outputPerMillion)) out per M")
                            .tag(model.id)
                    }
                }
                LabeledContent("Spent this month", value: "\(Pricing.format(brain.spentThisMonthUSD)) of \(Pricing.format(brain.monthlyBudgetUSD))")
                Stepper("Monthly cap: US$\(Int(brain.monthlyBudgetUSD))", value: $brain.monthlyBudgetUSD, in: 1...200, step: 1)
                Toggle("Allow Claude for overnight work", isOn: $brain.allowCloudOvernight)
            } header: {
                Text("Claude (optional)")
            } footer: {
                Text("Uses an API key from platform.claude.com. API credits are billed separately from a claude.ai Pro or Max plan. 11am stops using Claude when the monthly cap is reached.")
                    .font(.caption)
            }

            Section {
                Toggle("Use a local model server", isOn: $brain.localServerEnabled)
                TextField("Server URL", text: $brain.localServerURL)
                TextField("Model name", text: $brain.localServerModel)
                HStack {
                    Button("Check Server") {
                        Task {
                            let ok = await LocalServerProvider(baseURL: brain.localServerURL, model: brain.localServerModel).isReachable()
                            localResult = ok ? "Reachable." : "Not reachable. Is Ollama or LM Studio running?"
                        }
                    }
                    if !localResult.isEmpty { Text(localResult).font(.caption).foregroundStyle(.secondary) }
                }
            } header: {
                Text("Local model server (optional)")
            } footer: {
                Text("Used when Apple's on-device model isn't available. Ollama: http://localhost:11434/v1 · LM Studio: http://localhost:1234/v1. On 8 GB, keep to small models (2–4B).")
                    .font(.caption)
            }
        }
        .formStyle(.grouped)
    }

    private func price(_ value: Double) -> String {
        value < 1 ? String(format: "%.2f", value) : String(format: "%.0f", value)
    }

    private func test(key: String?) {
        guard let key = key ?? Keychain.read(account: Keychain.claudeAccount) else { return }
        testing = true
        testResult = ""
        Task {
            testResult = await ClaudeProvider.testKey(key, model: brain.claudeModel)
            testing = false
        }
    }
}

private struct MacSettings: View {
    @EnvironmentObject private var machine: MachineProfile

    var body: some View {
        Form {
            Section("This Mac") {
                LabeledContent("Chip", value: machine.chip)
                LabeledContent("Memory", value: "\(machine.memoryGB) GB")
                LabeledContent("Mode", value: machine.tier.title)
                Text(machine.tier.guidance)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Right now") {
                LabeledContent("Power", value: machine.onACPower ? "Charging" : "Battery")
                LabeledContent("Low Power Mode", value: machine.lowPowerMode ? "On" : "Off")
                LabeledContent("Temperature", value: machine.thermalTitle)
                LabeledContent("Memory pressure", value: machine.memoryPressure.rawValue.capitalized)
            }
        }
        .formStyle(.grouped)
    }
}
