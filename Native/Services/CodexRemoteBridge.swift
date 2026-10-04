import Foundation
import Network
import Observation

private func smartphonePagesForRemote(_ pages: [SmartphonePage]) -> [SmartphonePage] {
    pages.map { page in
        var sanitizedPage = page
        sanitizedPage.buttons = page.buttons.map { button in
            var sanitizedButton = button
            sanitizedButton.customIconData = nil
            if sanitizedButton.action.kind == .clipboardText {
                sanitizedButton.action.value = ""
            }
            if sanitizedButton.longPressAction.kind == .clipboardText {
                sanitizedButton.longPressAction.value = ""
            }
            sanitizedButton.folderShortcuts = button.folderShortcuts.map { shortcut in
                var sanitizedShortcut = shortcut
                sanitizedShortcut.customIconData = nil
                if sanitizedShortcut.action.kind == .clipboardText {
                    sanitizedShortcut.action.value = ""
                }
                if sanitizedShortcut.longPressAction.kind == .clipboardText {
                    sanitizedShortcut.longPressAction.value = ""
                }
                return sanitizedShortcut
            }
            return sanitizedButton
        }
        return sanitizedPage
    }
}

struct CodexRemoteState: Codable, Equatable, Sendable {
    let type: String
    let protocolVersion: Int
    let macConnected: Bool
    let codexConnected: Bool
    let activity: CodexActivity
    let message: String
    let usedPercent: Int?
    let remainingPercent: Int?
    let resetsAt: Date?
    let fiveHourUsedPercent: Int?
    let fiveHourRemainingPercent: Int?
    let fiveHourResetsAt: Date?
    let smartphonePages: [SmartphonePage]
    /// Optional for wire compatibility with older bridge clients and cached states.
    let smartphoneIconAssets: [String: SmartphoneIconAsset]?
    let approval: CodexRemoteApproval?
    let completionEventID: Int
    let activeSessionCount: Int
    let completionSoundVolumePercent: Int?
    let approvalSoundVolumePercent: Int?
    /// Optional so older cached/recorded bridge states remain decodable.
    let codexPhoneTheme: CodexPhoneTheme?
    let macSleepStatus: MacSleepStatus?

    init(
        macConnected: Bool,
        codexConnected: Bool,
        activity: CodexActivity,
        message: String,
        weeklyUsage: CodexWeeklyUsage?,
        fiveHourUsage: CodexFiveHourUsage?,
        smartphonePages: [SmartphonePage] = SmartphoneDefaults.pages(),
        smartphoneIconAssets: [String: SmartphoneIconAsset] = [:],
        approval: CodexRemoteApproval? = nil,
        completionEventID: Int = 0,
        activeSessionCount: Int = 0,
        completionSoundVolumePercent: Int = 100,
        approvalSoundVolumePercent: Int = 100,
        codexPhoneTheme: CodexPhoneTheme = .classic,
        macSleepStatus: MacSleepStatus? = nil
    ) {
        let used = weeklyUsage.map { min(max($0.usedPercent, 0), 100) }
        let fiveHourUsed = fiveHourUsage.map { min(max($0.usedPercent, 0), 100) }
        self.type = "state"
        self.protocolVersion = 2
        self.macConnected = macConnected
        self.codexConnected = codexConnected
        self.activity = activity
        self.message = message
        self.usedPercent = used
        self.remainingPercent = used.map { 100 - $0 }
        self.resetsAt = weeklyUsage?.resetsAt
        self.fiveHourUsedPercent = fiveHourUsed
        self.fiveHourRemainingPercent = fiveHourUsed.map { 100 - $0 }
        self.fiveHourResetsAt = fiveHourUsage?.resetsAt
        self.smartphonePages = smartphonePagesForRemote(smartphonePages)
        self.smartphoneIconAssets = smartphoneIconAssets
        self.approval = approval
        self.completionEventID = completionEventID
        self.activeSessionCount = activeSessionCount
        self.completionSoundVolumePercent = min(max(completionSoundVolumePercent, 0), 100)
        self.approvalSoundVolumePercent = min(max(approvalSoundVolumePercent, 0), 100)
        self.codexPhoneTheme = codexPhoneTheme
        self.macSleepStatus = macSleepStatus
    }
}

