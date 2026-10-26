import XCTest
import CryptoKit
import ImageIO
import CoreGraphics

#if targetEnvironment(simulator)
/// Runs against a second app's Files-visible Documents container. Simulator
/// permission behavior is not evidence of physical-device security scopes.
final class SharedFolderFileOperationsTests: XCTestCase {
    private let app = XCUIApplication()
    private let fm = FileManager.default
    private var root: URL!
    private var payloads: [String: Data] = [:]

    private func file(_ name: String, _ pane: Int) -> XCUIElement {
        app.cells["File-\(pane)-\(name)"]
    }
    private func navigate(_ path: URL, _ pane: Int) {
        let field = app.textFields["Path-\(pane)"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap(); field.tap(withNumberOfTaps: 3, numberOfTouches: 1)
        if let old = field.value as? String {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: old.count))
        }
        field.typeText(path.path + "\n")
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value ENDSWITH %@", path.lastPathComponent), object: field)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 10), .completed)
    }
    private func awaitPath(_ path: URL, exists: Bool = true) {
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            self.fm.fileExists(atPath: path.path) == exists
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 30), .completed, path.path)
    }
    private func verify(_ path: URL) throws {
        awaitPath(path)
        for (relative, data) in payloads {
            XCTAssertEqual(try Data(contentsOf: path.appendingPathComponent(relative)), data, relative)
        }
        var directory: ObjCBool = false
        XCTAssertTrue(fm.fileExists(atPath: path.appendingPathComponent("Leer").path, isDirectory: &directory))
        XCTAssertTrue(directory.boolValue)
    }
    private func evidence(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }
    func testExternalFolderCopyMoveZipAndUndo() throws {
        continueAfterFailure = false
        let environment = ProcessInfo.processInfo.environment
        guard let external = environment["OC_SHARED_ROOT"], let fixture = environment["OC_FIXTURE_NAME"] else {
            throw XCTSkip("Requires a separate simulator helper app's Documents container and an isolated fixture name")
        }
        XCTAssertTrue(fixture.hasPrefix("OpenCommander-FileOps-QA-"))
        root = URL(fileURLWithPath: external).appendingPathComponent(fixture)
        XCTAssertFalse(fm.fileExists(atPath: root.path), "Never overwrite an earlier test run")
        for directory in ["Source/Folder/Unterordner", "Source/Folder/Leer", "CopyTarget", "MoveTarget"] {
            try fm.createDirectory(at: root.appendingPathComponent(directory), withIntermediateDirectories: true)
        }
        payloads = ["Beweis.txt": Data("Copy, Move, ZIP on iOS\n".utf8),
                    "Unterordner/Grüsse 日本語.txt": Data("äöü — 日本語\n".utf8),
                    "Unterordner/data.bin": Data((0..<1_048_576).map { UInt8($0 % 251) }),
                    "empty.txt": Data()]
        let source = root.appendingPathComponent("Source/Folder")
        for (relative, data) in payloads { try data.write(to: source.appendingPathComponent(relative)) }
        app.launchArguments = ["-mobile_tree_1", "YES", "-mobile_tree_2", "YES"]; app.launch()
        if app.buttons["StorageSourcesClose"].waitForExistence(timeout: 5) { app.buttons["StorageSourcesClose"].tap() }
        // Physical Files selection is tested separately. This fixture explicitly
        // exercises an external container, not the app's own Documents directory.
        navigate(source.deletingLastPathComponent(), 1); navigate(root, 2)
        let operation = app.buttons["OperationButton"]
        if operation.isSelected { operation.tap() }
        XCTAssertFalse(operation.isSelected)
        XCTAssertTrue(file("Folder", 1).waitForExistence(timeout: 10))
        file("Folder", 1).press(forDuration: 1.5, thenDragTo: file("CopyTarget", 2), withVelocity: .slow, thenHoldForDuration: 1)
        let copied = root.appendingPathComponent("CopyTarget/Folder")
        try verify(copied); try verify(source); evidence("external-copy-byte-verified")

        navigate(copied.deletingLastPathComponent(), 1)
        operation.tap(); XCTAssertTrue(operation.isSelected)
        file("Folder", 1).press(forDuration: 1.5, thenDragTo: file("MoveTarget", 2), withVelocity: .slow, thenHoldForDuration: 1)
        let moved = root.appendingPathComponent("MoveTarget/Folder")
        try verify(moved); awaitPath(copied, exists: false); try verify(source)
        evidence("external-move-byte-verified")
        app.buttons["UndoButton"].tap()
        try verify(copied); awaitPath(moved, exists: false)
        app.buttons["UndoButton"].tap()
        awaitPath(copied, exists: false); try verify(source)
        evidence("external-copy-move-undo")

        operation.tap(); XCTAssertFalse(operation.isSelected)
        navigate(source.deletingLastPathComponent(), 1)
        file("Folder", 1).tap(); app.buttons["ZipButton"].tap()
        let archive = source.deletingLastPathComponent().appendingPathComponent("Folder.zip")
        awaitPath(archive)
        XCTAssertGreaterThan(try Data(contentsOf: archive).count, 0)
        file("Folder.zip", 1).doubleTap()
        XCTAssertTrue(file("Folder", 1).waitForExistence(timeout: 10))
        file("Folder", 1).doubleTap()
        XCTAssertTrue(file("Beweis.txt", 1).waitForExistence(timeout: 10))
        XCTAssertTrue(file("Unterordner", 1).exists)
        try verify(source); evidence("external-folder-zip-browsed")
        app.buttons["Breadcrumbs-1"].tap()
        app.buttons["Source"].tap()
        XCTAssertTrue(file("Folder.zip", 1).waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["Path-1"].value as? String, "Source")
        // Keep only this isolated fixture for independent host-side ZIP CRC,
        // Unicode filename, byte-content and empty-directory verification.
    }
    func testLargeFileCopyZipAndMissingFolderRecovery() throws {
        continueAfterFailure = false
        let env = ProcessInfo.processInfo.environment
        guard let external = env["OC_SHARED_ROOT"], let name = env["OC_FIXTURE_NAME"] else { throw XCTSkip("External fixture required") }
        XCTAssertTrue(name.hasPrefix("OpenCommander-FileOps-QA-"))
        root = URL(fileURLWithPath: external).appendingPathComponent(name + "-large")
        XCTAssertFalse(fm.fileExists(atPath: root.path))
        let source = root.appendingPathComponent("Source")
        let target = root.appendingPathComponent("Target")
        try fm.createDirectory(at: source, withIntermediateDirectories: true)
        try fm.createDirectory(at: target, withIntermediateDirectories: true)
        let big = source.appendingPathComponent("Large.bin")
        XCTAssertTrue(fm.createFile(atPath: big.path, contents: nil))
        let writer = try FileHandle(forWritingTo: big)
        var seed: UInt32 = 42
        let chunk = Data((0..<1_048_576).map { _ -> UInt8 in
            seed = seed &* 1664525 &+ 1013904223
            return UInt8(truncatingIfNeeded: seed >> 24)
        })
        var expected = SHA256()
        for _ in 0..<128 { try writer.write(contentsOf: chunk); expected.update(data: chunk) }
        try writer.close()
        func hash(_ url: URL) throws -> Data {
            let reader = try FileHandle(forReadingFrom: url); defer { try? reader.close() }
            var hash = SHA256()
            while let data = try reader.read(upToCount: 1_048_576), !data.isEmpty { hash.update(data: data) }
            return Data(hash.finalize())
        }
        let expectedHash = Data(expected.finalize())
        app.launchArguments = ["-language", "en"]; app.launch()
        if app.buttons["StorageSourcesClose"].waitForExistence(timeout: 5) { app.buttons["StorageSourcesClose"].tap() }
        navigate(source, 1); navigate(root, 2)
        if app.buttons["OperationButton"].isSelected { app.buttons["OperationButton"].tap() }
        XCTAssertTrue(file("Large.bin", 1).waitForExistence(timeout: 10))
        file("Large.bin", 1).press(forDuration: 1.5, thenDragTo: file("Target", 2), withVelocity: .slow, thenHoldForDuration: 1)
        let copied = target.appendingPathComponent("Large.bin")
        awaitPath(copied)
        XCTAssertEqual(try hash(copied), expectedHash)
        XCTAssertEqual(try hash(big), expectedHash)
        evidence("128MiB-copy-byte-verified")
        // The source pane remains open after the drag. Select its visible row
        // directly instead of retyping a long simulator-only container path.
        if !app.staticTexts["Selection-1"].label.hasPrefix("1/") { file("Large.bin", 1).tap() }
        app.buttons["ZipButton"].tap()
        let cancel = app.buttons["CancelFileOperation"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 3))
        cancel.tap()
        XCTAssertTrue(cancel.waitForNonExistence(timeout: 30))
        XCTAssertFalse(fm.fileExists(atPath: source.appendingPathComponent("Large.zip").path))
        XCTAssertEqual(try hash(big), expectedHash)
        XCTAssertTrue(app.buttons["ZipButton"].isEnabled)
        evidence("large-zip-cancelled-source-unchanged")
        app.buttons["ZipButton"].tap()
        awaitPath(source.appendingPathComponent("Large.zip"))
        XCTAssertEqual(try hash(big), expectedHash)
        // A provider-like disappearance must show recovery, not stale file rows.
        let parked = root.appendingPathComponent("Source-parked")
        try fm.moveItem(at: source, to: parked)
        app.buttons["Breadcrumbs-1"].tap(); app.buttons["Try Again"].tap()
        XCTAssertTrue(app.staticTexts["DirectoryMessage-1"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["DirectoryMessage-1"].label.contains("no longer available"))
        XCTAssertFalse(file("Large.bin", 1).isHittable)
        XCTAssertTrue(app.staticTexts["Selection-1"].label.hasPrefix("0/0"))
        evidence("missing-folder-actionable-recovery")
        try fm.moveItem(at: parked, to: source)
        app.buttons["DirectoryRetry-1"].tap()
        XCTAssertTrue(file("Large.bin", 1).waitForExistence(timeout: 10))
        XCTAssertEqual(try hash(big), expectedHash)
        evidence("folder-retry-restored")
    }
}
#endif


#if targetEnvironment(simulator)
final class MobileStorageUsabilityTests: XCTestCase {
    private let app = XCUIApplication()
    override func setUpWithError() throws { continueAfterFailure = false; XCUIDevice.shared.orientation = .portrait }
    override func tearDownWithError() throws { app.terminate(); XCUIDevice.shared.orientation = .portrait }
    private func start(_ language: String = "en") {
        app.launchArguments = ["-language", language, "-mobile_tree_1", "YES", "-mobile_tree_2", "YES"]
        app.launch()
        XCTAssertTrue(app.buttons["StorageSourcesClose"].waitForExistence(timeout: 15))
    }
    private func tapVisible(_ element: XCUIElement) {
        XCTAssertTrue(element.waitForExistence(timeout: 10))
        XCTAssertTrue(element.isHittable)
        XCTAssertTrue(app.frame.contains(element.frame), "Clipped control: \(element.identifier) \(element.frame)")
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }
    private func shot(_ name: String) {
        // Application screenshots can be cropped/rotated incorrectly by XCTest
        // after an orientation transition; capture the complete device screen.
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    func testSourceHubPermissionLabelsAndFriendlyPaths() {
        start()
        for key in ["media_photos", "media_videos", "media_music", "choose_another_folder", "local_documents"] {
            XCTAssertTrue(app.cells["Source-" + key].exists)
        }
        shot("sources-permission-status")
        let local = app.cells["Source-local_documents"]
        // Explicit visible scrolling is normal on a compact iPhone; never rely
        // on XCTest silently scrolling an offscreen row into view during tap.
        if !local.isHittable || !app.frame.contains(local.frame) { app.tables.firstMatch.swipeUp() }
        tapVisible(local)
        let path = app.textFields["Path-1"]
        XCTAssertFalse((path.value as? String ?? "").contains("/var/"))
        XCTAssertEqual(path.value as? String, "Local OpenCommander files")
        tapVisible(app.buttons["Breadcrumbs-1"])
        shot("friendly-breadcrumb-menu")
        app.tap() // dismiss the native menu
        tapVisible(app.buttons["Up-1"])
        XCTAssertTrue(app.buttons["StorageSourcesClose"].waitForExistence(timeout: 5))
    }
    func testPaneFocusTreeToggleAndBothOrientations() {
        for language in ["de", "ar", "fr"] {
            start(language); tapVisible(app.buttons["StorageSourcesClose"])
            for orientation in [UIDeviceOrientation.portrait, .landscapeLeft] {
                XCUIDevice.shared.orientation = orientation
                tapVisible(app.buttons["ToggleTree-1"])
                XCTAssertFalse(app.tables["TreeList-1"].isHittable)
                let before = app.tables["FileList-1"].frame
                tapVisible(app.buttons["FocusPane-1"])
                XCTAssertFalse(app.tables["FileList-2"].isHittable)
                let after = app.tables["FileList-1"].frame
                XCTAssertGreaterThan(after.width * after.height, before.width * before.height)
                shot("focused-" + language + "-" + String(orientation.rawValue))
                tapVisible(app.buttons["FocusPane-1"])
                XCTAssertTrue(app.tables["FileList-2"].isHittable)
                tapVisible(app.buttons["ToggleTree-1"])
                XCTAssertTrue(app.tables["TreeList-1"].isHittable)
                shot("dual-pane-" + language + "-" + String(orientation.rawValue))
            }
            app.terminate(); XCUIDevice.shared.orientation = .portrait
        }
    }
}
#endif

/// Desktop runs use their own bundle defaults, files and transfer queue.
/// Assertions check the real output bytes and persisted history, not just UI labels.
final class MacDesktopParityTests: XCTestCase {
    private let app = XCUIApplication()
    private var root: URL!

