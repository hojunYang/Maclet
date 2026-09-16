import AppKit
import XCTest
@testable import MacletApp

final class StatusItemActivationDecisionTests: XCTestCase {
    @MainActor
    func testApplicationMenuRegistersCommandCommaForSettings() {
        let previousMenu = NSApp.mainMenu
        defer { NSApp.mainMenu = previousMenu }

        AppMenuBuilder.configure(
            settingsTarget: nil,
            settingsAction: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            quitTarget: nil,
            quitAction: #selector(NSApplication.terminate(_:)),
            closeTarget: nil,
            closeAction: #selector(NSWindow.performClose(_:))
        )

        let settingsItem = NSApp.mainMenu?.items.first?.submenu?.items.first
        XCTAssertEqual(settingsItem?.title, "Settings…")
        XCTAssertEqual(settingsItem?.keyEquivalent, ",")
        XCTAssertEqual(settingsItem?.keyEquivalentModifierMask, [.command])
    }

    func testManagementWindowAlwaysTakesPriority() {
        XCTAssertEqual(
            StatusItemActivationDecision.resolve(
                managementWindowIsPresented: true,
                commandCenterIsActive: false
            ),
            .focusManagementWindow
        )
        XCTAssertEqual(
            StatusItemActivationDecision.resolve(
                managementWindowIsPresented: true,
                commandCenterIsActive: true
            ),
            .focusManagementWindow
        )
    }

    func testActiveCommandCenterIsHidden() {
        XCTAssertEqual(
            StatusItemActivationDecision.resolve(
                managementWindowIsPresented: false,
                commandCenterIsActive: true
            ),
            .hideCommandCenter
        )
    }

    func testCommandCenterIsShownWhenNoSurfaceIsActive() {
        XCTAssertEqual(
            StatusItemActivationDecision.resolve(
                managementWindowIsPresented: false,
                commandCenterIsActive: false
            ),
            .showCommandCenter
        )
    }

    func testAppModalPreventsCommandCenterDismissal() {
        XCTAssertFalse(
            CommandCenterDismissalDecision.shouldDismiss(
                isActive: true,
                isAppModalPresented: true,
                eventIsInsidePanel: false,
                eventIsStatusItem: false
            )
        )
    }

    func testOutsideClickDismissesCommandCenterWithoutModal() {
        XCTAssertTrue(
            CommandCenterDismissalDecision.shouldDismiss(
                isActive: true,
                isAppModalPresented: false,
                eventIsInsidePanel: false,
                eventIsStatusItem: false
            )
        )
    }

    func testManagementWindowUsesNormalApplicationActivationWhilePresented() {
        XCTAssertEqual(
            ManagementWindowPresentationPolicy.presentedActivationPolicy,
            .regular
        )
        XCTAssertEqual(
            ManagementWindowPresentationPolicy.dismissedActivationPolicy,
            .accessory
        )
    }

    func testManagementWindowParticipatesInSpacesWithoutJoiningFullScreenSpaces() {
        let behavior = ManagementWindowPresentationPolicy.collectionBehavior

        XCTAssertTrue(behavior.contains(.auxiliary))
        XCTAssertTrue(behavior.contains(.managed))
        XCTAssertTrue(behavior.contains(.participatesInCycle))
        XCTAssertTrue(behavior.contains(.fullScreenNone))
        XCTAssertTrue(behavior.contains(.fullScreenDisallowsTiling))
        XCTAssertFalse(behavior.contains(.moveToActiveSpace))
        XCTAssertFalse(behavior.contains(.canJoinAllSpaces))
        XCTAssertFalse(behavior.contains(.canJoinAllApplications))
        XCTAssertFalse(behavior.contains(.fullScreenAuxiliary))
    }
}
