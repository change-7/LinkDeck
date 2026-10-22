import SwiftUI

struct WorkflowEditorView: View {
    @Environment(\.colorScheme) private var colorScheme
    private var theme: MacAppearance { MacAppearance(scheme: colorScheme) }
    @Binding var action: PadAction
    var onRun: (() -> Void)?

    private var rowCount: Int { (min(6, action.workflowSteps.count + 1) + 2) / 3 }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("여러 동작 묶기").font(.system(size: 12, weight: .bold))
                Spacer()
                if let onRun {
                    Button(action: onRun) { Label("실행해 보기", systemImage: "play.fill") }
                        .buttonStyle(.bordered)
                        .font(.system(size: 10))
                }
            }
            VStack(spacing: 0) {
                ForEach(0..<rowCount, id: \.self) { row in
                    workflowRow(row)
                    if row < rowCount - 1 { rowConnection(row) }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .foregroundStyle(theme.foreground)
        .background(theme.control, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(theme.border))
        .accessibilityIdentifier("workflow-editor")
    }

    private func workflowRow(_ row: Int) -> some View {
        let first = row * 3
        let reverse = row % 2 == 1
        return HStack(spacing: 0) {
            ForEach(0..<3, id: \.self) { column in
                let index = first + (reverse ? 2 - column : column)
                node(index)
                if column < 2 {
                    let preceding = reverse ? index - 1 : index
                    if preceding + 1 <= action.workflowSteps.count {
                        horizontalConnection(after: preceding, reverse: reverse)
                    } else {
                        Color.clear.frame(width: 54, height: 1)
                    }
                }
            }
        }
    }

    @ViewBuilder private func node(_ index: Int) -> some View {
        if index < action.workflowSteps.count {
            WorkflowStepCard(step: stepBinding(index), number: index + 1) {
                action.workflowSteps.remove(at: index)
            }
            .frame(maxWidth: .infinity)
        } else if index == action.workflowSteps.count {
            Button {
                guard action.workflowSteps.count < 6 else { return }
                action.workflowSteps.append(WorkflowStep())
            } label: {
                Image(systemName: "plus").frame(width: 28, height: 28)
            }
            .buttonStyle(.bordered)
            .disabled(action.workflowSteps.count >= 6)
            .accessibilityLabel("동작 추가")
            .accessibilityIdentifier("workflow-add-step")
            .frame(maxWidth: .infinity, minHeight: 62,
                alignment: index % 3 == 0 ? .center : (index / 3 % 2 == 0 ? .leading : .trailing))
        } else {
            Color.clear.frame(maxWidth: .infinity, minHeight: 62)
        }
    }

    private func horizontalConnection(after index: Int, reverse: Bool) -> some View {
        ZStack {
            HStack(spacing: 0) {
                if reverse { Image(systemName: "chevron.left").font(.system(size: 7, weight: .bold)) }
                Rectangle().frame(height: 1)
                if !reverse { Image(systemName: "chevron.right").font(.system(size: 7, weight: .bold)) }
            }
            .foregroundStyle(theme.accent)
            if index + 1 < action.workflowSteps.count { delayControl(after: index) }
        }
        .frame(width: 54, height: 62)
    }

    private func rowConnection(_ row: Int) -> some View {
        let index = row * 3 + 2
        let onRight = row % 2 == 0
        return HStack(spacing: 0) {
            if onRight {
                ForEach(0..<2, id: \.self) { _ in
                    Color.clear.frame(maxWidth: .infinity)
                    Color.clear.frame(width: 54)
                }
            }
            VStack(spacing: 0) {
                Rectangle().fill(theme.accent).frame(width: 1, height: 6)
                if index + 1 < action.workflowSteps.count { delayControl(after: index) }
                Image(systemName: "arrow.down").font(.system(size: 9)).foregroundStyle(theme.accent)
            }
            .frame(maxWidth: .infinity, minHeight: 34)
            if !onRight {
                ForEach(0..<2, id: \.self) { _ in
                    Color.clear.frame(width: 54)
                    Color.clear.frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func delayControl(after index: Int) -> some View {
        let id = action.workflowSteps[index].id
        return HStack(spacing: 1) {
            TextField("0", value: Binding(
                get: { action.workflowSteps.first(where: { $0.id == id })?.delayAfter ?? 0 },
                set: { value in
                    guard value.isFinite,
                          let current = action.workflowSteps.firstIndex(where: { $0.id == id }) else { return }
                    action.workflowSteps[current].delayAfter = min(3600, max(0, value))
                }
            ), format: .number.precision(.fractionLength(0...2)))
            .textFieldStyle(.plain)
            .multilineTextAlignment(.center)
            .accessibilityLabel("동작 \(index + 1) 다음 대기 시간")
            Text("초").accessibilityHidden(true)
        }
        .font(.system(size: 9, weight: .semibold, design: .monospaced))
        .frame(width: 43)
        .padding(.vertical, 3)
        .background(theme.panel, in: Capsule())
        .overlay(Capsule().stroke(theme.accent.opacity(0.8)))
    }

    private func stepBinding(_ index: Int) -> Binding<WorkflowStep> {
        let id = action.workflowSteps[index].id
        return Binding(
            get: { action.workflowSteps.first(where: { $0.id == id }) ?? WorkflowStep(id: id) },
            set: { value in
                guard let current = action.workflowSteps.firstIndex(where: { $0.id == id }) else { return }
                action.workflowSteps[current] = value
            }
        )
    }
}

private struct WorkflowStepCard: View {
    @Environment(\.colorScheme) private var colorScheme
    private var theme: MacAppearance { MacAppearance(scheme: colorScheme) }
    @Binding var step: WorkflowStep
    let number: Int
    let onDelete: () -> Void
    @State private var showingShortcut = false
    @State private var errorMessage = ""

    var body: some View {
        VStack(spacing: 5) {
            HStack(spacing: 4) {
                Text("\(number)").font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundStyle(.secondary)
                Menu {
                    ForEach([ActionKind.app, .shortcut, .terminalCommand, .url]) { kind in
                        Button(kind.title) {
                            if step.action.kind != kind { step.action = PadAction(kind: kind) }
                        }
                    }
                } label: {
                    Text(step.action.kind.title).lineLimit(1)
                }
                .menuStyle(.borderlessButton)
                .accessibilityLabel("동작 \(number) 종류")
                Spacer(minLength: 0)
                Button(action: onDelete) { Image(systemName: "xmark").font(.system(size: 9)) }
                    .buttonStyle(.plain)
                    .accessibilityLabel("동작 \(number) 삭제")
            }
            .font(.system(size: 10, weight: .semibold))
            valueEditor
            if !errorMessage.isEmpty { Text(errorMessage).font(.system(size: 9)).foregroundStyle(.red) }
        }
        .padding(7)
        .frame(maxWidth: .infinity, minHeight: 62)
        .background(theme.input, in: RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(theme.border))
        .accessibilityIdentifier("workflow-step-\(number)")
    }

    @ViewBuilder private var valueEditor: some View {
        switch step.action.kind {
        case .app:
            Button {
                let id = step.id
                AppRegistrationService.chooseApplication { result in
                    guard step.id == id, step.action.kind == .app else { return }
                    switch result {
                    case .success(let app): step.action.value = app.bundleIdentifier; errorMessage = ""
                    case .failure(let error): errorMessage = error.localizedDescription
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "app")
                    Text(AppRegistrationService.displayName(for: step.action.value) ?? "앱 선택").lineLimit(1)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down").font(.system(size: 7))
                }
                .font(.system(size: 10)).padding(4)
                .background(theme.control, in: RoundedRectangle(cornerRadius: 4))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("동작 \(number) 앱 선택")
        case .shortcut:
            Button(step.action.value.isEmpty ? "단축키 등록" : step.action.value) { showingShortcut = true }
                .font(.system(size: 10)).buttonStyle(.bordered)
                .popover(isPresented: $showingShortcut) {
                    ShortcutComposerView(value: $step.action.value,
                        targetAppBundleIdentifier: $step.action.targetAppBundleIdentifier,
                        launchTargetAppIfNeeded: $step.action.launchTargetAppIfNeeded)
                        .padding(12).frame(width: 320)
                }
        case .url, .terminalCommand:
            HStack(spacing: 3) {
                TextField(step.action.kind == .url ? "https://example.com" : "명령어", text: $step.action.value)
                    .textFieldStyle(.plain)
                    .font(.system(size: 10, design: .monospaced))
                    .accessibilityLabel("동작 \(number) 설정값")
                Menu {
                    if step.action.kind == .url {
                        Toggle("현재 탭에서 열기", isOn: $step.action.openURLInCurrentTab)
                    } else {
                        Toggle("터미널 창 표시", isOn: $step.action.showTerminalWindow)
                    }
                } label: { Image(systemName: "ellipsis") }
                .menuStyle(.borderlessButton).fixedSize()
                .accessibilityLabel("동작 \(number) 실행 옵션")
            }
            .padding(4).background(theme.control, in: RoundedRectangle(cornerRadius: 4))
        case .workflow, .appQuit, .appFolder, .clipboardText, .none:
            Text("동작을 선택하세요").font(.system(size: 10)).foregroundStyle(.secondary)
        }
    }
}
