import Foundation

enum SyncLogLevel: String, Codable {
    case info
    case error
}

enum SyncLogKind: String, Codable {
    case syncStarted
    case syncCompleted
    case waitingForFolder
    case syncFailed
    case realtimeMonitoringFailed
    case realtimeMonitoringStarted
    case realtimeMonitoringUnavailable
    case githubSyncStarted
    case githubPushCompleted
    case githubSyncFailed
    case githubMonitoringStarted
    case githubMonitoringFailed
    case legacy

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        if rawValue == "waitingForDestination" {
            self = .waitingForFolder
        } else if let kind = Self(rawValue: rawValue) {
            self = kind
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unknown sync log kind: \(rawValue)"
            )
        }
    }
}

struct SyncLogMessage: Codable {
    let kind: SyncLogKind
    let pairName: String?
    let legacyText: String?

    init(kind: SyncLogKind, pairName: String) {
        self.kind = kind
        self.pairName = pairName
        legacyText = nil
    }

    private init(legacyText: String) {
        kind = .legacy
        pairName = nil
        self.legacyText = legacyText
    }

    var localizedText: String {
        let name = pairName ?? ""
        return switch kind {
        case .syncStarted: AppText.syncStarted(name)
        case .syncCompleted: AppText.syncCompleted(name)
        case .waitingForFolder: AppText.waitingForFolder(name)
        case .syncFailed: AppText.syncFailed(name)
        case .realtimeMonitoringFailed: AppText.realtimeMonitoringFailed(name)
        case .realtimeMonitoringStarted: AppText.realtimeMonitoringStarted(name)
        case .realtimeMonitoringUnavailable: AppText.realtimeMonitoringUnavailable(name)
        case .githubSyncStarted: AppText.githubSyncStarted(name)
        case .githubPushCompleted: AppText.githubPushCompleted(name)
        case .githubSyncFailed: AppText.githubSyncFailed(name)
        case .githubMonitoringStarted: AppText.githubMonitoringStarted(name)
        case .githubMonitoringFailed: AppText.githubMonitoringFailed(name)
        case .legacy: legacyText ?? ""
        }
    }

    static func migrateLegacy(_ message: String) -> Self {
        let patterns: [(String, SyncLogKind)] = [
            ("Sync started: ", .syncStarted),
            ("Sync completed: ", .syncCompleted),
            ("Waiting for destination: ", .waitingForFolder),
            ("Real-time monitoring failed: ", .realtimeMonitoringFailed),
            ("Real-time monitoring started: ", .realtimeMonitoringStarted)
        ]
        for (prefix, kind) in patterns where message.hasPrefix(prefix) {
            return SyncLogMessage(kind: kind, pairName: String(message.dropFirst(prefix.count)))
        }
        if message.hasPrefix("Sync failed (") {
            let remainder = message.dropFirst("Sync failed (".count)
            if let end = remainder.firstIndex(of: ")") {
                let name = String(remainder[..<end])
                return SyncLogMessage(kind: .syncFailed, pairName: name)
            }
        }
        if message.hasPrefix("Real-time monitoring unavailable (") {
            let remainder = message.dropFirst("Real-time monitoring unavailable (".count)
            if let end = remainder.firstIndex(of: ")") {
                let name = String(remainder[..<end])
                return SyncLogMessage(kind: .realtimeMonitoringUnavailable, pairName: name)
            }
        }
        return SyncLogMessage(legacyText: message)
    }
}

struct SyncLogEntry: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let level: SyncLogLevel
    let event: SyncLogMessage

    var message: String { event.localizedText }

    init(level: SyncLogLevel, event: SyncLogMessage) {
        id = UUID()
        timestamp = .now
        self.level = level
        self.event = event
    }

    private enum CodingKeys: String, CodingKey {
        case id, timestamp, level, event, message
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        level = try container.decode(SyncLogLevel.self, forKey: .level)
        if let event = try container.decodeIfPresent(SyncLogMessage.self, forKey: .event) {
            self.event = event
        } else {
            let legacyMessage = try container.decode(String.self, forKey: .message)
            event = SyncLogMessage.migrateLegacy(legacyMessage)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(level, forKey: .level)
        try container.encode(event, forKey: .event)
    }
}
