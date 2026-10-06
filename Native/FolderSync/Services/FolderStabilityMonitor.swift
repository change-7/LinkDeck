import Foundation

struct FolderSnapshot: Equatable {
    struct FileState: Equatable {
        let size: Int64
        let modificationDate: Date?
    }

    let files: [String: FileState]

    init(folder: URL) throws {
        let rootPath = folder.standardizedFileURL.path
        var files: [String: FileState] = [:]
        guard let enumerator = FileManager.default.enumerator(
            at: folder,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey],
            options: []
        ) else {
            self.files = files
            return
        }

        for case let fileURL as URL in enumerator {
            let values = try fileURL.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey])
            guard values.isDirectory != true else { continue }
            let relativePath = String(fileURL.standardizedFileURL.path.dropFirst(rootPath.count))
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            files[relativePath] = FileState(
                size: Int64(values.fileSize ?? 0),
                modificationDate: values.contentModificationDate
            )
        }
        self.files = files
    }
}

enum FolderStabilityMonitor {
    static func waitUntilStable(
        at folder: URL,
        stableChecks: Int = 4,
        pollIntervalNanoseconds: UInt64 = 1_000_000_000
    ) async throws {
        guard stableChecks > 1 else { return }
        var previous = try FolderSnapshot(folder: folder)
        var unchangedChecks = 0

        while unchangedChecks < stableChecks - 1 {
            try await Task.sleep(nanoseconds: pollIntervalNanoseconds)
            try Task.checkCancellation()
            let current = try FolderSnapshot(folder: folder)
            if current == previous {
                unchangedChecks += 1
            } else {
                unchangedChecks = 0
                previous = current
            }
        }
    }
}
