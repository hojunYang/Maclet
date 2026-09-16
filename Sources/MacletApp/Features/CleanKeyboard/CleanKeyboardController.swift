import AppKit

enum CleanKeyboardEventFilter {
    static func shouldIgnore(_ type: CGEventType) -> Bool {
        type == .keyDown || type == .keyUp || type == .flagsChanged
    }
}

private let cleanKeyboardEventCallback: CGEventTapCallBack = { _, type, event, _ in
    CleanKeyboardEventFilter.shouldIgnore(type) ? nil : Unmanaged.passUnretained(event)
}

@MainActor
final class CleanKeyboardController {
    func begin() {
        guard AXIsProcessTrusted() else {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            AXIsProcessTrustedWithOptions(options)
            showPermissionAlert()
            return
        }

        let eventMask = [CGEventType.keyDown, .keyUp, .flagsChanged].reduce(CGEventMask()) {
            $0 | (CGEventMask(1) << $1.rawValue)
        }
        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: cleanKeyboardEventCallback,
            userInfo: nil
        ), let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0) else {
            showPermissionAlert()
            return
        }

        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
        defer {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            CFMachPortInvalidate(eventTap)
        }

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Keyboard Cleaning Mode"
        alert.informativeText = "All keyboard input is being ignored. Use your mouse to stop cleaning."
        alert.addButton(withTitle: "Stop Cleaning")
        alert.window.level = NSWindow.Level(rawValue: NSWindow.Level.modalPanel.rawValue + 1)

        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private func showPermissionAlert() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Accessibility Access Required"
        alert.informativeText = "Allow Maclet in System Settings > Privacy & Security > Accessibility, then try again."
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")

        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
