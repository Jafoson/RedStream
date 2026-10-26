import XCTest

/// Clicks through the app in the simulator against the CI demo backend
/// (android/ci/demo_server.py, approvals done by ios/ci/auto_approve.py) and
/// saves a screenshot of every screen to $SHOTS_DIR
/// (.github/workflows/ios-screenshots.yml).
final class ScreenshotTests: XCTestCase {
    private var app: XCUIApplication!
    private var shotsDir: URL!

    override func setUp() {
        continueAfterFailure = true
        let dir = ProcessInfo.processInfo.environment["SHOTS_DIR"] ?? NSTemporaryDirectory() + "shots"
        shotsDir = URL(fileURLWithPath: dir)
        try? FileManager.default.createDirectory(at: shotsDir, withIntermediateDirectories: true)
        app = XCUIApplication()
    }

    private func shot(_ name: String) {
        let png = XCUIScreen.main.screenshot().pngRepresentation
        try? png.write(to: shotsDir.appendingPathComponent("\(name).png"))
        let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func pause(_ seconds: Double) {
        Thread.sleep(forTimeInterval: seconds)
    }

    /// First element (any type) whose label contains `text`.
    private func element(_ text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    private func button(_ text: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    @discardableResult
    private func waitFor(_ e: XCUIElement, _ timeout: Double = 30, _ what: String) -> Bool {
        let ok = e.waitForExistence(timeout: timeout)
        if !ok { XCTFail("'\(what)' not on screen after \(timeout)s") }
        return ok
    }

    private func tab(_ name: String) {
        let b = app.tabBars.buttons[name]
        if waitFor(b, 10, "tab \(name)") { b.tap() }
    }

    func testWalkthrough() {
        app.launch()

        // Setup + approval
        let field = app.textFields["serverAddress"]
        guard waitFor(field, 30, "server address") else { return }
        pause(1)
        shot("01_einrichtung")
        field.tap()
        field.typeText("http://127.0.0.1:8080\n")
        if waitFor(element("Zugriff angefragt"), 30, "Zugriff angefragt") {
            pause(1)
            shot("02_freigabe_code")
        }
        guard waitFor(element("Wer schaut?"), 90, "Wer schaut?") else { return }
        pause(1)
        shot("03_profilauswahl")
        button("Standard").tap()

        // Start
        if waitFor(element("Weiterschauen"), 30, "Weiterschauen") {
            pause(4)
            shot("04_start")
            app.swipeUp()
            pause(2)
            shot("05_start_leisten")
            app.swipeDown()
            pause(1)
        }

        // Detail
        let poster = button("Dandadan")
        if waitFor(poster, 15, "Dandadan") {
            poster.tap()
            if waitFor(element("Staffel 1"), 30, "Staffel 1") {
                pause(3)
                shot("06_detail")
                app.swipeUp()
                pause(2)
                shot("07_detail_folgen")
            }
        }

        // Player
        let episode = button("Folge 4")
        if waitFor(episode, 10, "Folge 4") {
            episode.tap()
            pause(12)
            shot("08_player")
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)).tap()
            pause(1)
            shot("09_player_steuerung")
            let back = app.buttons["Zurück"]
            if back.exists { back.tap() } else {
                app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)).tap()
                pause(1)
                app.buttons["Zurück"].tap()
            }
            pause(3)
        }

        // Entdecken, Suche, Meine Liste
        tab("Entdecken")
        pause(4)
        shot("10_entdecken")

        tab("Suche")
        let search = app.textFields["searchField"]
        if waitFor(search, 10, "search field") {
            search.tap()
            search.typeText("o\n")
            pause(4)
            shot("11_suche")
        }

        tab("Meine Liste")
        pause(4)
        shot("12_meine_liste")

        // Auf TV
        tab("Start")
        pause(1)
        let castButton = app.buttons["Auf TV abspielen"]
        if waitFor(castButton, 10, "Auf TV abspielen") {
            castButton.tap()
            let tv = button("TV Wohnzimmer")
            if waitFor(tv, 20, "TV Wohnzimmer") {
                pause(1)
                shot("13_tv_auswahl")
                tv.tap()
                pause(4)
                shot("14_fernbedienung")
            }
        }

        tab("Mehr")
        pause(2)
        shot("15_mehr")
    }
}
