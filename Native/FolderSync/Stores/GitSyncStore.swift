import Foundation
import Observation

@MainActor @Observable
final class GitSyncStore {
    private(set) var configurations: [GitSyncConfiguration] = []
    private(set) var jobs: [GitSyncJob] = []
    @ObservationIgnored private var tasks: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private let storage: UserDefaults
    @ObservationIgnored private let service: GitSyncService

    init(storage: UserDefaults = UserDefaults(suiteName: "com.pdg.FolderSync") ?? .standard, service: GitSyncService = GitSyncService()) {
        self.storage = storage
        self.service = service
        if let data = storage.data(forKey: "gitSyncConfigurations") { configurations = (try? JSONDecoder().decode([GitSyncConfiguration].self, from: data)) ?? [] }
        if let data = storage.data(forKey: "gitSyncJobs") { jobs = (try? JSONDecoder().decode([GitSyncJob].self, from: data)) ?? [] }
        for index in jobs.indices where !jobs[index].isFinished {
            jobs[index].phase = .interrupted
            jobs[index].success = false
            jobs[index].errorCode = .interrupted
            jobs[index].errorMessage = GitSyncFailure(code: .interrupted).message
            jobs[index].endedAt = Date()
        }
        persist()
    }

    func add(_ configuration: GitSyncConfiguration) {
        guard !configurations.contains(where: { $0.id == configuration.id }) else { return }
        configurations.append(configuration)
        persist()
    }
    func update(_ configuration: GitSyncConfiguration) {
        guard let index = configurations.firstIndex(where: { $0.id == configuration.id }) else { return }
        configurations[index] = configuration
        persist()
    }
    func remove(_ configuration: GitSyncConfiguration) {
        configurations.removeAll { $0.id == configuration.id }
        persist()
    }
    func inspect(folder: FolderReference) async throws -> GitSyncRepository { try await service.inspect(folder: folder) }
    func detect(folder: FolderReference, remote: String = "", branch: String = "") async throws -> GitSyncRepository {
        try await service.detect(folder: folder, remote: remote, branch: branch)
    }
    func job(id: UUID) -> GitSyncJob? { jobs.first { $0.id == id } }
    func latestJob(syncID: UUID) -> GitSyncJob? { jobs.first { $0.syncID == syncID } }

    @discardableResult
    func start(syncID: UUID, direction: GitSyncDirection? = nil) throws -> GitSyncJob {
        guard let configuration = configurations.first(where: { $0.id == syncID }) else { throw GitSyncFailure(code: .unknownConfiguration) }
        let requested = direction ?? configuration.direction
        if let running = jobs.first(where: { $0.syncID == syncID && !$0.isFinished }) {
            guard running.direction == requested else { throw GitSyncFailure(code: .repositoryBusy) }
            return running
        }
        let job = GitSyncJob(syncID: syncID, direction: requested)
        jobs.insert(job, at: 0)
        if let index = configurations.firstIndex(where: { $0.id == syncID }) { configurations[index].lastRunAt = job.startedAt }
        persist()
        tasks[job.id] = Task { [weak self, service] in
            let result = await service.run(configuration: configuration, job: job) { [weak self] phase in
                await self?.setPhase(jobID: job.id, phase: phase)
            }
            guard let self else { return }
            if let index = self.jobs.firstIndex(where: { $0.id == job.id }) { self.jobs[index] = result }
            if result.succeeded, let index = self.configurations.firstIndex(where: { $0.id == syncID }) { self.configurations[index].lastSuccessAt = result.endedAt }
            self.tasks[job.id] = nil
            self.persist()
        }
        return job
    }
    func wait(jobID: UUID) async -> GitSyncJob? {
        await tasks[jobID]?.value
        return job(id: jobID)
    }
    @discardableResult
    func cancel(jobID: UUID) async -> GitSyncJob? {
        tasks[jobID]?.cancel()
        return await wait(jobID: jobID)
    }
    private func setPhase(jobID: UUID, phase: GitSyncPhase) {
        if let index = jobs.firstIndex(where: { $0.id == jobID }) { jobs[index].phase = phase; persist() }
    }
    private func persist() {
        if let data = try? JSONEncoder().encode(configurations) { storage.set(data, forKey: "gitSyncConfigurations") }
        if let data = try? JSONEncoder().encode(jobs) { storage.set(data, forKey: "gitSyncJobs") }
    }
}
