import AVFoundation
import Foundation
import Observation

enum CodexCompletionSoundOutputTarget: String, CaseIterable, Codable, Identifiable, Sendable {
    case phone
    case mac

    var id: Self { self }

    var title: String {
        switch self {
        case .phone: "휴대폰"
        case .mac: "Mac"
        }
    }
}

struct CodexCompletionSoundOption: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let detail: String
}

enum CodexCompletionSoundImportError: LocalizedError {
    case unsupportedFormat
    case emptyFile
    case fileTooLarge

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat:
            "WAV, MP3, M4A, OGG 파일만 추가할 수 있습니다."
        case .emptyFile:
            "비어 있는 음성 파일은 추가할 수 없습니다."
        case .fileTooLarge:
            "음성 파일은 10MB 이하만 추가할 수 있습니다."
        }
    }
}

@Observable
final class CodexCompletionSoundLibrary {
    static let builtInID = "built-in"
    static let bundledVoiceID = "completion-voice"

    private struct ImportedSound: Codable, Equatable, Identifiable, Sendable {
        let id: String
        let title: String
        let fileName: String
        let mimeType: String
    }

    private let preferences: UserDefaults
    private let storageDirectory: URL
    private let recordsKey = "linkdeck.codex-completion-sounds"
    private let selectedSoundKey = "linkdeck.codex-completion-sound"
    private let outputTargetKey = "linkdeck.codex-completion-sound-output-target"
    private let volumePercentKey = "linkdeck.codex-completion-sound-volume-percent"
    private var importedSounds: [ImportedSound]
    @ObservationIgnored private var completionPlayer: AVAudioPlayer?

    private(set) var selectedSoundID: String
    private(set) var outputTarget: CodexCompletionSoundOutputTarget
    private(set) var volumePercent: Int
    private(set) var remoteSelection: CodexRemoteCompletionSound

    init(
        preferences: UserDefaults = UserDefaults(suiteName: "com.pdg.chatgpt-micro-launchpad.native") ?? .standard,
        storageDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/LinkDeck/CompletionSounds", isDirectory: true)
    ) {
        self.preferences = preferences
        self.storageDirectory = storageDirectory
        let records = preferences.data(forKey: recordsKey)
            .flatMap { try? JSONDecoder().decode([ImportedSound].self, from: $0) } ?? []
        let availableImportedSounds = records.filter {
            FileManager.default.fileExists(atPath: storageDirectory.appendingPathComponent($0.fileName).path)
        }
        importedSounds = availableImportedSounds

        let bundledVoiceExists = Self.bundledVoiceURL != nil
        let availableIDs = Set(availableImportedSounds.map(\.id) + [Self.builtInID] + (bundledVoiceExists ? [Self.bundledVoiceID] : []))
        let savedID = preferences.string(forKey: selectedSoundKey)
        selectedSoundID = savedID.flatMap { availableIDs.contains($0) ? $0 : nil }
            ?? (bundledVoiceExists ? Self.bundledVoiceID : Self.builtInID)
        outputTarget = CodexCompletionSoundOutputTarget(
            rawValue: preferences.string(forKey: outputTargetKey) ?? ""
        ) ?? .phone
        volumePercent = min(max(preferences.object(forKey: volumePercentKey) as? Int ?? 100, 0), 100)
        remoteSelection = .builtIn
        remoteSelection = makeRemoteSelection()
    }

    var options: [CodexCompletionSoundOption] {
        var result = [
            CodexCompletionSoundOption(
                id: Self.builtInID,
                title: "기존 완료음",
                detail: "기본 알림음"
            )
        ]
        if Self.bundledVoiceURL != nil {
            result.append(
                CodexCompletionSoundOption(
                    id: Self.bundledVoiceID,
                    title: "작업완료! (음성)",
                    detail: "추가된 WAV 음성"
                )
            )
        }
        result.append(contentsOf: importedSounds.map {
            CodexCompletionSoundOption(
                id: $0.id,
                title: $0.title,
                detail: "추가한 파일 · \(URL(fileURLWithPath: $0.fileName).pathExtension.uppercased())"
            )
        })
        return result
    }

    func select(_ id: String) {
        guard options.contains(where: { $0.id == id }) else { return }
        selectedSoundID = id
        preferences.set(id, forKey: selectedSoundKey)
        remoteSelection = makeRemoteSelection()
    }

