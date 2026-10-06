import Foundation

enum GitHubAuthEnvironment {
    static let configurationDirectory: URL = {
        let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return applicationSupport
            .appendingPathComponent("FolderSync", isDirectory: true)
            .appendingPathComponent("GitHubCLI", isDirectory: true)
    }()

    private static let inheritedCredentialKeys: Set<String> = [
        "GH_TOKEN",
        "GITHUB_TOKEN",
        "GH_ENTERPRISE_TOKEN",
        "GITHUB_ENTERPRISE_TOKEN",
        "GH_HOST",
        "GH_CONFIG_DIR"
    ]

    static func processEnvironment() -> [String: String] {
        processEnvironment(from: ProcessInfo.processInfo.environment)
    }

    static func processEnvironment(from base: [String: String]) -> [String: String] {
        var environment = base.filter { !inheritedCredentialKeys.contains($0.key) }
        environment["GH_CONFIG_DIR"] = configurationDirectory.path
        environment["GH_PROMPT_DISABLED"] = "1"
        return environment
    }

    static func prepareConfigurationDirectory() throws {
        try FileManager.default.createDirectory(
            at: configurationDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: configurationDirectory.path
        )
        guard FileManager.default.isWritableFile(atPath: configurationDirectory.path) else {
            throw CocoaError(.fileWriteNoPermission, userInfo: [NSFilePathErrorKey: configurationDirectory.path])
        }
    }
}

enum GitHubAuthCommandBuilder {
    static func statusCommand() -> GitHubCommand {
        GitHubCommand(
            arguments: ["auth", "status", "--active", "--hostname", "github.com"],
            workingDirectory: FileManager.default.homeDirectoryForCurrentUser
        )
    }

    static func loginCommand() -> GitHubCommand {
        GitHubCommand(
            arguments: [
                "auth", "login",
                "--hostname", "github.com",
                "--git-protocol", "https",
                "--web", "--clipboard", "--skip-ssh-key",
                "--scopes", "repo,read:org"
            ],
            workingDirectory: FileManager.default.homeDirectoryForCurrentUser
        )
    }

    static func repositoriesCommand() -> GitHubCommand {
        GitHubCommand(
            arguments: [
                "api", "--hostname", "github.com",
                "--method", "GET",
                "--paginate", "--slurp",
                "/user/repos?visibility=all&affiliation=owner,collaborator,organization_member&per_page=100"
            ],
            workingDirectory: FileManager.default.homeDirectoryForCurrentUser
        )
    }

    static func organizationsCommand() -> GitHubCommand {
        GitHubCommand(
            arguments: [
                "api", "--hostname", "github.com",
                "--method", "GET",
                "--paginate", "--slurp",
                "/user/orgs?per_page=100"
            ],
            workingDirectory: FileManager.default.homeDirectoryForCurrentUser
        )
    }

    static func createRepositoryCommand(
        name: String,
        description: String,
        visibility: GitHubRepositoryVisibility,
        owner: String? = nil
    ) -> GitHubCommand {
        var arguments = [
            "api", "--hostname", "github.com",
            "--method", "POST",
            "-f", "name=\(name)",
            "-F", "private=\(visibility == .privateRepository)"
        ]
        if !description.isEmpty {
            arguments += ["-f", "description=\(description)"]
        }
        arguments.append(owner.map { "/orgs/\($0)/repos" } ?? "/user/repos")
        return GitHubCommand(
            arguments: arguments,
            workingDirectory: FileManager.default.homeDirectoryForCurrentUser
        )
    }

    static func updateRepositoryCommand(
        fullName: String,
        name: String,
        description: String,
        visibility: GitHubRepositoryVisibility
    ) -> GitHubCommand {
        GitHubCommand(
            arguments: [
                "api", "--hostname", "github.com",
                "--method", "PATCH",
                "-f", "name=\(name)",
                "-f", "description=\(description)",
                "-F", "private=\(visibility == .privateRepository)",
                "/repos/\(fullName)"
            ],
            workingDirectory: FileManager.default.homeDirectoryForCurrentUser
        )
    }
}

enum GitHubAuthBrowser {
    static let deviceURL = URL(string: "https://github.com/login/device")!
}

enum GitHubAuthInput {
    static func acceptBrowserPrompt(on fileHandle: FileHandle) throws {
        try fileHandle.write(contentsOf: Data("\n".utf8))
        try fileHandle.close()
    }
}

private final class GitHubProcessOutput: @unchecked Sendable {
    var data = Data()
}

