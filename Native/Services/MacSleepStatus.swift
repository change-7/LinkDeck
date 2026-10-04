import Foundation
import IOKit.pwr_mgt
import Darwin

struct MacSleepStatus: Codable, Equatable, Sendable {
    let mode: String
    let label: String
    let sleepPreventionEnabled: Bool?

    static let unknown = MacSleepStatus(mode: "unknown", label: "상태 확인 불가", sleepPreventionEnabled: nil)

    static func from(assertions: [[String: Any]], processName: String) -> Bool {
        guard processName == "caffeinate" else { return false }
        return assertions.contains {
            let type = $0["AssertType"] as? String
            let level = ($0["AssertLevel"] as? NSNumber)?.intValue ?? 0
            return level != 0 && ["PreventUserIdleSystemSleep", "NoIdleSleepAssertion", "PreventSystemSleep"].contains(type ?? "")
        }
    }

    static func current() -> MacSleepStatus {
        var assertions: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsByProcess(&assertions) == kIOReturnSuccess,
              let dictionary = assertions?.takeRetainedValue() as? [NSNumber: [[String: Any]]] else { return .unknown }
        var enabled = false
        for (pid, entries) in dictionary {
            var name = [CChar](repeating: 0, count: 1024)
            let length = proc_name(pid.int32Value, &name, UInt32(name.count))
            guard length > 0 else { continue }
            let processName = String(decoding: name.prefix(Int(length)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
            if from(assertions: entries, processName: processName) { enabled = true; break }
        }
        return MacSleepStatus(mode: enabled ? "insomnia" : "sleep", label: enabled ? "불면증" : "숙면", sleepPreventionEnabled: enabled)
    }
}
