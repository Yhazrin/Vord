import AppKit
import XCTest
@testable import Vord

final class SelectionIntegrationTests: XCTestCase {
    func testSelectionNormalizesWhitespaceAndURLRoundTrips() throws {
        let request = try ExternalCaptureRequest(text: "  look \n after  ", source: "https://example.com/article?q=private#section")
        XCTAssertEqual(request.text, "look after")
        XCTAssertEqual(request.source, "https://example.com/article")
        XCTAssertEqual(try ExternalCaptureRequest(url: request.url), request)
        let contraction = try ExternalCaptureRequest(text: "can't")
        XCTAssertEqual(try ExternalCaptureRequest(url: contraction.url).text, "can't")
    }
    func testSelectionRejectsParagraphsScriptsAndUnrelatedURLActions() {
        for text in ["", "中文", "$(touch /tmp/file)", "one two three four five six seven eight nine", String(repeating: "a", count: 121)] {
            XCTAssertThrowsError(try ExternalCaptureRequest(text: text))
        }
        for url in ["vord://delete?text=cat", "https://capture?text=cat", "vord://capture?text=cat&text=dog", "vord://capture?text=cat&command=delete", "vord://capture/path?text=cat"] {
            XCTAssertThrowsError(try ExternalCaptureRequest(url: URL(string: url)!))
        }
        XCTAssertNil(try? ExternalCaptureRequest(text: "cat", source: "file:///etc/passwd").source)
    }
    @MainActor
    func testServiceCanReceiveBeforeWindowSetupWithoutLosingSelection() throws {
        let service = SelectionServiceDelegate()
        let request = try ExternalCaptureRequest(text: "plight")
        service.receive(request)
        var received: [ExternalCaptureRequest] = []
        service.configure { received.append($0) }
        XCTAssertEqual(received, [request])
        service.receive(try ExternalCaptureRequest(text: "reluctant"))
        XCTAssertEqual(received.map { $0.text }, ["plight", "reluctant"])
    }
    @MainActor
    func testServiceUsesOnlyItsSelectionPasteboardAndReportsBadInput() throws {
        let service = SelectionServiceDelegate()
        var received: [ExternalCaptureRequest] = []
        service.configure { received.append($0) }
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        board.setString("plight", forType: .string)
        var error: NSString?
        service.addSelectedWord(board, userData: nil, error: &error)
        XCTAssertNil(error); XCTAssertEqual(received.first?.text, "plight")
        board.clearContents(); board.setString("a whole paragraph with more than eight selected words here", forType: .string)
        service.addSelectedWord(board, userData: nil, error: &error)
        XCTAssertNotNil(error); XCTAssertEqual(received.count, 1)
    }
    @MainActor
    func testBrowserSetupInstallsAnExactOriginAndPackagedExtension() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let extensionFolder = try BrowserIntegrationSetup.install(home: folder)
        XCTAssertTrue(FileManager.default.fileExists(atPath: extensionFolder.appendingPathComponent("background.js").path))
        for browser in BrowserIntegrationTarget.allCases {
            _ = try BrowserIntegrationSetup.install(home: folder, browser: browser)
            let url = folder.appendingPathComponent("Library/Application Support/" + browser.profile + "/NativeMessagingHosts/app.vord.selection.json")
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
            XCTAssertEqual(json["allowed_origins"] as? [String], [BrowserIntegrationIdentity.origin])
            XCTAssertEqual(json["type"] as? String, "stdio")
            XCTAssertTrue(FileManager.default.isExecutableFile(atPath: try XCTUnwrap(json["path"] as? String)))
        }
        let manifest = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: extensionFolder.appendingPathComponent("manifest.json"))) as? [String: Any])
        XCTAssertEqual(Set(manifest["permissions"] as? [String] ?? []), Set(["contextMenus", "nativeMessaging", "storage"]))
        XCTAssertNil(manifest["host_permissions"])
    }
    func testInAppSelectionPrefersOneWordAndDoesNotUseASentenceAsTheHeadword() {
        XCTAssertEqual(InAppSelection.capture(from: "  Reluctant, "), .word("Reluctant"))
        XCTAssertEqual(InAppSelection.capture(from: "look after"), .word("look after"))
        XCTAssertEqual(InAppSelection.capture(from: "It is a cat."), .word("cat"))
        guard case .choose(let words) = InAppSelection.capture(from: "she seemed reluctant to answer the question today.") else {
            return XCTFail("A sentence should offer words instead of one headword")
        }
        XCTAssertTrue(words.contains { $0.lowercased() == "reluctant" })
        XCTAssertFalse(words.contains { $0.lowercased() == "the" || $0.lowercased() == "to" })
        XCTAssertNotEqual(words.joined(separator: " "), "she seemed reluctant to answer the question today")
        XCTAssertNil(InAppSelection.capture(from: "中文句子"))
        XCTAssertNil(InAppSelection.capture(from: "   "))
    }
    @MainActor
    func testSentenceChoicesStayOutOfTheQuickAddField() async throws {
        let repo = SQLiteVocabularyRepository(database: try AppDatabase(path: ":memory:"), onChange: {})
        let translation = TranslationService(selectedID: "local")
        translation.register(LocalDictionaryProvider())
        let model = QuickAddModel(repository: repo, translation: translation)
        model.presentWordChoices(["seemed", "reluctant", "answer"])
        XCTAssertEqual(model.text, "")
        XCTAssertTrue(model.selectionPrompt?.contains("reluctant") == true)
        let saved = await model.submit()
        XCTAssertFalse(saved)
        let entries = try await repo.activeEntries()
        XCTAssertTrue(entries.isEmpty)
    }
    @MainActor
    func testExternalSelectionPrefillsQuickAddAndKeepsSourceOnSave() async throws {
        let repo = SQLiteVocabularyRepository(database: try AppDatabase(path: ":memory:"), onChange: {})
        let translation = TranslationService(selectedID: "local")
        translation.register(LocalDictionaryProvider())
        let model = QuickAddModel(repository: repo, translation: translation)
        model.prepare(selection: try ExternalCaptureRequest(text: "plight", source: "https://example.com/article"))
        XCTAssertEqual(model.text, "plight")
        let before = try await repo.activeEntries()
        XCTAssertTrue(before.isEmpty)
        let success = await model.submit()
        XCTAssertTrue(success)
        let entries = try await repo.activeEntries()
        let word = try XCTUnwrap(entries.first)
        XCTAssertEqual(word.english, "plight")
        XCTAssertTrue(word.chinese.contains("困境"))
        XCTAssertNotNil(word.englishDefinition)
        XCTAssertEqual(word.source, "https://example.com/article")
    }
}
