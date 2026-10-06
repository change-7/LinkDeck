import Foundation

enum AppText {
    static var folders: String { value("Folders") }
    static var syncList: String { value("Sync list") }
    static var add: String { value("Add") }
    static var noFoldersYet: String { value("No folders yet") }
    static var emptyStateDescription: String { value("Add Folder A and Folder B to start syncing.") }
    static var addFolderPair: String { value("Add folders") }
    static var delete: String { value("Delete") }
    static var sync: String { value("Sync") }
    static var pairSettings: String { value("Sync settings") }
    static var appSettings: String { value("App settings") }
    static var appearance: String { value("Appearance") }
    static var lightAppearance: String { value("Light") }
    static var darkAppearance: String { value("Dark") }
    static var systemAppearance: String { value("System") }
    static var settings: String { value("Settings…") }
    static var syncNow: String { value("Sync now") }
    static var status: String { value("Status") }
    static var lastSynced: String { value("Last synced") }
    static var latest: String { value("Latest") }
    static var enabled: String { value("Enabled") }
    static var syncWhenFolderAChanges: String { value("Sync when Folder A changes") }
    static var syncWhenFolderBChanges: String { value("Sync when Folder B changes") }
    static var waitForFilesToFinish: String { value("Wait for files to finish before syncing") }
    static var automaticSyncSettings: String { value("Automatic execution") }
    static var launchSyncSettings: String { value("Sync on app launch") }
    static var syncOnLaunch: String { value("Sync this list when FolderSync starts") }
    static var syncOnLaunchDescription: String { value("Runs this sync list once when FolderSync opens.") }
    static var enableAutomaticSync: String { value("Enable automatic sync") }
    static var fileHandlingSettings: String { value("File handling") }
    static var automaticSyncTwoWayUnavailable: String { value("Automatic folder monitoring is unavailable for two-way sync.") }
    static var deleteFilesTwoWayUnavailable: String { value("Delete-extra file cleanup is unavailable for two-way sync.") }
    static var syncWhenFolderAChangesDescription: String { value("Runs automatically when Folder A changes.") }
    static var syncWhenFolderBChangesDescription: String { value("Runs automatically when Folder B changes.") }
    static var includeHiddenFilesDescription: String { value("Include hidden files and folders in the sync.") }
    static var maximumFileSizeDescription: String { value("Files larger than the selected limit are skipped.") }
    static var waitForFileOperations: String { value("Wait for file operations to finish before every sync") }
    static var waitForFileOperationsDescription: String { value("Applies to every sync list. The default is on to avoid syncing incomplete files.") }
    static var automaticAction: String { value("Automatic action") }
    static var automaticTrigger: String { value("Run when") }
    static var fileChangesTrigger: String { value("When files change") }
    static var intervalTrigger: String { value("On a schedule") }
    static var syncInterval: String { value("Repeat") }
    static var intervalSyncDescription: String { value("Starts after the selected interval and repeats while automatic sync is enabled.") }
    static var intervalSyncToggleDescription: String { value("Runs automatically according to the selected interval.") }
    static var syncChanges: String { value("Sync changes") }
    static var transferChanges: String { value("Transfer changes") }
    static var latestActivity: String { value("Latest activity") }
    static var advancedOptions: String { value("Advanced options") }
    static var includeHiddenFiles: String { value("Include hidden files") }
    static var excludeNestedDestination: String { value("Exclude nested destination folder") }
    static var excludeNestedDestinationDescription: String { value("When the destination is inside the source, exclude that nested folder from the source scan.") }
    static var deleteFilesOnlyInFolderA: String { value("Delete files found only in Folder A") }
    static var deleteFilesOnlyInFolderB: String { value("Delete files found only in Folder B") }
    static var maximumFileSize: String { value("Maximum file size") }
    static var noFileSizeLimit: String { value("No limit") }
    static var oneHundredMegabytes: String { value("100 MB") }
    static var oneGigabyte: String { value("1 GB") }
    static var fiveGigabytes: String { value("5 GB") }
    static var newFolderPair: String { value("New sync") }
    static var name: String { value("Name") }
    static var namePrompt: String { value("e.g. Downloads Backup") }
    static var cancel: String { value("Cancel") }
    static var done: String { value("Done") }
    static var openFolderSync: String { value("Open FolderSync") }
    static var quitFolderSync: String { value("Quit FolderSync") }
    static var syncDirection: String { value("Sync direction") }
    static var folderA: String { value("Folder A") }
    static var folderB: String { value("Folder B") }
    static var folderAOrGitHub: String { value("Folder A or GitHub URL") }
    static var folderBOrGitHub: String { value("Folder B or GitHub URL") }
    static var localFolderOnly: String { value("Local folder only") }
    static var chooseFolderA: String { value("Choose Folder A") }
    static var chooseFolderB: String { value("Choose Folder B") }
    static var changeEndpoint: String { value("Edit endpoint") }
    static var cancelFolderSelection: String { value("Cancel folder selection") }
    static var changeFolder: String { value("Change folder") }
    static var folderRowHint: String { value("Click to choose a folder or Finder-connected drive, or drag a folder here") }
    static var folderPickerTitle: String { value("Choose a folder or Finder-connected drive") }
    static var folderPickerMessage: String { value("iCloud Drive, Google Drive, OneDrive, Dropbox, NAS, and other Finder-connected locations can be selected here.") }
    static var invalidFolderDrop: String { value("The dropped item is not an accessible folder.") }
    static var aToB: String { value("A → B") }
    static var bToA: String { value("B → A") }
    static var twoWay: String { value("A ↔ B") }
    static var twoWaySafetyMessage: String { value("Two-way transfer is not available until conflict handling is enabled.") }
    static var twoWayUnavailable: String { value("Two-way sync is not available yet. Choose a one-way direction.") }
    static var changeToOneWay: String { value("Change to A → B") }
    static var transferCannotDeleteExtraFiles: String { value("Automatic transfer cannot be combined with delete-extra cleanup.") }
    static var githubSync: String { value("GitHub sync") }
    static var githubAccount: String { value("GitHub account") }
    static var githubRepositoryManagement: String { value("GitHub repository management") }
    static var githubRepositoryManagementDescription: String { value("Create and manage your GitHub repositories from FolderSync.") }
    static var githubRepositoryEdit: String { value("Edit repository") }
    static var githubRepositorySaveChanges: String { value("Save changes") }
    static var githubRepositoryUpdating: String { value("Saving changes…") }
    static var githubRepositoryUpdateFailed: String { value("Could not update the GitHub repository.") }
    static func githubRepositoryUpdateFailedWithOutput(_ output: String) -> String {
        String(format: value("Could not update the GitHub repository: %@"), output)
    }
    static var githubRepositoryInvalidUpdateResponse: String { value("GitHub returned an unexpected response after updating the repository.") }
    static var githubConnect: String { value("Connect a GitHub repository") }
    static var githubCreateOnly: String { value("Sync Folder A directly to GitHub") }
    static var githubDirectSyncDescription: String { value("The GitHub endpoint is synced through an app-managed Git repository. The selected direction determines push or pull. Automatic mode watches local changes for uploads or checks GitHub at the configured interval for downloads.") }
    static var githubRepositoryURL: String { value("Repository URL") }
    static var githubRepositoryURLPrompt: String { value("https://github.com/account/repository.git") }
    static var githubChooseRepository: String { value("Choose a repository") }
    static var githubCreateRepository: String { value("Create repository") }
    static var githubNewRepository: String { value("New GitHub repository") }
    static var githubRepositoryName: String { value("Repository name") }
    static var githubRepositoryNamePrompt: String { value("my-project") }
    static var githubRepositoryDescription: String { value("Description") }
    static var githubRepositoryDescriptionPrompt: String { value("What is this repository for?") }
    static var githubRepositoryOwner: String { value("Account") }
    static var githubPersonalAccount: String { value("Personal account") }
    static var githubOrganizationsLoading: String { value("Loading organizations…") }
    static var githubOrganizationsUnavailable: String { value("Organizations could not be loaded. You can still create a personal repository.") }
    static var githubVisibility: String { value("Visibility") }
    static var githubPublic: String { value("Public") }
    static var githubPrivate: String { value("Private") }
    static var githubCreateRepositoryHelp: String { value("The repository will be created empty. Files are not uploaded automatically.") }
    static var githubCreatingRepository: String { value("Creating repository…") }
    static var githubRefreshRepositories: String { value("Refresh repositories") }
    static var githubSearchRepositories: String { value("Search repositories") }
    static var githubRepositoriesLoading: String { value("Loading repositories…") }
    static var githubNoRepositories: String { value("No repositories available.") }
    static var githubNoMatchingRepositories: String { value("No matching repositories.") }
    static var githubArchivedRepository: String { value("Archived") }
    static var githubCommitMessage: String { value("Commit message") }
    static var githubCommitMessagePrompt: String { value("Sync changes from FolderSync") }
    static var githubRemotePollInterval: String { value("Check GitHub every") }
    static var githubAutomaticPullDescription: String { value("Checks GitHub at the selected interval and downloads completed changes.") }
    static func githubRemotePollIntervalLabel(_ minutes: Int) -> String {
        if minutes == 0 { return value("Do not check automatically") }
        return String(format: value("Every %d minutes"), minutes)
    }
    static var githubPushNow: String { value("Push to GitHub") }
    static var githubSyncNow: String { sync }
    static var githubLogIn: String { value("Log in with GitHub") }
    static var githubLoginHelp: String { value("A browser will open. The one-time code is copied to your clipboard; paste it at GitHub and use any supported sign-in method, including Google, Apple, passkeys, or two-factor authentication.") }
    static var githubConnected: String { value("GitHub connected") }
    static var githubNotLoggedIn: String { value("Not signed in") }
    static var githubCheckingLogin: String { value("Checking GitHub login…") }
    static var githubLoggingIn: String { value("Complete GitHub login in your browser.") }
    static var githubCLIUnavailable: String { value("Install GitHub CLI to sign in with GitHub.") }
    static var generalSettings: String { value("General") }
    static var localAPI: String { value("Local API") }
    static var localAPIDescription: String { value("FolderSync starts a local HTTP API automatically when the app launches. Other apps on this Mac can start syncs and read their status through 127.0.0.1:8765.") }
    static var localAPIUsage: String { value("How to use") }
    static var localAPIStepOne: String { value("Keep FolderSync running. The API is available automatically; no separate server command is needed.") }
    static var localAPIStepTwo: String { value("Call the start endpoint. Omit pairId to use the sync list currently selected in FolderSync, or send a specific pairId.") }
    static var localAPIStepThree: String { value("Save the returned jobId and poll the job endpoint until the status becomes completed or failed.") }
    static var localAPIEndpoints: String { value("Endpoints") }
    static var localAPIHealth: String { value("Connection check") }
    static var localAPIStart: String { value("Start sync") }
    static var localAPIJobs: String { value("List jobs") }
    static var localAPIJobStatus: String { value("Job status") }
    static var localAPIExamples: String { value("Usage examples") }
    static var localAPIHealthExample: String { value("Check the API") }
    static var localAPIStartExample: String { value("Start the selected sync") }
    static var localAPIStatusExample: String { value("Read a job") }
    static var localAPIStatuses: String { value("Status values") }
    static var localAPIQueued: String { value("Waiting to start") }
    static var localAPIRunning: String { value("Sync is in progress") }
    static var localAPICompleted: String { value("Sync finished successfully") }
    static var localAPIFailed: String { value("Sync failed; the response includes error and finishedAt") }
    static var localAPISecurityNote: String { value("The API listens only on 127.0.0.1, so it is not exposed directly to the internet. It controls the same selected workspace and sync engine as the FolderSync app.") }
    static var mcpServer: String { value("ChatGPT MCP server") }
    static var mcpServerDescription: String { value("ChatGPT developer-mode apps do not launch local MCP programs directly. Use Secure MCP Tunnel to connect FolderSync privately.") }
    static var mcpChatGPTConnection: String { value("ChatGPT connection") }
    static var mcpRequiredValues: String { value("Values to prepare") }
    static var mcpTunnelManagementPage: String { value("Tunnel ID: OpenAI Platform Tunnels") }
    static var mcpRuntimeKeyPage: String { value("Runtime API key: Organization API keys") }
    static var mcpStepCreateTunnel: String { value("Open the Tunnels management page below, choose Create tunnel, and create a tunnel. Copy the ID shown after creation; it starts with tunnel_. Do not invent this value or use the API key here.") }
    static var mcpStepConfigureTunnel: String { value("Create or use a runtime API key from the API keys page below. In Terminal, set CONTROL_PLANE_API_KEY to that key. Do not use an organization admin key, and never paste the key into FolderSync or ChatGPT.") }
    static var mcpStepRunTunnel: String { value("Replace <TUNNEL_ID> in the setup command with the copied tunnel_… ID, then run it once. Run the doctor command to check the profile, then run the Tunnel command and keep that Terminal window open while ChatGPT uses FolderSync.") }
    static var mcpStepConnectChatGPT: String { value("In ChatGPT on the web, open the developer-mode custom app creation screen. Choose Connection → Tunnel instead of Server URL, select the same Tunnel, scan the tools, and create or enable the app. A workspace admin may need to enable developer mode or approve it.") }
    static var mcpStepWorkspace: String { value("Before asking ChatGPT to work, select the FolderSync sync list you want to use. MCP can read and change files only inside that list's local folder. For GitHub edits that must arrive locally, configure the direction as GitHub → local.") }
    static var mcpStepFinalizeGitHubSync: String { value("When ChatGPT finishes editing GitHub, ask it to call finalize_github_sync as the last step. This pulls the completed GitHub source into the selected local folder. If the Mac is off or tunnel-client is stopped, run the command after reconnecting.") }
    static var mcpTunnelSetupCommand: String { value("Tunnel setup command") }
    static var mcpTunnelDoctorCommand: String { value("Tunnel profile check") }
    static var mcpTunnelRunCommand: String { value("Tunnel run command") }
    static var mcpChatGPTRegistrationSteps: String { value("Create a Tunnel in OpenAI Platform, replace <TUNNEL_ID> in the setup command, and set CONTROL_PLANE_API_KEY in Terminal. Run both commands above and keep tunnel-client running while ChatGPT scans or calls the tools. In ChatGPT's developer-mode app registration screen, choose Connection → Tunnel instead of Server URL, select the same Tunnel, and scan the tools. The Tunnel must be associated with the target ChatGPT workspace. Never enter the API key in FolderSync.") }
    static var mcpLocalClientDetails: String { value("For local MCP clients that support stdio") }
    static var mcpCommand: String { value("Command") }
    static var mcpArguments: String { value("Arguments") }
    static var mcpWorkingDirectory: String { value("Working directory") }
    static var mcpLeaveEmpty: String { value("Leave empty") }
    static var mcpRegistrationSteps: String { value("For a local MCP client that launches commands directly, enter the first value in Command, --mcp in Arguments, and leave Working directory empty. Select the displayed text to copy it.") }
    static var githubLoginFailed: String { value("GitHub login failed.") }
    static var githubLoginTimedOut: String { value("GitHub login timed out.") }
    static var githubBrowserOpenFailed: String { value("Could not open the GitHub login page.") }
    static var githubRepositoryLoginRequired: String { value("Sign in to GitHub to load your repositories.") }
    static var githubRepositoryFetchFailed: String { value("Could not load GitHub repositories.") }
    static func githubRepositoryFetchFailedWithOutput(_ output: String) -> String {
        String(format: value("Could not load GitHub repositories: %@"), output)
    }
    static var githubRepositoryInvalidResponse: String { value("GitHub returned an unexpected repository list.") }
    static var githubRepositoryCreateFailed: String { value("Could not create the GitHub repository.") }
    static func githubRepositoryCreateFailedWithOutput(_ output: String) -> String {
        String(format: value("Could not create the GitHub repository: %@"), output)
    }
    static var githubRepositoryInvalidCreationResponse: String { value("GitHub returned an unexpected response after creating the repository.") }
    static func githubLoginFailedWithOutput(_ output: String) -> String {
        String(format: value("GitHub login failed: %@"), output)
    }
    static var githubBothEndpointsInvalid: String { value("Choose a folder on one side and a GitHub repository on the other.") }
    static var githubLocalFolderRequired: String { value("Choose a local folder for the other side.") }
    static var githubNotConfigured: String { value("Add a GitHub repository URL to enable pushing.") }
    static var githubStatusNotRepository: String { value("Folder A is not connected to a Git repository yet.") }
    static var githubStatusNoChanges: String { value("No local changes to push.") }
    static var githubStatusReady: String { value("Ready to push") }
    static var githubGitNotAvailable: String { value("Git is not available on this Mac.") }
    static var githubRsyncNotAvailable: String { value("rsync is not available on this Mac.") }
    static var githubInvalidRepositoryURL: String { value("Enter a valid HTTPS GitHub repository URL.") }
    static var githubAuthenticationRequired: String { value("Sign in to GitHub in app settings before syncing.") }
    static func githubMirrorIsNotRepository(_ path: String) -> String { format("The app-managed GitHub mirror is not a Git repository: %@", path) }
    static var githubMirrorIsInsideSource: String { value("The GitHub mirror cannot be inside Folder A.") }
    static var githubRemoteMismatch: String { value("The saved GitHub repository does not match the mirror repository.") }
    static var githubNoBranch: String { value("The Git repository does not have an active branch.") }
    static var githubRemoteAhead: String { value("GitHub has newer commits. Pull or resolve the changes before pushing.") }
    static var githubCommandTimedOut: String { value("The Git command timed out.") }
    static var githubCommandFailed: String { value("Git command failed.") }

