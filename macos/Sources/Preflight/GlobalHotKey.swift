import Carbon

// Register a dedicated shortcut; no keystroke stream or send interception is needed.
@MainActor
final class GlobalHotKey {
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    let action: @MainActor () -> Void

    init(action: @escaping @MainActor () -> Void) { self.action = action }

    func start() throws {
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let result = InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context else { return OSStatus(eventNotHandledErr) }
            // Carbon application event handlers run on the main event loop.
            MainActor.assumeIsolated {
                Unmanaged<GlobalHotKey>.fromOpaque(context).takeUnretainedValue().action()
            }
            return noErr
        }, 1, &event, Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard result == noErr else { throw ClientError.message("Could not register the shortcut handler. Use the menu bar instead.") }
        let identifier = EventHotKeyID(signature: 0x5052464C, id: 1)
        let status = RegisterEventHotKey(UInt32(kVK_Return), UInt32(cmdKey | optionKey), identifier, GetApplicationEventTarget(), 0, &hotKey)
        guard status == noErr else {
            stop()
            throw ClientError.message("⌥⌘Return is already in use. You can open Preflight from the menu bar.")
        }
    }

    func stop() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
        hotKey = nil
        handler = nil
    }
}
