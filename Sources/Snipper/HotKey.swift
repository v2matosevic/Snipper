import AppKit
import Carbon.HIToolbox

/// Registers one system-wide hotkey via Carbon's `RegisterEventHotKey`.
///
/// Carbon hotkeys are global without needing Accessibility permission
/// (unlike `CGEventTap`), which keeps Snipper's permission footprint to just
/// Screen Recording. The hotkey fires regardless of which app is frontmost.
final class HotKey {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private let action: () -> Void

    /// - Parameters:
    ///   - keyCode: a `kVK_ANSI_*` virtual key code (e.g. `kVK_ANSI_S`).
    ///   - modifiers: Carbon modifier mask, e.g. `UInt32(shiftKey | optionKey)`.
    ///   - action: invoked on the main thread each time the combo is pressed.
    init?(keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) {
        self.action = action

        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let context = Unmanaged.passUnretained(self).toOpaque()

        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData -> OSStatus in
                guard let userData else { return OSStatus(eventNotHandledErr) }
                let me = Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue()
                me.action()
                return noErr
            },
            1, &spec, context, &eventHandler
        )
        guard installStatus == noErr else { return nil }

        let id = EventHotKeyID(signature: OSType(0x534E4950), id: 1) // 'SNIP'
        let registerStatus = RegisterEventHotKey(
            keyCode, modifiers, id, GetApplicationEventTarget(), 0, &hotKeyRef
        )
        guard registerStatus == noErr else { return nil }
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }
}