enum GitHubAuthError: LocalizedError, Equatable {
    case gitHubCLIUnavailable
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .gitHubCLIUnavailable:
            AppText.githubCLIUnavailable
        case .commandFailed(let output):
            output.isEmpty ? AppText.githubLoginFailed : AppText.githubLoginFailedWithOutput(output)
        }
    }
}

enum GitHubRepositoryError: LocalizedError, Equatable {
    case authenticationRequired
    case commandFailed(String)
    case invalidResponse
    case creationFailed(String)
    case invalidCreationResponse
    case updateFailed(String)
    case invalidUpdateResponse

    var errorDescription: String? {
        switch self {
        case .authenticationRequired:
            AppText.githubRepositoryLoginRequired
        case .commandFailed(let output):
            output.isEmpty ? AppText.githubRepositoryFetchFailed : AppText.githubRepositoryFetchFailedWithOutput(output)
        case .invalidResponse:
            AppText.githubRepositoryInvalidResponse
        case .creationFailed(let output):
            output.isEmpty ? AppText.githubRepositoryCreateFailed : AppText.githubRepositoryCreateFailedWithOutput(output)
        case .invalidCreationResponse:
            AppText.githubRepositoryInvalidCreationResponse
        case .updateFailed(let output):
            output.isEmpty ? AppText.githubRepositoryUpdateFailed : AppText.githubRepositoryUpdateFailedWithOutput(output)
        case .invalidUpdateResponse:
            AppText.githubRepositoryInvalidUpdateResponse
        }
    }
}

enum GitHubAuthState: Equatable {
    case unknown
    case checking
    case loggedOut
    case loggedIn
    case loggingIn
    case failed(String)
}

