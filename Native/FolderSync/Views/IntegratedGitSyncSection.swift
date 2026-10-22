import SwiftUI

struct IntegratedGitSyncSection: View {
    let pair: FolderPair
    let store: FolderPairStore
    @State private var isEditing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Git Sync").font(.headline)
                Spacer()
                Button("Git 설정…") { isEditing = true }
            }
            Text("기존 동기화 방향으로 로컬 Git 저장소를 Pull / Push합니다. 양방향은 fast-forward 가능한 경우에 실행합니다.")
                .font(.caption).foregroundStyle(.secondary)
            Toggle(AppText.syncOnLaunch, isOn: Binding(
                get: { pair.syncOnLaunch }, set: { store.setSyncOnLaunch($0, for: pair) }))
            Toggle(AppText.enableAutomaticSync, isOn: Binding(
                get: { pair.isRealtimeEnabled }, set: { store.setRealtimeEnabled($0, for: pair) }))
            if pair.isRealtimeEnabled, let endpoint = pair.githubSync {
                Picker(AppText.githubRemotePollInterval, selection: Binding(
                    get: { endpoint.remotePollIntervalMinutes },
                    set: { minutes in
                        var updated = endpoint
                        updated.remotePollIntervalMinutes = minutes
                        store.setGitHubSync(updated, for: pair)
                    })) {
                    ForEach(GitHubSyncConfiguration.remotePollIntervalOptions, id: \.self) {
                        Text(AppText.githubRemotePollIntervalLabel($0)).tag($0)
                    }
                }
            }
            if let job = store.gitSyncStore.latestJob(syncID: pair.id) {
                Text(job.errorMessage ?? "\(job.phase.rawValue) · Commit \(job.commitCount) · 파일 \(job.fileCount)")
                    .font(.caption).textSelection(.enabled)
                if !job.isFinished {
                    Button("취소") { Task { await store.gitSyncStore.cancel(jobID: job.id) } }
                }
            }
        }
        .sheet(isPresented: $isEditing) {
            if let configuration = store.integratedGitConfiguration(for: pair) {
                GitSyncEditor(store: store.gitSyncStore, configuration: configuration, onSave: { _ in }, integrated: true)
            }
        }
    }
}
