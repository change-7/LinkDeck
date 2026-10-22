import SwiftUI

struct GitSyncEditor: View {
    @Environment(\.dismiss) private var dismiss
    let store: GitSyncStore
    let configuration: GitSyncConfiguration?
    let onSave: (UUID) -> Void
    var integrated = false
    @State private var name = ""
    @State private var folder: FolderReference?
    @State private var repository: GitSyncRepository?
    @State private var remote = ""
    @State private var branch = ""
    @State private var direction = GitSyncDirection.bidirectional
    @State private var autoCommit = false
    @State private var includePatterns = ""
    @State private var excludePatterns = ""
    @State private var commitMessage = "LinkDeck Git Sync"
    @State private var isChecking = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(configuration == nil ? "Git 저장소 추가" : "Git Sync 편집").font(.title2)
            Form {
                if !integrated { TextField(AppText.name, text: $name) }
                LabeledContent("로컬 Git 폴더") {
                    Text(folder?.displayPath ?? "선택되지 않음")
                        .lineLimit(1).truncationMode(.middle)
                    if !integrated { Button("선택…") { chooseFolder() }.disabled(isChecking) }
                }
                if isChecking { ProgressView("Git 저장소 확인 중…") }
                if let repository {
                    LabeledContent("현재 브랜치", value: repository.localBranch.isEmpty ? "Detached HEAD · 브랜치를 먼저 체크아웃하세요" : repository.localBranch)
                    if !remote.isEmpty && !branch.isEmpty {
                        LabeledContent("감지된 대상", value: "\(remote) / \(branch)")
                    }
                    DisclosureGroup("원격 / 추적 브랜치 선택", isExpanded: Binding(
                        get: { selectingTarget || remote.isEmpty || branch.isEmpty },
                        set: { selectingTarget = $0 }
                    )) {
                        Picker("원격", selection: Binding(get: { remote }, set: { remote = $0; branch = "" })) {
                            Text("원격 선택").tag("")
                            ForEach(repository.remotes, id: \.self) { Text($0).tag($0) }
                        }
                        TextField("원격 브랜치", text: $branch, prompt: Text("upstream 브랜치 이름"))
                        let branches = repository.branches.filter { $0.hasPrefix(remote + "/") && !$0.hasSuffix("/HEAD") }
                        if !branches.isEmpty {
                            Menu("감지된 브랜치 선택") {
                                ForEach(branches, id: \.self) { reference in
                                    Button(reference) { branch = String(reference.dropFirst(remote.count + 1)) }
                                }
                            }
                        }
                        Text("기존 upstream을 우선 사용합니다. upstream이 없거나 대상이 여러 개인 경우 사용할 원격과 브랜치를 선택하세요.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if !integrated {
                    Picker("동기화 방향", selection: $direction) {
                        ForEach(GitSyncDirection.allCases, id: \.self) { Text($0.uiTitle).tag($0) }
                    }
                } else {
                    LabeledContent("동기화 방향", value: direction.uiTitle)
                }
                Toggle("자동 Commit", isOn: $autoCommit)
                    .disabled(direction == .pull)
                if autoCommit && direction != .pull {
                    TextField("Commit 메시지", text: $commitMessage)
                    TextField("포함 규칙 (한 줄에 하나)", text: $includePatterns, axis: .vertical)
                        .lineLimit(2...4)
                    TextField("제외 규칙 (한 줄에 하나)", text: $excludePatterns, axis: .vertical)
                        .lineLimit(2...4)
                    Text("추적 파일 변경을 Commit합니다. 새 파일과 삭제는 포함 규칙에 맞는 경우만 처리하며 .gitignore를 따릅니다. 민감정보 검사는 모든 비밀을 찾지 못하므로 포함 대상을 확인하세요.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red).textSelection(.enabled)
                    .accessibilityIdentifier("git-sync-editor-error")
            }
            HStack {
                Spacer()
                Button(AppText.cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(isChecking)
                Button("저장") { Task { await save() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(isChecking || isRunning || folder == nil || repository == nil || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || remote.isEmpty || branch.isEmpty)
                    .accessibilityIdentifier("git-sync-save")
            }
        }
        .padding(20)
        .frame(width: 570, height: 620)
        .interactiveDismissDisabled(isChecking)
        .task {
            guard let configuration else { return }
            name = configuration.name
            folder = configuration.folder
            remote = configuration.remote
            branch = configuration.branch
            direction = configuration.direction
            autoCommit = configuration.autoCommit
            includePatterns = configuration.includePatterns.joined(separator: "\n")
            excludePatterns = configuration.excludePatterns.joined(separator: "\n")
            commitMessage = configuration.commitMessage
            await inspect(configuration.folder, preserveTarget: !configuration.remote.isEmpty && !configuration.branch.isEmpty)
        }
        .accessibilityIdentifier("git-sync-editor")
    }

    @State private var selectingTarget = false

    private var isRunning: Bool {
        guard let configuration, let job = store.latestJob(syncID: configuration.id) else { return false }
        return !job.isFinished
    }

    private func chooseFolder() {
        FolderPicker.chooseFolder { url in
            Task {
                do {
                    let reference = try FolderReference(url: url)
                    folder = reference
                    repository = nil
                    remote = ""
                    branch = ""
                    if name.isEmpty { name = url.lastPathComponent }
                    await inspect(reference, preserveTarget: false)
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func inspect(_ folder: FolderReference, preserveTarget: Bool) async {
        isChecking = true
        errorMessage = nil
        defer { isChecking = false }
        do {
            let detected = try await store.inspect(folder: folder)
            repository = detected
            if !preserveTarget {
                remote = detected.remote
                branch = detected.branch
            }
            if detected.remotes.isEmpty {
                errorMessage = "설정된 원격 저장소가 없습니다. Git에서 원격을 추가한 뒤 폴더를 다시 선택하세요."
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func save() async {
        guard let folder else { return }
        isChecking = true
        errorMessage = nil
        defer { isChecking = false }
        do {
            let detected = try await store.detect(folder: folder, remote: remote.trimmingCharacters(in: .whitespacesAndNewlines),
                                                  branch: branch.trimmingCharacters(in: .whitespacesAndNewlines))
            var item = GitSyncConfiguration(
                id: configuration?.id ?? UUID(), name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                folder: folder, remote: detected.remote, branch: detected.branch, direction: direction,
                autoCommit: autoCommit && direction != .pull,
                includePatterns: includePatterns.split(whereSeparator: \.isNewline).map(String.init),
                excludePatterns: excludePatterns.split(whereSeparator: \.isNewline).map(String.init),
                commitMessage: commitMessage
            )
            guard !isRunning else { throw GitSyncFailure(code: .repositoryBusy) }
            let current = store.configurations.first { $0.id == configuration?.id }
            item.lastRunAt = current?.lastRunAt
            item.lastSuccessAt = current?.lastSuccessAt
            if current == nil { store.add(item) } else { store.update(item) }
            onSave(item.id)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
