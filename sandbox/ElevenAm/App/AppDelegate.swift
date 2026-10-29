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
        applyLaunchArguments(notch: notch)
    }

    /// Developer flags for screenshots and quick checks, e.g.
    /// `ElevenAm -startSection lab -forceAppearance dark -openNotch YES -activate YES`
    private func applyLaunchArguments(notch: NotchController) {
        let arguments = UserDefaults.standard
        if let start = arguments.string(forKey: "startSection"), let section = AppSection(rawValue: start) {
            model.section = section
        }
        if let appearance = arguments.string(forKey: "forceAppearance"), let value = Appearance(rawValue: appearance) {
            model.theme.values.appearance = value
        }
        if arguments.bool(forKey: "openNotch") {
            notch.openPreview()
        }
        if let tool = arguments.string(forKey: "photoTool"), let value = PhotoTool(rawValue: tool) {
            model.photo.tool = value
        }
        // -photoLook and -videoLook take a built-in look's name, e.g. "Teal & orange".
        if let name = arguments.string(forKey: "photoLook"), let look = LookLibrary.builtIns.first(where: { $0.name == name }) {
            model.photo.settings = look.settings
        }
        if arguments.bool(forKey: "videoSample") {
            let look = arguments.string(forKey: "videoLook").flatMap { name in LookLibrary.builtIns.first { $0.name == name } }
            model.video.loadSamples(grade: look?.settings)
        }
        if arguments.bool(forKey: "activate") {
            NSApp.activate()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // 11am keeps living in the notch when its windows are closed.
        false
    }

    func openAsk() {
        notch?.openAsk()
    }
}
