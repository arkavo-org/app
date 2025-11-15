import XCTest

/// Tests for authentication flows in HYPΞRforum
final class AuthenticationTests: XCTestCase {
    var app: XCUIApplication!
    var helpers: TestHelpers!

    override func setUpWithError() throws {
        continueAfterFailure = false

        app = XCUIApplication()
        app.launch()

        helpers = TestHelpers(app: app)

        // Wait for app to be ready
        sleep(2)
    }

    override func tearDownWithError() throws {
        app = nil
        helpers = nil
    }

    // MARK: - Welcome Screen Tests

    func testWelcomeScreenDisplay() throws {
        // Verify app launches to welcome screen when not authenticated
        assertWelcomeViewDisplayed(in: app)

        // Verify branding elements
        let logo = app.staticTexts["logo_xi"]
        XCTAssertTrue(logo.exists, "Xi logo should be displayed")

        let appTitle = app.staticTexts["text_appTitle"]
        XCTAssertTrue(appTitle.exists, "App title should be displayed")
        XCTAssertEqual(appTitle.label, "HYPΞRforum", "App title should be 'HYPΞRforum'")

        let subtitle = app.staticTexts["text_appSubtitle"]
        XCTAssertTrue(subtitle.exists, "App subtitle should be displayed")
        XCTAssertEqual(subtitle.label, "Cyber-Renaissance Communication", "Subtitle should match")
    }

    func testWelcomeScreenFeatureList() throws {
        assertWelcomeViewDisplayed(in: app)

        // Verify feature list is displayed
        let featureList = app.otherElements["list_welcomeFeatures"]
        XCTAssertTrue(featureList.exists, "Feature list should be displayed")

        // Verify key features are mentioned
        XCTAssertTrue(app.staticTexts["Group Discussions"].exists, "Should list Group Discussions feature")
        XCTAssertTrue(app.staticTexts["AI Council"].exists, "Should list AI Council feature")
        XCTAssertTrue(app.staticTexts["End-to-End Encrypted"].exists, "Should list encryption feature")
        XCTAssertTrue(app.staticTexts["Passkey Authentication"].exists, "Should list passkey auth feature")
    }

    func testSignInButtonPresent() throws {
        assertWelcomeViewDisplayed(in: app)

        let signInButton = app.buttons["button_signInPasskey"]
        XCTAssertTrue(signInButton.exists, "Sign in button should be displayed")
        XCTAssertTrue(signInButton.label.contains("Sign In with Passkey"), "Button should have correct label")
    }

    // MARK: - Authentication Sheet Tests

    func testOpenAuthenticationSheet() throws {
        assertWelcomeViewDisplayed(in: app)

        // Click sign in button
        let signInButton = app.buttons["button_signInPasskey"]
        signInButton.click()

        sleep(1)

        // Verify authentication sheet appears
        let authView = app.otherElements["view_authentication"]
        XCTAssertTrue(authView.waitForExistence(timeout: 5), "Authentication sheet should be displayed")
    }

    func testAuthenticationSheetElements() throws {
        assertWelcomeViewDisplayed(in: app)

        let signInButton = app.buttons["button_signInPasskey"]
        signInButton.click()

        sleep(1)

        let authView = app.otherElements["view_authentication"]
        XCTAssertTrue(authView.exists, "Authentication sheet should be displayed")

        // Verify UI elements
        let accountField = app.textFields["field_accountName"]
        XCTAssertTrue(accountField.exists, "Account name field should exist")

        let authButton = app.buttons["button_signIn"]
        XCTAssertTrue(authButton.exists, "Sign in button should exist")

        let toggleButton = app.buttons["button_toggleAuthMode"]
        XCTAssertTrue(toggleButton.exists, "Toggle auth mode button should exist")

        let cancelButton = app.buttons["button_cancelAuth"]
        XCTAssertTrue(cancelButton.exists, "Cancel button should exist")
    }

    func testToggleBetweenSignInAndRegister() throws {
        assertWelcomeViewDisplayed(in: app)

        let signInButton = app.buttons["button_signInPasskey"]
        signInButton.click()

        sleep(1)

        // Should start in sign-in mode
        let signInAuthButton = app.buttons["button_signIn"]
        XCTAssertTrue(signInAuthButton.exists, "Should show sign-in button initially")

        // Toggle to register mode
        let toggleButton = app.buttons["button_toggleAuthMode"]
        toggleButton.click()

        usleep(500000)

        // Should now show register button
        let registerButton = app.buttons["button_register"]
        XCTAssertTrue(registerButton.exists, "Should show register button after toggling")

        // Toggle back to sign-in
        toggleButton.click()

        usleep(500000)

        // Should show sign-in button again
        XCTAssertTrue(signInAuthButton.exists, "Should show sign-in button after toggling back")
    }

