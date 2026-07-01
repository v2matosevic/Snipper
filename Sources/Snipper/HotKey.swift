import AppKit
import Carbon.HIToolbox

/// Registers one system-wide hotkey via Carbon's `RegisterEventHotKey`.
///
/// Carbon hotkeys are global without needing Accessibility permission
/// (unlike `CGEventTap`), which keeps Snipper's permission footprint to just
/// Screen Recording. The hotkey fires regardless of which app is frontmost.
///
/// Multiple instances coexist: each registers under a unique Carbon id, and
/// each handler checks the fired hotkey's id — returning `eventNotHandledErr`
/// for someone else's key so Carbon keeps walking the handler chain until the
/// owner runs its action.
final class HotKey {
    private static var nextID: UInt32 = 1

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private let hotKeyID: EventHotKeyID
    private let action: () -> Void

    /// - Parameters:
    ///   - keyCode: a `kVK_ANSI_*` virtual key code (e.g. `kVK_ANSI_S`).
    ///   - modifiers: Carbon modifier mask, e.g. `UInt32(shiftKey | optionKey)`.
    ///   - action: invoked on the main thread each time the combo is pressed.
    init?(keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) {
        self.action = action
        self.hotKeyID = EventHotKeyID(signature: OSType(0x534E4950), // 'SNIP'
                                      id: HotKey.nextID)
        HotKey.nextID += 1

        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let context = Unmanaged.passUnretained(self).toOpaque()

        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData -> OSStatus in
                guard let event, let userData else { return OSStatus(eventNotHandledErr) }
                var fired = EventHotKeyID()
                GetEventParameter(event,
                                  EventParamName(kEventParamDirectObject),
                                  EventParamType(typeEventHotKeyID),
                                  nil,
                                  MemoryLayout<EventHotKeyID>.size,
                                  nil,
                                  &fired)
                let me = Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue()
                guard fired.id == me.hotKeyID.id else { return OSStatus(eventNotHandledErr) }
                me.action()
                return noErr
            },
            1, &spec, context, &eventHandler
        )
        guard installStatus == noErr else { return nil }

        let registerStatus = RegisterEventHotKey(
            keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef
        )
        guard registerStatus == noErr else { return nil }
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }
}
