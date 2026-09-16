import AppKit

@MainActor
enum AppMenuBuilder {
    static func configure(
        applicationName: String = "Maclet",
        settingsTitle: String = "Settings…",
        settingsTarget: AnyObject?,
        settingsAction: Selector,
        quitTitle: String = "Quit Maclet",
        quitTarget: AnyObject?,
        quitAction: Selector,
        closeTitle: String = "Close",
        closeTarget: AnyObject?,
        closeAction: Selector
    ) {
        let mainMenu = NSMenu()
        mainMenu.addItem(applicationMenuItem(
            applicationName: applicationName,
            settingsTitle: settingsTitle,
            settingsTarget: settingsTarget,
            settingsAction: settingsAction,
            quitTitle: quitTitle,
            quitTarget: quitTarget,
            quitAction: quitAction
        ))
        mainMenu.addItem(fileMenuItem(closeTitle: closeTitle, closeTarget: closeTarget, closeAction: closeAction))
        mainMenu.addItem(editMenuItem())
        NSApp.mainMenu = mainMenu
    }

    private static func applicationMenuItem(
        applicationName: String,
        settingsTitle: String,
        settingsTarget: AnyObject?,
        settingsAction: Selector,
        quitTitle: String,
        quitTarget: AnyObject?,
        quitAction: Selector
    ) -> NSMenuItem {
        let menuItem = NSMenuItem()
        let menu = NSMenu(title: applicationName)
        let settingsMenuItem = NSMenuItem(
            title: settingsTitle,
            action: settingsAction,
            keyEquivalent: ","
        )
        settingsMenuItem.target = settingsTarget
        settingsMenuItem.keyEquivalentModifierMask = [.command]
        menu.addItem(settingsMenuItem)
        menu.addItem(.separator())

        let quitMenuItem = NSMenuItem(title: quitTitle, action: quitAction, keyEquivalent: "q")
        quitMenuItem.target = quitTarget
        quitMenuItem.keyEquivalentModifierMask = [.command]
        menu.addItem(quitMenuItem)
        menuItem.submenu = menu
        return menuItem
    }

    private static func fileMenuItem(
        closeTitle: String,
        closeTarget: AnyObject?,
        closeAction: Selector
    ) -> NSMenuItem {
        let menuItem = NSMenuItem()
        let menu = NSMenu(title: "File")
        let closeMenuItem = NSMenuItem(title: closeTitle, action: closeAction, keyEquivalent: "w")
        closeMenuItem.target = closeTarget
        closeMenuItem.keyEquivalentModifierMask = [.command]
        menu.addItem(closeMenuItem)
        menuItem.submenu = menu
        return menuItem
    }

    private static func editMenuItem() -> NSMenuItem {
        let menuItem = NSMenuItem()
        let menu = NSMenu(title: "Edit")

        addItem(to: menu, title: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        addItem(to: menu, title: "Redo", action: Selector(("redo:")), keyEquivalent: "z", modifiers: [.command, .shift])
        menu.addItem(.separator())
        addItem(to: menu, title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        addItem(to: menu, title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        addItem(to: menu, title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        menu.addItem(.separator())
        addItem(to: menu, title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        menuItem.submenu = menu
        return menuItem
    }

    @discardableResult
    private static func addItem(
        to menu: NSMenu,
        title: String,
        action: Selector,
        keyEquivalent: String,
        modifiers: NSEvent.ModifierFlags = [.command]
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = nil
        item.keyEquivalentModifierMask = modifiers
        menu.addItem(item)
        return item
    }
}
