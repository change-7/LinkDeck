import Foundation

struct RsyncCommand {
    let executableURL: URL
    let arguments: [String]
}

enum RsyncCommandBuilder {
    static func copyCommand(from: URL, to: URL, options: SyncOptions = SyncOptions()) -> RsyncCommand {
        command(from: from, to: to, options: options, additionalArguments: [])
    }

    static func transferCommand(from: URL, to: URL, options: SyncOptions = SyncOptions()) -> RsyncCommand {
        command(from: from, to: to, options: options, additionalArguments: ["--remove-source-files"])
    }

    private static func command(
        from: URL,
        to: URL,
        options: SyncOptions,
        additionalArguments: [String]
    ) -> RsyncCommand {
        var arguments = ["-a", "--update"]
        arguments += additionalArguments
        if options.deleteExtraFiles {
            arguments.append("--delete")
        }
        if !options.includeHiddenFiles {
            arguments.append("--exclude=.*")
        }
        if let maxFileSize = options.maxFileSize.rsyncValue {
            arguments.append("--max-size=\(maxFileSize)")
        }
        if options.excludeNestedDestination,
           let relativeDestination = FolderPathRelationship.relativePath(of: to, inside: from) {
            arguments.append("--exclude=/\(relativeDestination)/")
        }
        arguments += ["--", directoryContentsPath(from), directoryContentsPath(to)]
        return RsyncCommand(
            executableURL: URL(fileURLWithPath: "/usr/bin/rsync"),
            arguments: arguments
        )
    }

    private static func directoryContentsPath(_ url: URL) -> String {
        url.path.hasSuffix("/") ? url.path : url.path + "/"
    }
}

enum SyncError: LocalizedError {
    case inputFolderIsNotDirectory(String)
    case outputFolderIsNotDirectory(String)
    case unsafeFolderRelationship
    case twoWayRequiresConflictHandling
    case transferCannotDeleteExtraFiles
    case rsyncFailed(String)

    var errorDescription: String? {
        switch self {
        case .inputFolderIsNotDirectory(let path): AppText.inputFolderIsNotDirectory(path)
        case .outputFolderIsNotDirectory(let path): AppText.outputFolderIsNotDirectory(path)
        case .unsafeFolderRelationship: AppText.unsafeFolderRelationship
        case .twoWayRequiresConflictHandling: AppText.twoWaySafetyMessage
        case .transferCannotDeleteExtraFiles: AppText.transferCannotDeleteExtraFiles
        case .rsyncFailed: AppText.rsyncFailed
        }
    }
}

actor RsyncRunner {
    func copy(from: URL, to: URL, options: SyncOptions = SyncOptions()) async throws {
        try validate(from: from, to: to, options: options)
        let command = RsyncCommandBuilder.copyCommand(from: from, to: to, options: options)
        try run(command)
    }

    func transfer(from: URL, to: URL, options: SyncOptions = SyncOptions()) async throws {
        guard !options.deleteExtraFiles else {
            throw SyncError.transferCannotDeleteExtraFiles
        }
        try validate(from: from, to: to, options: options)
        let command = RsyncCommandBuilder.transferCommand(from: from, to: to, options: options)
        try run(command)
    }

    private func run(_ command: RsyncCommand) throws {
        let process = Process()
        let output = Pipe()
        process.executableURL = command.executableURL
        process.arguments = command.arguments
        process.standardOutput = output
        process.standardError = output
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let data = output.fileHandleForReading.readDataToEndOfFile()
            throw SyncError.rsyncFailed(String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    private func validate(from: URL, to: URL, options: SyncOptions) throws {
        var inputIsDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: from.path, isDirectory: &inputIsDirectory), inputIsDirectory.boolValue else {
            throw SyncError.inputFolderIsNotDirectory(from.path)
        }
        var outputIsDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: to.path, isDirectory: &outputIsDirectory), outputIsDirectory.boolValue else {
            throw SyncError.outputFolderIsNotDirectory(to.path)
        }
        let inputPath = from.resolvingSymlinksInPath().standardizedFileURL.path
        let outputPath = to.resolvingSymlinksInPath().standardizedFileURL.path
        let destinationIsNested = outputPath.hasPrefix(inputPath + "/")
        let sourceIsNested = inputPath.hasPrefix(outputPath + "/")
        guard inputPath != outputPath,
              !sourceIsNested,
              !destinationIsNested || options.excludeNestedDestination else {
            throw SyncError.unsafeFolderRelationship
        }
    }
}