    func testCancelAuthenticationSheet() throws {
        assertWelcomeViewDisplayed(in: app)

        let signInButton = app.buttons["button_signInPasskey"]
        signInButton.click()

        sleep(1)

        let authView = app.otherElements["view_authentication"]
        XCTAssertTrue(authView.exists, "Authentication sheet should be displayed")

        // Click cancel
        let cancelButton = app.buttons["button_cancelAuth"]
        cancelButton.click()

        sleep(1)

        // Should return to welcome screen
        XCTAssertFalse(authView.exists, "Authentication sheet should be dismissed")
        assertWelcomeViewDisplayed(in: app)
    }

    func testAuthButtonDisabledWhenAccountNameEmpty() throws {
        assertWelcomeViewDisplayed(in: app)

        let signInButton = app.buttons["button_signInPasskey"]
        signInButton.click()

        sleep(1)

        // Sign in button should be disabled when account name is empty
        let authButton = app.buttons["button_signIn"]
        XCTAssertFalse(authButton.isEnabled, "Sign in button should be disabled when account name is empty")

        // Type an account name
        let accountField = app.textFields["field_accountName"]
        accountField.click()
        accountField.typeText("testuser")

        // Button should now be enabled
        XCTAssertTrue(authButton.isEnabled, "Sign in button should be enabled when account name is entered")
    }

    // MARK: - Authentication Flow Tests (Integration with Real Services)

    func testSignInFlow() throws {
        assertWelcomeViewDisplayed(in: app)

        // NOTE: This test will attempt real WebAuthn authentication
        // It requires:
        // 1. An existing account on the WebAuthn server
        // 2. A registered passkey for the test account
        // 3. Manual interaction to approve the passkey prompt

        let signInButton = app.buttons["button_signInPasskey"]
        signInButton.click()

        sleep(1)

        // Enter account name
        let accountField = app.textFields["field_accountName"]
        accountField.click()

        // TODO: Replace with your test account name
        accountField.typeText("test_user")

        // Click sign in
        let authButton = app.buttons["button_signIn"]
        authButton.click()

        // Wait for authentication progress
        let progressIndicator = app.progressIndicators["progress_authenticating"]
        XCTAssertTrue(progressIndicator.waitForExistence(timeout: 5), "Should show authentication progress")

        // Note: Authentication will pause for passkey approval
        // In automated testing, you'd need to handle this with test credentials
        // or mock the authentication

        // Wait longer for potential manual approval
        sleep(10)

        // If authentication succeeds, should navigate to main forum
        // If it fails, error message should appear
        let mainForumView = app.otherElements["view_mainForum"]
        let errorText = app.staticTexts["text_authError"]

        let authenticated = mainForumView.waitForExistence(timeout: 5)
        let errorOccurred = errorText.exists

        XCTAssertTrue(authenticated || errorOccurred, "Should either authenticate successfully or show error")

        if authenticated {
            assertAuthenticated(in: app)
        } else if errorOccurred {
            XCTAssertTrue(errorText.label.count > 0, "Error message should not be empty")
        }
    }

    func testRegistrationFlow() throws {
        assertWelcomeViewDisplayed(in: app)

        let signInButton = app.buttons["button_signInPasskey"]
        signInButton.click()

        sleep(1)

        // Toggle to registration mode
        let toggleButton = app.buttons["button_toggleAuthMode"]
        toggleButton.click()

        usleep(500000)

        // Enter account name for new user
        let accountField = app.textFields["field_accountName"]
        accountField.click()

        // Generate unique account name for testing
        let timestamp = Int(Date().timeIntervalSince1970)
        accountField.typeText("test_user_\(timestamp)")

        // Click register
        let registerButton = app.buttons["button_register"]
        registerButton.click()

        // Wait for registration progress
        let progressIndicator = app.progressIndicators["progress_authenticating"]
        XCTAssertTrue(progressIndicator.waitForExistence(timeout: 5), "Should show registration progress")

        // Note: Registration requires passkey creation
        // Manual approval will be needed for real testing

        sleep(10)

        // Check for success or error
        let mainForumView = app.otherElements["view_mainForum"]
        let errorText = app.staticTexts["text_authError"]

        XCTAssertTrue(mainForumView.waitForExistence(timeout: 5) || errorText.exists, "Should either register successfully or show error")
    }

    // MARK: - Error Handling Tests