    override func setUpWithError() throws {
#if os(macOS) || targetEnvironment(macCatalyst)
        continueAfterFailure = false
        root = URL(fileURLWithPath: "/private/tmp/OpenCommander-MacUITest-" + UUID().uuidString, isDirectory: true)
        let fm = FileManager.default
        for directory in ["Left/Pack", "Right/DropHere"] { try fm.createDirectory(at: root.appendingPathComponent(directory), withIntermediateDirectories: true) }
        try Data("Mac parity copy and drag fixture\n".utf8).write(to: root.appendingPathComponent("Left/Alpha.txt"))
        try Data("nested ZIP contents\n".utf8).write(to: root.appendingPathComponent("Left/Pack/Note.txt"))
        app.launchArguments = ["--mac-parity-fixtures", "--mac-parity-reset"]
        app.launchEnvironment["OPENCOMMANDER_MAC_UI_ROOT"] = root.path
        app.launch()
        XCTAssertTrue(app.otherElements["TitleToolbar"].waitForExistence(timeout: 15))
        XCTAssertEqual(canonical(app.textFields["Path-1"].value as? String), canonical(root.appendingPathComponent("Left").path))
        XCTAssertEqual(canonical(app.textFields["Path-2"].value as? String), canonical(root.appendingPathComponent("Right").path))
#else
        throw XCTSkip("Mac desktop acceptance runs on Mac Catalyst")
#endif
    }

    override func tearDownWithError() throws {
        if let root { app.terminate(); try FileManager.default.removeItem(at: root) }
    }

    private func file(_ name: String, pane: Int) -> XCUIElement { app.descendants(matching: .any)["File-\(pane)-\(name)"] }
    private func canonical(_ path: String?) -> String? { path.map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path } }
    private func waitForFile(_ relative: String, exists: Bool) {
        let path = root.appendingPathComponent(relative).path
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in FileManager.default.fileExists(atPath: path) == exists }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 20), .completed)
    }

#if os(macOS) || targetEnvironment(macCatalyst)
    private func openTestArchive(_ url: URL) {
        let path = app.textFields.matching(identifier: "Path-1").firstMatch
        path.tap(); path.typeKey("a", modifierFlags: .command); path.typeText(url.path + "\n")
        let opened = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            (path.value as? String)?.contains(url.lastPathComponent + "!/") == true
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [opened], timeout: 15), .completed)
    }

    private func makeTestTar(_ name: String, members: [(String, UInt8, String, UInt64)]) throws -> URL {
        var bytes = Data()
        for (path, type, link, size) in members {
            var header = [UInt8](repeating: 0, count: 512)
            func field(_ offset: Int, _ value: String) {
                let value = Array(value.utf8); precondition(offset + value.count < 512)
                header.replaceSubrange(offset..<(offset + value.count), with: value)
            }
            precondition(path.utf8.count < 100 && link.utf8.count < 100)
            field(0, path); field(100, "0000644"); field(108, "0000000"); field(116, "0000000")
            field(124, String(format: "%011llo", size)); field(136, "00000000000")
            header.replaceSubrange(148..<156, with: Array(repeating: UInt8(32), count: 8))
            header[156] = type; field(157, link); field(257, "ustar"); field(263, "00")
            field(148, String(format: "%06o", header.reduce(0) { $0 + Int($1) }) + "\0 ")
            bytes.append(contentsOf: header)
        }
        bytes.append(Data(repeating: 0, count: 1024))
        let url = root.appendingPathComponent("Left/" + name + ".tar")
        try bytes.write(to: url); return url
    }
#endif

    func testBoundedTextPreviewIsReadonlyAndReportsBinaryAndTruncation() throws {
#if os(macOS) || targetEnvironment(macCatalyst)
        let samples: [(String, Data, String)] = [
            ("Alpha.txt", Data("Grüße 日本語 👋\n".utf8), "Read-only"),
            ("Large.txt", Data(repeating: 65, count: 2 * 1024 * 1024 + 20), "2 MiB"),
            ("Binary.bin", Data([65, 0, 66, 255]), "not UTF-8")
        ]
        for (name, bytes, expectedStatus) in samples {
            let source = root.appendingPathComponent("Left/" + name)
            try bytes.write(to: source)
            let path = app.textFields.matching(identifier: "Path-1").firstMatch
            path.tap(); path.typeKey("a", modifierFlags: .command); path.typeText(source.deletingLastPathComponent().path + "\n")
            let row = file(name, pane: 1)
            XCTAssertTrue(row.waitForExistence(timeout: 10)); row.tap()
            app.typeKey(" ", modifierFlags: [])
            let status = app.staticTexts.matching(identifier: "TextPreviewStatus").firstMatch
            XCTAssertTrue(status.waitForExistence(timeout: 15))
            let loaded = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in status.label.contains(expectedStatus) }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [loaded], timeout: 20), .completed)
            let text = app.textViews.matching(identifier: "TextPreviewContent").firstMatch
            if name == "Alpha.txt" { XCTAssertEqual(text.value as? String, String(data: bytes, encoding: .utf8)) }
            let close = app.buttons.matching(identifier: "TextPreviewClose").firstMatch
            XCTAssertTrue(close.exists)
            if name == "Large.txt" { close.tap() } else { app.typeKey(XCUIKeyboardKey.escape.rawValue, modifierFlags: []) }
            XCTAssertTrue(close.waitForNonExistence(timeout: 10))
            XCTAssertEqual(try Data(contentsOf: source), bytes)
        }
#endif
    }

    func testImagePreviewRejectsOversizeAndCorruptionAndRecovers() throws {
#if os(macOS) || targetEnvironment(macCatalyst)
        let source = root.appendingPathComponent("Left/Limit.png")
        XCTAssertTrue(FileManager.default.createFile(atPath: source.path, contents: nil))
        let handle = try FileHandle(forWritingTo: source)
        try handle.truncate(atOffset: 128 * 1024 * 1024 + 1)
        try handle.close()
        let path = app.textFields.matching(identifier: "Path-1").firstMatch
        path.tap(); path.typeKey("a", modifierFlags: .command); path.typeText(source.deletingLastPathComponent().path + "\n")
        let row = file("Limit.png", pane: 1)
        XCTAssertTrue(row.waitForExistence(timeout: 10)); row.tap()
        app.buttons.matching(identifier: "DesktopAction-preview").firstMatch.tap()
        let error = app.staticTexts.matching(identifier: "ImageViewerError").firstMatch
        XCTAssertTrue(error.waitForExistence(timeout: 15))
        XCTAssertTrue(error.label.contains("128 MiB"))
        XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: source.path)[.size] as? NSNumber)?.intValue, 128 * 1024 * 1024 + 1)
        let corrupt = Data("not an image".utf8)
        try corrupt.write(to: source)
        app.buttons.matching(identifier: "ImageViewerRetry").firstMatch.tap()
        let invalid = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            error.exists && !error.label.contains("128 MiB") && error.label.contains("image")
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [invalid], timeout: 15), .completed)
        XCTAssertEqual(try Data(contentsOf: source), corrupt)
        let context = CGContext(data: nil, width: 32, height: 16, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        let destination = CGImageDestinationCreateWithURL(source as CFURL, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        let valid = try Data(contentsOf: source)
        app.buttons.matching(identifier: "ImageViewerRetry").firstMatch.tap()
        XCTAssertTrue(error.waitForNonExistence(timeout: 15))
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "ImageViewerLoading").firstMatch.waitForNonExistence(timeout: 15))
        XCTAssertFalse(error.exists)
        XCTAssertTrue(app.images.matching(identifier: "ImageViewerImage").firstMatch.exists)
        app.buttons.matching(identifier: "ImageViewerClose").firstMatch.tap()
        XCTAssertEqual(try Data(contentsOf: source), valid)
#endif
    }

    func testVectorPreviewLimitAndNormalRecovery() throws {
#if os(macOS) || targetEnvironment(macCatalyst)
        let source = root.appendingPathComponent("Left/Vector.svg")
        let bytes = Data("<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"32\" height=\"16\"><rect width=\"32\" height=\"16\" fill=\"blue\"/></svg>".utf8)
        XCTAssertTrue(FileManager.default.createFile(atPath: source.path, contents: nil))
        let handle = try FileHandle(forWritingTo: source)
        try handle.truncate(atOffset: 128 * 1024 * 1024 + 1); try handle.close()
        app.typeKey("r", modifierFlags: .command)
        let row = file("Vector.svg", pane: 1)
        XCTAssertTrue(row.waitForExistence(timeout: 10)); row.tap()
        app.typeKey(" ", modifierFlags: [])
        let error = app.staticTexts.matching(identifier: "ImageViewerError").firstMatch
        XCTAssertTrue(error.waitForExistence(timeout: 15)); XCTAssertTrue(error.label.contains("128 MiB"))
        try bytes.write(to: source)
        app.buttons.matching(identifier: "ImageViewerRetry").firstMatch.tap()
        XCTAssertTrue(error.waitForNonExistence(timeout: 15))
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "ImageViewerLoading").firstMatch.waitForNonExistence(timeout: 15))
        XCTAssertFalse(error.exists)
        XCTAssertTrue(app.images.matching(identifier: "ImageViewerImage").firstMatch.exists)
        app.typeKey(XCUIKeyboardKey.escape.rawValue, modifierFlags: [])
        XCTAssertEqual(try Data(contentsOf: source), bytes)
#endif
    }

    func testOnlineLargeImageAndVideoRefuseBeforeDownloading() throws {
#if os(macOS) || targetEnvironment(macCatalyst)
        app.terminate(); app.launchArguments += ["--mac-parity-online-preview", "--mac-parity-online-large"]; app.launch()
        app.buttons.matching(identifier: "Location-OneDriveOnline").firstMatch.tap()
        for (name, limit) in [("Huge.png", "128 MiB"), ("Huge.mp4", "2048 MiB")] {
            let row = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@ AND identifier BEGINSWITH %@", name, "OneDriveFile-")).firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: 15)); row.tap()
            app.buttons.matching(identifier: "DesktopAction-preview").firstMatch.tap()
            let error = app.staticTexts.matching(identifier: "OnlineReadError-1").firstMatch
            XCTAssertTrue(error.waitForExistence(timeout: 15)); XCTAssertTrue(error.label.contains(limit))
            XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("PreviewAnyDownload.txt").path))
            XCTAssertFalse(app.buttons.matching(identifier: "CancelFileOperation").firstMatch.exists)
            XCTAssertTrue(row.exists)
        }
#endif
    }

    func testOnlineQuotaShowsDatedCacheWithoutRequestStormAndNavigationCancelsRetry() throws {
#if os(macOS) || targetEnvironment(macCatalyst)
        app.terminate(); app.launchArguments += ["--mac-parity-online-preview"]; app.launch()
        app.buttons.matching(identifier: "Location-OneDriveOnline").firstMatch.tap()
        let row = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@ AND identifier BEGINSWITH %@", "Proof.txt", "OneDriveFile-")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 15)); row.tap()
        try Data("synthetic quota only".utf8).write(to: root.appendingPathComponent("PreviewQuota.txt"))
        app.typeKey("r", modifierFlags: .command)
        let warning = app.staticTexts.matching(identifier: "OnlineCachedListingWarning").firstMatch
        XCTAssertTrue(warning.waitForExistence(timeout: 15))
        XCTAssertTrue(warning.label.contains("Cached listing from") && warning.label.contains("quota"))
        let countFile = root.appendingPathComponent("PreviewListRequests.txt")
        let before = try String(contentsOf: countFile, encoding: .utf8)
        app.typeKey("r", modifierFlags: .command)
        XCTAssertEqual(try String(contentsOf: countFile, encoding: .utf8), before)
        app.buttons.matching(identifier: "Location-/").firstMatch.tap()
        let path = app.textFields.matching(identifier: "Path-1").firstMatch
        XCTAssertTrue(path.waitForExistence(timeout: 10)); XCTAssertEqual(path.value as? String, "/")
        let staleRetry = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            (try? String(contentsOf: countFile, encoding: .utf8)) != before
        }, object: nil)
        staleRetry.isInverted = true
        XCTAssertEqual(XCTWaiter.wait(for: [staleRetry], timeout: 12), .completed)
#endif
    }

    func testOnlineListingFailureRecoversWithoutLoginOrMutation() throws {
#if os(macOS) || targetEnvironment(macCatalyst)
        app.terminate()
        let outage = root.appendingPathComponent("PreviewOffline.txt")
        try Data("only this synthetic transport is offline".utf8).write(to: outage)
        app.launchArguments += ["--mac-parity-online-preview", "--mac-parity-online-offline"]
        app.launch()
        app.buttons.matching(identifier: "Location-OneDriveOnline").firstMatch.tap()
        let failureText = app.staticTexts.matching(identifier: "OnlineReadError-1").firstMatch
        XCTAssertTrue(failureText.waitForExistence(timeout: 15))
        let status = failureText
        let failed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            status.exists && status.label.contains("cloud request failed")
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [failed], timeout: 15), .completed)
        XCTAssertFalse(app.alerts.firstMatch.exists)
        try FileManager.default.removeItem(at: outage)
        app.buttons.matching(identifier: "OnlineReadRetry-1").firstMatch.tap()
        let row = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@ AND identifier BEGINSWITH %@", "Proof.txt", "OneDriveFile-")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 15))
        XCTAssertFalse(app.alerts.firstMatch.exists)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("PreviewDownloadPath.txt").path))
