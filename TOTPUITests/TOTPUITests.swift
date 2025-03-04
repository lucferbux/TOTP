//
//  TOTPUITests.swift
//  TOTPUITests
//
//  Created by Lucas Fernández Aragón on 4/3/25.
//

import XCTest

final class TOTPUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testInitialAppLaunch() throws {
        let app = XCUIApplication()
        app.launch()
        
        // Test that the app launches with initial account
        let accountElement = app.staticTexts["Red Hat"]
        XCTAssertTrue(accountElement.exists, "Initial Red Hat account should be visible")
        
        // Test that the help text exists
        let helpText = app.staticTexts["Click account to copy the current code to your clipboard."]
        XCTAssertTrue(helpText.exists, "Help text should be visible")
    }
    
    @MainActor
    func testAddNewAccount() throws {
        let app = XCUIApplication()
        app.launch()
        
        // Open add account form
        app.images["plus.circle.fill"].tap()
        
        // Fill in the form
        let otpKeyTextField = app.secureTextFields["OTP Key"]
        XCTAssertTrue(otpKeyTextField.waitForExistence(timeout: 2), "OTP Key field should be visible")
        otpKeyTextField.tap()
        otpKeyTextField.typeText("testsecretkey")
        
        let issuerField = app.textFields["Issuer"]
        XCTAssertTrue(issuerField.exists, "Issuer field should be visible")
        issuerField.tap()
        issuerField.typeText("TestIssuer")
        
        let accountNameField = app.textFields["Account Name"]
        XCTAssertTrue(accountNameField.exists, "Account Name field should be visible")
        accountNameField.tap()
        accountNameField.typeText("test@example.com")
        
        // Submit the form
        app.buttons["Add"].tap()
        
        // Verify new account appears
        let newAccountElement = app.staticTexts["TestIssuer"]
        XCTAssertTrue(newAccountElement.waitForExistence(timeout: 2), "New TestIssuer account should be visible")
    }
    
    @MainActor
    func testCopyCode() throws {
        let app = XCUIApplication()
        app.launch()
        
        // Find the TOTP card for Red Hat
        let redHatText = app.staticTexts["Red Hat"]
        XCTAssertTrue(redHatText.exists, "Red Hat account should be visible")
        
        // Tap directly on the text element to copy the code
        redHatText.tap()
        
        // Verify toast appears
        let toast = app.staticTexts["Code copied to clipboard"]
        XCTAssertTrue(toast.waitForExistence(timeout: 2), "Toast notification should appear after copying code")
    }
    
    
    @MainActor
    func testHotpMode() throws {
        let app = XCUIApplication()
        app.launch()
        
        // Open add account form
        app.images["plus.circle.fill"].tap()
        
        // Switch to HOTP mode
        app.buttons["HOTP"].tap()
        
        // Verify HOTP specific fields appear
        let counterStepper = app.staticTexts["Counter: 0"]
        XCTAssertTrue(counterStepper.exists, "Counter field should be visible in HOTP mode")
        
        // Increment counter
        app.buttons["Increment"].firstMatch.tap()
        let incrementedCounter = app.staticTexts["Counter: 1"]
        XCTAssertTrue(incrementedCounter.waitForExistence(timeout: 2), "Counter should increment to 1")
        
        // Fill other fields
        app.secureTextFields["OTP Key"].tap()
        app.secureTextFields["OTP Key"].typeText("hotptestkey")
        
        app.textFields["Issuer"].tap()
        app.textFields["Issuer"].typeText("HOTP Test")
        
        // Add the HOTP account
        app.buttons["Add"].tap()
        
        // Verify HOTP account was added
        let hotpAccount = app.staticTexts["HOTP Test"]
        XCTAssertTrue(hotpAccount.waitForExistence(timeout: 2), "HOTP Test account should be visible")
    }
    
    @MainActor
    func testLaunchPerformance() throws {
        if #available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 7.0, *) {
            measure(metrics: [XCTApplicationLaunchMetric()]) {
                XCUIApplication().launch()
            }
        }
    }
}