    static func githubCommandFailedWithOutput(_ output: String) -> String {
        String(format: value("Git command failed: %@"), output)
    }

    static func githubSyncStarted(_ name: String) -> String { format("GitHub sync started: %@", name) }
    static func githubPushCompleted(_ name: String) -> String { format("GitHub push completed: %@", name) }
    static func githubSyncFailed(_ name: String) -> String { format("GitHub sync failed: %@", name) }
    static func githubMonitoringStarted(_ name: String) -> String { format("GitHub monitoring started: %@", name) }
    static func githubMonitoringFailed(_ name: String) -> String { format("GitHub monitoring failed: %@", name) }

    static var idle: String { value("Idle") }
    static var syncing: String { value("Syncing…") }
    static var waitingForFolder: String { value("Waiting for folder") }
    static var completed: String { value("Completed") }
    static var error: String { value("Error") }

    static func syncStarted(_ name: String) -> String {
        format("Sync started: %@", name)
    }

    static func syncCompleted(_ name: String) -> String {
        format("Sync completed: %@", name)
    }

    static func waitingForFolder(_ name: String) -> String {
        format("Waiting for folder: %@", name)
    }

    static func syncFailed(_ name: String, _ message: String) -> String {
        String(format: value("Sync failed (%@): %@"), name, message)
    }