#endif
    }

    func testOnlinePreviewTimeoutCleansStagingAndAllowsRetry() throws {
#if os(macOS) || targetEnvironment(macCatalyst)
        app.terminate()
        app.launchArguments += ["--mac-parity-online-preview", "--mac-parity-preview-timeout"]
        app.launch()
        app.buttons.matching(identifier: "Location-OneDriveOnline").firstMatch.tap()
        let row = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@ AND identifier BEGINSWITH %@", "Proof.txt", "OneDriveFile-")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 15)); row.tap()
        app.buttons.matching(identifier: "DesktopAction-preview").firstMatch.tap()
        let failureText = app.staticTexts.matching(identifier: "OnlineReadError-1").firstMatch
        XCTAssertTrue(failureText.waitForExistence(timeout: 15))
        XCTAssertTrue(failureText.label.contains("timed out"))
        let marker = root.appendingPathComponent("PreviewDownloadPath.txt")
        let staging = URL(fileURLWithPath: try String(contentsOf: marker, encoding: .utf8)).deletingLastPathComponent()
        XCTAssertFalse(FileManager.default.fileExists(atPath: staging.path))
        XCTAssertFalse(app.buttons.matching(identifier: "CancelFileOperation").firstMatch.exists)
        XCTAssertTrue(row.exists)
        app.buttons.matching(identifier: "OnlineReadRetry-1").firstMatch.tap()
        let text = app.textViews.matching(identifier: "TextPreviewContent").firstMatch
        XCTAssertTrue(text.waitForExistence(timeout: 20))
        XCTAssertEqual(text.value as? String, "Synthetic cloud preview: Grüße 日本語 👋\n")
        app.typeKey(XCUIKeyboardKey.escape.rawValue, modifierFlags: [])
        XCTAssertTrue(text.waitForNonExistence(timeout: 10))
        app.buttons.matching(identifier: "HistoryButton").firstMatch.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label == %@", "No actions in history")).firstMatch.waitForExistence(timeout: 10))
#endif
    }

    func testOnlinePreviewProgressCancellationAndRetryWithoutHistory() throws {
#if os(macOS) || targetEnvironment(macCatalyst)
        app.terminate()
        app.launchArguments.append("--mac-parity-online-preview")
        app.launch()
        app.buttons.matching(identifier: "Location-OneDriveOnline").firstMatch.tap()
        let row = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@ AND identifier BEGINSWITH %@", "Proof.txt", "OneDriveFile-")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 15)); row.tap()
        app.buttons.matching(identifier: "DesktopAction-preview").firstMatch.tap()
        let cancel = app.buttons.matching(identifier: "CancelFileOperation").firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 10))
        let loading = app.descendants(matching: .any).matching(identifier: "OneDriveLoading").firstMatch
        XCTAssertEqual(loading.label, "Opening file…")
        let started = root.appendingPathComponent("PreviewDownloadPath.txt")
        waitForFile("PreviewDownloadPath.txt", exists: true)
        let firstPath = try String(contentsOf: started, encoding: .utf8)
        cancel.tap()
        XCTAssertTrue(cancel.waitForNonExistence(timeout: 15))
        XCTAssertFalse(app.alerts.firstMatch.exists)
        XCTAssertFalse(app.textViews.matching(identifier: "TextPreviewContent").firstMatch.exists)
        XCTAssertFalse(FileManager.default.fileExists(atPath: URL(fileURLWithPath: firstPath).deletingLastPathComponent().path))
        XCTAssertTrue(row.exists)
        XCTAssertTrue(app.buttons.matching(identifier: "RenameButton").firstMatch.isEnabled)
        row.tap(); app.buttons.matching(identifier: "DesktopAction-preview").firstMatch.tap()
        XCTAssertTrue(cancel.waitForExistence(timeout: 10))
        let text = app.textViews.matching(identifier: "TextPreviewContent").firstMatch
        XCTAssertTrue(text.waitForExistence(timeout: 20))
        XCTAssertEqual(text.value as? String, "Synthetic cloud preview: Grüße 日本語 👋\n")
        XCTAssertFalse(cancel.exists)
        let secondPath = try String(contentsOf: started, encoding: .utf8)
        XCTAssertTrue(FileManager.default.fileExists(atPath: secondPath))
        app.typeKey(XCUIKeyboardKey.escape.rawValue, modifierFlags: [])
        XCTAssertTrue(text.waitForNonExistence(timeout: 10))
        XCTAssertFalse(FileManager.default.fileExists(atPath: URL(fileURLWithPath: secondPath).deletingLastPathComponent().path))
        XCTAssertTrue(app.buttons.matching(identifier: "RenameButton").firstMatch.isEnabled)
        app.buttons.matching(identifier: "HistoryButton").firstMatch.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label == %@", "No actions in history")).firstMatch.waitForExistence(timeout: 10))
#endif
    }

    func testLateCancelDiscardsCompletedLocalToolResultsAndRenamePlan() throws {
#if os(macOS) || targetEnvironment(macCatalyst)
        let fm = FileManager.default
        let original = try Data(contentsOf: root.appendingPathComponent("Left/Alpha.txt"))
        for mode in ["search", "compare", "rename"] {
            let flag = root.appendingPathComponent("PauseToolResultsAfterRead")
            let ready = root.appendingPathComponent("ToolResultsReady.txt")
            if fm.fileExists(atPath: ready.path) { try fm.removeItem(at: ready) }
            try Data("own read-only tool gate".utf8).write(to: flag)
            file("Alpha.txt", pane: 1).tap()
            if mode == "search" { app.typeKey("f", modifierFlags: .command) }
            else if mode == "compare" { app.typeKey("c", modifierFlags: [.command, .option]) }
            else { app.typeKey("m", modifierFlags: [.command, .shift]) }
            let run = app.buttons.matching(identifier: "CommanderToolRun").firstMatch
            XCTAssertTrue(run.waitForExistence(timeout: 10)); run.tap()
            waitForFile("ToolResultsReady.txt", exists: true)
            let close = app.buttons.matching(identifier: "CommanderToolClose").firstMatch
            close.tap()
            let status = app.staticTexts.matching(identifier: "CommanderToolStatus").firstMatch
            XCTAssertTrue(status.label.lowercased().contains("cancelling"))
            try fm.removeItem(at: flag)
            let stopped = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in run.isEnabled && status.label.lowercased().contains("cancel") }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [stopped], timeout: 10), .completed, mode)
            XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "CommanderToolResult-0").firstMatch.exists)
            if mode == "rename" { XCTAssertFalse(app.buttons.matching(identifier: "CommanderToolApply").firstMatch.isEnabled) }
            XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("Left/Alpha.txt")), original)
            // An independent retry must produce results after cancellation.
            run.tap()
            XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "CommanderToolResult-0").firstMatch.waitForExistence(timeout: 15))
            close.tap(); XCTAssertTrue(run.waitForNonExistence(timeout: 10))
        }
#endif
    }

    func testOnlineCompareCancelDoesNotPublishEqualityAndRetryIsUsable() throws {
#if os(macOS) || targetEnvironment(macCatalyst)
        let original = Data("Synthetic cloud preview: Grüße 日本語 👋\n".utf8)
        let proof = root.appendingPathComponent("Right/Proof.txt")
        try original.write(to: proof)
        app.terminate(); app.launchArguments.append("--mac-parity-online-preview"); app.launch()
        app.buttons.matching(identifier: "Location-OneDriveOnline").firstMatch.tap()
        let item = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@ AND identifier BEGINSWITH %@", "Proof.txt", "OneDriveFile-")).firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 15)); item.tap()
        app.typeKey("c", modifierFlags: [.command, .option])
        let run = app.buttons.matching(identifier: "CommanderToolRun").firstMatch
        XCTAssertTrue(run.waitForExistence(timeout: 10)); run.tap()
        waitForFile("PreviewDownloadPath.txt", exists: true)
        let download = try String(contentsOf: root.appendingPathComponent("PreviewDownloadPath.txt"), encoding: .utf8)
        let close = app.buttons.matching(identifier: "CommanderToolClose").firstMatch
        close.tap()
        let status = app.staticTexts.matching(identifier: "CommanderToolStatus").firstMatch
        let stopped = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in run.isEnabled && status.label.lowercased().contains("cancelled") }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [stopped], timeout: 15), .completed)
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "CommanderToolResult-0").firstMatch.exists)
        XCTAssertFalse(FileManager.default.fileExists(atPath: URL(fileURLWithPath: download).deletingLastPathComponent().path))
        XCTAssertEqual(try Data(contentsOf: proof), original)
        run.tap()
        let result = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "CommanderToolResult-", "Equal · Proof.txt")).firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 20))
        XCTAssertEqual(try Data(contentsOf: proof), original)
        close.tap(); XCTAssertTrue(run.waitForNonExistence(timeout: 10))
#endif
    }

    func testUnsafeArchivesRefuseListingAndExtractionWithoutPublication() throws {
#if os(macOS) || targetEnvironment(macCatalyst)
        let sentinel = root.appendingPathComponent("Outside.txt")
        let proof = Data("outside extraction target: must remain unchanged\n".utf8)
        try proof.write(to: sentinel)
        let cases: [(String, [(String, UInt8, String, UInt64)])] = [
            ("Traversal", [("../Outside.txt", 48, "", 0)]),
            ("Absolute", [(sentinel.path, 48, "", 0)]),
            ("Symlink", [("link", 50, "../Outside.txt", 0)]),
            ("Hardlink", [("link", 49, "../Outside.txt", 0)]),
            ("FIFO", [("pipe", 54, "", 0)]),
            ("Device", [("device", 51, "", 0)]),
            ("Duplicate", [("same", 48, "", 0), ("same", 48, "", 0)]),
            ("CaseCollision", [("Same", 48, "", 0), ("same", 48, "", 0)]),
            ("DeclaredTooLarge", [("huge", 48, "", 4 * 1024 * 1024 * 1024 + 1)])]
        for (name, members) in cases {
            let archive = try makeTestTar(name, members: members)
            let original = try Data(contentsOf: archive)
            openTestArchive(archive)
            XCTAssertTrue(app.buttons["DirectoryRetry-1"].waitForExistence(timeout: 15), name)
            XCTAssertTrue(app.staticTexts["DirectoryMessage-1"].label.contains("archive"), name)
            let extract = app.buttons["DesktopAction-extract_archive"]
            XCTAssertTrue(extract.waitForExistence(timeout: 10)); extract.tap()
            let failed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                let text = self.app.staticTexts["GlobalStatus"].label
                return text.contains("Unsafe") || text.contains("archive could not be read")
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [failed], timeout: 15), .completed, name)
            XCTAssertEqual(try Data(contentsOf: sentinel), proof, name)
            XCTAssertEqual(try Data(contentsOf: archive), original, name)
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("Right").path), ["DropHere"], name)
        }
#endif
    }

    func testArchivePreflightPreservesValidZIPBrowseAndExtraction() throws {
#if os(macOS) || targetEnvironment(macCatalyst)
        file("Pack", pane: 1).tap(); app.buttons["ZipButton"].tap()
        let save = app.buttons["Save"]
        XCTAssertTrue(save.waitForExistence(timeout: 10))
        // AppKit's Save panel sits beside the Catalyst accessibility tree.
        // Activate its observed default button with Return rather than asking
        // XCTest to resolve that hybrid button a second time.
        app.typeKey("\r", modifierFlags: [])
        waitForFile("Left/Pack.zip", exists: true)
        let archive = root.appendingPathComponent("Left/Pack.zip")
        let before = try Data(contentsOf: archive)
        openTestArchive(archive)
        XCTAssertTrue(file("Pack", pane: 1).waitForExistence(timeout: 15))
        file("Pack", pane: 1).doubleTap()
        XCTAssertTrue(file("Note.txt", pane: 1).waitForExistence(timeout: 15))
        app.buttons["DesktopAction-extract_archive"].tap()
        waitForFile("Right/Pack/Note.txt", exists: true)
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("Right/Pack/Note.txt")),
                       try Data(contentsOf: root.appendingPathComponent("Left/Pack/Note.txt")))
        XCTAssertEqual(try Data(contentsOf: archive), before)
#endif
    }

    func testEmptyTruncatedAndEncryptedZIPShowHonestStateWithoutMutation() throws {
#if os(macOS) || targetEnvironment(macCatalyst)
        let empty = root.appendingPathComponent("Left/Empty.zip")
        try Data([0x50, 0x4b, 5, 6] + Array(repeating: UInt8(0), count: 18)).write(to: empty)
        openTestArchive(empty)
        XCTAssertTrue(app.staticTexts["DirectoryMessage-1"].waitForExistence(timeout: 15))
        XCTAssertEqual(app.staticTexts["DirectoryMessage-1"].label, "This folder is empty.")
        XCTAssertFalse(app.buttons["DirectoryRetry-1"].exists)
        let broken = root.appendingPathComponent("Left/Truncated.zip")
        let original = Data([0x50, 0x4b, 3, 4, 0, 0, 0])
        try original.write(to: broken)
        openTestArchive(broken)
        XCTAssertTrue(app.buttons["DirectoryRetry-1"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["DirectoryMessage-1"].label.contains("Password-protected archives are not supported"))
        XCTAssertEqual(try Data(contentsOf: broken), original)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("Right").path), ["DropHere"])
        // Real ZipCrypto fixture generated with system zip and independently
        // verified by unzip -t using the public test password test-fixture-only.
        let encrypted = root.appendingPathComponent("Left/Protected.zip")
        let protectedBytes = try XCTUnwrap(Data(base64Encoded: "UEsDBAoACQAAAGBHWV3JozvvRgAAADoAAAAKABwAU2VjcmV0LnR4dFVUCQADw7bdasO23Wp1eAsAAQT1AQAABAAAAADEiX+SqhbmYihCCim0CiNdRijEbb5bIgv+Q6uvxuP+3SNz08AocHvyWlvqhURgm2wcG3H18pvCWonP+T1l0lyiEAqf8w6TUEsHCMmjO+9GAAAAOgAAAFBLAQIeAwoACQAAAGBHWV3JozvvRgAAADoAAAAKABgAAAAAAAEAAACkgQAAAABTZWNyZXQudHh0VVQFAAPDtt1qdXgLAAEE9QEAAAQAAAAAUEsFBgAAAAABAAEAUAAAAJoAAAAAAA=="))
        try protectedBytes.write(to: encrypted)
        openTestArchive(encrypted)
        app.buttons["DesktopAction-extract_archive"].tap()
        let refused = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            self.app.staticTexts["GlobalStatus"].label.contains("Password-protected archives are not supported")
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [refused], timeout: 15), .completed)
        XCTAssertEqual(app.secureTextFields.count, 0, "Do not imply a working password assistant")
        XCTAssertEqual(try Data(contentsOf: encrypted), protectedBytes)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("Right").path), ["DropHere"])
