//
//  TOTPUITests.swift
//  TOTPUITests
//
//  Runs the app with `-UITestMode`: seeded in-memory accounts, no iCloud, no app lock.
//  Seed: "Example Corp" (with prefix), "GitHub", "Counter Bank" (HOTP).
//

import XCTest

final class TOTPUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-UITestMode"]
        app.launch()
    }

    private func account(_ title: String) -> XCUIElement {
        app.buttons["account-\(title)"].firstMatch
    }

    private func openActions(for title: String) {
        let element = account(title)
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        element.press(forDuration: 1.2)
    }

    // MARK: - Tests

    func testLaunchShowsSeededAccounts() {
        XCTAssertTrue(account("Example Corp").waitForExistence(timeout: 5))
        XCTAssertTrue(account("GitHub").exists)
        XCTAssertTrue(account("Counter Bank").exists)
        XCTAssertTrue(app.buttons["addAccountButton"].exists)
    }

    func testCopyShowsConfirmation() {
        let row = account("GitHub")
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        // The row's accessibility label reports the copied state
        let copied = NSPredicate(format: "label CONTAINS 'Copied'")
        expectation(for: copied, evaluatedWith: row)
        waitForExpectations(timeout: 3)
    }

    func testSearchFiltersAccounts() {
        XCTAssertTrue(account("GitHub").waitForExistence(timeout: 5))
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("git")
        XCTAssertTrue(account("GitHub").waitForExistence(timeout: 3))
        XCTAssertFalse(account("Example Corp").exists)
    }

    func testAddAccountManually() {
        app.buttons["addAccountButton"].tap()

        let issuer = app.textFields["issuerField"]
        XCTAssertTrue(issuer.waitForExistence(timeout: 5))
        issuer.tap()
        issuer.typeText("Acme")

        // Reveal the field: typing into secure fields is unreliable in the simulator
        app.buttons["Show Secret Key"].tap()
        let secret = app.textFields["secretField"]
        secret.tap()
        secret.typeText("JBSWY3DPEHPK3PXP")

        app.buttons["saveButton"].tap()
        XCTAssertTrue(account("Acme").waitForExistence(timeout: 5))
    }

    func testInvalidSecretShowsError() {
        app.buttons["addAccountButton"].tap()
        let secret = app.secureTextFields["secretField"]
        XCTAssertTrue(secret.waitForExistence(timeout: 5))
        secret.tap()
        secret.typeText("NOT-VALID-189")
        app.buttons["saveButton"].tap()
        XCTAssertTrue(app.alerts["Can't Save Account"].waitForExistence(timeout: 3))
        app.alerts.buttons["OK"].tap()
        app.buttons["cancelButton"].tap()
        XCTAssertTrue(account("Example Corp").waitForExistence(timeout: 3))
    }

    func testEditAccount() {
        openActions(for: "GitHub")
        app.buttons["editAction"].firstMatch.tap()

        let issuer = app.textFields["issuerField"]
        XCTAssertTrue(issuer.waitForExistence(timeout: 5))
        issuer.tap()
        issuer.typeText(" Enterprise")
        app.buttons["saveButton"].tap()

        XCTAssertTrue(account("GitHub Enterprise").waitForExistence(timeout: 5))
    }

    func testDeleteAccount() {
        openActions(for: "Counter Bank")
        app.buttons["deleteAction"].firstMatch.tap()
        let confirm = app.buttons["confirmDeleteButton"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 3))
        confirm.firstMatch.tap()
        let gone = NSPredicate(format: "exists == false")
        expectation(for: gone, evaluatedWith: account("Counter Bank"))
        waitForExpectations(timeout: 5)
    }

    func testOtpAuthLinkPrefillsForm() {
        app.open(URL(string: "otpauth://totp/Linked%20Service:me@example.com?secret=JBSWY3DPEHPK3PXP&issuer=Linked%20Service")!)
        let issuer = app.textFields["issuerField"]
        XCTAssertTrue(issuer.waitForExistence(timeout: 5))
        XCTAssertEqual(issuer.value as? String, "Linked Service")
        app.buttons["saveButton"].tap()
        XCTAssertTrue(account("Linked Service").waitForExistence(timeout: 5))
    }

    #if os(iOS)
    func testSettingsSheet() {
        app.buttons["settingsButton"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.switches["appLockToggle"].exists || app.buttons["appLockToggle"].exists)
        app.buttons["Done"].tap()
    }

    func testRotationKeepsContent() {
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(account("Example Corp").waitForExistence(timeout: 5))
        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(account("Example Corp").waitForExistence(timeout: 5))
    }
    #endif
}
