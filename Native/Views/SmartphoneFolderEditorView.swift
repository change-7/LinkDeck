import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SmartphoneFolderEditorSlot: Identifiable, Hashable {
    let id: String
    let isParent: Bool
    let shortcut: SmartphoneFolderShortcut?
}

func smartphoneFolderEditorSlots(for folder: SmartphoneButton) -> [SmartphoneFolderEditorSlot] {
    var slots = [
        SmartphoneFolderEditorSlot(
            id: "\(folder.id)_parent",
            isParent: true,
            shortcut: nil
        )
    ]
    slots += folder.folderShortcuts.map {
        SmartphoneFolderEditorSlot(id: $0.id, isParent: false, shortcut: $0)
    }
    while slots.count < 16 {
        slots.append(
            SmartphoneFolderEditorSlot(
                id: "\(folder.id)_empty_\(slots.count)",
                isParent: false,
                shortcut: nil
            )
        )
    }
    return slots
}

struct SmartphoneFolderEditorView: View {
    @Environment(\.colorScheme) private var colorScheme
    private var theme: MacAppearance { MacAppearance(scheme: colorScheme) }
    @Bindable var store: LaunchpadStore
    let pageIndex: Int
    let folderButtonID: String
    var folderUsesLongPress = false
    @Environment(\.dismiss) private var dismiss
    @State private var selectedShortcutID: String?
    @State private var registrationError = ""
    @State private var isShortcutSymbolPickerPresented = false
    @State private var isCustomIconDropTargeted = false
    @State private var customIconError = ""
    @State private var editingLongPress = false

    private let shortcutSymbolChoices = [
        "", "app.fill", "folder.fill", "command", "play.fill", "terminal.fill",
        "globe", "star.fill", "gearshape.fill", "message.fill", "photo",
        "bolt.fill", "house.fill", "checkmark", "heart.fill", "music.note",
        "link", "doc.text", "magnifyingglass", "camera.fill", "bookmark.fill",
        "calendar", "clock.fill", "person.fill", "paperplane.fill", "sparkles"
    ]

    private var folderButton: SmartphoneButton? {
        store.smartphonePages[safe: pageIndex]?.buttons.first { $0.id == folderButtonID }
    }

    private var selectedShortcut: SmartphoneFolderShortcut? {
        folderButton?.folderShortcuts.first { $0.id == selectedShortcutID }
    }

    private var folderAction: PadAction {
        guard let folderButton else { return PadAction() }
        return folderUsesLongPress ? folderButton.longPressAction : folderButton.action
    }

