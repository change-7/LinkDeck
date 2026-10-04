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

    func testApprovalSound_usesImportedSoundForMacAndPhoneAndPersistsBuiltInSelection() throws {
        let testRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexApprovalSoundTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: testRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: testRoot) }

        let preferencesDomain = "CodexApprovalSoundTests.\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: preferencesDomain))
        defer { preferences.removePersistentDomain(forName: preferencesDomain) }

        let sourceURL = testRoot.appendingPathComponent("Approval.wav")
        let sourceData = Data([0x52, 0x49, 0x46, 0x46, 0x07, 0x06])
        try sourceData.write(to: sourceURL)
        let storageDirectory = testRoot.appendingPathComponent("stored", isDirectory: true)
        let library = CodexCompletionSoundLibrary(preferences: preferences, storageDirectory: storageDirectory)
        let selectedCompletionSoundID = library.selectedSoundID

        XCTAssertFalse(library.approvalSoundConfigured)
        XCTAssertTrue(library.remoteApprovalSelection.useBuiltIn)
        XCTAssertEqual(library.approvalSoundOutputTarget, .phone)
        XCTAssertEqual(library.remoteApprovalSelection.outputTarget, .phone)
        XCTAssertEqual(library.approvalVolumePercent, 100)

        let approvalSoundID = try library.importSound(from: sourceURL, selectForCompletion: false)
        XCTAssertEqual(library.selectedSoundID, selectedCompletionSoundID)
        library.selectApprovalSound(approvalSoundID)

        XCTAssertTrue(library.approvalSoundConfigured)
        XCTAssertEqual(library.remoteApprovalSelection.title, "Approval")
        XCTAssertEqual(library.remoteApprovalSelection.mimeType, "audio/wav")
        XCTAssertEqual(library.remoteApprovalSelection.outputTarget, .phone)
        XCTAssertEqual(Data(base64Encoded: try XCTUnwrap(library.remoteApprovalSelection.data)), sourceData)
        XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(library.previewURL(for: approvalSoundID)).path))

        library.setVolumePercent(62)
        library.setApprovalVolumePercent(35)
        XCTAssertEqual(library.remoteApprovalSelection.volumePercent, 35)
        XCTAssertEqual(library.remoteSelection.volumePercent, 62)

        library.setApprovalSoundOutputTarget(.mac)
        XCTAssertFalse(library.remoteApprovalSelection.outputTarget.playsOnPhone)
        XCTAssertTrue(library.remoteApprovalSelection.outputTarget.playsOnMac)
        XCTAssertEqual(library.remoteApprovalSelection.outputTarget, .mac)

        library.selectApprovalSound(CodexCompletionSoundLibrary.builtInID)
        XCTAssertTrue(library.remoteApprovalSelection.useBuiltIn)
        XCTAssertTrue(library.remoteApprovalSelection.configured)
        XCTAssertNil(library.remoteApprovalSelection.data)

        let reloadedLibrary = CodexCompletionSoundLibrary(preferences: preferences, storageDirectory: storageDirectory)
        XCTAssertEqual(reloadedLibrary.selectedApprovalSoundID, CodexCompletionSoundLibrary.builtInID)
        XCTAssertTrue(reloadedLibrary.approvalSoundConfigured)
        XCTAssertEqual(reloadedLibrary.approvalSoundOutputTarget, .mac)
        XCTAssertEqual(reloadedLibrary.remoteApprovalSelection.outputTarget, .mac)
        XCTAssertEqual(reloadedLibrary.approvalVolumePercent, 35)
        XCTAssertEqual(reloadedLibrary.remoteApprovalSelection.volumePercent, 35)
        reloadedLibrary.setApprovalVolumePercent(-1)
        XCTAssertEqual(reloadedLibrary.remoteApprovalSelection.volumePercent, 0)
        reloadedLibrary.setApprovalVolumePercent(101)
        XCTAssertEqual(reloadedLibrary.remoteApprovalSelection.volumePercent, 100)

        reloadedLibrary.setApprovalSoundOutputTarget(.phone)
        XCTAssertTrue(reloadedLibrary.remoteApprovalSelection.outputTarget.playsOnPhone)
        XCTAssertFalse(reloadedLibrary.remoteApprovalSelection.outputTarget.playsOnMac)
    }

    func testNotificationSoundOutputTarget_updatesBothSoundsAndPersists() throws {
        let domain = "NotificationSoundRouting.\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: domain))
        defer { preferences.removePersistentDomain(forName: domain) }
        let library = CodexCompletionSoundLibrary(preferences: preferences)
        library.setOutputTarget(.phone)
        library.setApprovalSoundOutputTarget(.mac)
        library.setNotificationSoundOutputTarget(.phone)
        XCTAssertEqual(library.remoteSelection.outputTarget, .phone)
        XCTAssertEqual(library.remoteApprovalSelection.outputTarget, .phone)
        library.setNotificationSoundOutputTarget(.mac)
        XCTAssertEqual(library.remoteSelection.outputTarget, .mac)
        XCTAssertEqual(library.remoteApprovalSelection.outputTarget, .mac)
        let reloaded = CodexCompletionSoundLibrary(preferences: preferences)
        XCTAssertEqual(reloaded.outputTarget, .mac)
        XCTAssertEqual(reloaded.approvalSoundOutputTarget, .mac)
    }

    func testApprovalSound_migratesBothDevicePreferenceToPhone() throws {
        let domain = "ApprovalSoundMigration.\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: domain))
        defer { preferences.removePersistentDomain(forName: domain) }
        preferences.set("both", forKey: "linkdeck.codex-approval-sound-output-target")
        let library = CodexCompletionSoundLibrary(preferences: preferences)
        XCTAssertEqual(library.approvalSoundOutputTarget, .phone)
        XCTAssertEqual(preferences.string(forKey: "linkdeck.codex-approval-sound-output-target"), "phone")
    }
}
