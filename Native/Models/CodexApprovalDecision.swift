import Foundation

struct CodexRemoteApprovalOption: Codable, Equatable, Sendable {
    let id: String
    let title: String
    let detail: String
}

struct CodexApprovalDecision: Equatable, Sendable {
    let option: CodexRemoteApprovalOption
    let value: CodexIPCJSONValue

    static func options(method: String, params: [String: CodexIPCJSONValue]) -> [Self] {
        let kind = CodexDesktopApprovalKind(method: method)
        guard kind == .commandExecution || kind == .fileChange || kind == .permissions else { return [] }
        if kind == .permissions {
            guard case .object? = params["permissions"] else { return [] }
        }
        let values: [CodexIPCJSONValue]
        if case let .array(provided)? = params["availableDecisions"] {
            values = provided
        } else {
            if let provided = params["availableDecisions"], provided != .null { return [] }
            var defaults: [CodexIPCJSONValue] = [.string("accept")]
            if kind != .commandExecution || params["networkApprovalContext"]?.foundationValue is [String: Any] {
                defaults.append(.string("acceptForSession"))
            }
            if kind == .commandExecution {
                if case let .array(prefix)? = params["proposedExecpolicyAmendment"], !prefix.isEmpty {
                    defaults.append(.object(["acceptWithExecpolicyAmendment": .object(["execpolicy_amendment": .array(prefix)])]))
                }
                if case let .array(amendments)? = params["proposedNetworkPolicyAmendments"] {
                    for amendment in amendments {
                        if case let .object(fields) = amendment, fields["action"] == .string("allow") {
                            defaults.append(.object(["applyNetworkPolicyAmendment": .object(["network_policy_amendment": amendment])]))
                        }
                    }
                }
            }
            defaults.append(.string("decline"))
            values = defaults
        }
        return values.enumerated().compactMap { index, value in
            let id: String
            let title: String
            var detail = ""
            switch value {
            case .string("accept"): id = "accept"; title = "한 번만 허용"
            case .string("acceptForSession"): id = "acceptForSession"; title = "이 대화에서만 허용"
            case .string("decline"): id = "decline"; title = "거부"
            case .string("cancel"): id = "cancel"; title = "취소"
            case let .object(fields) where kind == .commandExecution:
                id = "policy-\(index)"
                if case let .object(amendment)? = fields["acceptWithExecpolicyAmendment"],
                   case let .array(prefix)? = amendment["execpolicy_amendment"],
                   !prefix.isEmpty, prefix.allSatisfy({ if case .string = $0 { return true }; return false }) {
                    title = "항상 허용"
                    detail = "다음으로 시작하는 명령: " + prefix.compactMap(\.stringValue).joined(separator: " ")
                } else if case let .object(wrapper)? = fields["applyNetworkPolicyAmendment"],
                          case let .object(amendment)? = wrapper["network_policy_amendment"],
                          let host = amendment["host"]?.stringValue, !host.isEmpty,
                          amendment["action"] == .string("allow") || amendment["action"] == .string("deny") {
                    title = amendment["action"] == .string("allow") ? "항상 허용" : "항상 거부"
                    detail = "호스트: \(host)"
                } else { return nil }
            default: return nil
            }
            return Self(option: CodexRemoteApprovalOption(id: id, title: title, detail: detail), value: value)
        }
    }
}