    func setOutputTarget(_ target: CodexCompletionSoundOutputTarget) {
        guard outputTarget != target else { return }
        outputTarget = target
        preferences.set(target.rawValue, forKey: outputTargetKey)
        if target == .phone {
            completionPlayer?.stop()
            completionPlayer = nil
        }
        remoteSelection = makeRemoteSelection()
    }

    func setVolumePercent(_ value: Int) {
        let nextValue = min(max(value, 0), 100)
        guard volumePercent != nextValue else { return }
        volumePercent = nextValue
        preferences.set(nextValue, forKey: volumePercentKey)
        completionPlayer?.volume = Float(nextValue) / 100
        remoteSelection = makeRemoteSelection()
    }

    func playSelectedSoundOnMac() {
        guard outputTarget == .mac,
              let url = previewURL(for: selectedSoundID),
              let player = try? AVAudioPlayer(contentsOf: url) else { return }
        completionPlayer?.stop()
        completionPlayer = player
        player.volume = Float(volumePercent) / 100
        player.play()
    }

    func previewURL(for id: String) -> URL? {
        if id == Self.builtInID {
            return Bundle.module.url(forResource: "codex_completion_chime", withExtension: "mp3")
        }
        if id == Self.bundledVoiceID { return Self.bundledVoiceURL }
        guard let imported = importedSounds.first(where: { $0.id == id }) else { return nil }
        return storageDirectory.appendingPathComponent(imported.fileName)
    }

    func importSound(from sourceURL: URL) throws {
        let fileExtension = sourceURL.pathExtension.lowercased()
        let mimeType: String
        switch fileExtension {
        case "wav": mimeType = "audio/wav"
        case "mp3": mimeType = "audio/mpeg"
        case "m4a": mimeType = "audio/mp4"
        case "ogg": mimeType = "audio/ogg"
        default: throw CodexCompletionSoundImportError.unsupportedFormat
        }

        let hasScopedAccess = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if hasScopedAccess { sourceURL.stopAccessingSecurityScopedResource() }
        }
        let data = try Data(contentsOf: sourceURL)
        guard !data.isEmpty else { throw CodexCompletionSoundImportError.emptyFile }
        guard data.count <= 10 * 1_024 * 1_024 else { throw CodexCompletionSoundImportError.fileTooLarge }

        try FileManager.default.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
        let id = UUID().uuidString.lowercased()
        let fileName = "\(id).\(fileExtension)"
        try data.write(to: storageDirectory.appendingPathComponent(fileName), options: .atomic)
        importedSounds.append(ImportedSound(
            id: id,
            title: sourceURL.deletingPathExtension().lastPathComponent,
            fileName: fileName,
            mimeType: mimeType
        ))
        if let encoded = try? JSONEncoder().encode(importedSounds) {
            preferences.set(encoded, forKey: recordsKey)
        }
        select(id)
    }

    private func makeRemoteSelection() -> CodexRemoteCompletionSound {
        if outputTarget == .mac {
            return CodexRemoteCompletionSound(
                id: selectedSoundID,
                outputTarget: .mac,
                volumePercent: volumePercent
            )
        }
        if selectedSoundID == Self.builtInID {
            return CodexRemoteCompletionSound(id: selectedSoundID, volumePercent: volumePercent)
        }

        let fileURL: URL
        let fileName: String
        let mimeType: String
        if selectedSoundID == Self.bundledVoiceID, let bundledURL = Self.bundledVoiceURL {
            fileURL = bundledURL
            fileName = bundledURL.lastPathComponent
            mimeType = "audio/wav"
        } else if let imported = importedSounds.first(where: { $0.id == selectedSoundID }) {
            fileURL = storageDirectory.appendingPathComponent(imported.fileName)
            fileName = imported.fileName
            mimeType = imported.mimeType
        } else {
            return CodexRemoteCompletionSound(id: Self.builtInID, volumePercent: volumePercent)
        }

        guard let data = try? Data(contentsOf: fileURL), data.count <= 10 * 1_024 * 1_024 else {
            return CodexRemoteCompletionSound(id: Self.builtInID, volumePercent: volumePercent)
        }
        return CodexRemoteCompletionSound(
            id: selectedSoundID,
            fileName: fileName,
            mimeType: mimeType,
            data: data.base64EncodedString(),
            outputTarget: .phone,
            volumePercent: volumePercent
        )
    }

    private static var bundledVoiceURL: URL? {
        Bundle.module.url(forResource: "codex_completion_voice", withExtension: "wav")
    }
}
