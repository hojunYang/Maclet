import AppKit
import Carbon
import MacletCore

private let globalHotKeySignature: OSType = 0x4D_4C_45_54 // MLET
private let globalHotKeyIdentifier: UInt32 = 1

private func handleGlobalHotKey(
    _ handlerCall: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event, let userData else {
        return OSStatus(eventNotHandledErr)
    }

    var identifier = EventHotKeyID()
    let parameterStatus = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &identifier
    )
    guard parameterStatus == noErr,
          identifier.signature == globalHotKeySignature,
          identifier.id == globalHotKeyIdentifier else {
        return OSStatus(eventNotHandledErr)
    }

    let manager = Unmanaged<GlobalHotKeyManager>
        .fromOpaque(userData)
        .takeUnretainedValue()
    manager.performAction()
    return noErr
}

final class GlobalHotKeyManager {
    private let action: () -> Void
    private var eventHandler: EventHandlerRef?
    private var hotKeyRef: EventHotKeyRef?

    init(action: @escaping () -> Void) {
        self.action = action
    }

    deinit {
        unregister()
        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
    }

    func setShortcut(_ shortcut: GlobalShortcut?) -> String? {
        unregister()

        guard let shortcut else {
            return nil
        }

        if let error = installEventHandlerIfNeeded() {
            return error
        }

        let identifier = EventHotKeyID(
            signature: globalHotKeySignature,
            id: globalHotKeyIdentifier
        )
        var registeredHotKey: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(shortcut.keyCode),
            shortcut.carbonModifierFlags,
            identifier,
            GetApplicationEventTarget(),
            OptionBits(kEventHotKeyNoOptions),
            &registeredHotKey
        )

        guard status == noErr, let registeredHotKey else {
            return Self.errorMessage(for: status)
        }

        hotKeyRef = registeredHotKey
        return nil
    }

    private func installEventHandlerIfNeeded() -> String? {
        guard eventHandler == nil else {
            return nil
        }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        var installedHandler: EventHandlerRef?
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            handleGlobalHotKey,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &installedHandler
        )

        guard status == noErr, let installedHandler else {
            return Self.errorMessage(for: status)
        }

        eventHandler = installedHandler
        return nil
    }

    private func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
    }

    fileprivate func performAction() {
        action()
    }

    private static func errorMessage(for status: OSStatus) -> String {
        let description = NSError(domain: NSOSStatusErrorDomain, code: Int(status)).localizedDescription
        return "Could not register this shortcut. \(description)"
    }
}

extension GlobalShortcut {
    static func make(from event: NSEvent) -> GlobalShortcut? {
        var modifiers = Set<ShortcutModifier>()
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        if flags.contains(.function) { modifiers.insert(.function) }
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.command) { modifiers.insert(.command) }

        guard !modifiers.isEmpty else {
            return nil
        }

        return GlobalShortcut(keyCode: event.keyCode, modifiers: modifiers)
    }

    var displayName: String {
        let modifierNames: [(ShortcutModifier, String)] = [
            (.function, "fn"),
            (.control, "⌃"),
            (.option, "⌥"),
            (.shift, "⇧"),
            (.command, "⌘")
        ]
        let prefixes = modifierNames.compactMap { modifier, name in
            modifiers.contains(modifier) ? name : nil
        }
        return (prefixes + [Self.keyNames[keyCode] ?? "Key \(keyCode)"])
            .joined(separator: " + ")
    }

    fileprivate var carbonModifierFlags: UInt32 {
        var flags: UInt32 = 0
        if modifiers.contains(.function) { flags |= UInt32(kEventKeyModifierFnMask) }
        if modifiers.contains(.control) { flags |= UInt32(controlKey) }
        if modifiers.contains(.option) { flags |= UInt32(optionKey) }
        if modifiers.contains(.shift) { flags |= UInt32(shiftKey) }
        if modifiers.contains(.command) { flags |= UInt32(cmdKey) }
        return flags
    }

    private static let keyNames: [UInt16: String] = [
        UInt16(kVK_ANSI_A): "A", UInt16(kVK_ANSI_B): "B",
        UInt16(kVK_ANSI_C): "C", UInt16(kVK_ANSI_D): "D",
        UInt16(kVK_ANSI_E): "E", UInt16(kVK_ANSI_F): "F",
        UInt16(kVK_ANSI_G): "G", UInt16(kVK_ANSI_H): "H",
        UInt16(kVK_ANSI_I): "I", UInt16(kVK_ANSI_J): "J",
        UInt16(kVK_ANSI_K): "K", UInt16(kVK_ANSI_L): "L",
        UInt16(kVK_ANSI_M): "M", UInt16(kVK_ANSI_N): "N",
        UInt16(kVK_ANSI_O): "O", UInt16(kVK_ANSI_P): "P",
        UInt16(kVK_ANSI_Q): "Q", UInt16(kVK_ANSI_R): "R",
        UInt16(kVK_ANSI_S): "S", UInt16(kVK_ANSI_T): "T",
        UInt16(kVK_ANSI_U): "U", UInt16(kVK_ANSI_V): "V",
        UInt16(kVK_ANSI_W): "W", UInt16(kVK_ANSI_X): "X",
        UInt16(kVK_ANSI_Y): "Y", UInt16(kVK_ANSI_Z): "Z",
        UInt16(kVK_ANSI_0): "0", UInt16(kVK_ANSI_1): "1",
        UInt16(kVK_ANSI_2): "2", UInt16(kVK_ANSI_3): "3",
        UInt16(kVK_ANSI_4): "4", UInt16(kVK_ANSI_5): "5",
        UInt16(kVK_ANSI_6): "6", UInt16(kVK_ANSI_7): "7",
        UInt16(kVK_ANSI_8): "8", UInt16(kVK_ANSI_9): "9",
        UInt16(kVK_Space): "Space", UInt16(kVK_Return): "Return",
        UInt16(kVK_Tab): "Tab", UInt16(kVK_Delete): "Delete",
        UInt16(kVK_ForwardDelete): "Forward Delete",
        UInt16(kVK_Home): "Home", UInt16(kVK_End): "End",
        UInt16(kVK_PageUp): "Page Up", UInt16(kVK_PageDown): "Page Down",
        UInt16(kVK_LeftArrow): "←", UInt16(kVK_RightArrow): "→",
        UInt16(kVK_UpArrow): "↑", UInt16(kVK_DownArrow): "↓",
        UInt16(kVK_F1): "F1", UInt16(kVK_F2): "F2",
        UInt16(kVK_F3): "F3", UInt16(kVK_F4): "F4",
        UInt16(kVK_F5): "F5", UInt16(kVK_F6): "F6",
        UInt16(kVK_F7): "F7", UInt16(kVK_F8): "F8",
        UInt16(kVK_F9): "F9", UInt16(kVK_F10): "F10",
        UInt16(kVK_F11): "F11", UInt16(kVK_F12): "F12"
    ]
}
