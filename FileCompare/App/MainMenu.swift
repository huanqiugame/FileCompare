import AppKit

@MainActor
enum MainMenu {
    static func build(coordinator: AppCoordinator) -> NSMenu {
        let mainMenu = NSMenu()
        mainMenu.autoenablesItems = true

        mainMenu.addItem(appMenuItem())
        mainMenu.addItem(fileMenuItem(coordinator: coordinator))
        mainMenu.addItem(editMenuItem(coordinator: coordinator))
        mainMenu.addItem(compareMenuItem(coordinator: coordinator))
        mainMenu.addItem(viewMenuItem(coordinator: coordinator))
        mainMenu.addItem(navigateMenuItem(coordinator: coordinator))
        mainMenu.addItem(windowMenuItem())

        applyMenuIcons(to: mainMenu)
        return mainMenu
    }

    /// Menu titles stay textual for accessibility and discoverability; SF
    /// Symbols are added alongside the actions that benefit from a visual cue.
    private static func applyMenuIcons(to mainMenu: NSMenu) {
        let icons: [Selector: String] = [
            #selector(AppCoordinator.openLeftFile(_:)): "sidebar.leading",
            #selector(AppCoordinator.openRightFile(_:)): "sidebar.trailing",
            #selector(AppCoordinator.reloadComparison(_:)): "arrow.clockwise",
            #selector(AppCoordinator.find(_:)): "magnifyingglass",
            #selector(AppCoordinator.findNext(_:)): "chevron.down",
            #selector(AppCoordinator.findPrevious(_:)): "chevron.up",
            #selector(AppCoordinator.swapSides(_:)): "arrow.left.arrow.right",
            #selector(AppCoordinator.toggleLineNumbers(_:)): "list.number",
            #selector(AppCoordinator.increaseFontSize(_:)): "textformat.size.larger",
            #selector(AppCoordinator.decreaseFontSize(_:)): "textformat.size.smaller",
            #selector(AppCoordinator.actualSize(_:)): "textformat.size",
            #selector(AppCoordinator.nextDifference(_:)): "arrow.down.to.line",
            #selector(AppCoordinator.previousDifference(_:)): "arrow.up.to.line"
        ]

        for topLevel in mainMenu.items {
            guard let submenu = topLevel.submenu else { continue }
            for item in submenu.items {
                guard let action = item.action, let symbol = icons[action] else { continue }
                item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            }
        }
    }

