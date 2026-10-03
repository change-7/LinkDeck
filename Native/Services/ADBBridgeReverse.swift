import Foundation

enum ADBBridgeReverse {
    static func configureConnectedPhones() {
        let adb = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Android/sdk/platform-tools/adb")
        guard FileManager.default.isExecutableFile(atPath: adb.path),
              let devices = run(adb, arguments: ["devices"]) else { return }
        for line in devices.split(separator: "\n") {
            let fields = line.split(separator: "\t")
            guard fields.count == 2, fields[1] == "device" else { continue }
            let serial = String(fields[0])
            let arguments = ["-s", serial, "reverse"]
            guard let current = run(adb, arguments: arguments + ["--list"]),
                  !current.contains("tcp:43123 tcp:43123") else { continue }
            _ = run(adb, arguments: arguments + ["tcp:43123", "tcp:43123"])
        }
    }

    private static func run(_ executable: URL, arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }
}