    func testAuthenticationErrorDisplay() throws {
        assertWelcomeViewDisplayed(in: app)

        let signInButton = app.buttons["button_signInPasskey"]
        signInButton.click()

        sleep(1)

        // Try to sign in with a non-existent account
        let accountField = app.textFields["field_accountName"]
        accountField.click()
        accountField.typeText("nonexistent_user_12345")

        let authButton = app.buttons["button_signIn"]
        authButton.click()

        // Wait for authentication to fail
        sleep(5)

        // Should show error message
        let errorText = app.staticTexts["text_authError"]
        if errorText.waitForExistence(timeout: 10) {
            XCTAssertTrue(errorText.exists, "Error message should be displayed")
            XCTAssertTrue(errorText.label.count > 0, "Error message should not be empty")

            // Error message should mention account not found or similar
            let errorMessage = errorText.label.lowercased()
            XCTAssertTrue(errorMessage.contains("not found") || errorMessage.contains("failed") || errorMessage.contains("error"), "Error should indicate account not found or authentication failed")
        }
    }

    // MARK: - Sign Out Tests

    func testSignOutFlow() throws {
        // This test assumes user is already authenticated
        // You may need to authenticate first or skip if not authenticated

        let mainForumView = app.otherElements["view_mainForum"]
        guard mainForumView.waitForExistence(timeout: 5) else {
            throw XCTSkip("User not authenticated, cannot test sign out")
        }

        // Open user profile menu
        let userProfileMenu = app.menus["menu_userProfile"]
        if userProfileMenu.exists {
            userProfileMenu.click()
        } else {
            // Try alternative way to access menu
            let menuButton = app.menuButtons.firstMatch
            if menuButton.exists {
                menuButton.click()
            }
        }

        sleep(1)

        // Click sign out
        let signOutButton = app.buttons["button_signOut"]
        if signOutButton.waitForExistence(timeout: 5) {
            signOutButton.click()

            sleep(2)

            // Should return to welcome screen
            assertWelcomeViewDisplayed(in: app)
        } else {
            XCTFail("Sign out button not found")
        }
    }

    // MARK: - Persistence Tests

    func testAuthStatePersistence() throws {
        // Test that authentication state persists across app restarts
        // This requires being authenticated first

        let mainForumView = app.otherElements["view_mainForum"]
        guard mainForumView.waitForExistence(timeout: 5) else {
            throw XCTSkip("User not authenticated, cannot test persistence")
        }

        // Terminate and relaunch app
        app.terminate()
        sleep(2)
        app.launch()
        sleep(3)

        // Should attempt to reconnect and stay authenticated
        // Or may show welcome screen if reconnection fails
        let stillAuthenticated = mainForumView.waitForExistence(timeout: 10)
        let backToWelcome = app.buttons["button_signInPasskey"].exists

        XCTAssertTrue(stillAuthenticated || backToWelcome, "Should either maintain authentication or return to welcome screen")
    }

    // MARK: - UI/UX Tests

    func testAuthenticationSheetSize() throws {
        assertWelcomeViewDisplayed(in: app)

        let signInButton = app.buttons["button_signInPasskey"]
        signInButton.click()

        sleep(1)

        let authView = app.otherElements["view_authentication"]
        XCTAssertTrue(authView.exists, "Authentication sheet should be displayed")

        // Verify sheet has reasonable size (not full screen, not tiny)
        let frame = authView.frame
        XCTAssertGreaterThan(frame.width, 300, "Auth sheet should be wider than 300px")
        XCTAssertLessThan(frame.width, 1000, "Auth sheet should not be too wide")
        XCTAssertGreaterThan(frame.height, 400, "Auth sheet should be taller than 400px")
        XCTAssertLessThan(frame.height, 800, "Auth sheet should not be too tall")
    }

    func testAccountNameFieldValidation() throws {
        assertWelcomeViewDisplayed(in: app)

        let signInButton = app.buttons["button_signInPasskey"]
        signInButton.click()

        sleep(1)

        let accountField = app.textFields["field_accountName"]
        XCTAssertTrue(accountField.exists, "Account name field should exist")

        // Verify placeholder text
        let placeholderValue = accountField.placeholderValue ?? ""
        XCTAssertTrue(placeholderValue.contains("username") || placeholderValue.contains("Account"), "Should have helpful placeholder text")

        // Field should accept text input
        accountField.click()
        accountField.typeText("test_input")

        // Field should not auto-capitalize or auto-correct (for usernames)
        // This is harder to test directly in UI tests, but we can verify text was entered
        // by checking if the sign-in button becomes enabled
        let authButton = app.buttons["button_signIn"]
        XCTAssertTrue(authButton.isEnabled, "Sign in button should be enabled after entering text")
    }
}
