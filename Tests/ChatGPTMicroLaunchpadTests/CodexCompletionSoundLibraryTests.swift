import Foundation
import XCTest
@testable import ChatGPTMicroLaunchpad

final class CodexCompletionSoundLibraryTests: XCTestCase {
    func testImportSound_whenWavIsAdded_selectsAndPreparesItForPhoneSync() throws {
        let testRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexCompletionSoundLibraryTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: testRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: testRoot) }

        let preferencesDomain = "CodexCompletionSoundLibraryTests.\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: preferencesDomain))
        defer { preferences.removePersistentDomain(forName: preferencesDomain) }

        let sourceURL = testRoot.appendingPathComponent("Cheer.wav")
        let sourceData = Data([0x52, 0x49, 0x46, 0x46, 0x01, 0x02, 0x03])
        try sourceData.write(to: sourceURL)
        let library = CodexCompletionSoundLibrary(
            preferences: preferences,
            storageDirectory: testRoot.appendingPathComponent("stored", isDirectory: true)
        )

        XCTAssertNotNil(library.previewURL(for: CodexCompletionSoundLibrary.builtInID))
        XCTAssertNotNil(library.previewURL(for: CodexCompletionSoundLibrary.bundledVoiceID))
        XCTAssertEqual(library.outputTarget, .phone)
        XCTAssertEqual(library.volumePercent, 100)

        try library.importSound(from: sourceURL)

        XCTAssertEqual(library.options.last?.title, "Cheer")
        XCTAssertEqual(library.options.last?.id, library.selectedSoundID)
        XCTAssertEqual(library.remoteSelection.mimeType, "audio/wav")
        XCTAssertEqual(library.remoteSelection.outputTarget, .phone)
        XCTAssertEqual(Data(base64Encoded: try XCTUnwrap(library.remoteSelection.data)), sourceData)
        library.setVolumePercent(42)
        XCTAssertEqual(library.remoteSelection.volumePercent, 42)
        let importedPreviewURL = try XCTUnwrap(library.previewURL(for: library.selectedSoundID))
        XCTAssertTrue(FileManager.default.fileExists(atPath: importedPreviewURL.path))
        XCTAssertEqual(importedPreviewURL.pathExtension, "wav")

        library.setOutputTarget(.mac)
        XCTAssertEqual(library.remoteSelection.outputTarget, .mac)
        XCTAssertEqual(library.remoteSelection.volumePercent, 42)
        XCTAssertTrue(library.remoteSelection.useBuiltIn)
        XCTAssertNil(library.remoteSelection.data)
        let reloadedLibrary = CodexCompletionSoundLibrary(
            preferences: preferences,
            storageDirectory: testRoot.appendingPathComponent("stored", isDirectory: true)
        )
        XCTAssertEqual(reloadedLibrary.outputTarget, .mac)
        XCTAssertEqual(reloadedLibrary.volumePercent, 42)
        library.setOutputTarget(.phone)
        XCTAssertEqual(library.remoteSelection.outputTarget, .phone)
        XCTAssertEqual(library.remoteSelection.volumePercent, 42)
        XCTAssertEqual(Data(base64Encoded: try XCTUnwrap(library.remoteSelection.data)), sourceData)
    }
}
