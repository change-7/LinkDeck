import SwiftUI

struct GitSyncWorkspaceView: View {
    @Environment(\.colorScheme) private var colorScheme
    let folderStore: FolderPairStore
    private var store: GitSyncStore { folderStore.gitSyncStore }
    private var theme: MacAppearance { MacAppearance(scheme: colorScheme) }
    @State private var selection: UUID?
    @State private var isAdding = false
    @State private var editing: GitSyncConfiguration?
    @State private var errorMessage: String?

    var body: some View {
        HStack(spacing: 12) {
            ScrollView {
                if let configuration = store.configurations.first(where: { $0.id == selection }) {
                    detail(configuration)
                } else {
                    ContentUnavailableView {
                        Label("Git Sync", systemImage: "arrow.triangle.branch")
                    } description: {
                        Text("기존 로컬 Git 저장소를 등록해 Pull, Push 또는 양방향 동기화를 실행하세요.")
                    } actions: {
                        Button("Git 저장소 추가") { isAdding = true }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(theme.panel, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(theme.border))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            VStack {
                HStack {
                    Text("Git Sync").font(.headline)
                    Spacer()
                    Button(AppText.add, systemImage: "plus") { isAdding = true }
                        .accessibilityIdentifier("git-sync-add")
                }
                List(selection: $selection) {
                    ForEach(store.configurations) { configuration in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(configuration.name).font(.headline)
                            Text("\(configuration.remote)/\(configuration.branch)")
                                .font(.caption).foregroundStyle(.secondary)
                            Text(store.latestJob(syncID: configuration.id)?.phase.uiTitle ?? "대기 중")
                                .font(.caption)
                        }
                        .tag(configuration.id)
                    }
                }
                .listStyle(.sidebar)
            }
            .padding(12)
            .frame(width: 250)
            .background(theme.panel, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(theme.border))
        }
        .padding(12)
        .background(theme.canvas, in: RoundedRectangle(cornerRadius: 12))
        .foregroundStyle(theme.foreground)
        .tint(theme.accent)
        .onAppear { selection = selection ?? store.configurations.first?.id }
        .onChange(of: selection) { _, _ in errorMessage = nil }
        .sheet(isPresented: $isAdding) {
            GitSyncEditor(store: store, configuration: nil) { selection = $0 }
        }
        .sheet(item: $editing) { configuration in
            GitSyncEditor(store: store, configuration: configuration) { selection = $0 }
        }
        .accessibilityIdentifier("git-sync-workspace")
    }

    private func detail(_ configuration: GitSyncConfiguration) -> some View {
        let latest = store.latestJob(syncID: configuration.id)
        let running = latest.map { $0.endedAt == nil } ?? false
        return VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label(configuration.name, systemImage: "arrow.triangle.branch").font(.title2)
                Spacer()
                Button("편집") { editing = configuration }
                    .disabled(running)
                Button(AppText.delete, role: .destructive) {
                    store.remove(configuration)
                    for pair in folderStore.pairs where pair.gitSyncLink?.syncID == configuration.id {
                        folderStore.setGitSyncLink(nil, for: pair)
                    }
                    selection = store.configurations.first?.id
                }
                .disabled(running)
            }
            Text(configuration.folder.displayPath).textSelection(.enabled)
            LabeledContent("원격 / 브랜치", value: "\(configuration.remote) / \(configuration.branch)")
            LabeledContent("방향", value: configuration.direction.uiTitle)
            LabeledContent("자동 Commit", value: configuration.autoCommit ? "사용" : "사용 안 함")
            HStack {
                Button(AppText.syncNow, systemImage: "arrow.triangle.2.circlepath") {
                    do {
                        errorMessage = nil
                        _ = try store.start(syncID: configuration.id)
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(running)
                .accessibilityIdentifier("git-sync-run")
                if let latest, running {
                    ProgressView().controlSize(.small)
                    Button(AppText.cancel) { Task { _ = await store.cancel(jobID: latest.id) } }
                        .accessibilityIdentifier("git-sync-cancel")
                }
                Text(latest?.phase.uiTitle ?? "대기 중")
            }
            if let errorMessage { Text(errorMessage).foregroundStyle(.red).textSelection(.enabled) }
            if let lastRunAt = configuration.lastRunAt {
                LabeledContent("마지막 실행", value: lastRunAt.formatted(date: .abbreviated, time: .shortened))
            }
            if let lastSuccessAt = configuration.lastSuccessAt {
                LabeledContent("마지막 성공", value: lastSuccessAt.formatted(date: .abbreviated, time: .shortened))
            }
            if let latest, let message = latest.errorMessage {
                Text(latest.errorCode == .diverged ? "충돌로 중단: \(message)" : message)
                    .foregroundStyle(.red).textSelection(.enabled)
            }
            let linked = folderStore.pairs.filter { $0.gitSyncLink?.syncID == configuration.id }
            GroupBox("FolderSync 연결") {
                VStack(alignment: .leading, spacing: 8) {
                    if linked.isEmpty {
                        Text("연결 없음. 폴더 탭의 Git Sync 연계에서 실행 순서와 방향을 선택할 수 있습니다.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(linked) { pair in
                        Text("\(pair.name) · \(pair.gitSyncLink?.position == .before ? "폴더 동기화 전" : "폴더 동기화 후")")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            Text("실행 기록").font(.headline)
            ForEach(store.jobs.filter { $0.syncID == configuration.id }.sorted { $0.startedAt > $1.startedAt }) { job in
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("작업 ID: \(job.id.uuidString)").textSelection(.enabled)
                        Text("커밋 \(job.commitCount)개 · 파일 \(job.fileCount)개")
                        if let endedAt = job.endedAt {
                            Text("종료: \(endedAt.formatted(date: .abbreviated, time: .standard))")
                        }
                        if let code = job.errorCode { Text("오류: \(code.rawValue)").foregroundStyle(.red) }
                        if let message = job.errorMessage { Text(message).foregroundStyle(.red).textSelection(.enabled) }
                        ForEach(Array(job.steps.enumerated()), id: \.offset) { _, step in
                            Label("\(step.phase.uiTitle): \(step.message)", systemImage: step.success ? "checkmark.circle" : "xmark.circle")
                        }
                        if let verifiedAt = job.verifiedAt {
                            Text("검증: \(verifiedAt.formatted(date: .abbreviated, time: .standard))")
                        }
                        if let head = job.localHEAD { Text("로컬 HEAD: \(head)").textSelection(.enabled) }
                        if let head = job.remoteHEAD { Text("원격 HEAD: \(head)").textSelection(.enabled) }
                    }
                    .font(.caption)
                    .frame(maxWidth: .infinity, alignment: .leading)
                } label: {
                    Text("\(job.startedAt.formatted(date: .abbreviated, time: .shortened)) · \(job.phase.uiTitle)")
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct GitSyncLinkSection: View {
    let pair: FolderPair
    let store: FolderPairStore

    var body: some View {
        DisclosureGroup("Git Sync 연계") {
            VStack(alignment: .leading, spacing: 8) {
                Picker("Git 항목", selection: Binding(
                    get: { pair.gitSyncLink?.syncID },
                    set: { id in
                        store.setGitSyncLink(id.map {
                            GitSyncLink(syncID: $0, position: pair.gitSyncLink?.position ?? .before,
                                        direction: pair.gitSyncLink?.direction)
                        }, for: pair)
                    }
                )) {
                    Text("사용 안 함").tag(nil as UUID?)
                    ForEach(store.gitSyncStore.configurations) { configuration in
                        Text(configuration.name).tag(Optional(configuration.id))
                    }
                    if let id = pair.gitSyncLink?.syncID, !store.gitSyncStore.configurations.contains(where: { $0.id == id }) {
                        Text("삭제된 Git 항목").tag(Optional(id))
                    }
                }
                if let link = pair.gitSyncLink {
                    Picker("실행 순서", selection: Binding(
                        get: { link.position },
                        set: { store.setGitSyncLink(GitSyncLink(syncID: link.syncID, position: $0, direction: link.direction), for: pair) }
                    )) {
                        Text("폴더 동기화 전").tag(GitSyncLinkPosition.before)
                        Text("폴더 동기화 후").tag(GitSyncLinkPosition.after)
                    }
                    Picker("실행 방향", selection: Binding(
                        get: { link.direction },
                        set: { store.setGitSyncLink(GitSyncLink(syncID: link.syncID, position: link.position, direction: $0), for: pair) }
                    )) {
                        Text("Git 항목 설정 사용").tag(nil as GitSyncDirection?)
                        ForEach(GitSyncDirection.allCases, id: \.self) { direction in
                            Text(direction.uiTitle).tag(Optional(direction))
                        }
                    }
                    Text("이전 Git 작업이 실패하면 폴더 동기화를 중단하며, 이후 Git 작업은 폴더 동기화 성공 시 실행합니다.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.top, 8)
        }
        .accessibilityIdentifier("folder-git-sync-link")
    }
}

extension GitSyncDirection {
    var uiTitle: String {
        switch self {
        case .pull: "Pull · 원격 → 로컬"
        case .push: "Push · 로컬 → 원격"
        case .bidirectional: "양방향"
        }
    }
}

extension GitSyncPhase {
    var uiTitle: String {
        switch self {
        case .queued: "대기 중"
        case .checking: "원격 상태 확인 중"
        case .fetching: "Fetch 중"
        case .committing: "Commit 중"
        case .pulling: "Pull 중"
        case .pushing: "Push 중"
        case .verifying: "결과 확인 중"
        case .completed: "완료"
        case .failed: "실패"
        case .cancelled: "취소됨"
        case .interrupted: "앱 종료로 중단됨"
        }
    }
}
