import Foundation

enum GitSyncDirection: String, Codable, CaseIterable, Sendable { case pull, push, bidirectional }
enum GitSyncPhase: String, Codable, Sendable {
    case queued, checking, fetching, committing, pulling, pushing, verifying, completed, failed, cancelled, interrupted
    var isFinished: Bool { [.completed, .failed, .cancelled, .interrupted].contains(self) }
}
enum GitSyncErrorCode: String, Codable, Sendable {
    case notRepository, missingRemote, missingUpstream, detachedHead, authenticationFailed, networkFailed
    case dirtyWorktree, stagedChanges, diverged, repositoryBusy, repositoryChanged, pushRejected
    case sensitiveFile, cancelled, interrupted, commandFailed, timedOut, unknownConfiguration
}
struct GitSyncFailure: LocalizedError, Sendable {
    let code: GitSyncErrorCode
    var errorDescription: String? { message }
    var message: String {
        switch code {
        case .notRepository: "선택한 폴더가 Git 작업 저장소가 아닙니다."
        case .missingRemote: "원격 저장소를 선택해 주세요."
        case .missingUpstream: "추적할 원격 브랜치를 선택해 주세요."
        case .detachedHead: "브랜치를 체크아웃한 뒤 다시 실행해 주세요."
        case .authenticationFailed: "Git 인증에 실패했습니다. 시스템 Git 인증을 확인해 주세요."
        case .networkFailed: "원격 저장소에 연결할 수 없습니다."
        case .dirtyWorktree: "로컬 변경 사항을 보존하기 위해 Pull을 중단했습니다."
        case .stagedChanges: "기존 staged 변경 사항이 있어 자동 Commit을 중단했습니다."
        case .diverged: "로컬과 원격 이력이 갈라졌습니다. 직접 병합한 뒤 다시 실행해 주세요."
        case .repositoryBusy: "이 저장소에서 다른 Git 작업이 진행 중입니다."
        case .repositoryChanged: "실행 중 저장소가 변경되어 작업을 중단했습니다."
        case .pushRejected: "원격이 Push를 거절했습니다. 원격 상태를 확인해 주세요."
        case .sensitiveFile: "민감정보가 의심되는 파일이 있어 자동 Commit을 중단했습니다. 포함·제외 규칙을 확인해 주세요."
        case .cancelled: "작업이 취소되었습니다. 이미 완료된 Commit 및 Push는 유지됩니다."
        case .interrupted: "앱 종료로 중단된 작업입니다. 저장소 상태를 확인해 주세요."
        case .timedOut: "Git 명령 제한 시간을 초과했습니다."
        case .unknownConfiguration: "등록된 Git Sync 항목을 찾을 수 없습니다."
        case .commandFailed: "Git 명령이 실패했습니다. 로컬 Git 상태를 확인해 주세요."
        }
    }
}
struct GitSyncConfiguration: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    var name: String
    var folder: FolderReference
    var remote = ""
    var branch = ""
    var direction: GitSyncDirection = .bidirectional
    var autoCommit = false
    var includePatterns: [String] = []
    var excludePatterns: [String] = []
    var commitMessage = "Sync changes from LinkDeck"
    var lastRunAt: Date?
    var lastSuccessAt: Date?
}
struct GitSyncRepository: Sendable {
    var rootPath: String
    var commonDirectory: String
    var gitDirectory: String
    var localBranch: String
    var remote: String
    var branch: String
    var remotes: [String]
    var branches: [String] = []
}
struct GitSyncStepResult: Codable, Sendable {
    var phase: GitSyncPhase
    var success: Bool
    var message: String
}
struct GitSyncJob: Identifiable, Codable, Sendable {
    var id = UUID()
    var syncID: UUID
    var direction: GitSyncDirection
    var phase: GitSyncPhase = .queued
    var success: Bool?
    var errorCode: GitSyncErrorCode?
    var errorMessage: String?
    var startedAt = Date()
    var endedAt: Date?
    var steps: [GitSyncStepResult] = []
    var commitCount = 0
    var fileCount = 0
    var verifiedAt: Date?
    var localHEAD: String?
    var remoteHEAD: String?
    var isFinished: Bool { phase.isFinished }
    var succeeded: Bool { success == true }
}
