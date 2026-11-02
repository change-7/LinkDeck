import Foundation
import CryptoKit

@MainActor
final class CodexRemoteSync {
    let sessionID = UUID().uuidString
    private(set) var sequence = 0
    private(set) var revisions: [String: String] = [:]
    private var resources: [String: Data] = [:]
    private var lastState: CodexRemoteState?
    private var completionSound: CodexRemoteCompletionSound?
    private var approvalSound: CodexRemoteApprovalSound?
    private var lastWireIcons: [String: SmartphoneIconAsset]?
    private var liveState: Data?
    static let heartbeat = Data("{\"type\":\"heartbeat\",\"protocolVersion\":3}\n".utf8)

    @discardableResult
    func update(_ state: CodexRemoteState, completionSound: CodexRemoteCompletionSound,
                approvalSound: CodexRemoteApprovalSound) -> Bool {
        guard state != lastState || self.completionSound != completionSound || self.approvalSound != approvalSound else { return false }
        if state.smartphonePages != lastState?.smartphonePages {
            setResource("buttons", ["smartphonePages": state.smartphonePages])
        }
        let assets = state.smartphoneIconAssets ?? [:]
        let wireIcons = assets.filter { assets[$0.key + "__A"] == nil && assets[$0.key + "__B"] == nil }
        if wireIcons != lastWireIcons {
            setResource("icons", CodexRemoteIconAssets(assets: wireIcons))
            lastWireIcons = wireIcons
        }
        if completionSound != self.completionSound { setResource("completionSound", completionSound) }
        if approvalSound != self.approvalSound { setResource("approvalSound", approvalSound) }
        sequence += 1
        var compact = state
        compact.smartphonePages = []
        compact.smartphoneIconAssets = nil
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        if let encoded = try? encoder.encode(compact),
           var object = (try? JSONSerialization.jsonObject(with: encoded)) as? [String: Any] {
            object.removeValue(forKey: "smartphonePages")
            object["protocolVersion"] = 3
            object["sessionID"] = sessionID
            object["sequence"] = sequence
            liveState = (try? JSONSerialization.data(withJSONObject: object)).map { $0 + Data([10]) }
        }
        lastState = state
        self.completionSound = completionSound
        self.approvalSound = approvalSound
        return true
    }

    func frames(cachedRevisions: [String: String]) -> [Data] {
        guard let liveState,
              let manifest = try? JSONSerialization.data(withJSONObject: [
                "type": "sync", "protocolVersion": 3, "sessionID": sessionID,
                "sequence": sequence, "resourceRevisions": revisions
              ]) else { return [] }
        return [manifest + Data([10])] + revisions.keys.sorted().compactMap { name in
            cachedRevisions[name] == revisions[name] ? nil : resources[name]
        } + [liveState]
    }

    private func setResource<T: Encodable>(_ name: String, _ value: T) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .secondsSince1970
        guard let payloadData = try? encoder.encode(value),
              let payload = try? JSONSerialization.jsonObject(with: payloadData) else { return }
        let revision = SHA256.hash(data: payloadData).map { String(format: "%02x", $0) }.joined()
        guard let encoded = try? JSONSerialization.data(withJSONObject: [
            "type": "resource", "protocolVersion": 3, "sessionID": sessionID,
            "name": name, "revision": revision, "payload": payload
        ]) else { return }
        revisions[name] = revision
        resources[name] = encoded + Data([10])
    }
}
