import SwiftUI

@main
struct ElevenAmApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup("11am", id: "main") {
            RootView()
                .withAppEnvironment(appDelegate.model)
                .frame(minWidth: 980, minHeight: 640)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1240, height: 800)
        .commands {
            CommandMenu("Team") {
                // ⌥Space is registered system-wide by AppDelegate, so the menu item carries no shortcut.
                Button("Ask the Team (⌥Space)") { appDelegate.openAsk() }
                Button("Run Tonight's Work Now") {
                    Task { await appDelegate.model.nightShift.runNow() }
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                Divider()
                Button("Show or Hide Agent Pane") {
                    appDelegate.model.showsPane.toggle()
                }
                .keyboardShortcut("\\", modifiers: .command)
            }
            CommandGroup(after: .sidebar) {
                ForEach(AppSection.allCases.filter { $0.shortcutNumber != nil }) { section in
                    Button(section.title) { appDelegate.model.go(to: section) }
                        .keyboardShortcut(KeyEquivalent(Character("\(section.shortcutNumber ?? 1)")), modifiers: .command)
                }
                ForEach(AppSection.allCases.filter { $0.shortcutNumber == nil }) { section in
                    Button(section.title) { appDelegate.model.go(to: section) }
                }
            }
        }

        Settings {
            SettingsView()
                .withAppEnvironment(appDelegate.model)
        }
    }
}

extension View {
    /// Injects every shared model so any view in the tree can read it.
    func withAppEnvironment(_ model: AppModel) -> some View {
        self
            .environmentObject(model)
            .environmentObject(model.theme)
            .environmentObject(model.machine)
            .environmentObject(model.brain)
            .environmentObject(model.files)
            .environmentObject(model.today)
            .environmentObject(model.nightShift)
            .environmentObject(model.voice)
            .environmentObject(model.mail)
            .environmentObject(model.calendar)
            .environmentObject(model.write)
            .environmentObject(model.research)
            .environmentObject(model.money)
            .environmentObject(model.business)
            .environmentObject(model.design)
            .environmentObject(model.looks)
            .environmentObject(model.photo)
            .environmentObject(model.video)
            .environmentObject(model.learn)
            .environmentObject(model.build)
    }
}