    static func syncFailed(_ name: String) -> String {
        format("Sync failed: %@", name)
    }

    static func deleteFilesWarning(_ targetFolder: String, _ sourceFolder: String) -> String {
        String(format: value("Files only in %@, and not in %@, may be deleted."), targetFolder, sourceFolder)
    }

    static func deleteFilesDescription(_ sourceFolder: String, _ targetFolder: String) -> String {
        String(format: value("Delete files found only in %@. This aligns %@ with %@."), targetFolder, targetFolder, sourceFolder)
    }

    static func syncChangesDescription(_ fromFolder: String, _ toFolder: String) -> String {
        String(format: value("Copy changes from %@ to %@ and keep the originals."), fromFolder, toFolder)
    }

    static func transferActionDescription(_ fromFolder: String, _ toFolder: String) -> String {
        String(format: value("Move completed files from %@ to %@ and remove them from the source."), fromFolder, toFolder)
    }

    static func everyMinutes(_ minutes: Int) -> String {
        String(format: value("Every %d minutes"), minutes)
    }

    static func realtimeMonitoringFailed(_ name: String) -> String {
        format("Real-time monitoring failed: %@", name)
    }

    static func realtimeMonitoringStarted(_ name: String) -> String {
        format("Real-time monitoring started: %@", name)
    }