/// A small, transport-safe icon asset keyed by SmartphoneButton.id.
/// `data` is base64-encoded PNG data so the newline-delimited JSON bridge stays self-contained.
struct SmartphoneIconAsset: Codable, Equatable, Sendable {
    let kind: String
    let mimeType: String
    let data: String

    init(kind: String = "app", mimeType: String = "image/png", data: String) {
        self.kind = kind
        self.mimeType = mimeType
        self.data = data
    }
}

struct CodexRemoteIconAssets: Codable, Equatable, Sendable {
    let type: String
    let protocolVersion: Int
    let assets: [String: SmartphoneIconAsset]

    init(assets: [String: SmartphoneIconAsset]) {
        self.type = "smartphoneIconAssets"
        self.protocolVersion = 1
        self.assets = assets
    }
}

struct CodexRemoteCompletionSound: Codable, Equatable, Sendable {
    let type: String
    let protocolVersion: Int
    let id: String
    let fileName: String?
    let mimeType: String?
    let data: String?
    let useBuiltIn: Bool
    let outputTarget: CodexCompletionSoundOutputTarget
    let volumePercent: Int

    init(
        id: String,
        fileName: String? = nil,
        mimeType: String? = nil,
        data: String? = nil,
        outputTarget: CodexCompletionSoundOutputTarget = .phone,
        volumePercent: Int = 100
    ) {
        self.type = "codexCompletionSound"
        self.protocolVersion = 1
        self.id = id
        self.fileName = fileName
        self.mimeType = mimeType
        self.data = data
        self.useBuiltIn = data == nil
        self.outputTarget = outputTarget
        self.volumePercent = min(max(volumePercent, 0), 100)
    }

    static let builtIn = CodexRemoteCompletionSound(id: "built-in")
}

struct CodexRemoteApprovalSound: Codable, Equatable, Sendable {
    let type: String
    let protocolVersion: Int
    let id: String
    let title: String?
    let fileName: String?
    let mimeType: String?
    let data: String?
    let useBuiltIn: Bool
    let configured: Bool
    let outputTarget: CodexApprovalSoundOutputTarget
    let volumePercent: Int

    init(
        id: String,
        title: String? = nil,
        fileName: String? = nil,
        mimeType: String? = nil,
        data: String? = nil,
        configured: Bool = false,
        outputTarget: CodexApprovalSoundOutputTarget = .phone,
        volumePercent: Int = 100
    ) {
        self.type = "codexApprovalSound"
        self.protocolVersion = 1
        self.id = id
        self.title = title
        self.fileName = fileName
        self.mimeType = mimeType
        self.data = data
        self.useBuiltIn = data == nil
        self.configured = configured
        self.outputTarget = outputTarget
        self.volumePercent = min(max(volumePercent, 0), 100)
    }

    private enum CodingKeys: String, CodingKey {
        case type, protocolVersion, id, title, fileName, mimeType, data, useBuiltIn, configured, outputTarget, volumePercent
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let data = try values.decodeIfPresent(String.self, forKey: .data)
        type = try values.decodeIfPresent(String.self, forKey: .type) ?? "codexApprovalSound"
        protocolVersion = try values.decodeIfPresent(Int.self, forKey: .protocolVersion) ?? 1
        id = try values.decode(String.self, forKey: .id)
        title = try values.decodeIfPresent(String.self, forKey: .title)
        fileName = try values.decodeIfPresent(String.self, forKey: .fileName)
        mimeType = try values.decodeIfPresent(String.self, forKey: .mimeType)
        self.data = data
        useBuiltIn = try values.decodeIfPresent(Bool.self, forKey: .useBuiltIn) ?? (data == nil)
        configured = try values.decodeIfPresent(Bool.self, forKey: .configured) ?? false
        outputTarget = try values.decodeIfPresent(CodexApprovalSoundOutputTarget.self, forKey: .outputTarget) ?? .phone
        volumePercent = min(max(try values.decodeIfPresent(Int.self, forKey: .volumePercent) ?? 100, 0), 100)
    }

