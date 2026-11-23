import SwiftUI

@main
struct ElevenAmApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        // Before any window is built: views drawn earlier would keep a fallback face for good.
        FontRegistry.registerBundledFonts()
    }

    // Each app opens in its own window, made by `AppWindows` (AppDelegate restores them at launch), so the only
    // SwiftUI scene is Settings; the menus hang off it.
    var body: some Scene {
        Settings {
            SettingsView()
                .withAppEnvironment(appDelegate.model)
        }
        .commands {
            CommandMenu("Team") {
                // ⌥Space is registered system-wide by AppDelegate, so the menu item carries no shortcut.
                Button("Talk to the Team (hold ⌥Space)") { appDelegate.openAsk() }
                Button("Show or Hide the Puck") { appDelegate.togglePuck() }
                Button("New Quick Note (⌥⇧N)") { appDelegate.quickNote() }
                Button("Run Tonight's Work Now") {
                    Task { await appDelegate.model.nightShift.runNow() }
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                Divider()
                Button("Ask the Agent for This App") {
                    appDelegate.toggleAgent()
                }
                .keyboardShortcut("\\", modifiers: .command)
            }
            // ⌘1…⌘9 open (or bring forward) the first nine apps' windows.
            CommandMenu("Apps") {
                ForEach(AppSection.allCases.filter { $0.shortcutNumber != nil }) { section in
                    Button(section.title) { appDelegate.model.go(to: section) }
                        .keyboardShortcut(KeyEquivalent(Character("\(section.shortcutNumber ?? 1)")), modifiers: .command)
                }
                Divider()
                ForEach(AppSection.allCases.filter { $0.shortcutNumber == nil }) { section in
                    Button(section.title) { appDelegate.model.go(to: section) }
                }
            }
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
            .environmentObject(model.browser)
            .environmentObject(model.today)
            .environmentObject(model.nightShift)
            .environmentObject(model.voice)
            .environmentObject(model.mail)
            .environmentObject(model.calendar)
            .environmentObject(model.notes)
            .environmentObject(model.pdf)
            .environmentObject(model.write)
            .environmentObject(model.research)
            .environmentObject(model.money)
            .environmentObject(model.ledger)
            .environmentObject(model.sheets)
            .environmentObject(model.business)
            .environmentObject(model.design)
            .environmentObject(model.studio)
            .environmentObject(model.decks)
            .environmentObject(model.looks)
            .environmentObject(model.photo)
            .environmentObject(model.video)
            .environmentObject(model.audio)
            .environmentObject(model.learn)
            .environmentObject(model.build)
            .environmentObject(model.terminal)
            .environmentObject(model.scripts)
            .environmentObject(model.automations)
            .environmentObject(model.phone)
            .environmentObject(model.languages)
            .environmentObject(model.tasks)
            .environmentObject(model.windows)
            .environmentObject(model.shelf)
            .modifier(BrandEnvironment())
    }
}

/// Brand v2 for everything underneath: Instrument Sans as the default face, and ink in place of an accent colour.
private struct BrandEnvironment: ViewModifier {
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        content
            .font(BrandFont.body(13))
            .tint(BrandTokens.ink(scheme))
    }
}