#endif
    }

    func testCopyHistoryRelaunchAndUndo() throws {
#if os(macOS) || targetEnvironment(macCatalyst)
        file("Alpha.txt", pane: 1).tap()
        app.typeKey("\u{F708}", modifierFlags: []) // F5
        waitForFile("Right/Alpha.txt", exists: true)
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("Left/Alpha.txt")), try Data(contentsOf: root.appendingPathComponent("Right/Alpha.txt")))
        app.buttons["HistoryButton"].tap()
        XCTAssertTrue(app.buttons["HistoryUndo-0"].waitForExistence(timeout: 10))
        app.terminate()
        app.launchArguments = ["--mac-parity-fixtures"]
        app.launch()
        app.buttons["HistoryButton"].tap()
        XCTAssertTrue(app.buttons["HistoryUndo-0"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["HistoryTime-0"].exists)
        app.buttons["UndoButton"].tap()
        waitForFile("Right/Alpha.txt", exists: false)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("Left/Alpha.txt").path))
#endif
    }

    func testKeyboardClipboardPaneSwitchAndTextEditingDoNotMutateSelection() throws {
#if os(macOS) || targetEnvironment(macCatalyst)
        let source = root.appendingPathComponent("Left/Alpha.txt")
        let original = try Data(contentsOf: source)
        file("Alpha.txt", pane: 1).tap()
        app.typeKey("c", modifierFlags: .command)
        app.typeKey("\t", modifierFlags: [])
        app.typeKey("v", modifierFlags: .command)
        waitForFile("Right/Alpha.txt", exists: true)
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("Right/Alpha.txt")), original)
        file("Alpha.txt", pane: 2).tap()
        app.typeKey("f", modifierFlags: .command)
        let searchPath = app.textFields["CommanderSearchPath"]
        XCTAssertTrue(searchPath.waitForExistence(timeout: 10))
        XCTAssertEqual(canonical(searchPath.value as? String), canonical(root.appendingPathComponent("Right").path))
        app.buttons["CommanderToolClose"].tap()

        // Editing shortcuts must operate on text, never the still-selected file.
        let path = app.textFields.matching(identifier: "Path-2").firstMatch
        path.tap(); path.typeKey("a", modifierFlags: .command)
        path.typeKey("c", modifierFlags: .command)
        path.typeKey("x", modifierFlags: .command)
        XCTAssertEqual(path.value as? String, "")
        path.typeKey("v", modifierFlags: .command)
        XCTAssertEqual(canonical(path.value as? String), canonical(root.appendingPathComponent("Right").path))
        path.typeKey("a", modifierFlags: .command)
        path.typeText(XCUIKeyboardKey.delete.rawValue)
        XCTAssertEqual(path.value as? String, "")
        path.typeText(root.appendingPathComponent("Right").path + "\n")
        XCTAssertEqual(try Data(contentsOf: source), original)
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("Right/Alpha.txt")), original)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("Right/Alpha (2).txt").path))
        file("Alpha.txt", pane: 2).tap()
        app.typeKey("y", modifierFlags: .command)
        XCTAssertTrue(app.buttons["TextPreviewClose"].waitForExistence(timeout: 10))
        app.typeKey(XCUIKeyboardKey.escape.rawValue, modifierFlags: [])
        let closed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            !self.app.buttons["TextPreviewClose"].exists
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [closed], timeout: 10), .completed)
#endif
    }

    func testSearchUsesPanePathAndShowsResultPath() throws {
        file("Alpha.txt", pane: 1).tap()
        app.buttons["CommanderSearchButton"].tap()
        let path = app.textFields["CommanderSearchPath"]
        XCTAssertTrue(path.waitForExistence(timeout: 10))
        XCTAssertEqual(canonical(path.value as? String), canonical(root.appendingPathComponent("Left").path))
        XCTAssertFalse(app.buttons["CommanderSearchMatchCase"].isSelected)
        let query = app.textFields["CommanderToolField-0"]
        query.tap()
#if os(macOS) || targetEnvironment(macCatalyst)
        query.typeKey("a", modifierFlags: .command)
#endif
        query.typeText("alpha.txt")
        app.buttons["CommanderToolRun"].tap()
        let result = app.descendants(matching: .any)["CommanderToolResult-0"]
        XCTAssertTrue(result.waitForExistence(timeout: 10))
        XCTAssertTrue(result.label.contains(root.appendingPathComponent("Left/Alpha.txt").path),
                      "Search result must expose its complete path; actual accessible label: \(result.label)")
        app.buttons["CommanderToolClose"].tap()
    }

    func testNativeDragBetweenPanesPublishesCompleteFile() throws {
        let source = file("Alpha.txt", pane: 1), target = file("DropHere", pane: 2)
        XCTAssertTrue(source.waitForExistence(timeout: 10)); XCTAssertTrue(target.exists)
        source.press(forDuration: 1.0, thenDragTo: target, withVelocity: .slow, thenHoldForDuration: 0.5)
        waitForFile("Right/DropHere/Alpha.txt", exists: true)
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("Left/Alpha.txt")), try Data(contentsOf: root.appendingPathComponent("Right/DropHere/Alpha.txt")))
    }

    func testDragToggleCopyMoveAndReadonlyTargetPreserveExactBytes() throws {
        app.terminate()
        let fm = FileManager.default
        let beta = root.appendingPathComponent("Left/Beta.txt")
        let betaBytes = Data("independent move fixture: Grüße\n".utf8)
        try betaBytes.write(to: beta)
        let readonly = root.appendingPathComponent("Right/Readonly")
        try fm.createDirectory(at: readonly, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o555])
        app.launch()
        let source = file("Alpha.txt", pane: 1), target = file("DropHere", pane: 2)
        XCTAssertTrue(source.waitForExistence(timeout: 10)); XCTAssertTrue(target.exists)
        let alphaBytes = try Data(contentsOf: root.appendingPathComponent("Left/Alpha.txt"))
        source.tap()
        let toggle = app.switches["OperationModeSwitch"]
        XCTAssertEqual(toggle.value as? String, "0")
        source.press(forDuration: 1, thenDragTo: target, withVelocity: .slow, thenHoldForDuration: 0.5)
        waitForFile("Right/DropHere/Alpha.txt", exists: true)
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("Left/Alpha.txt")), alphaBytes)
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("Right/DropHere/Alpha.txt")), alphaBytes)
        let moveSource = file("Beta.txt", pane: 1)
        XCTAssertTrue(moveSource.exists); moveSource.tap(); toggle.tap()
        XCTAssertEqual(toggle.value as? String, "1")
        moveSource.press(forDuration: 1, thenDragTo: target, withVelocity: .slow, thenHoldForDuration: 0.5)
        waitForFile("Right/DropHere/Beta.txt", exists: true); waitForFile("Left/Beta.txt", exists: false)
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("Right/DropHere/Beta.txt")), betaBytes)
        source.tap()
        let forbidden = file("Readonly", pane: 2)
        XCTAssertTrue(forbidden.exists)
        source.press(forDuration: 1, thenDragTo: forbidden, withVelocity: .slow, thenHoldForDuration: 0.5)
        XCTAssertEqual(try fm.contentsOfDirectory(atPath: readonly.path), [])
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("Left/Alpha.txt")), alphaBytes)
    }

    func testSettingsKeyboardNavigationEditsReordersAndPreservesFiles() throws {
#if os(macOS) || targetEnvironment(macCatalyst)
        app.terminate()
        let favourite = root.appendingPathComponent("Left/Favourite", isDirectory: true)
        try FileManager.default.createDirectory(at: favourite, withIntermediateDirectories: false)
        let proof = favourite.appendingPathComponent("Keep.txt")
        let bytes = Data("Keyboard preference edits do not change file contents.\n".utf8)
        try bytes.write(to: proof)
        try JSONSerialization.data(withJSONObject: [["path": favourite.path, "name": "Keyboard favourite", "enabled": true, "custom": true]])
            .write(to: root.appendingPathComponent("AcceptanceLocations.json"), options: .atomic)
        app.launchArguments = ["--mac-parity-fixtures"]; app.launch()
        app.typeKey(",", modifierFlags: .command)
        let list = app.descendants(matching: .any).matching(identifier: "LocationSettingsList").firstMatch
        XCTAssertTrue(list.waitForExistence(timeout: 15))
        // Six general settings, OneDrive and then our own first favourite.
        for _ in 0..<8 { app.typeKey("\t", modifierFlags: []) }
        XCTAssertEqual(list.value as? String, "Keyboard favourite")
        let shortcut = app.buttons.matching(identifier: "Location-" + (canonical(favourite.path) ?? favourite.path)).firstMatch
        XCTAssertTrue(shortcut.exists)
        app.typeKey(" ", modifierFlags: [])
        XCTAssertFalse(shortcut.exists)
        app.typeKey(" ", modifierFlags: [])
        XCTAssertTrue(shortcut.waitForExistence(timeout: 10))
        app.typeKey(XCUIKeyboardKey.upArrow.rawValue, modifierFlags: .option)
        let ownRow = app.cells.matching(identifier: "LocationSetting-" + favourite.path).firstMatch
        let oneDrive = app.cells.matching(identifier: "LocationSetting-onedrive://online").firstMatch
        XCTAssertLessThan(ownRow.frame.minY, oneDrive.frame.minY)
        app.typeKey("\r", modifierFlags: [])
        let name = app.textFields.matching(NSPredicate(format: "value == %@", "Keyboard favourite")).firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 10))
        name.typeKey("a", modifierFlags: .command); name.typeText("Keyboard renamed")
        app.typeKey("\r", modifierFlags: [])
        let renamed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            shortcut.label.contains("Keyboard renamed")
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [renamed], timeout: 10), .completed)
        app.typeKey("n", modifierFlags: .command)
        XCTAssertTrue(app.buttons["SSH – SFTP (SCP)"].waitForExistence(timeout: 10))
        app.typeKey(XCUIKeyboardKey.escape.rawValue, modifierFlags: [])
        XCTAssertTrue(list.exists)
        app.typeKey(XCUIKeyboardKey.escape.rawValue, modifierFlags: [])
        let closed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in !list.exists }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [closed], timeout: 10), .completed)
        XCTAssertEqual(try Data(contentsOf: proof), bytes)
        app.terminate(); app.launch()
        XCTAssertTrue(shortcut.waitForExistence(timeout: 15))
        XCTAssertTrue(shortcut.label.contains("Keyboard renamed"))
        app.typeKey(",", modifierFlags: .command)
        XCTAssertTrue(ownRow.waitForExistence(timeout: 15))
        XCTAssertLessThan(ownRow.frame.minY, oneDrive.frame.minY)
        XCTAssertEqual(try Data(contentsOf: proof), bytes)
#endif
    }

    func testTransferQueueKeyboardResumesAndRemovesCardsNotFiles() throws {
#if os(macOS) || targetEnvironment(macCatalyst)
        app.terminate()
        let ids = [UUID(), UUID()]
        let source = root.appendingPathComponent("Left/Alpha.txt")
        let bytes = try Data(contentsOf: source)
        let jobs: [[String: Any]] = ids.enumerated().map { index, id in [
            "id": id.uuidString, "source": source.path,
            "destination": root.appendingPathComponent("Right/Keyboard-\(index).txt").path,
            "state": "paused", "bytes": 0, "total": bytes.count,
            "created": Date().timeIntervalSinceReferenceDate + Double(index), "compact": true, "engine": "file"] }
        let transfers = root.appendingPathComponent("Transfers", isDirectory: true)
        try FileManager.default.createDirectory(at: transfers, withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: ["version": 1, "limit": 1, "jobs": jobs])
            .write(to: transfers.appendingPathComponent("copy-jobs-v1.json"), options: .atomic)
        app.launchArguments = ["--mac-parity-fixtures"]; app.launch()
        file("Alpha.txt", pane: 1).tap()
        app.typeKey("t", modifierFlags: [.command, .shift])
        let panel = app.descendants(matching: .any).matching(identifier: "TransferQueuePanel").firstMatch
        XCTAssertTrue(panel.waitForExistence(timeout: 15))
        XCTAssertEqual(canonical(panel.value as? String), canonical(root.appendingPathComponent("Right/Keyboard-1.txt").path))
        app.typeKey("\u{F708}", modifierFlags: []) // File-pane F5 must not leak through the focused queue.
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("Right/Alpha.txt").path))
        let detail = app.buttons["transfer_compact-\(ids[1])"]
        let compactLabel = detail.label
        app.typeKey(" ", modifierFlags: [])
        let expanded = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in detail.label != compactLabel }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [expanded], timeout: 10), .completed)
        file("Alpha.txt", pane: 1).tap()
        app.typeKey("f", modifierFlags: .command)
        XCTAssertTrue(app.textFields["CommanderSearchPath"].waitForExistence(timeout: 10), "Clicking a file must leave queue keyboard mode")
        app.buttons["CommanderToolClose"].tap()
        app.typeKey("t", modifierFlags: [.command, .shift])
        app.typeKey("r", modifierFlags: [])
        waitForFile("Right/Keyboard-1.txt", exists: true)
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("Right/Keyboard-1.txt")), bytes)
        let finished = app.buttons["transfer_forget-\(ids[1])"]
        XCTAssertTrue(finished.waitForExistence(timeout: 15))
        app.typeKey(XCUIKeyboardKey.delete.rawValue, modifierFlags: [])
        let forgotten = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in !finished.exists }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [forgotten], timeout: 10), .completed)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("Right/Keyboard-1.txt").path))
        app.typeKey(XCUIKeyboardKey.downArrow.rawValue, modifierFlags: [])
        XCTAssertEqual(canonical(panel.value as? String), canonical(root.appendingPathComponent("Right/Keyboard-0.txt").path))
        app.typeKey("r", modifierFlags: [])
        waitForFile("Right/Keyboard-0.txt", exists: true)
        XCTAssertTrue(app.buttons["transfer_forget-\(ids[0])"].waitForExistence(timeout: 15))
        app.typeKey(XCUIKeyboardKey.delete.rawValue, modifierFlags: [.command, .shift])
        let empty = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            !self.app.buttons["TransferRemoveCompleted"].isEnabled
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [empty], timeout: 10), .completed)
        app.typeKey(XCUIKeyboardKey.escape.rawValue, modifierFlags: [])
        let closed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in !panel.exists }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [closed], timeout: 10), .completed)
        XCTAssertEqual(try Data(contentsOf: source), bytes)
        for index in 0..<2 { XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("Right/Keyboard-\(index).txt")), bytes) }