actor GitHubAuthService {
    static let executableURL = [
        URL(filePath: "/opt/homebrew/bin/gh"),
        URL(filePath: "/usr/local/bin/gh"),
        URL(filePath: "/usr/bin/gh")
    ].first(where: { FileManager.default.isExecutableFile(atPath: $0.path) })

    private let commandTimeout: TimeInterval

    init(commandTimeout: TimeInterval = 300) {
        self.commandTimeout = commandTimeout
    }

    func isAuthenticated() throws -> Bool {
        guard let executableURL = Self.executableURL else {
            throw GitHubAuthError.gitHubCLIUnavailable
        }
        let result = try run(executableURL: executableURL, command: GitHubAuthCommandBuilder.statusCommand())
        return result.status == 0
    }

    func login() throws {
        guard let executableURL = Self.executableURL else {
            throw GitHubAuthError.gitHubCLIUnavailable
        }
        let result = try run(
            executableURL: executableURL,
            command: GitHubAuthCommandBuilder.loginCommand(),
            sendsNewlineToStandardInput: true
        )
        guard result.status == 0 else {
            throw GitHubAuthError.commandFailed(result.output)
        }
    }

    func listRepositories() throws -> [GitHubRepository] {
        guard let executableURL = Self.executableURL else {
            throw GitHubRepositoryError.commandFailed(AppText.githubCLIUnavailable)
        }

        do {
            let result = try run(executableURL: executableURL, command: GitHubAuthCommandBuilder.repositoriesCommand())
            guard result.status == 0 else {
                throw GitHubRepositoryError.commandFailed(result.output)
            }

            let data = Data(result.output.utf8)
            let repositories: [GitHubRepository]
            if let pages = try? JSONDecoder().decode([[GitHubRepository]].self, from: data) {
                repositories = pages.flatMap { $0 }
            } else if let values = try? JSONDecoder().decode([GitHubRepository].self, from: data) {
                repositories = values
            } else {
                throw GitHubRepositoryError.invalidResponse
            }

            return repositories.sorted {
                $0.fullName.localizedCaseInsensitiveCompare($1.fullName) == .orderedAscending
            }
        } catch let error as GitHubRepositoryError {
            throw error
        } catch let error as GitHubAuthError {
            throw GitHubRepositoryError.commandFailed(error.localizedDescription)
        }
    }

    func listOrganizations() throws -> [GitHubOrganization] {
        guard let executableURL = Self.executableURL else {
            throw GitHubRepositoryError.commandFailed(AppText.githubCLIUnavailable)
        }

        do {
            let result = try run(executableURL: executableURL, command: GitHubAuthCommandBuilder.organizationsCommand())
            guard result.status == 0 else {
                throw GitHubRepositoryError.commandFailed(result.output)
            }

            let data = Data(result.output.utf8)
            if let pages = try? JSONDecoder().decode([[GitHubOrganization]].self, from: data) {
                return pages.flatMap { $0 }.sorted {
                    $0.login.localizedCaseInsensitiveCompare($1.login) == .orderedAscending
                }
            }
            throw GitHubRepositoryError.invalidResponse
        } catch let error as GitHubRepositoryError {
            throw error
        } catch let error as GitHubAuthError {
            throw GitHubRepositoryError.commandFailed(error.localizedDescription)
        }
    }

    func createRepository(
        name: String,
        description: String,
        visibility: GitHubRepositoryVisibility,
        owner: String? = nil
    ) throws -> GitHubRepository {
        guard let executableURL = Self.executableURL else {
            throw GitHubRepositoryError.creationFailed(AppText.githubCLIUnavailable)
        }
        guard try isAuthenticated() else {
            throw GitHubRepositoryError.authenticationRequired
        }

        do {
            let result = try run(
                executableURL: executableURL,
                command: GitHubAuthCommandBuilder.createRepositoryCommand(
                    name: name,
                    description: description,
                    visibility: visibility,
                    owner: owner
                )
            )
            guard result.status == 0 else {
                throw GitHubRepositoryError.creationFailed(result.output)
            }
            guard let repository = try? JSONDecoder().decode(GitHubRepository.self, from: Data(result.output.utf8)) else {
                throw GitHubRepositoryError.invalidCreationResponse
            }
            return repository
        } catch let error as GitHubRepositoryError {
            throw error
        } catch let error as GitHubAuthError {
            throw GitHubRepositoryError.creationFailed(error.localizedDescription)
        }
    }

    func updateRepository(
        _ repository: GitHubRepository,
        name: String,
        description: String,
        visibility: GitHubRepositoryVisibility
    ) throws -> GitHubRepository {
        guard let executableURL = Self.executableURL else {
            throw GitHubRepositoryError.updateFailed(AppText.githubCLIUnavailable)
        }
        guard try isAuthenticated() else {
            throw GitHubRepositoryError.authenticationRequired
        }

        do {
            let result = try run(
                executableURL: executableURL,
                command: GitHubAuthCommandBuilder.updateRepositoryCommand(
                    fullName: repository.fullName,
                    name: name,
                    description: description,
                    visibility: visibility
                )
            )
            guard result.status == 0 else {
                throw GitHubRepositoryError.updateFailed(result.output)
            }
            guard let updatedRepository = try? JSONDecoder().decode(
                GitHubRepository.self,
                from: Data(result.output.utf8)
            ) else {
                throw GitHubRepositoryError.invalidUpdateResponse
            }
            return updatedRepository
        } catch let error as GitHubRepositoryError {
            throw error
        } catch let error as GitHubAuthError {
            throw GitHubRepositoryError.updateFailed(error.localizedDescription)
        }
    }

    func run(
        executableURL: URL,
        command: GitHubCommand,
        sendsNewlineToStandardInput: Bool = false
    ) throws -> (status: Int32, output: String) {
        do {
            try GitHubAuthEnvironment.prepareConfigurationDirectory()
        } catch {
            throw GitHubAuthError.commandFailed(error.localizedDescription)
        }
        let process = Process()
        let outputPipe = Pipe()
        let inputPipe = Pipe()
        let completion = DispatchSemaphore(value: 0)
        process.executableURL = executableURL
        process.arguments = command.arguments
        process.currentDirectoryURL = command.workingDirectory
        process.standardOutput = outputPipe
        process.standardError = outputPipe
        process.standardInput = inputPipe
        var environment = GitHubAuthEnvironment.processEnvironment()
        if sendsNewlineToStandardInput {
            environment["GH_BROWSER"] = "/usr/bin/true"
        }
        process.environment = environment
        process.terminationHandler = { _ in completion.signal() }

        do {
            try process.run()
            if sendsNewlineToStandardInput {
                try GitHubAuthInput.acceptBrowserPrompt(on: inputPipe.fileHandleForWriting)
            }
        } catch {
            throw GitHubAuthError.commandFailed(error.localizedDescription)
        }

        let outputReadCompletion = DispatchSemaphore(value: 0)
        let outputData = GitHubProcessOutput()
        DispatchQueue.global(qos: .userInitiated).async {
            outputData.data = outputPipe.fileHandleForReading.readDataToEndOfFile()
            outputReadCompletion.signal()
        }

        guard completion.wait(timeout: .now() + commandTimeout) == .success else {
            process.terminate()
            _ = outputReadCompletion.wait(timeout: .now() + 5)
            throw GitHubAuthError.commandFailed(AppText.githubLoginTimedOut)
        }
        _ = outputReadCompletion.wait(timeout: .now() + 5)
        let output = String(decoding: outputData.data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (process.terminationStatus, output)
    }
}
