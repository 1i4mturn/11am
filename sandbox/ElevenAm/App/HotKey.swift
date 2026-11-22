import Carbon.HIToolbox

/// A system-wide hotkey using Carbon's RegisterEventHotKey. It needs no Accessibility permission.
/// It can also say when the keys are let go, for holding a key to talk.
final class HotKey {
    private static var actions: [UInt32: @MainActor () -> Void] = [:]
    private static var releases: [UInt32: @MainActor () -> Void] = [:]
    private static var nextID: UInt32 = 1
    private static var handlerInstalled = false

    private let id: UInt32
    private var reference: EventHotKeyRef?

    init(keyCode: UInt32, modifiers: UInt32, action: @escaping @MainActor () -> Void, onRelease: (@MainActor () -> Void)? = nil) {
        id = HotKey.nextID
        HotKey.nextID += 1
        HotKey.actions[id] = action
        HotKey.releases[id] = onRelease
        HotKey.installHandlerIfNeeded()

        let hotKeyID = EventHotKeyID(signature: OSType(0x3131_414D), id: id) // "11AM"
        RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &reference)
    }

    deinit {
        if let reference {
            UnregisterEventHotKey(reference)
        }
        HotKey.actions[id] = nil
        HotKey.releases[id] = nil
    }

    private static func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        handlerInstalled = true

        var eventTypes = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            if status == noErr {
                let key = hotKeyID.id
                let released = GetEventKind(event) == UInt32(kEventHotKeyReleased)
                Task { @MainActor in
                    if released { HotKey.releases[key]?() } else { HotKey.actions[key]?() }
                }
            }
            return noErr
        }, 2, &eventTypes, nil, nil)
    }
}