#endif
    }

    func testCloudProgressAllowsIndependentPaneNavigationWithoutRedirectingOwner() throws {
#if os(macOS) || targetEnvironment(macCatalyst)
        app.terminate()
        let hold = root.appendingPathComponent("HoldPreviewDownload.txt")
        try Data(UUID().uuidString.utf8).write(to: hold)
        app.launchArguments.append("--mac-parity-online-preview")
        app.launch()
        app.buttons.matching(identifier: "Location-OneDriveOnline").firstMatch.tap()
        let proof = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@ AND identifier BEGINSWITH %@", "Proof.txt", "OneDriveFile-")).firstMatch
        XCTAssertTrue(proof.waitForExistence(timeout: 15)); proof.tap()
        app.buttons["DesktopAction-preview"].tap()
        let cancel = app.buttons["CancelFileOperation"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 10))
        waitForFile("PreviewDownloadPath.txt", exists: true)
        let ownerPath = app.staticTexts["OneDriveOnlinePath"]
        XCTAssertTrue(ownerPath.label.contains("OneDrive online:/"))
        app.buttons["Location-/"].tap()
        XCTAssertTrue(ownerPath.exists, "Locations must not unmount the running operation owner")
        let right = app.textFields["Path-2"]
        right.tap(); right.typeKey("a", modifierFlags: .command)
        right.typeText(root.appendingPathComponent("Right/DropHere").path + "\n")
        let navigated = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            self.canonical(right.value as? String) == self.canonical(self.root.appendingPathComponent("Right/DropHere").path)
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [navigated], timeout: 15), .completed)
        XCTAssertTrue(cancel.exists)
        app.typeKey("n", modifierFlags: [.command, .shift])
        XCTAssertFalse(app.alerts.firstMatch.exists, "Navigation mode must not enable concurrent mutations")
        app.typeKey("l", modifierFlags: .command)
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 10), "Read-only navigation shortcuts remain available")
        app.alerts.firstMatch.buttons["Cancel"].tap()
        XCTAssertTrue(cancel.exists)
        // Another pane may establish a read-only provider list without starting
        // another foreground operation or stealing the original Cancel target.
        app.buttons.matching(identifier: "Location-OneDriveOnline").firstMatch.tap()
        let secondRead = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            self.app.staticTexts.matching(identifier: "OneDriveOnlinePath").count == 2 &&
            self.app.descendants(matching: .any).matching(NSPredicate(format: "label == %@ AND identifier BEGINSWITH %@", "Proof.txt", "OneDriveFile-")).count >= 2
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [secondRead], timeout: 15), .completed)
        XCTAssertTrue(cancel.exists)
        try FileManager.default.removeItem(at: hold)
        let content = app.textViews["TextPreviewContent"]
        XCTAssertTrue(content.waitForExistence(timeout: 20))
        XCTAssertEqual(content.value as? String, "Synthetic cloud preview: Grüße 日本語 👋\n")
        app.typeKey(XCUIKeyboardKey.escape.rawValue, modifierFlags: [])
        XCTAssertTrue(content.waitForNonExistence(timeout: 10))
        XCTAssertFalse(cancel.exists)
        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@ AND identifier BEGINSWITH %@", "Proof.txt", "OneDriveFile-")).element(boundBy: 1).tap()
        XCTAssertTrue(app.buttons["RenameButton"].isEnabled)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("Right/DropHere").path), [])
#endif
    }

    func testCloudCopyKeepsOriginalDestinationWhileOtherPaneNavigates() throws {
#if os(macOS) || targetEnvironment(macCatalyst)
        app.terminate()
        let hold = root.appendingPathComponent("HoldPreviewDownload.txt")
        try Data(UUID().uuidString.utf8).write(to: hold)
        app.launchArguments.append("--mac-parity-online-preview")
        app.launch()
        app.buttons.matching(identifier: "Location-OneDriveOnline").firstMatch.tap()
        let proof = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@ AND identifier BEGINSWITH %@", "Proof.txt", "OneDriveFile-")).firstMatch
        XCTAssertTrue(proof.waitForExistence(timeout: 15)); proof.tap()
        app.typeKey("c", modifierFlags: .command)
        let right = app.textFields["Path-2"]
        right.tap(); right.typeKey("a", modifierFlags: .command)
        right.typeText(root.appendingPathComponent("Right/DropHere").path + "\n")
        app.typeKey("v", modifierFlags: .command)
        let cancel = app.buttons["CancelFileOperation"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 15))
        waitForFile("PreviewDownloadPath.txt", exists: true)
        right.tap(); right.typeKey("a", modifierFlags: .command)
        right.typeText(root.appendingPathComponent("Right").path + "\n")
        let navigated = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            self.canonical(right.value as? String) == self.canonical(self.root.appendingPathComponent("Right").path)
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [navigated], timeout: 15), .completed)
        XCTAssertTrue(cancel.exists)
        app.typeKey("v", modifierFlags: .command) // No second mutation in navigation mode.
        try FileManager.default.removeItem(at: hold)
        waitForFile("Right/DropHere/Proof.txt", exists: true)
        XCTAssertTrue(cancel.waitForNonExistence(timeout: 15))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("Right/Proof.txt").path))
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("Right/DropHere/Proof.txt")), Data("Synthetic cloud preview: Grüße 日本語 👋\n".utf8))
        XCTAssertTrue(proof.exists, "A copy must preserve the remote source")
        app.buttons["HistoryButton"].tap()
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "HistoryUndo-")).firstMatch.tap()
        waitForFile("Right/DropHere/Proof.txt", exists: false)
#endif
    }

    func testTransferMetricsShowExactDurationCountsAndUnknownPausedRate() throws {
#if os(macOS) || targetEnvironment(macCatalyst)
        app.terminate()
        let id = UUID()
        let transfers = root.appendingPathComponent("Transfers", isDirectory: true)
        try FileManager.default.createDirectory(at: transfers, withIntermediateDirectories: true)
        let job: [String: Any] = ["id": id.uuidString,
            "source": root.appendingPathComponent("Left/Alpha.txt").path,
            "destination": root.appendingPathComponent("Right/Unpublished.txt").path,
            "state": "paused", "bytes": 100, "total": 100,
            "filesDone": 3, "filesTotal": 4, "elapsed": 90061,
            "created": Date().timeIntervalSinceReferenceDate, "compact": false, "engine": "file"]
        try JSONSerialization.data(withJSONObject: ["version": 1, "limit": 2, "jobs": [job]])
            .write(to: transfers.appendingPathComponent("copy-jobs-v1.json"), options: .atomic)
        app.launch()
        app.typeKey("t", modifierFlags: [.command, .shift])
        let details = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "1 day 1 h 1 min 1 s")).firstMatch
        XCTAssertTrue(details.waitForExistence(timeout: 15))
        XCTAssertTrue(details.label.contains("99%"), "Unpublished last block must not report completion")
        XCTAssertTrue(details.label.contains("Files: 3 / 4"))
        XCTAssertTrue(details.label.contains("Speed: —"))
        XCTAssertTrue(details.label.contains("Remaining ~: —"))
        app.typeKey(XCUIKeyboardKey.escape.rawValue, modifierFlags: [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("Right/Unpublished.txt").path))
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("Left/Alpha.txt")), Data("Mac parity copy and drag fixture\n".utf8))
#endif
    }

    func testCompactAndWideWindowKeepControlsAndSettingsUsable() throws {
#if os(macOS) || targetEnvironment(macCatalyst)
        for (flag, width) in [("--mac-parity-window-compact", 900.0), ("--mac-parity-window-wide", 1366.0)] {
            app.terminate()
            app.launchArguments = ["--mac-parity-fixtures", "--mac-parity-reset", flag]; app.launch()
            let window = app.windows.firstMatch
            let resized = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                abs(window.frame.width - width) < 30
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [resized], timeout: 15), .completed, "Actual window: \(window.frame)")
            for id in ["LocationSettingsButton", "TransferQueueButton", "CommanderSearchButton", "RenameButton", "ZipButton", "DesktopAction-preview"] {
                let button = app.buttons[id]
                XCTAssertTrue(button.isHittable, "\(id) at \(window.frame)")
                XCTAssertTrue(window.frame.contains(button.frame), "Clipped \(id): \(button.frame)")
            }
            XCTAssertTrue(file("Alpha.txt", pane: 1).isHittable)
            for pane in 1...2 {
                let path = app.textFields["Path-\(pane)"]
                XCTAssertTrue(path.isHittable)
                XCTAssertGreaterThan(path.frame.width, 80)
            }
            app.typeKey(",", modifierFlags: .command)
            let language = app.buttons["SettingsLanguageDropdown"]
            XCTAssertTrue(language.waitForExistence(timeout: 15))
            XCTAssertTrue(window.frame.contains(language.frame))
            let settingsShot = XCTAttachment(screenshot: app.screenshot())
            settingsShot.name = "Settings-\(Int(width))-points-Retina"; settingsShot.lifetime = .keepAlways; add(settingsShot)
            // Mouse and keyboard share the same bounded dropdown controller.
            app.typeKey("\t", modifierFlags: []); app.typeKey("\r", modifierFlags: [])
            let choices = app.tables["SettingsLanguageChoices"]
            XCTAssertTrue(choices.waitForExistence(timeout: 10))
            XCTAssertTrue(app.cells["LanguageChoice-de"].exists)
            app.typeKey(XCUIKeyboardKey.escape.rawValue, modifierFlags: [])
            let menuClosed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                !choices.exists
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [menuClosed], timeout: 10), .completed)
            XCTAssertTrue(language.exists, "Escape from the language menu must not close settings")
            language.tap()
            XCTAssertTrue(choices.waitForExistence(timeout: 10))
            app.cells["LanguageChoice-de"].tap()
            let chosen = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in !choices.exists }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [chosen], timeout: 10), .completed)
            app.typeKey(XCUIKeyboardKey.escape.rawValue, modifierFlags: [])
            let closed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in !language.exists }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [closed], timeout: 10), .completed)
            XCTAssertTrue(app.buttons["LocationSettingsButton"].label.contains("Einstellungen"))
            app.typeKey("t", modifierFlags: [.command, .shift])
            XCTAssertTrue(app.buttons["TransferRemoveCompleted"].waitForExistence(timeout: 10))
            for id in ["TransferPauseAll", "TransferResumeAll", "TransferRemoveCompleted"] {
                XCTAssertTrue(window.frame.contains(app.buttons[id].frame), "Clipped German queue control \(id)")
                XCTAssertGreaterThan(app.buttons[id].frame.width, 20)
            }
            let queueShot = XCTAttachment(screenshot: app.screenshot())
            queueShot.name = "German-Transfers-\(Int(width))-points-Retina"; queueShot.lifetime = .keepAlways; add(queueShot)
            app.typeKey(XCUIKeyboardKey.escape.rawValue, modifierFlags: [])
        }