    static let builtIn = CodexRemoteApprovalSound(id: "built-in")
}

struct CodexRemoteApproval: Codable, Equatable, Sendable {
    let requestID: Int?
    let title: String
    let detail: String
    let requestKey: String?
    let source: String
    let canRespond: Bool

    init(
        requestID: Int? = nil,
        title: String,
        detail: String,
        requestKey: String? = nil,
        source: String = "appServer",
        canRespond: Bool = true
    ) {
        self.requestID = requestID
        self.title = title
        self.detail = detail
        self.requestKey = requestKey
        self.source = source
        self.canRespond = canRespond
    }

    private enum CodingKeys: String, CodingKey {
        case requestID, title, detail, requestKey, source, canRespond
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        requestID = try values.decodeIfPresent(Int.self, forKey: .requestID)
        title = try values.decode(String.self, forKey: .title)
        detail = try values.decode(String.self, forKey: .detail)
        requestKey = try values.decodeIfPresent(String.self, forKey: .requestKey)
        source = try values.decodeIfPresent(String.self, forKey: .source) ?? "appServer"
        canRespond = try values.decodeIfPresent(Bool.self, forKey: .canRespond) ?? true
    }
}

struct CodexRemoteCommand: Codable, Equatable, Sendable {
    let type: String
    let protocolVersion: Int
    let id: String
    let command: String
    let buttonID: String?
    let action: PadAction?
    let decision: String?
    let approvalRequestKey: String?

    init(
        type: String,
        protocolVersion: Int,
        id: String,
        command: String,
        buttonID: String? = nil,
        action: PadAction? = nil,
        decision: String? = nil,
        approvalRequestKey: String? = nil
    ) {
        self.type = type
        self.protocolVersion = protocolVersion
        self.id = id
        self.command = command
        self.buttonID = buttonID
        self.action = action
        self.decision = decision
        self.approvalRequestKey = approvalRequestKey
    }
}

struct CodexRemoteCommandResult: Codable, Equatable, Sendable {
    let type: String
    let protocolVersion: Int
    let id: String
    let success: Bool
    let message: String

    init(id: String, success: Bool, message: String) {
        self.type = "commandResult"
        self.protocolVersion = 1
        self.id = id
        self.success = success
        self.message = message
    }
}

@MainActor
@Observable
final class CodexRemoteBridge {
    static let port: UInt16 = 43_123
    static let serviceType = "_micro-launchpad._tcp"

    private(set) var isRunning = false
    private(set) var clientCount = 0
    var onCommand: (@MainActor (CodexRemoteCommand) async -> CodexRemoteCommandResult)?
    var onMicrophoneAudio: ((Data) -> Void)?
    var onMicrophoneStop: (() -> Void)?
    var onPhoneMicrophoneActivityChanged: ((Bool) -> Void)?

    private var listener: NWListener?
    private var connections: [UUID: NWConnection] = [:]
    private var receiveBuffers: [UUID: Data] = [:]
    private var lastState: CodexRemoteState?
    private var lastIconAssets: [String: SmartphoneIconAsset]?
    private var lastCompletionSoundID: String?
    private var lastCompletionSoundOutputTarget: CodexCompletionSoundOutputTarget?
    private var lastCompletionSound: CodexRemoteCompletionSound?
    private var lastApprovalSoundID: String?
    private var lastApprovalSoundConfigured: Bool?
    private var lastApprovalSoundOutputTarget: CodexApprovalSoundOutputTarget?
    private var lastApprovalSound: CodexRemoteApprovalSound?
    private var microphoneConnectionID: UUID?
    private let queue = DispatchQueue(label: "MicroLaunchpad.remote-bridge", qos: .userInitiated)

