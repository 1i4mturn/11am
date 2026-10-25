import AppKit
import Carbon.HIToolbox

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private var notch: NotchController?
    private var askHotKey: HotKey?

    func applicationDidFinishLaunching(_ notification: Notification) {
        FontRegistry.registerBundledFonts()

        let notch = NotchController(model: model)
        notch.show()
        self.notch = notch

        // ⌥Space opens Ask in the notch from anywhere.
        askHotKey = HotKey(keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey)) { [weak self] in
            self?.openAsk()
        }

        model.start()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // 11am keeps living in the notch when its windows are closed.
        false
    }

    func openAsk() {
        notch?.openAsk()
    }
}