#endif
    }

    func testConnectionsRefreshAndCloseInCurrentWindow() throws {
        app.buttons["DesktopAction-connections"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["ConnectionsList"].waitForExistence(timeout: 10))
        app.buttons["ConnectionsRefresh"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["ConnectionsList"].exists)
        app.buttons["ConnectionsClose"].tap()
        XCTAssertTrue(app.textFields["Path-1"].waitForExistence(timeout: 10))
        XCTAssertEqual(canonical(app.textFields["Path-1"].value as? String), canonical(root.appendingPathComponent("Left").path))
    }

    func testIndependentCompactCardsPersistAfterRestart() throws {
        app.terminate()
        let ids = [UUID(), UUID()]
        let jobs: [[String: Any]] = ids.enumerated().map { index, id in [
            "id": id.uuidString, "source": root.appendingPathComponent("Left/Alpha.txt").path,
            "destination": root.appendingPathComponent("Right/Paused-\(index).txt").path,
            "state": "paused", "bytes": 0, "total": 32,
            "created": Date().timeIntervalSinceReferenceDate, "compact": true, "engine": "file"] }
        let transfers = root.appendingPathComponent("Transfers", isDirectory: true)
        try FileManager.default.createDirectory(at: transfers, withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: ["version": 1, "limit": 2, "jobs": jobs])
            .write(to: transfers.appendingPathComponent("copy-jobs-v1.json"), options: .atomic)
        app.launchArguments = ["--mac-parity-fixtures"]
        app.launch()
        app.buttons["TransferQueueButton"].tap()
        let first = app.buttons["transfer_compact-\(ids[0])"]
        let second = app.buttons["transfer_compact-\(ids[1])"]
        XCTAssertTrue(first.waitForExistence(timeout: 15))
        let compactLabel = first.label
        XCTAssertEqual(second.label, compactLabel)
        first.tap()
        XCTAssertNotEqual(first.label, compactLabel)
        XCTAssertEqual(second.label, compactLabel)
        XCTAssertTrue(app.buttons["transfer_resume-\(ids[0])"].isEnabled)
        XCTAssertTrue(app.buttons["transfer_resume-\(ids[1])"].isEnabled)
        app.terminate(); app.launch()
        app.buttons["TransferQueueButton"].tap()
        XCTAssertTrue(first.waitForExistence(timeout: 15))
        XCTAssertNotEqual(first.label, compactLabel)
        XCTAssertEqual(second.label, compactLabel)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("Right/Paused-0.txt").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("Right/Paused-1.txt").path))
    }

    func testRemoveCompletedRefreshesPagesAndListingsWithoutDeletingFiles() throws {
#if os(macOS) || targetEnvironment(macCatalyst)
        app.terminate()
        let bytes = try Data(contentsOf: root.appendingPathComponent("Left/Alpha.txt"))
        var completed: [URL] = []
        var jobs: [[String: Any]] = []
        for index in 0..<65 {
            let destination = root.appendingPathComponent("Right/Completed-\(index).txt")
            try bytes.write(to: destination); completed.append(destination)
            jobs.append(["id": UUID().uuidString, "source": root.appendingPathComponent("Left/Alpha.txt").path,
                         "destination": destination.path, "state": "completed", "bytes": bytes.count,
                         "total": bytes.count, "created": Date().timeIntervalSinceReferenceDate + Double(index),
                         "compact": true, "engine": "file"])
        }
        let paused = UUID()
        jobs.append(["id": paused.uuidString, "source": root.appendingPathComponent("Left/Alpha.txt").path,
                     "destination": root.appendingPathComponent("Right/Paused.txt").path,
                     "state": "paused", "bytes": 0, "total": bytes.count,
                     "created": Date().timeIntervalSinceReferenceDate + 66, "compact": true, "engine": "file"])
        let transfers = root.appendingPathComponent("Transfers", isDirectory: true)
        try FileManager.default.createDirectory(at: transfers, withIntermediateDirectories: true)
        let journal = transfers.appendingPathComponent("copy-jobs-v1.json")
        try JSONSerialization.data(withJSONObject: ["version": 1, "limit": 2, "jobs": jobs])
            .write(to: journal, options: .atomic)
        app.launchArguments = ["--mac-parity-fixtures"]; app.launch()
        app.buttons["TransferQueueButton"].tap()
        let older = app.buttons["TransferPageOlder"]
        XCTAssertTrue(older.waitForExistence(timeout: 15)); XCTAssertTrue(older.isEnabled)
        older.tap()
        XCTAssertTrue(app.buttons["TransferPageNewer"].isEnabled)
        let lateFile = root.appendingPathComponent("Right/CreatedAfterListing.txt")
        try bytes.write(to: lateFile)
        XCTAssertFalse(file(lateFile.lastPathComponent, pane: 2).exists)
        app.buttons["TransferRemoveCompleted"].tap()
        XCTAssertTrue(app.buttons["transfer_resume-\(paused)"].waitForExistence(timeout: 15))
        XCTAssertFalse(older.exists)
        XCTAssertFalse(app.buttons["TransferRemoveCompleted"].isEnabled)
        XCTAssertTrue(file(lateFile.lastPathComponent, pane: 2).waitForExistence(timeout: 15))
        for url in completed { XCTAssertEqual(try Data(contentsOf: url), bytes) }
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("Left/Alpha.txt")), bytes)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("Right/Paused.txt").path))
        app.terminate(); app.launch()
        app.buttons["TransferQueueButton"].tap()
        XCTAssertTrue(app.buttons["transfer_resume-\(paused)"].waitForExistence(timeout: 15))
        let saved = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: journal)) as? [String: Any])
        XCTAssertEqual((saved["jobs"] as? [[String: Any]])?.count, 1)
#endif
    }

    func testTwentyThousandLocalEntriesFilterAndWarmNavigation() throws {
#if os(macOS) || targetEnvironment(macCatalyst)
        let directory = root.appendingPathComponent("Left/Large", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        for index in 0..<20_000 {
            try Data().write(to: directory.appendingPathComponent(String(format: "Entry-%05d.txt", index)))
        }
        let path = app.textFields.matching(identifier: "Path-1").firstMatch
        func openLarge() {
            path.tap(); path.typeKey("a", modifierFlags: .command); path.typeText(directory.path + "\n")
            // A recursive `any` query asks Catalyst to materialize all 20,000
            // offscreen cell accessibility elements before reading the header.
            let selection = app.staticTexts.matching(identifier: "Selection-1").firstMatch
            let complete = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "/20000"), object: selection)
            XCTAssertEqual(XCTWaiter.wait(for: [complete], timeout: 60), .completed)
        }
        let cold = Date(); openLarge()
        let coldSeconds = Date().timeIntervalSince(cold)
        app.buttons.matching(identifier: "Sort-1-0").firstMatch.tap()
        let filter = app.textFields.matching(identifier: "Filter-1").firstMatch
        filter.tap(); filter.typeText("Entry-19999.txt")
        XCTAssertTrue(file("Entry-19999.txt", pane: 1).waitForExistence(timeout: 15))
        XCTAssertFalse(file("Entry-00000.txt", pane: 1).exists)
        filter.typeKey("a", modifierFlags: .command); filter.typeText(XCUIKeyboardKey.delete.rawValue)
        app.buttons.matching(identifier: "Up-1").firstMatch.tap()
        let warm = Date(); openLarge()
        let attachment = XCTAttachment(string: "20,000 local APFS empty entries; cold UI sequence \(coldSeconds)s; warm \(Date().timeIntervalSince(warm))s. XCTest input/observation overhead included; not a subsecond latency certification.")
        attachment.name = "Large-directory-observed-timings"; attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertEqual(canonical(app.textFields.matching(identifier: "Path-2").firstMatch.value as? String), canonical(root.appendingPathComponent("Right").path))
#endif
    }

    func testSpecialCharacterTypedPathsAndInvalidPathRefusal() throws {
#if os(macOS) || targetEnvironment(macCatalyst)
        let special = root.appendingPathComponent("Left/Grüsse $(false) ; ' & # % 文件", isDirectory: true)
        try FileManager.default.createDirectory(at: special, withIntermediateDirectories: false)
        try Data("literal path, never shell syntax\n".utf8).write(to: special.appendingPathComponent("Proof.txt"))
        let path = app.textFields.matching(identifier: "Path-1").firstMatch
        path.tap(); path.typeKey("a", modifierFlags: .command); path.typeText(special.path + "\n")
        XCTAssertTrue(file("Proof.txt", pane: 1).waitForExistence(timeout: 15),
                      "URL handoff path: \(String(describing: path.value)); right: \(String(describing: app.textFields["Path-2"].value))")
        XCTAssertEqual(canonical(path.value as? String), canonical(special.path))
        let right = canonical(app.textFields["Path-2"].value as? String)
        for input in [root.appendingPathComponent("Left").path, special.absoluteString] {
            path.tap(); path.typeKey("a", modifierFlags: .command)
            if input.hasPrefix("file:") {
                path.typeText("file"); path.typeKey(":", modifierFlags: []); path.typeText(String(input.dropFirst(5)))
            } else { path.typeText(input) }
            XCTAssertEqual(path.value as? String, input, "Path field must preserve the literal typed text")
            path.typeText("\n")
            let expected = input == special.absoluteString ? special.path : root.appendingPathComponent("Left").path
            let navigation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                self.canonical(path.value as? String) == self.canonical(expected)
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [navigation], timeout: 15), .completed,
                           "Input: \(input); actual: \(String(describing: path.value)); status: \(app.staticTexts["GlobalStatus"].label)")
            XCTAssertEqual(canonical(path.value as? String), canonical(expected))
        }
        for input in ["https://example.invalid/not-a-local-folder", "file://remote.invalid/tmp", "relative-folder"] {
            path.tap(); path.typeKey("a", modifierFlags: .command); path.typeText(input + "\n")
            XCTAssertTrue(file("Proof.txt", pane: 1).exists)
            XCTAssertEqual(canonical(app.textFields["Path-2"].value as? String), right)
            XCTAssertFalse(app.staticTexts["GlobalStatus"].label.isEmpty)
        }
#endif
    }

    func testHistoryAndPausedQueueRemainTogetherAfterRelaunch() throws {
#if os(macOS) || targetEnvironment(macCatalyst)
        file("Alpha.txt", pane: 1).tap(); app.typeKey("\u{F708}", modifierFlags: [])
        waitForFile("Right/Alpha.txt", exists: true)
        app.buttons["HistoryButton"].tap()
        XCTAssertTrue(app.buttons["HistoryUndo-0"].waitForExistence(timeout: 15))
        app.terminate()
        let id = UUID()
        let journal = root.appendingPathComponent("Transfers/copy-jobs-v1.json")
        var saved = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: journal)) as? [String: Any])
        var jobs = try XCTUnwrap(saved["jobs"] as? [[String: Any]])
        XCTAssertTrue(jobs.contains { $0["state"] as? String == "completed" })
        jobs.append(["id": id.uuidString, "source": root.appendingPathComponent("Left/Alpha.txt").path,
                     "destination": root.appendingPathComponent("Right/Paused.txt").path,
                     "state": "paused", "bytes": 0, "total": 32,
                     "created": Date().timeIntervalSinceReferenceDate, "compact": true, "engine": "file"])
        saved["jobs"] = jobs
        try JSONSerialization.data(withJSONObject: saved).write(to: journal, options: .atomic)
        app.launchArguments = ["--mac-parity-fixtures"]; app.launch()
        app.buttons["TransferQueueButton"].tap()
        XCTAssertTrue(app.buttons["transfer_resume-\(id)"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["transfer_resume-\(id)"].isEnabled)
        app.buttons["HistoryButton"].tap()
        XCTAssertTrue(app.buttons["HistoryUndo-0"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["HistoryTime-0"].exists)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("Right/Paused.txt").path))
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("Left/Alpha.txt")),
                       try Data(contentsOf: root.appendingPathComponent("Right/Alpha.txt")))
#endif
    }

    func testCustomLocationRenameVisibilityAndShortcutOnlyRemoval() throws {
#if os(macOS) || targetEnvironment(macCatalyst)
        let directory = root.appendingPathComponent("Left/Favourite", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        let sentinel = directory.appendingPathComponent("Keep.txt")
        let bytes = Data("Shortcut edits must never alter this file.\n".utf8)
        try bytes.write(to: sentinel)
        app.terminate()
        try JSONSerialization.data(withJSONObject: [["path": directory.path,
            "name": "Own test favourite", "enabled": true, "custom": true]])
            .write(to: root.appendingPathComponent("AcceptanceLocations.json"), options: .atomic)
        app.launchArguments = ["--mac-parity-fixtures"]; app.launch()
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("AcceptanceLocationsImported.txt").path), "Bounded favourite fixture was not imported")
        let shortcut = app.buttons.matching(identifier: "Location-" + (canonical(directory.path) ?? directory.path)).firstMatch
        XCTAssertTrue(shortcut.waitForExistence(timeout: 15))
        app.buttons["LocationSettingsButton"].tap()
        let row = app.cells.matching(identifier: "LocationSetting-" + directory.path).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 15))
        row.staticTexts["Own test favourite"].tap()
        let name = app.textFields.matching(NSPredicate(format: "value == %@", "Own test favourite")).firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 10))
        name.tap(); name.typeKey("a", modifierFlags: .command); name.typeText("Renamed own favourite")
        app.buttons["Save"].tap()
        let renameClosed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            !self.app.buttons["Save"].exists
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [renameClosed], timeout: 10), .completed)
        let toggle = app.switches.matching(identifier: "LocationVisible-" + directory.path).firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 10))
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let hidden = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in !shortcut.exists }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [hidden], timeout: 15), .completed)
        XCTAssertFalse(shortcut.exists)
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(shortcut.waitForExistence(timeout: 10))
        XCTAssertTrue(shortcut.label.contains("Renamed own favourite"))
        app.terminate(); app.launch()
        XCTAssertTrue(shortcut.waitForExistence(timeout: 15))
        XCTAssertTrue(shortcut.label.contains("Renamed own favourite"))
        app.buttons["LocationSettingsButton"].tap()
        XCTAssertTrue(row.waitForExistence(timeout: 15))
        row.staticTexts["Renamed own favourite"].tap()
        app.buttons["Remove shortcut only"].tap()
        let removed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in !shortcut.exists }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [removed], timeout: 15), .completed)
        XCTAssertFalse(shortcut.exists)
        XCTAssertEqual(try Data(contentsOf: sentinel), bytes)
        app.terminate(); app.launch()
        XCTAssertFalse(shortcut.exists)
        XCTAssertEqual(try Data(contentsOf: sentinel), bytes)
#endif
    }

}

#if !os(macOS) && !targetEnvironment(macCatalyst)
final class AppReviewVideoTests: XCTestCase {
    private let app = XCUIApplication()