    func start() {
        guard listener == nil else { return }
        do {
            let listener = try NWListener(using: .tcp, on: NWEndpoint.Port(rawValue: Self.port)!)
            listener.service = NWListener.Service(name: "LinkDeck", type: Self.serviceType)
            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if case .failed = state {
                        self.isRunning = false
                    } else if case .ready = state {
                        self.isRunning = true
                    }
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor [weak self] in
                    self?.accept(connection)
                }
            }
            self.listener = listener
            listener.start(queue: queue)
        } catch {
            isRunning = false
        }
    }

    func stop() {
        if microphoneConnectionID != nil {
            onMicrophoneStop?()
            onPhoneMicrophoneActivityChanged?(false)
        }
        microphoneConnectionID = nil
        listener?.cancel()
        listener = nil
        for connection in connections.values { connection.cancel() }
        connections.removeAll()
        receiveBuffers.removeAll()
        lastIconAssets = nil
        lastCompletionSoundID = nil
        lastCompletionSoundOutputTarget = nil
        lastCompletionSound = nil
        lastApprovalSoundID = nil
        lastApprovalSoundConfigured = nil
        lastApprovalSoundOutputTarget = nil
        lastApprovalSound = nil
        clientCount = 0
        isRunning = false
    }

    func publish(
        _ state: CodexRemoteState,
        completionSound: CodexRemoteCompletionSound,
        approvalSound: CodexRemoteApprovalSound = .builtIn
    ) {
        let iconAssetsChanged = state.smartphoneIconAssets != lastIconAssets
        let completionSoundChanged = completionSound.id != lastCompletionSoundID
            || completionSound.outputTarget != lastCompletionSoundOutputTarget
        let approvalSoundChanged = approvalSound.id != lastApprovalSoundID
            || approvalSound.configured != lastApprovalSoundConfigured
            || approvalSound.outputTarget != lastApprovalSoundOutputTarget
        lastState = state
        lastIconAssets = state.smartphoneIconAssets
        lastCompletionSoundID = completionSound.id
        lastCompletionSoundOutputTarget = completionSound.outputTarget
        lastCompletionSound = completionSound
        lastApprovalSoundID = approvalSound.id
        lastApprovalSoundConfigured = approvalSound.configured
        lastApprovalSoundOutputTarget = approvalSound.outputTarget
        lastApprovalSound = approvalSound
        if completionSoundChanged {
            send(completionSound, to: connections.values)
        }
        if approvalSoundChanged {
            send(approvalSound, to: connections.values)
        }
        guard let data = encodedLine(state, includingSmartphoneIconAssets: false) else { return }
        for connection in connections.values {
            connection.send(content: data, completion: .contentProcessed { _ in })
        }
        if iconAssetsChanged, let assets = state.smartphoneIconAssets {
            send(CodexRemoteIconAssets(assets: assets), to: connections.values)
        }
    }

    private func accept(_ connection: NWConnection) {
        let id = UUID()
        connections[id] = connection
        receiveBuffers[id] = Data()
        clientCount = connections.count
        connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if case .failed = state { self.remove(connectionID: id) }
                if case .cancelled = state { self.remove(connectionID: id) }
            }
        }
        connection.start(queue: queue)
        receive(from: connection, id: id)
    }

    private func receive(from connection: NWConnection, id: UUID) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let data, !data.isEmpty {
                    self.receiveBuffers[id, default: Data()].append(data)
                    self.consumeLines(for: connection, id: id)
                }
                if isComplete { self.remove(connectionID: id) }
                else if self.connections[id] != nil { self.receive(from: connection, id: id) }
            }
        }
    }

    private func consumeLines(for connection: NWConnection, id: UUID) {
        guard var buffer = receiveBuffers[id] else { return }
        while let newlineIndex = buffer.firstIndex(of: 10) {
            let line = buffer.prefix(upTo: newlineIndex)
            buffer.removeSubrange(...newlineIndex)
            guard let object = try? JSONSerialization.jsonObject(with: line),
                  let payload = object as? [String: Any],
                  let type = payload["type"] as? String else { continue }
            if type == "hello" {
                sendCurrentState(to: connection)
            } else if type == "microphoneAudio", microphoneConnectionID == id,
                      let encoded = payload["data"] as? String, encoded.count <= 1024,
                      let audio = Data(base64Encoded: encoded), audio.count == 640 {
                onMicrophoneAudio?(audio)
            } else if type == "command", let commandName = payload["command"] as? String,
                      (commandName == "microphoneStart" || commandName == "microphoneStop"),
                      let activeID = microphoneConnectionID, activeID != id,
                      let commandID = payload["id"] as? String {
                send(CodexRemoteCommandResult(id: commandID, success: false, message: "다른 휴대폰에서 마이크를 사용 중입니다."), to: connection)
            } else if type == "command",
                      let commandData = try? JSONSerialization.data(withJSONObject: payload),
                      let command = try? JSONDecoder().decode(CodexRemoteCommand.self, from: commandData) {
                Task { @MainActor [weak self] in
                    guard let self, let result = await self.onCommand?(command) else { return }
                    if result.success && command.command == "microphoneStart" {
                        self.microphoneConnectionID = id
                        self.onPhoneMicrophoneActivityChanged?(true)
                    } else if command.command == "microphoneStop" && self.microphoneConnectionID == id {
                        self.microphoneConnectionID = nil
                        self.onPhoneMicrophoneActivityChanged?(false)
                    }
                    self.send(result, to: connection)
                }
            }
        }
        receiveBuffers[id] = buffer
    }

    private func sendCurrentState(to connection: NWConnection) {
        guard let state = lastState, let data = encodedLine(state, includingSmartphoneIconAssets: false) else { return }
        if let completionSound = lastCompletionSound {
            send(completionSound, to: [connection])
        }
        if let approvalSound = lastApprovalSound {
            send(approvalSound, to: [connection])
        }
        connection.send(content: data, completion: .contentProcessed { _ in })
        if let assets = state.smartphoneIconAssets {
            send(CodexRemoteIconAssets(assets: assets), to: [connection])
        }
    }

    private func send(_ result: CodexRemoteCommandResult, to connection: NWConnection) {
        guard let data = encodedLine(result) else { return }
        connection.send(content: data, completion: .contentProcessed { _ in })
    }

    private func send<T: Encodable>(_ value: T, to connections: Dictionary<UUID, NWConnection>.Values) {
        guard let data = encodedLine(value) else { return }
        for connection in connections {
            connection.send(content: data, completion: .contentProcessed { _ in })
        }
    }

    private func send<T: Encodable>(_ value: T, to connections: [NWConnection]) {
        guard let data = encodedLine(value) else { return }
        for connection in connections {
            connection.send(content: data, completion: .contentProcessed { _ in })
        }
    }

    private func remove(connectionID id: UUID) {
        if microphoneConnectionID == id {
            microphoneConnectionID = nil
            onMicrophoneStop?()
            onPhoneMicrophoneActivityChanged?(false)
        }
        connections[id]?.cancel()
        connections.removeValue(forKey: id)
        receiveBuffers.removeValue(forKey: id)
        clientCount = connections.count
    }

    private func encodedLine(_ state: CodexRemoteState, includingSmartphoneIconAssets: Bool = true) -> Data? {
        let encoder = JSONEncoder()
        // The Android client interprets reset timestamps as Unix epoch seconds.
        // Make that wire format explicit instead of Foundation's default
        // reference-date encoding (seconds since 2001).
        encoder.dateEncodingStrategy = .secondsSince1970
        guard let encoded = try? encoder.encode(state) else { return nil }
        if includingSmartphoneIconAssets { return encoded + Data([0x0A]) }
        guard var object = try? JSONSerialization.jsonObject(with: encoded) as? [String: Any] else { return nil }
        object.removeValue(forKey: "smartphoneIconAssets")
        guard let stripped = try? JSONSerialization.data(withJSONObject: object) else { return nil }
        return stripped + Data([0x0A])
    }

    private func encodedLine<T: Encodable>(_ value: T) -> Data? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        guard let encoded = try? encoder.encode(value) else { return nil }
        return encoded + Data([0x0A])
    }
}
