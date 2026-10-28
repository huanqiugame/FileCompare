import AppKit
import Testing

@testable import FileCompare

@Suite(.serialized)
@MainActor
struct MainMenuTests {
    @Test func menuHasActionsAndSymbols() {
        let menu = MainMenu.build(coordinator: AppCoordinator.shared)

        #expect(menu.items.count >= 7)
        #expect(NSApp.windowsMenu != nil)

        func item(for action: Selector) -> NSMenuItem? {
            for topLevel in menu.items {
                guard let submenu = topLevel.submenu else { continue }
                if let found = submenu.items.first(where: { $0.action == action }) {
                    return found
                }
            }
            return nil
        }

        let expected: [(Selector, String, String)] = [
            (#selector(AppCoordinator.openLeftFile(_:)), "o", "sidebar.leading"),
            (#selector(AppCoordinator.openRightFile(_:)), "O", "sidebar.trailing"),
            (#selector(AppCoordinator.revealInFinder(_:)), "R", "folder"),
            (#selector(AppCoordinator.reloadComparison(_:)), "r", "arrow.clockwise"),
            (#selector(AppCoordinator.find(_:)), "f", "magnifyingglass"),
            (#selector(AppCoordinator.swapSides(_:)), "x", "arrow.left.arrow.right"),
            (#selector(AppCoordinator.toggleLineNumbers(_:)), "l", "list.number"),
            (#selector(AppCoordinator.nextDifference(_:)), "\u{F701}", "arrow.down.to.line")
        ]

        for (action, key, symbol) in expected {
            let found = item(for: action)
            #expect(found != nil)
            #expect(found?.keyEquivalent == key)
            #expect(found?.image != nil)
            #expect(found?.target === AppCoordinator.shared)
            _ = symbol
        }
    }
}