    private var selectedAction: PadAction {
        guard let selectedShortcut else { return PadAction() }
        return editingLongPress ? selectedShortcut.longPressAction : selectedShortcut.action
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let folderButton {
                header(folderButton)
                HStack(alignment: .top, spacing: 14) {
                    folderGrid(folderButton)
                    shortcutEditor(folderButton)
                }
            } else {
                Text("폴더 버튼을 찾을 수 없습니다.")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(22)
        .foregroundStyle(theme.foreground)
        .background(theme.canvas)
        .frame(width: 900, height: 640)
    }

    private func header(_ folderButton: SmartphoneButton) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "iphone").foregroundStyle(theme.accent)
                Text("스마트폰 버튼 설정")
                    .font(.system(size: 20, weight: .bold))
                Text("· \(folderButton.title.isEmpty ? "앱 폴더" : folderButton.title)")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
                Text("폴더 내부 4×4 버튼 구성")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Label("상위 폴더", systemImage: "chevron.left")
                }
                .buttonStyle(.plain)
                .foregroundStyle(theme.accent)
                Button {
                    addShortcut()
                } label: {
                    Label("버튼 추가", systemImage: "plus")
                }
                .buttonStyle(.plain)
                .foregroundStyle(theme.accent)
                .disabled(folderButton.folderShortcuts.count >= 15)
                .opacity(folderButton.folderShortcuts.count >= 15 ? 0.45 : 1)
            }
            HStack(spacing: 8) {
                TextField("폴더 이름", text: folderTitleBinding)
                    .textFieldStyle(.roundedBorder)
                TextField("SF Symbol", text: folderSymbolBinding)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 160)
                Button("앱 변경") { registerFolderApplication() }
                    .buttonStyle(.bordered)
                if !folderAction.value.isEmpty {
                    Text(AppRegistrationService.displayName(for: folderAction.value) ?? folderAction.value)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            if !registrationError.isEmpty {
                Text(registrationError)
                    .font(.system(size: 10))
                    .foregroundStyle(.red)
            }
        }
        .padding(.bottom, 4)
        .overlay(alignment: .bottom) { Divider().overlay(theme.foreground.opacity(0.16)) }
    }

    private func folderGrid(_ folderButton: SmartphoneButton) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("폴더 버튼")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(folderButton.folderShortcuts.count)/15 등록")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            ScrollView(.vertical) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                    ForEach(smartphoneFolderEditorSlots(for: folderButton)) { slot in
                        folderSlot(slot)
                    }
                }
            }
            .frame(maxHeight: 410)
        }
        .frame(minWidth: 530, maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(theme.inset, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(theme.foreground.opacity(0.08)))
    }

    @ViewBuilder
    private func folderSlot(_ slot: SmartphoneFolderEditorSlot) -> some View {
        if slot.isParent {
            Button { dismiss() } label: {
                VStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 20, weight: .semibold))
                    Text("상위 폴더")
                        .font(.system(size: 11, weight: .medium))
                }
                .frame(maxWidth: .infinity, minHeight: 78)
                .foregroundStyle(theme.accent)
                .background(theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(theme.accent, lineWidth: 1.5))
            }
            .buttonStyle(.plain)
        } else if let shortcut = slot.shortcut {
            Button { selectedShortcutID = shortcut.id } label: {
                VStack(spacing: 6) {
                    shortcutIcon(shortcut, size: 24)
                    Text(shortcut.title.isEmpty ? "이름 없음" : shortcut.title)
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                    VStack(spacing: 2) {
                        if shortcut.action.kind != .none {
                            Text("짧게 · \(shortcut.action.kind.title)")
                        }
                        if shortcut.longPressAction.kind != .none {
                            Text("길게 · \(shortcut.longPressAction.kind.title)")
                        }
                        if shortcut.action.kind == .none && shortcut.longPressAction.kind == .none {
                            Text("동작 없음")
                        }
                    }
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
                .frame(maxWidth: .infinity, minHeight: 78)
                .foregroundStyle(selectedShortcutID == shortcut.id ? theme.accent : theme.foreground)
                .background(selectedShortcutID == shortcut.id ? theme.accent.opacity(0.14) : theme.control, in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(selectedShortcutID == shortcut.id ? theme.accent : theme.foreground.opacity(0.12), lineWidth: selectedShortcutID == shortcut.id ? 1.5 : 1))
            }
            .buttonStyle(.plain)
        } else {
            Button { addShortcut() } label: {
                VStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.system(size: 20, weight: .medium))
                    Text("버튼 추가")
                        .font(.system(size: 11, weight: .medium))
                }
                .frame(maxWidth: .infinity, minHeight: 78)
                .foregroundStyle(theme.foreground.opacity(0.46))
                .background(theme.control, in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(theme.foreground.opacity(0.12)))
            }
            .buttonStyle(.plain)
            .disabled((folderButton?.folderShortcuts.count ?? 15) >= 15)
        }
    }

    private func shortcutEditor(_ folderButton: SmartphoneButton) -> some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("버튼 편집")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if selectedShortcut != nil {
                        Button(role: .destructive) {
                            removeSelectedShortcut()
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.plain)
                    }
                }
                if let selectedShortcut {
                    TextField("버튼 라벨", text: shortcutTitleBinding)
                        .textFieldStyle(.roundedBorder)
                    HStack(spacing: 6) {
                        TextField("SF Symbol", text: shortcutSymbolBinding)
                            .textFieldStyle(.roundedBorder)
                        Button {
                            isShortcutSymbolPickerPresented.toggle()
                        } label: {
                            Label("아이콘 선택", systemImage: "square.grid.3x3")
                                .labelStyle(.iconOnly)
                                .frame(width: 28, height: 24)
                        }
                        .buttonStyle(.bordered)
                        .help("SF Symbol 아이콘 선택")
                        .popover(isPresented: $isShortcutSymbolPickerPresented, arrowEdge: .trailing) {
                            shortcutSymbolPicker(for: selectedShortcut)
                        }
                    }
                    shortcutPNGEditor(for: selectedShortcut)
                    Picker("누르기 동작", selection: $editingLongPress) {
                        Text("짧게 누르기").tag(false)
                        Text("길게 누르기").tag(true)
                    }
                    .pickerStyle(.segmented)
                    Picker("동작", selection: shortcutKindBinding) {
                        ForEach([ActionKind.none, .shortcut, .app, .terminalCommand, .url, .clipboardText]) { kind in
                            Text(kind.title).tag(kind)
                        }
                    }
                    shortcutActionEditor
                } else {
                    Image(systemName: "square.grid.2x2")
                        .font(.system(size: 28, weight: .medium))
                        .foregroundStyle(theme.accent)
                    Text("4×4 버튼에서 편집할 버튼을 선택하세요.")
                        .font(.system(size: 13, weight: .medium))
                    Text("빈 칸은 ‘버튼 추가’로 등록할 수 있습니다.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }
            .padding(13)
        }
        .frame(width: 285, alignment: .leading)
        .frame(maxHeight: .infinity)
        .background(theme.panel, in: RoundedRectangle(cornerRadius: 13))
        .overlay(RoundedRectangle(cornerRadius: 13).stroke(theme.foreground.opacity(0.12)))
    }

    @ViewBuilder
    private var shortcutActionEditor: some View {
        switch selectedAction.kind {
        case .shortcut:
            ShortcutComposerView(
                value: shortcutValueBinding,
                targetAppBundleIdentifier: shortcutTargetBinding,
                launchTargetAppIfNeeded: shortcutLaunchBinding
            )
            .id("\(selectedShortcutID ?? "")_\(editingLongPress)")
        case .app:
            Button(selectedAction.value.isEmpty ? "앱 등록" : "앱 변경") {
                registerShortcutApplication()
            }
            .buttonStyle(.bordered)
            if !selectedAction.value.isEmpty {
                Text(AppRegistrationService.displayName(for: selectedAction.value) ?? selectedAction.value)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        case .terminalCommand:
            TextField("예: open -a Safari", text: shortcutValueBinding)
                .textFieldStyle(.roundedBorder)
            Toggle("터미널 창 표시", isOn: Binding(
                get: { selectedAction.showTerminalWindow },
                set: { value in updateSelectedAction { $0.showTerminalWindow = value } }
            ))
            .toggleStyle(.checkbox)
        case .url:
            TextField("https://example.com", text: shortcutValueBinding)
                .textFieldStyle(.roundedBorder)
            URLTabPicker(openInCurrentTab: Binding(
                get: { selectedAction.openURLInCurrentTab },
                set: { value in updateSelectedAction { $0.openURLInCurrentTab = value } }
            ))
        case .clipboardText:
            Text("현재 활성 앱에 붙여넣을 텍스트")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            TextEditor(text: shortcutValueBinding)
                .font(.system(size: 12))
                .scrollContentBackground(.hidden)
                .padding(7)
                .frame(height: 100)
                .background(theme.input, in: RoundedRectangle(cornerRadius: 8))
        case .none:
            Text("\(editingLongPress ? "길게" : "짧게") 누르면 실행하지 않습니다.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        case .appFolder:
            Text("폴더 내부에는 앱 폴더를 추가할 수 없습니다.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }

    private var folderTitleBinding: Binding<String> {
        Binding(
            get: { folderButton?.title ?? "" },
            set: { newValue in updateFolderButton { $0.title = newValue } }
        )
    }

    private var folderSymbolBinding: Binding<String> {
        Binding(
            get: { folderButton?.symbol ?? "" },
            set: { newValue in updateFolderButton { $0.symbol = newValue } }
        )
    }

    private var shortcutTitleBinding: Binding<String> {
        Binding(
            get: { selectedShortcut?.title ?? "" },
            set: { newValue in updateSelectedShortcut { $0.title = newValue } }
        )
    }

    private var shortcutSymbolBinding: Binding<String> {
        Binding(
            get: { selectedShortcut?.symbol ?? "command" },
            set: { newValue in updateSelectedShortcut { $0.symbol = newValue } }
        )
    }

    private var shortcutValueBinding: Binding<String> {
        Binding(
            get: { selectedAction.value },
            set: { newValue in updateSelectedAction { $0.value = newValue } }
        )
    }

    private var shortcutTargetBinding: Binding<String> {
        Binding(
            get: { selectedAction.targetAppBundleIdentifier },
            set: { newValue in updateSelectedAction { $0.targetAppBundleIdentifier = newValue } }
        )
    }

    private var shortcutLaunchBinding: Binding<Bool> {
        Binding(
            get: { selectedAction.launchTargetAppIfNeeded },
            set: { newValue in updateSelectedAction { $0.launchTargetAppIfNeeded = newValue } }
        )
    }

    private var shortcutKindBinding: Binding<ActionKind> {
        Binding(
            get: { selectedAction.kind },
            set: { kind in
                guard selectedAction.kind != kind else { return }
                updateSelectedAction {
                    $0 = PadAction(
                        kind: kind,
                        value: kind == .url ? "https://example.com" : "",
                        targetAppBundleIdentifier: kind == .shortcut ? folderAction.value : ""
                    )
                }
            }
        )
    }

    private func updateSelectedAction(_ change: (inout PadAction) -> Void) {
        updateSelectedShortcut { shortcut in
            if editingLongPress {
                change(&shortcut.longPressAction)
            } else {
                change(&shortcut.action)
            }
        }
    }

    private func updateFolderButton(_ change: (inout SmartphoneButton) -> Void) {
        guard var button = folderButton else { return }
        change(&button)
        store.updateSmartphoneButton(button, at: pageIndex)
    }

    private func updateSelectedShortcut(_ change: (inout SmartphoneFolderShortcut) -> Void) {
        guard let selectedShortcutID else { return }
        updateShortcut(id: selectedShortcutID, change)
    }

    private func updateShortcut(
        id shortcutID: String,
        _ change: (inout SmartphoneFolderShortcut) -> Void
    ) {
        guard var button = folderButton,
              let index = button.folderShortcuts.firstIndex(where: { $0.id == shortcutID }) else { return }
        change(&button.folderShortcuts[index])
        store.updateSmartphoneButton(button, at: pageIndex)
    }

    @ViewBuilder
    private func shortcutSymbolPicker(for shortcut: SmartphoneFolderShortcut) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: 5), spacing: 5) {
            ForEach(shortcutSymbolChoices, id: \.self) { symbol in
                Button {
                    updateShortcut(id: shortcut.id) { $0.symbol = symbol }
                    isShortcutSymbolPickerPresented = false
                } label: {
                    Image(systemName: symbol.isEmpty ? "circle.slash" : symbol)
                        .font(.system(size: 16, weight: .medium))
                        .frame(width: 34, height: 34)
                        .foregroundStyle(shortcut.symbol == symbol ? theme.accent : .primary)
                        .background(
                            shortcut.symbol == symbol ? theme.accent.opacity(0.14) : Color.primary.opacity(0.06),
                            in: RoundedRectangle(cornerRadius: 6)
                        )
                }
                .buttonStyle(.plain)
                .help(symbol.isEmpty ? "아이콘 없음" : symbol)
            }
        }
        .padding(10)
        .frame(width: 205)
    }

    @ViewBuilder
    private func shortcutIcon(_ shortcut: SmartphoneFolderShortcut, size: CGFloat) -> some View {
        if let data = shortcut.customIconData, let image = NSImage(data: data) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: size, height: size)
        } else {
            Image(systemName: shortcut.symbol.isEmpty ? "command" : shortcut.symbol)
                .font(.system(size: size, weight: .medium))
                .frame(width: size, height: size)
        }
    }

    private func shortcutPNGEditor(for shortcut: SmartphoneFolderShortcut) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("사용자 PNG 이미지")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: 7) {
                Group {
                    if let data = shortcut.customIconData, let image = NSImage(data: data) {
                        Image(nsImage: image)
                            .resizable()
                            .interpolation(.high)
                            .scaledToFit()
                            .padding(3)
                    } else {
                        Image(systemName: "photo")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 34, height: 34)
                .background(theme.input, in: RoundedRectangle(cornerRadius: 6))

                VStack(alignment: .leading, spacing: 2) {
                    Text(shortcut.customIconData == nil ? "PNG 없음" : "PNG 적용됨")
                        .font(.system(size: 10, weight: .semibold))
                    Text("파일 선택·붙여넣기·드래그")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Button("선택") { chooseShortcutPNG(for: shortcut.id) }
                    .font(.system(size: 10, weight: .semibold))
                    .buttonStyle(.plain)
                    .foregroundStyle(theme.accent)
                Button("붙여넣기") { pasteShortcutPNG(for: shortcut.id) }
                    .font(.system(size: 10, weight: .semibold))
                    .buttonStyle(.plain)
                    .foregroundStyle(theme.accent)
                if shortcut.customIconData != nil {
                    Button {
                        clearShortcutPNG(for: shortcut.id)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.red.opacity(0.9))
                    .help("사용자 PNG 제거")
                }
            }
            .padding(7)
            .background(theme.input, in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isCustomIconDropTargeted ? theme.accent : theme.foreground.opacity(0.12), lineWidth: isCustomIconDropTargeted ? 1.5 : 1)
            )
            .onDrop(
                of: [UTType.fileURL.identifier, UTType.png.identifier],
                isTargeted: $isCustomIconDropTargeted
            ) { providers in
                importShortcutPNG(from: providers, shortcutID: shortcut.id)
            }
            .onPasteCommand(of: [UTType.png, UTType.fileURL]) { _ in
                pasteShortcutPNG(for: shortcut.id)
            }
            if !customIconError.isEmpty {
                Text(customIconError)
                    .font(.system(size: 9))
                    .foregroundStyle(.red.opacity(0.9))
            }
        }
    }

    private func chooseShortcutPNG(for shortcutID: String) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                let data = try Data(contentsOf: url)
                Task { @MainActor in applyShortcutPNG(data, to: shortcutID) }
            } catch {
                Task { @MainActor in customIconError = "PNG 파일을 읽지 못했습니다." }
            }
        }
    }

    private func pasteShortcutPNG(for shortcutID: String) {
        guard let data = SmartphoneIconData.dataFromPasteboard() else {
            customIconError = "클립보드에서 이미지를 찾지 못했습니다."
            return
        }
        applyShortcutPNG(data, to: shortcutID)
    }

    private func importShortcutPNG(from providers: [NSItemProvider], shortcutID: String) -> Bool {
        guard let provider = providers.first else { return false }
        customIconError = ""

        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                let url: URL?
                if let item = item as? URL {
                    url = item
                } else if let item = item as? NSURL {
                    url = item as URL
                } else if let data = item as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else {
                    url = nil
                }
                guard let url, let data = try? Data(contentsOf: url) else {
                    Task { @MainActor in customIconError = "PNG 파일을 읽지 못했습니다." }
                    return
                }
                Task { @MainActor in applyShortcutPNG(data, to: shortcutID) }
            }
            return true
        }

        provider.loadDataRepresentation(forTypeIdentifier: UTType.png.identifier) { data, _ in
            guard let data else {
                Task { @MainActor in customIconError = "PNG 이미지를 읽지 못했습니다." }
                return
            }
            Task { @MainActor in applyShortcutPNG(data, to: shortcutID) }
        }
        return true
    }

    private func applyShortcutPNG(_ data: Data, to shortcutID: String) {
        guard let normalizedData = SmartphoneIconData.normalizedPNGData(from: data) else {
            customIconError = "유효한 PNG 이미지만 추가할 수 있습니다."
            return
        }
        updateShortcut(id: shortcutID) { $0.customIconData = normalizedData }
        customIconError = ""
    }

    private func clearShortcutPNG(for shortcutID: String) {
        updateShortcut(id: shortcutID) { $0.customIconData = nil }
        customIconError = ""
    }

    private func addShortcut() {
        guard var button = folderButton else { return }
        guard button.folderShortcuts.count < 15 else { return }
        let shortcut = SmartphoneFolderShortcut(
            id: "\(button.id)_folder_\(UUID().uuidString)",
            title: "단축키 \(button.folderShortcuts.count + 1)",
            symbol: "command",
            action: PadAction(kind: .shortcut, targetAppBundleIdentifier: folderAction.value)
        )
        button.folderShortcuts.append(shortcut)
        store.updateSmartphoneButton(button, at: pageIndex)
        selectedShortcutID = shortcut.id
        editingLongPress = false
    }

    private func removeSelectedShortcut() {
        guard let selectedShortcutID else { return }
        updateFolderButton { button in
            button.folderShortcuts.removeAll { $0.id == selectedShortcutID }
        }
        self.selectedShortcutID = nil
    }

    private func registerFolderApplication() {
        registrationError = ""
        let previousBundleIdentifier = folderAction.value
        AppRegistrationService.chooseApplication { result in
            switch result {
            case .success(let application):
                updateFolderButton { button in
                    if folderUsesLongPress {
                        button.longPressAction.value = application.bundleIdentifier
                    } else {
                        button.action.value = application.bundleIdentifier
                    }
                    button.folderShortcuts = button.folderShortcuts.map { shortcut in
                        var updated = shortcut
                        if !previousBundleIdentifier.isEmpty {
                            if updated.action.kind == .shortcut && updated.action.targetAppBundleIdentifier == previousBundleIdentifier {
                                updated.action.targetAppBundleIdentifier = application.bundleIdentifier
                            }
                            if updated.longPressAction.kind == .shortcut && updated.longPressAction.targetAppBundleIdentifier == previousBundleIdentifier {
                                updated.longPressAction.targetAppBundleIdentifier = application.bundleIdentifier
                            }
                        }
                        return updated
                    }
                }
            case .failure(let error):
                registrationError = error.localizedDescription
            }
        }
    }

    private func registerShortcutApplication() {
        guard let selectedShortcutID else { return }
        let usesLongPress = editingLongPress
        registrationError = ""
        AppRegistrationService.chooseApplication { result in
            switch result {
            case .success(let application):
                updateShortcut(id: selectedShortcutID) { shortcut in
                    if usesLongPress {
                        shortcut.longPressAction.value = application.bundleIdentifier
                    } else {
                        shortcut.action.value = application.bundleIdentifier
                    }
                }
            case .failure(let error):
                registrationError = error.localizedDescription
            }
        }
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