    override func setUpWithError() throws {
#if os(macOS) || targetEnvironment(macCatalyst)
        throw XCTSkip("iOS review flows are container-specific; run MacDesktopParityTests on Mac Catalyst")
#else
        continueAfterFailure = false
        if name.contains("testMainFolderOnboarding") {
            app.launchArguments = ["--reset-file-access-onboarding"]
        } else if name.contains("testPhysicalFilesFolderAccess") {
            app.launchArguments = ["--app-review-fixtures", "--reset-file-access-onboarding"]
        } else if name.contains("testPhysicalStorageSmoke") {
            app.launchArguments = []
        } else if name.contains("testStaleFolderBookmark") {
            app.launchArguments = ["--stale-folder-bookmark-fixture"]
        } else if name.contains("testPhotoMediaImport") {
#if !targetEnvironment(simulator)
            throw XCTSkip("This reset-based fixture test is simulator-only; physical media tests preserve the user's files")
#endif
            app.launchArguments = ["--app-review-fixtures", "--reset-media-import-fixtures"]
        } else {
            app.launchArguments = ["--app-review-fixtures"]
        }
        app.launch()
        if !name.contains("testMainFolder") && !name.contains("testPhysicalFilesFolderAccess") {
            if app.buttons["StorageSourcesClose"].waitForExistence(timeout: 5) { app.buttons["StorageSourcesClose"].tap() }
            XCTAssertTrue(app.otherElements["TitleToolbar"].waitForExistence(timeout: 15))
        }
#endif
    }

    func testMainFolderHubAndRelaunch() throws {
        XCTAssertTrue(app.descendants(matching: .any)["StorageSources"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.cells["Source-media_photos"].exists)
        app.buttons["StorageSourcesClose"].tap()
        app.terminate(); app.launchArguments = []; app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["StorageSources"].waitForExistence(timeout: 15))
    }

    func testTypicalFileManagementFlowForAppReview() throws {
        // Show that Copy/Move is one compact toggle and both states are reachable.
        let operation = app.buttons["OperationButton"]
        XCTAssertTrue(operation.waitForExistence(timeout: 5))
        operation.tap()
        sleep(1)
        operation.tap()
        sleep(1)

        // Copy a real folder between panes using the same long-press drag users perform.
        let dragMe = app.descendants(matching: .any)["File-1-DragMe"]
        let dropHere = app.descendants(matching: .any)["File-2-DropHere"]
        XCTAssertTrue(dragMe.waitForExistence(timeout: 5))
        XCTAssertTrue(dropHere.waitForExistence(timeout: 5))
        dragMe.press(forDuration: 1.5, thenDragTo: dropHere, withVelocity: .slow, thenHoldForDuration: 1.0)
        sleep(3)
        dropHere.doubleTap()
        sleep(1)
        XCTAssertTrue(app.descendants(matching: .any)["File-2-DragMe"].waitForExistence(timeout: 5))

        // ZIP a folder, then expose the operation history and undo control.
        let source = app.descendants(matching: .any)["File-1-Source"]
        XCTAssertTrue(source.waitForExistence(timeout: 5))
        source.tap()
        app.buttons["ZipButton"].tap()
        sleep(4)
        XCTAssertTrue(app.descendants(matching: .any)["File-1-Source.zip"].waitForExistence(timeout: 5))
        app.buttons["HistoryButton"].tap()
        sleep(2)
        XCTAssertTrue(app.scrollViews["HistoryList"].exists)
        app.buttons["UndoButton"].tap()
        sleep(3)

        // Show the in-app help and the complete language chooser.
        app.buttons["HelpButton"].tap()
        sleep(2)
        app.navigationBars.buttons.firstMatch.tap()
        sleep(1)
        app.buttons["LanguageButton"].tap()
        sleep(3)
        XCTAssertTrue(app.sheets.firstMatch.exists)
    }