    private static func appMenuItem() -> NSMenuItem {
        let item = NSMenuItem()
        let menu = NSMenu(title: "FileCompare")
        menu.autoenablesItems = true

        let about = NSMenuItem(
            title: String(localized: "menu.app.about", defaultValue: "About FileCompare"),
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: ""
        )
        about.target = NSApp
        menu.addItem(about)
        menu.addItem(.separator())

        let services = NSMenu(title: String(localized: "menu.app.services", defaultValue: "Services"))
        let servicesItem = NSMenuItem(
            title: String(localized: "menu.app.services", defaultValue: "Services"),
            action: nil,
            keyEquivalent: ""
        )
        servicesItem.submenu = services
        menu.addItem(servicesItem)
        NSApp.servicesMenu = services
        menu.addItem(.separator())

        let hide = NSMenuItem(
            title: String(localized: "menu.app.hide", defaultValue: "Hide FileCompare"),
            action: #selector(NSApplication.hide(_:)),
            keyEquivalent: "h"
        )
        hide.target = NSApp
        menu.addItem(hide)

        let hideOthers = NSMenuItem(
            title: String(localized: "menu.app.hide_others", defaultValue: "Hide Others"),
            action: #selector(NSApplication.hideOtherApplications(_:)),
            keyEquivalent: "h"
        )
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        hideOthers.target = NSApp
        menu.addItem(hideOthers)

        let showAll = NSMenuItem(
            title: String(localized: "menu.app.show_all", defaultValue: "Show All"),
            action: #selector(NSApplication.unhideAllApplications(_:)),
            keyEquivalent: ""
        )
        showAll.target = NSApp
        menu.addItem(showAll)
        menu.addItem(.separator())

        let quit = NSMenuItem(
            title: String(localized: "menu.app.quit", defaultValue: "Quit FileCompare"),
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        quit.target = NSApp
        menu.addItem(quit)

        item.title = menu.title
        item.submenu = menu
        return item
    }

    private static func fileMenuItem(coordinator: AppCoordinator) -> NSMenuItem {
        let item = NSMenuItem()
        let menu = NSMenu(title: String(localized: "menu.file", defaultValue: "File"))

        menu.addItem(customItem(
            title: String(localized: "menu.file.open_left", defaultValue: "Open Left File…"),
            action: #selector(AppCoordinator.openLeftFile(_:)),
            key: "o",
            coordinator: coordinator
        ))
        menu.addItem(customItem(
            title: String(localized: "menu.file.open_right", defaultValue: "Open Right File…"),
            action: #selector(AppCoordinator.openRightFile(_:)),
            key: "O",
            modifiers: [.command, .shift],
            coordinator: coordinator
        ))
        menu.addItem(.separator())
        menu.addItem(customItem(
            title: String(localized: "menu.file.reload", defaultValue: "Reload"),
            action: #selector(AppCoordinator.reloadComparison(_:)),
            key: "r",
            coordinator: coordinator
        ))
        menu.addItem(customItem(
            title: String(localized: "menu.file.auto_reload", defaultValue: "Auto Reload"),
            action: #selector(AppCoordinator.toggleAutoReload(_:)),
            coordinator: coordinator
        ))
        menu.addItem(.separator())

        let close = NSMenuItem(
            title: String(localized: "menu.file.close", defaultValue: "Close"),
            action: #selector(NSWindow.performClose(_:)),
            keyEquivalent: "w"
        )
        close.target = nil
        menu.addItem(close)

        item.title = menu.title
        item.submenu = menu
        return item
    }

    private static func editMenuItem(coordinator: AppCoordinator) -> NSMenuItem {
        let item = NSMenuItem()
        let menu = NSMenu(title: String(localized: "menu.edit", defaultValue: "Edit"))

        menu.addItem(standardItem(
            String(localized: "menu.edit.undo", defaultValue: "Undo"),
            action: Selector(("undo:")), key: "z"
        ))
        menu.addItem(standardItem(
            String(localized: "menu.edit.redo", defaultValue: "Redo"),
            action: Selector(("redo:")), key: "Z", modifiers: [.command, .shift]
        ))
        menu.addItem(.separator())
        menu.addItem(standardItem(
            String(localized: "menu.edit.cut", defaultValue: "Cut"),
            action: #selector(NSText.cut(_:)), key: "x"
        ))
        menu.addItem(standardItem(
            String(localized: "menu.edit.copy", defaultValue: "Copy"),
            action: #selector(NSText.copy(_:)), key: "c"
        ))
        menu.addItem(standardItem(
            String(localized: "menu.edit.paste", defaultValue: "Paste"),
            action: #selector(NSText.paste(_:)), key: "v"
        ))
        menu.addItem(standardItem(
            String(localized: "menu.edit.select_all", defaultValue: "Select All"),
            action: #selector(NSText.selectAll(_:)), key: "a"
        ))
        menu.addItem(.separator())
        menu.addItem(customItem(
            title: String(localized: "menu.edit.find", defaultValue: "Find…"),
            action: #selector(AppCoordinator.find(_:)),
            key: "f",
            coordinator: coordinator
        ))
        menu.addItem(customItem(
            title: String(localized: "menu.edit.find_next", defaultValue: "Find Next"),
            action: #selector(AppCoordinator.findNext(_:)),
            key: "g",
            coordinator: coordinator
        ))
        menu.addItem(customItem(
            title: String(localized: "menu.edit.find_previous", defaultValue: "Find Previous"),
            action: #selector(AppCoordinator.findPrevious(_:)),
            key: "G",
            modifiers: [.command, .shift],
            coordinator: coordinator
        ))

        item.title = menu.title
        item.submenu = menu
        return item
    }

    private static func compareMenuItem(coordinator: AppCoordinator) -> NSMenuItem {
        let item = NSMenuItem()
        let menu = NSMenu(title: String(localized: "menu.compare", defaultValue: "Compare"))

        menu.addItem(customItem(
            title: String(localized: "menu.compare.swap", defaultValue: "Swap Sides"),
            action: #selector(AppCoordinator.swapSides(_:)),
            key: "x",
            modifiers: [.command, .shift],
            coordinator: coordinator
        ))
        menu.addItem(.separator())
        menu.addItem(customItem(
            title: String(localized: "menu.compare.ignore_whitespace", defaultValue: "Ignore Whitespace"),
            action: #selector(AppCoordinator.toggleIgnoreWhitespace(_:)),
            coordinator: coordinator
        ))
        menu.addItem(customItem(
            title: String(localized: "menu.compare.ignore_case", defaultValue: "Ignore Case"),
            action: #selector(AppCoordinator.toggleIgnoreCase(_:)),
            coordinator: coordinator
        ))

        item.title = menu.title
        item.submenu = menu
        return item
    }

    private static func viewMenuItem(coordinator: AppCoordinator) -> NSMenuItem {
        let item = NSMenuItem()
        let menu = NSMenu(title: String(localized: "menu.view", defaultValue: "View"))

        menu.addItem(customItem(
            title: String(localized: "menu.view.line_numbers", defaultValue: "Show Line Numbers"),
            action: #selector(AppCoordinator.toggleLineNumbers(_:)),
            key: "l",
            modifiers: [.command, .shift],
            coordinator: coordinator
        ))
        menu.addItem(.separator())
        menu.addItem(customItem(
            title: String(localized: "menu.view.increase_text", defaultValue: "Increase Text Size"),
            action: #selector(AppCoordinator.increaseFontSize(_:)),
            key: "=",
            coordinator: coordinator
        ))
        menu.addItem(customItem(
            title: String(localized: "menu.view.decrease_text", defaultValue: "Decrease Text Size"),
            action: #selector(AppCoordinator.decreaseFontSize(_:)),
            key: "-",
            coordinator: coordinator
        ))
        menu.addItem(customItem(
            title: String(localized: "menu.view.actual_size", defaultValue: "Actual Size"),
            action: #selector(AppCoordinator.actualSize(_:)),
            key: "0",
            coordinator: coordinator
        ))
        menu.addItem(.separator())

        let fullScreen = NSMenuItem(
            title: String(localized: "menu.view.full_screen", defaultValue: "Enter Full Screen"),
            action: #selector(NSWindow.toggleFullScreen(_:)),
            keyEquivalent: "f"
        )
        fullScreen.keyEquivalentModifierMask = [.command, .control]
        fullScreen.target = nil
        menu.addItem(fullScreen)

        item.title = menu.title
        item.submenu = menu
        return item
    }

    private static func navigateMenuItem(coordinator: AppCoordinator) -> NSMenuItem {
        let item = NSMenuItem()
        let menu = NSMenu(title: String(localized: "menu.navigate", defaultValue: "Navigate"))

        menu.addItem(customItem(
            title: String(localized: "menu.navigate.next", defaultValue: "Next Difference"),
            action: #selector(AppCoordinator.nextDifference(_:)),
            key: "\u{F701}",
            modifiers: [.command, .option],
            coordinator: coordinator
        ))
        menu.addItem(customItem(
            title: String(localized: "menu.navigate.previous", defaultValue: "Previous Difference"),
            action: #selector(AppCoordinator.previousDifference(_:)),
            key: "\u{F700}",
            modifiers: [.command, .option],
            coordinator: coordinator
        ))

        item.title = menu.title
        item.submenu = menu
        return item
    }

    private static func windowMenuItem() -> NSMenuItem {
        let item = NSMenuItem()
        let menu = NSMenu(title: String(localized: "menu.window", defaultValue: "Window"))

        let minimize = NSMenuItem(
            title: String(localized: "menu.window.minimize", defaultValue: "Minimize"),
            action: #selector(NSWindow.performMiniaturize(_:)),
            keyEquivalent: "m"
        )
        minimize.target = nil
        menu.addItem(minimize)

        let zoom = NSMenuItem(
            title: String(localized: "menu.window.zoom", defaultValue: "Zoom"),
            action: #selector(NSWindow.performZoom(_:)),
            keyEquivalent: ""
        )
        zoom.target = nil
        menu.addItem(zoom)
        menu.addItem(.separator())

        let front = NSMenuItem(
            title: String(localized: "menu.window.bring_all", defaultValue: "Bring All to Front"),
            action: #selector(NSApplication.arrangeInFront(_:)),
            keyEquivalent: ""
        )
        front.target = NSApp
        menu.addItem(front)

        NSApp.windowsMenu = menu
        item.title = menu.title
        item.submenu = menu
        return item
    }

    private static func customItem(
        title: String,
        action: Selector,
        key: String = "",
        modifiers: NSEvent.ModifierFlags = [.command],
        coordinator: AppCoordinator
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = coordinator
        if !key.isEmpty {
            item.keyEquivalentModifierMask = modifiers
        }
        return item
    }

    private static func standardItem(
        _ title: String,
        action: Selector,
        key: String = "",
        modifiers: NSEvent.ModifierFlags = [.command]
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = nil
        if !key.isEmpty {
            item.keyEquivalentModifierMask = modifiers
        }
        return item
    }
}