    static func realtimeMonitoringUnavailable(_ name: String, _ message: String) -> String {
        String(format: value("Real-time monitoring unavailable (%@): %@"), name, message)
    }

    static func realtimeMonitoringUnavailable(_ name: String) -> String {
        format("Real-time monitoring unavailable: %@", name)
    }

    static func inputFolderIsNotDirectory(_ path: String) -> String {
        format("The selected folder is not accessible: %@", path)
    }

    static func outputFolderIsNotDirectory(_ path: String) -> String {
        format("The selected folder is not accessible: %@", path)
    }

    static var unsafeFolderRelationship: String {
        value("Folder A and Folder B cannot contain one another.")
    }

    static var rsyncFailed: String { value("rsync failed.") }

    static func staleBookmark(_ path: String) -> String {
        format("Folder permission needs to be renewed: %@", path)
    }

    static func inaccessibleFolder(_ path: String) -> String {
        format("Folder is unavailable: %@", path)
    }

    static func accessDenied(_ path: String) -> String {
        format("Folder permission was denied: %@", path)
    }

    static func invalidBookmark(_ path: String) -> String {
        format("Saved folder access is invalid. Choose the folder again: %@", path)
    }

    private static let localizationBundle: Bundle = {
        .module
    }()

    private static func value(_ key: String) -> String {
        String(localized: String.LocalizationValue(key), bundle: localizationBundle, locale: .current)
    }

    private static func format(_ key: String, _ value: String) -> String {
        String(format: self.value(key), value)
    }
}

extension SyncMode {
    var title: String {
        switch self {
        case .aToB: AppText.aToB
        case .bToA: AppText.bToA
        case .twoWay: AppText.twoWay
        }
    }

}

extension MaxFileSize {
    var title: String {
        switch self {
        case .unlimited: AppText.noFileSizeLimit
        case .megabytes100: AppText.oneHundredMegabytes
        case .gigabyte: AppText.oneGigabyte
        case .gigabytes5: AppText.fiveGigabytes
        }
    }
}

extension RealtimeAction {
    var title: String {
        switch self {
        case .sync: AppText.syncChanges
        case .transfer: AppText.transferChanges
        }
    }
}

extension AutomaticSyncTrigger {
    var title: String {
        switch self {
        case .fileChanges: AppText.fileChangesTrigger
        case .interval: AppText.intervalTrigger
        }
    }
}