    func testPhysicalFilesFolderAccessAndPersistence() throws {
        let chooseFolder = app.cells["Source-choose_another_folder"]
        XCTAssertTrue(chooseFolder.waitForExistence(timeout: 10))
        chooseFolder.tap()
        XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 15))
        let open = app.navigationBars.buttons["Öffnen"].firstMatch
        if !open.waitForExistence(timeout: 3) {
            let browse = app.tabBars.buttons["Durchsuchen"]
            XCTAssertTrue(browse.waitForExistence(timeout: 10))
            browse.tap()
            sleep(2)

            let onMyIPhone = app.staticTexts["Auf meinem iPhone"].firstMatch
            XCTAssertTrue(onMyIPhone.waitForExistence(timeout: 10))
            onMyIPhone.tap()
            sleep(2)
        }

        // Select the app's visible folder inside "On My iPhone" when the picker
        // is currently showing the location root. If already inside it, no row exists.
        let openCommanderFolder = app.cells.containing(.staticText, identifier: "OpenCommander").firstMatch
        if openCommanderFolder.waitForExistence(timeout: 3) {
            openCommanderFolder.tap()
            sleep(2)
        }

        XCTAssertTrue(open.waitForExistence(timeout: 10))
        XCTAssertTrue(open.isEnabled)
        open.tap()

        XCTAssertTrue(app.descendants(matching: .any)["Tree-1-Documents"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.descendants(matching: .any)["Tree-2-Documents"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.descendants(matching: .any)["File-1-Source"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["File-2-Source"].waitForExistence(timeout: 10))

        // Prove that the user-selected Apple Files location is writable, not just visible.
        app.descendants(matching: .any)["File-1-Source"].tap()
        app.buttons["ZipButton"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["File-1-Source.zip"].waitForExistence(timeout: 15))
        app.buttons["HistoryButton"].tap()
        XCTAssertTrue(app.scrollViews["HistoryList"].waitForExistence(timeout: 5))
        app.buttons["UndoButton"].tap()
        XCTAssertFalse(app.descendants(matching: .any)["File-1-Source.zip"].waitForExistence(timeout: 5))

        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "physical-on-my-iphone-both-panes"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        app.terminate()
        app.launchArguments = []
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["Tree-1-Documents"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.descendants(matching: .any)["Tree-2-Documents"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.descendants(matching: .any)["File-1-Source"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["File-2-Source"].waitForExistence(timeout: 10))
    }

    func testStaleFolderBookmarkFallsBackAndCanBeReplaced() throws {
        let recovery = app.alerts.firstMatch
        XCTAssertTrue(recovery.waitForExistence(timeout: 10))
        XCTAssertTrue(recovery.buttons["Choose another folder"].exists)

        XCTAssertTrue(app.descendants(matching: .any)["Tree-1-Documents"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["Tree-2-Documents"].waitForExistence(timeout: 10))
        let leftMessage = app.staticTexts["DirectoryMessage-1"]
        let rightMessage = app.staticTexts["DirectoryMessage-2"]
        if leftMessage.exists { XCTAssertFalse(leftMessage.label.contains("Could not load")) }
        if rightMessage.exists { XCTAssertFalse(rightMessage.label.contains("Could not load")) }

        let fallbackScreenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        fallbackScreenshot.name = "stale-bookmark-fallback"
        fallbackScreenshot.lifetime = .keepAlways
        add(fallbackScreenshot)

        recovery.buttons["Later"].tap()
        app.terminate()
        app.launchArguments = []
        app.launch()
        XCTAssertTrue(app.otherElements["TitleToolbar"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.alerts.firstMatch.waitForExistence(timeout: 2))
        XCTAssertTrue(app.descendants(matching: .any)["Tree-1-Documents"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["Tree-2-Documents"].exists)
    }

    func testMediaFolderAndPhotoPickerEntry() throws {
        app.buttons["OpenFolderButton"].tap()
        let menu = app.descendants(matching: .any)["StorageSources"]
        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        XCTAssertTrue(app.cells["Source-media_folder"].exists)
        XCTAssertTrue(app.cells["Source-import_photos_videos"].exists)
        XCTAssertTrue(app.cells["Source-media_music"].exists)
        XCTAssertTrue(app.cells["Source-local_documents"].exists)
        XCTAssertTrue(app.cells["Source-choose_another_folder"].exists)

        app.cells["Source-media_folder"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["Tree-1-Media"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["Path-1"].value as? String, "/Documents/Media")

        app.buttons["OpenFolderButton"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["StorageSources"].waitForExistence(timeout: 5))
        app.cells["Source-import_photos_videos"].tap()
        XCTAssertTrue(app.buttons["Cancel"].firstMatch.waitForExistence(timeout: 10))

        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "system-photo-video-picker"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.buttons["Cancel"].firstMatch.tap()
        XCTAssertTrue(app.otherElements["TitleToolbar"].waitForExistence(timeout: 10))
    }

    func testPhotoMediaImportAndLargeViewer() throws {
        app.buttons["OpenFolderButton"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["StorageSources"].waitForExistence(timeout: 5))
        app.cells["Source-import_photos_videos"].tap()
        XCTAssertTrue(app.buttons["Cancel"].firstMatch.waitForExistence(timeout: 10))

        // The private system picker doesn't expose its photo grid to the host app's
        // accessibility hierarchy. Activate visible settled coordinates instead.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.16, dy: 0.42)).tap()
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.90, dy: 0.08)).tap()

        XCTAssertEqual(app.textFields["Path-1"].value as? String, "/Documents/Media")
        let importedFiles = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH 'File-1-'")
        )
        XCTAssertTrue(importedFiles.firstMatch.waitForExistence(timeout: 20))
        importedFiles.firstMatch.doubleTap()
        XCTAssertTrue(app.otherElements["ImageViewer"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.images["ImageViewerImage"].exists)

        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "imported-photo-large-viewer"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.buttons["ImageViewerClose"].tap()
    }

    func testPhysicalStorageSmokeDoesNotStartInAnUnreadableFolder() throws {
        let recovery = app.alerts.firstMatch
        if recovery.waitForExistence(timeout: 2), recovery.buttons["Later"].exists {
            recovery.buttons["Later"].tap()
        }
        XCTAssertTrue(app.buttons["OpenFolderButton"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.tables["TreeList-1"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.tables["TreeList-2"].waitForExistence(timeout: 10))
        let leftMessage = app.staticTexts["DirectoryMessage-1"]
        let rightMessage = app.staticTexts["DirectoryMessage-2"]
        if leftMessage.exists { XCTAssertFalse(leftMessage.label.contains("Could not load")) }
        if rightMessage.exists { XCTAssertFalse(rightMessage.label.contains("Could not load")) }

        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "physical-storage-readable"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}

final class ImageViewerTests: XCTestCase {
    private let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["--image-viewer-fixtures"]
        app.launch()
        if app.buttons["StorageSourcesClose"].waitForExistence(timeout: 5) { app.buttons["StorageSourcesClose"].tap() }
        XCTAssertTrue(app.otherElements["TitleToolbar"].waitForExistence(timeout: 15))
        for _ in 0..<3 where app.alerts.buttons["OK"].exists { app.alerts.buttons["OK"].tap() }
    }

    func testFolderAndZipImageGallery() throws {
        let folder = app.descendants(matching: .any)["File-1-ImageViewerQA"]
        XCTAssertTrue(folder.waitForExistence(timeout: 10))
        folder.doubleTap()
        let first = app.descendants(matching: .any)["File-1-01-first.png"]
        XCTAssertTrue(first.waitForExistence(timeout: 10))
        first.tap()
        XCTAssertTrue(app.staticTexts["Selection-1"].label.hasPrefix("1/"))
        app.descendants(matching: .any)["File-1-01-first.png"].doubleTap()

        let page = app.staticTexts["ImageViewerPage"]
        let title = app.staticTexts["ImageViewerTitle"]
        let image = app.images["ImageViewerImage"]
        XCTAssertTrue(page.waitForExistence(timeout: 10))
        XCTAssertEqual(page.label, "1 / 3")
        XCTAssertEqual(title.label, "01-first.png")
        XCTAssertTrue(image.exists)
        attach("folder-first")

        image.swipeLeft()
        XCTAssertTrue(waitForLabel(page, "2 / 3"))
        XCTAssertEqual(title.label, "02-second.png")
        attach("folder-second")
        image.swipeLeft()
        XCTAssertTrue(waitForLabel(page, "3 / 3"))
        XCTAssertTrue(app.staticTexts["ImageViewerError"].waitForExistence(timeout: 5))
        image.swipeLeft()
        XCTAssertEqual(page.label, "3 / 3")
        image.swipeRight()
        XCTAssertTrue(waitForLabel(page, "2 / 3"))

        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(app.buttons["ImageViewerClose"].waitForExistence(timeout: 5))
        XCTAssertTrue(page.isHittable)
        attach("landscape")
        XCUIDevice.shared.orientation = .portrait
        app.buttons["ImageViewerClose"].tap()
        XCTAssertTrue(first.waitForExistence(timeout: 5))

        let zip = app.descendants(matching: .any)["File-1-gallery.zip"]
        XCTAssertTrue(zip.waitForExistence(timeout: 5))
        zip.doubleTap()
        let zippedFirst = app.descendants(matching: .any)["File-1-01-first.png"]
        XCTAssertTrue(zippedFirst.waitForExistence(timeout: 5))
        zippedFirst.doubleTap()
        XCTAssertTrue(waitForLabel(page, "1 / 2"))
        app.images["ImageViewerImage"].swipeLeft()
        XCTAssertTrue(waitForLabel(page, "2 / 2"))
        XCTAssertEqual(title.label, "02-second.png")
        attach("zip-second")
    }

    private func waitForLabel(_ element: XCUIElement, _ label: String) -> Bool {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == %@", label), object: element)
        return XCTWaiter.wait(for: [expectation], timeout: 5) == .completed
    }

    private func attach(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

// Fixtures are copied into this unique directory through devicectl before the
// run. This exercises the shipping Release binary without DEBUG launch hooks.
final class ReleaseFileManagementUITests: XCTestCase {
    private let app = XCUIApplication()
    private let root = "/Documents/OpenCommander-Release-QA-1_3_9-8CF631E2"
    private func openPath(_ path: String, pane: Int) {
        let field = app.textFields["Path-\(pane)"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.press(forDuration: 1.2)
        let selectAllPredicate = NSPredicate(format: "label IN %@", ["Select All", "Alles auswählen", "Tout sélectionner"])
        let selectAll = app.menuItems.matching(selectAllPredicate).firstMatch
        let selectAllButton = app.buttons.matching(selectAllPredicate).firstMatch
        if selectAll.waitForExistence(timeout: 1) { selectAll.tap() }
        else if selectAllButton.waitForExistence(timeout: 1) { selectAllButton.tap() }
        else { field.tap(withNumberOfTaps: 3, numberOfTouches: 1) }
        field.typeText(path + "\n")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", path), object: field)], timeout: 15), .completed)
    }
    private func file(_ name: String, pane: Int) -> XCUIElement {
        app.descendants(matching: .any)["File-\(pane)-\(name)"]
    }
    private func evidence(_ name: String) {
        let screenshot = XCTAttachment(screenshot: app.screenshot()); screenshot.name = name; screenshot.lifetime = .keepAlways; add(screenshot)
        let hierarchy = XCTAttachment(string: app.debugDescription); hierarchy.name = name + "-hierarchy"; hierarchy.lifetime = .keepAlways; add(hierarchy)
    }
    func testIsolatedReleaseCopyMoveZipAndUndo() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = []; app.launch()
        XCTAssertTrue(app.buttons["StorageSourcesClose"].waitForExistence(timeout: 15))
        app.buttons["StorageSourcesClose"].tap()
        openPath(root, pane: 1); openPath(root, pane: 2)
        let operation = app.buttons["OperationButton"]
        if operation.isSelected { operation.tap() }
        XCTAssertFalse(operation.isSelected)

        // A fresh empty destination proves that this drag actually copied data.
        openPath(root + "/DropHere", pane: 2)
        XCTAssertTrue(file("Destination.txt", pane: 2).waitForExistence(timeout: 10))
        XCTAssertFalse(file("DragMe", pane: 2).exists)
        openPath(root, pane: 2)
        file("DragMe", pane: 1).press(forDuration: 1.5, thenDragTo: file("DropHere", pane: 2), withVelocity: .slow, thenHoldForDuration: 1)
        file("DropHere", pane: 2).doubleTap()
        XCTAssertTrue(file("DragMe", pane: 2).waitForExistence(timeout: 20))
        file("DragMe", pane: 2).doubleTap()
        XCTAssertTrue(file("Proof.txt", pane: 2).waitForExistence(timeout: 10))
        XCTAssertTrue(file("DragMe", pane: 1).exists)
        evidence("release-drag-copy")

        // Navigating clears the previous selection; ZIP must contain Source only.
        openPath(root, pane: 1)
        XCTAssertFalse(file("Source.zip", pane: 1).exists)
        file("Source", pane: 1).tap()
        XCTAssertTrue(app.staticTexts["Selection-1"].label.hasPrefix("1/"))
        app.buttons["ZipButton"].tap()
        XCTAssertTrue(file("Source.zip", pane: 1).waitForExistence(timeout: 20))
        file("Source.zip", pane: 1).doubleTap()
        XCTAssertTrue(file("Source", pane: 1).waitForExistence(timeout: 10))
        file("Source", pane: 1).doubleTap()
        XCTAssertTrue(file("Welcome.txt", pane: 1).waitForExistence(timeout: 10))
        evidence("release-folder-zip-opened")
        openPath(root, pane: 1)
        app.buttons["UndoButton"].tap()
        XCTAssertTrue(file("Source.zip", pane: 1).waitForNonExistence(timeout: 15))

        // Move the app-created copy, then restore it and undo the initial copy.
        // This avoids transfer-tool protection attributes on fixture originals.
        openPath(root + "/DropHere", pane: 1); openPath(root, pane: 2)
        operation.tap(); XCTAssertTrue(operation.isSelected)
        file("DragMe", pane: 1).press(forDuration: 1.5, thenDragTo: file("MoveHere", pane: 2), withVelocity: .slow, thenHoldForDuration: 1)
        XCTAssertTrue(file("DragMe", pane: 1).waitForNonExistence(timeout: 20))
        file("MoveHere", pane: 2).doubleTap()
        XCTAssertTrue(file("DragMe", pane: 2).waitForExistence(timeout: 10))
        file("DragMe", pane: 2).doubleTap()
        XCTAssertTrue(file("Proof.txt", pane: 2).waitForExistence(timeout: 10))
        evidence("release-drag-move")
        openPath(root + "/MoveHere", pane: 2)
        app.buttons["UndoButton"].tap()
        XCTAssertTrue(file("DragMe", pane: 1).waitForExistence(timeout: 15))
        // Re-enter to discard UIKit accessibility cells cached after reloadData.
        openPath(root, pane: 2); openPath(root + "/MoveHere", pane: 2)
        XCTAssertTrue(app.staticTexts["Selection-2"].label.hasPrefix("0/0 |"))
        XCTAssertEqual(app.tables["FileList-2"].label, "This folder is empty.")
        evidence("release-move-undo-empty-destination")
        app.buttons["UndoButton"].tap()
        openPath(root, pane: 1); openPath(root + "/DropHere", pane: 1)
        XCTAssertTrue(app.staticTexts["Selection-1"].label.hasPrefix("0/1 |"))
        XCTAssertTrue(file("Destination.txt", pane: 1).exists)
        openPath(root, pane: 1)
        XCTAssertTrue(file("DragMe", pane: 1).waitForExistence(timeout: 10))
        operation.tap(); XCTAssertFalse(operation.isSelected)
        evidence("release-undo-restored-fixtures")
    }
}

final class MediaLibraryUITests: XCTestCase {
    private let app = XCUIApplication()
    override func setUpWithError() throws {
        continueAfterFailure = false
        app.launchArguments = []
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["StorageSources"].waitForExistence(timeout: 15))
    }
    private func evidence(_ name: String) {
        let screenshot = XCTAttachment(screenshot: app.screenshot()); screenshot.name = name; screenshot.lifetime = .keepAlways; add(screenshot)
        let hierarchy = XCTAttachment(string: app.debugDescription); hierarchy.name = name + "-hierarchy"; hierarchy.lifetime = .keepAlways; add(hierarchy)
    }
    private func grantLibraryPermission() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        if springboard.alerts.firstMatch.waitForExistence(timeout: 3) {
            let allow = springboard.alerts.buttons.matching(NSPredicate(format: "label IN %@", ["Allow Full Access", "Vollen Zugriff erlauben", "Vollzugriff erlauben", "Allow", "Erlauben", "OK", "Zugriff auf alle Fotos erlauben"])).firstMatch
            XCTAssertTrue(allow.waitForExistence(timeout: 5), springboard.alerts.debugDescription)
            allow.tap()
        }
    }
    func testSourcesAndPhotoSwipe() throws {
        for key in ["media_photos", "media_videos", "media_music", "choose_another_folder", "local_documents"] {
            XCTAssertTrue(app.cells["Source-" + key].exists)
        }
        evidence("sources")
        app.cells["Source-media_photos"].tap()
        grantLibraryPermission()
        XCTAssertTrue(app.descendants(matching: .any)["PhotoLibrary"].waitForExistence(timeout: 10))
        let first = app.cells["PhotoAsset-0"]
        guard first.waitForExistence(timeout: 20) else {
            evidence("photos-empty-or-denied"); throw XCTSkip("No permitted photos available on physical device")
        }
        let hasSecond = app.cells["PhotoAsset-1"].exists
        first.tap()
        XCTAssertTrue(app.otherElements["LibraryMediaViewer"].waitForExistence(timeout: 10))
        let image = app.images["LibraryMediaImage"]
        XCTAssertTrue(image.waitForExistence(timeout: 20))
        XCTAssertTrue(NSPredicate(format: "value == 'loaded'").evaluate(with: image) || XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == 'loaded'"), object: image)], timeout: 30) == .completed)
        let before = app.staticTexts["LibraryMediaCounter"].label
        evidence("photo-fullscreen")
        if hasSecond {
            app.otherElements["LibraryMediaViewer"].swipeLeft()
            XCTAssertTrue(app.staticTexts["LibraryMediaCounter"].label.hasPrefix("2 /"))
            XCTAssertTrue(NSPredicate(format: "value == 'loaded'").evaluate(with: image) || XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == 'loaded'"), object: image)], timeout: 30) == .completed)
            app.otherElements["LibraryMediaViewer"].swipeRight()
            XCTAssertEqual(app.staticTexts["LibraryMediaCounter"].label, before)
            XCUIDevice.shared.orientation = .landscapeLeft
            evidence("photo-landscape")
        }
        app.buttons["LibraryMediaClose"].tap()
        XCTAssertTrue(app.otherElements["LibraryMediaViewer"].waitForNonExistence(timeout: 15))
        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(app.buttons["PhotoSelect"].waitForExistence(timeout: 10))
        app.buttons["PhotoSelect"].tap()
        first.tap()
        XCTAssertTrue(app.buttons["PhotoExport"].isEnabled)
        app.buttons["PhotoExport"].tap()
        let save = app.navigationBars.buttons.matching(NSPredicate(format: "label IN %@", ["Save", "Sichern", "Export", "Exportieren", "Move", "Bewegen"])).firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 40), app.debugDescription)
        evidence("photo-export-destination")
        // Interrupt before saving: no personal files or library originals are modified.
        app.terminate(); app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["StorageSources"].waitForExistence(timeout: 15))
        app.cells["Source-media_photos"].tap()
        XCTAssertTrue(app.cells["PhotoAsset-0"].waitForExistence(timeout: 20))
    }
    func testPhotoExportToLocalFiles() throws {
        app.cells["Source-media_photos"].tap(); grantLibraryPermission()
        let first = app.cells["PhotoAsset-0"]
        guard first.waitForExistence(timeout: 20) else { throw XCTSkip("No permitted photos available") }
        app.buttons["PhotoSelect"].tap(); first.tap(); app.buttons["PhotoExport"].tap()
        let nameField = app.textFields["DOCPicker.filenameTextField"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 40))
        let fixtureName = "OpenCommander-Export-QA-" + UUID().uuidString
        nameField.tap()
        if let value = nameField.value as? String { nameField.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: value.count)) }
        nameField.typeText(fixtureName)
        let save = app.navigationBars.buttons.matching(NSPredicate(format: "label IN %@", ["Save", "Sichern"])).firstMatch
        XCTAssertTrue(save.exists); save.tap()
        XCTAssertTrue(nameField.waitForNonExistence(timeout: 20))
        evidence("photo-export-saved")
        app.navigationBars.buttons["BackButton"].tap()
        app.cells["Source-local_documents"].tap()
        let exported = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "File-1-" + fixtureName)).firstMatch
        XCTAssertTrue(exported.waitForExistence(timeout: 15), app.debugDescription)
        exported.doubleTap()
        XCTAssertTrue(app.otherElements["ImageViewer"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.images["ImageViewerImage"].exists)
        XCTAssertTrue(app.activityIndicators["ImageViewerLoading"].waitForNonExistence(timeout: 20))
        XCTAssertFalse(app.staticTexts["ImageViewerError"].exists)
        evidence("exported-photo-opened-as-file")
        app.buttons["ImageViewerClose"].tap()
    }

    func testVideoLibrary() throws {
        app.cells["Source-media_videos"].tap(); grantLibraryPermission()
        let first = app.cells["PhotoAsset-0"]
        guard first.waitForExistence(timeout: 15) else { evidence("videos-empty"); throw XCTSkip("No permitted videos available") }
        first.tap()
        XCTAssertTrue(app.otherElements["LibraryMediaViewer"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["LibraryVideoPlayer"].waitForExistence(timeout: 30))
        let counter = app.staticTexts["LibraryMediaCounter"]
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in Double(counter.value as? String ?? "") != nil }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 10), .completed)
        let initialTime = Double(counter.value as? String ?? "0") ?? 0
        app.descendants(matching: .any)["LibraryVideoPlayer"].tap()
        let play = app.buttons.matching(NSPredicate(format: "label IN %@", ["Play", "Wiedergabe", "Abspielen"])).firstMatch
        if play.waitForExistence(timeout: 2) { play.tap() }
        let progressed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            (Double(counter.value as? String ?? "0") ?? 0) > initialTime + 0.5
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [progressed], timeout: 20), .completed)
        evidence("video-player-playing")
        app.buttons["LibraryMediaClose"].tap()
    }
    func testMusicLibraryAndPlayback() throws {
        app.cells["Source-media_music"].tap(); grantLibraryPermission()
        XCTAssertTrue(app.descendants(matching: .any)["MusicLibrary"].waitForExistence(timeout: 10))
        let first = app.cells["MusicSong-0"]
        guard first.waitForExistence(timeout: 15) else {
            XCTAssertFalse(app.buttons["MusicPlayPause"].isEnabled)
            evidence("music-empty-or-denied"); throw XCTSkip("No playable song in this device library")
        }
        first.tap()
        let now = app.staticTexts["MusicNowPlaying"]
        XCTAssertTrue(now.waitForExistence(timeout: 20))
        XCTAssertTrue(app.buttons["MusicStop"].isEnabled)
        evidence("music-playing")
        app.buttons["MusicPlayPause"].tap()
        app.buttons["MusicPlayPause"].tap()
        app.buttons["MusicStop"].tap()
        evidence("music-stopped")
    }
}
#endif
