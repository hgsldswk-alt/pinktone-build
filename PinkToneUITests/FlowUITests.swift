import XCTest

final class FlowUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        executionTimeAllowance = 900
    }

    private func launch(_ language: String, extra: [String] = []) {
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-AppleLanguages", "(\(language))",
                               "-AppleLocale", language == "ja" ? "ja_JP" : language] + extra
        app.launch()
    }

    private func element(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    @discardableResult
    private func wait(_ timeout: TimeInterval, _ ready: () -> Bool) -> Bool {
        let until = Date().addingTimeInterval(timeout)
        while Date() < until {
            if ready() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return ready()
    }

    private func tap(_ id: String, timeout: TimeInterval = 15) {
        let item = element(id)
        XCTAssertTrue(item.waitForExistence(timeout: timeout), id)
        if !item.isHittable {
            for _ in 0..<3 where !item.isHittable { app.swipeUp() }
        }
        XCTAssertTrue(wait(timeout) { item.isHittable && item.isEnabled }, id)
        item.tap()
    }

    private func shot(_ name: String) {
        let item = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        item.name = name
        item.lifetime = .keepAlways
        add(item)
    }

    func testSeededSixPhotoFlowRetriesOneFailureAndImportsCode() {
        launch("en", extra: ["-seed", "-fail-once", "-paid-mode"])
        tap("pickPhotos")
        let count = element("selectionCount")
        XCTAssertTrue(count.waitForExistence(timeout: 50))
        XCTAssertTrue(count.label.contains("6"))
        tap("photo.0")
        tap("preset.softpink")
        let strength = app.sliders["toneStrength"]
        XCTAssertTrue(strength.waitForExistence(timeout: 15))
        XCTAssertEqual(element("strengthValue").label, "60%")
        strength.adjust(toNormalizedSliderPosition: 0.78)
        XCTAssertTrue(wait(8) { self.element("strengthValue").label != "60%" })

        let photo = element("holdOriginal")
        XCTAssertTrue(photo.waitForExistence(timeout: 15))
        let held = photo.value as? String
        photo.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.48)).press(forDuration: 0.65)
        XCTAssertTrue(wait(8) { (photo.value as? String) != held && photo.label == "Edited" })
        tap("toggleOriginal")
        XCTAssertTrue(wait(5) { photo.label == "Original" })
        tap("toggleOriginal")
        XCTAssertTrue(wait(5) { photo.label == "Edited" })

        tap("saveBatch")
        XCTAssertTrue(wait(150) { self.element("savedCount").exists && self.element("savedCount").label == "Saved 5 photos" })
        XCTAssertTrue(element("failedCount").waitForExistence(timeout: 10))
        XCTAssertEqual(element("failedCount").label, "Failed to save 1 photo")
        tap("retryFailed")
        XCTAssertTrue(wait(60) { self.element("savedCount").label == "Saved 6 photos" })
        XCTAssertTrue(wait(15) { !self.element("failedCount").exists })
        tap("shareCard")
        XCTAssertTrue(element("sharePreview").waitForExistence(timeout: 30))
        XCTAssertTrue(element("shareImage").exists)
        tap("copyCode")
        XCTAssertTrue(wait(8) { self.element("copyCode").label == "Code copied" })
        tap("closeShare")
        tap("resultHome")
        tap("importPreset")
        let field = app.textFields["presetCode"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText("PT1:white:73")
        tap("dismissCodeKeyboard")
        XCTAssertTrue(wait(10) { !self.app.keyboards.firstMatch.exists })
        XCTAssertTrue(element("codePreview").waitForExistence(timeout: 10))
        tap("applyCode")
        tap("pickPhotos")
        XCTAssertTrue(element("strengthValue").waitForExistence(timeout: 15))
        XCTAssertEqual(element("strengthValue").label, "73%")
    }

    func testExpiredBatchAndLockedPreset() {
        launch("en", extra: ["-seed", "-expired"])
        tap("pickPhotos")
        let count = element("selectionCount")
        XCTAssertTrue(count.waitForExistence(timeout: 40))
        XCTAssertTrue(count.label.contains("3"))
        tap("preset.milktea")
        XCTAssertTrue(element("buyPro").waitForExistence(timeout: 12))
        tap("closePaywall")
        tap("preset.white")
        tap("saveBatch")
        XCTAssertTrue(wait(50) { self.element("savedCount").exists && self.element("savedCount").label == "Saved 3 photos" })
    }

    func testSaveNamedPresetAfterDismissingKeyboard() {
        launch("en", extra: ["-seed", "-single"])
        tap("pickPhotos")
        XCTAssertTrue(element("holdOriginal").waitForExistence(timeout: 30))
        tap("savePreset")
        let field = app.textFields["presetName"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText("Morning Pink")
        tap("dismissNameKeyboard")
        XCTAssertTrue(wait(10) { !self.app.keyboards.firstMatch.exists })
        tap("confirmSavePreset")
        tap("showGrid")
        tap("closeEditor")
        tap("myPresets")
        XCTAssertTrue(app.staticTexts["Morning Pink"].waitForExistence(timeout: 15))
    }

    private func store(_ language: String) {
        launch(language, extra: ["-seed", "-single"])
        tap("pickPhotos")
        tap("preset.softpink", timeout: 35)
        XCTAssertTrue(element("holdOriginal").waitForExistence(timeout: 25))
        XCTAssertTrue(wait(25) { self.element("saveBatch").isEnabled })
        shot("store-\(language)-01-tone")

        app.terminate()
        launch(language, extra: ["-seed", "-three"])
        tap("pickPhotos")
        let batch = element("selectionCount")
        XCTAssertTrue(batch.waitForExistence(timeout: 40))
        XCTAssertTrue(wait(25) { self.element("saveBatch").isEnabled })
        sleep(4)
        shot("store-\(language)-02-batch")

        tap("photo.0")
        XCTAssertTrue(element("holdOriginal").waitForExistence(timeout: 18))
        let photo = element("holdOriginal")
        let edited = photo.label
        tap("toggleOriginal")
        XCTAssertTrue(wait(8) { photo.label != edited })
        shot("store-\(language)-03-original")
        tap("toggleOriginal")
        tap("saveBatch")
        let success = element("savedCount")
        XCTAssertTrue(wait(80) { success.exists && success.label.contains("3") && self.element("shareCard").isEnabled })
        sleep(3)
        shot("store-\(language)-04-saved")
        tap("shareCard")
        XCTAssertTrue(element("sharePreview").waitForExistence(timeout: 25))
        XCTAssertTrue(element("shareImage").exists)
        shot("store-\(language)-05-share")
    }

    func testStoreJapanese() { store("ja") }
    func testStoreEnglish() { store("en") }
    func testStoreSimplified() { store("zh-Hans") }
    func testStoreTraditional() { store("zh-Hant") }

    func testPaidScreenshot() {
        launch("zh-Hans", extra: ["-paid-mode", "-expired"])
        tap("openSettings")
        tap("openPaywall")
        XCTAssertTrue(element("buyPro").waitForExistence(timeout: 10))
        shot("paid-01-paywall")
    }
}

