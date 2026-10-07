import SwiftUI

struct InspectorView: View {
    @Environment(\.colorScheme) private var colorScheme
    private var theme: MacAppearance { MacAppearance(scheme: colorScheme) }
    @Binding var pad: Pad
    let pages: [LaunchPage]
    @Binding var selectedMainScreen: MainScreen
    let selectedPageLEDIndex: Int?
    let codexIsConnected: Bool
    let midiIsConnected: Bool
    let onOpenBackupRestore: () -> Void
    let onOpenCodexSettings: () -> Void
    let onSelectPageLED: (Int?) -> Void
    let onUpdatePageColor: (Int, String, Bool) -> Void
    let onUpdatePageName: (Int, String) -> Void
    let onReset: () -> Void
    let onRun: (PadAction) -> Void
    @State private var registrationError = ""
    @State private var appRegistrationRequestID = UUID()
    @State private var editingSecondAction = false

    private var selectedAction: PadAction {
        editingSecondAction ? (pad.secondAction ?? PadAction()) : pad.action
    }

    private var selectedSymbolBinding: Binding<String> {
        Binding(
            get: { editingSecondAction ? pad.secondSymbol ?? pad.symbol : pad.symbol },
            set: { if editingSecondAction { pad.secondSymbol = $0 } else { pad.symbol = $0 } }
        )
    }

    private var selectedTitleBinding: Binding<String> {
        Binding(
            get: { editingSecondAction ? pad.secondTitle ?? "" : pad.title },
            set: { if editingSecondAction { pad.secondTitle = $0.isEmpty ? nil : $0 } else { pad.title = $0 } }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(selectedPageLEDIndex == nil ? "SELECTED PAD" : "SELECTED TOP BUTTON")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(.yellow)
                    Spacer(minLength: 0)
                    MainScreenSidebarNavigation(
                        selection: $selectedMainScreen,
                        midiIsConnected: midiIsConnected,
                        compact: true
                    )
                    .padding(.trailing, selectedPageLEDIndex == nil ? 34 : 0)
                }
                Text(inspectorTitle).font(.system(size: 17, weight: .bold)).foregroundStyle(theme.foreground)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .topTrailing) {
                if selectedPageLEDIndex == nil {
                    Button(role: .destructive, action: onReset) { Image(systemName: "trash").frame(width: 30, height: 30).background(Color.red.opacity(0.16), in: RoundedRectangle(cornerRadius: 6)) }
                        .buttonStyle(.plain)
                }
            }
            .padding(.bottom, 11)
            .overlay(alignment: .bottom) { Divider().overlay(theme.foreground.opacity(0.18)) }

            if let pageIndex = selectedPageLEDIndex, pages.indices.contains(pageIndex) {
                fieldSection("P 버튼 이름") {
                    DarkTextField(text: Binding(
                        get: { pages[pageIndex].name },
                        set: { onUpdatePageName(pageIndex, $0) }
                    ))
                }
                sectionDivider
                fieldSection("런치패드 LED 색상") {
                    Button("현재 패드 LED 색상으로 돌아가기") {
                        onSelectPageLED(nil)
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .buttonStyle(.plain)
                    HStack(alignment: .top, spacing: 16) {
                        pagePalette(title: "P\(pageIndex + 1) 대기 색상", selection: pages[pageIndex].pageIdleColor, selected: false, index: pageIndex)
                        pagePalette(title: "P\(pageIndex + 1) 선택된 페이지 색상", selection: pages[pageIndex].pageActiveColor, selected: true, index: pageIndex)
                    }
                }
            } else {
                fieldSection(pad.secondAction == nil ? "버튼 라벨" : "버튼 라벨 \(editingSecondAction ? "B" : "A")") {
                    DarkTextField(text: selectedTitleBinding, placeholder: editingSecondAction ? "B 이름" : "A 이름")
                }

                sectionDivider
                if let descriptor = PadDefaults.sideButtonDescriptor(for: pad.id) {
                    sideButtonRoleSection(descriptor)
                    sectionDivider
                }
                fieldSection("할당할 동작") {
                    Toggle("A/B 동작 전환", isOn: Binding(
                        get: { pad.secondAction != nil },
                        set: { enabled in
                            if enabled {
                                if pad.secondAction == nil {
                                    pad.secondAction = PadAction()
                                    pad.isSecondActionActive = false
                                }
                            } else {
                                pad.secondAction = nil
                                pad.isSecondActionActive = false
                                editingSecondAction = false
                            }
                        }
                    ))
                    .toggleStyle(.checkbox)
                    if pad.secondAction != nil {
                        HStack(spacing: 8) {
                            Picker("편집 동작", selection: $editingSecondAction) {
                                Text("A").tag(false)
                                Text("B").tag(true)
                            }
                            .pickerStyle(.segmented)
                            Text("현재 \(pad.isSecondActionActive ? "B" : "A")")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(theme.accent)
                        }
                    }
                    fieldSection("아이콘 \(editingSecondAction ? "B" : "A")") {
                        LaunchpadIconPicker(selection: selectedSymbolBinding, isSideButton: pad.id.hasPrefix("side_"))
                    }
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 9) {
                        actionButton(.app)
                        actionButton(.shortcut)
                        actionButton(.terminalCommand)
                        actionButton(.url)
                    }
                    if selectedAction.kind != .none {
                        actionRegistration
                        Button("이 동작 실행") { onRun(selectedAction) }
                            .font(.system(size: 12, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .foregroundStyle(theme.accent)
                            .background(theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                            .buttonStyle(.plain)
                    }
                }

                sectionDivider
                fieldSection("런치패드 LED 색상") {
                    HStack(alignment: .top, spacing: 16) {
                        palette(title: "대기 색상", selection: $pad.idleColor)
                        palette(title: "눌렀을 때 색상", selection: $pad.activeColor)
                    }
                }
            }
            Spacer(minLength: 0)
            MainSidebarFooter(
                codexIsConnected: codexIsConnected,
                midiIsConnected: midiIsConnected,
                onOpenBackupRestore: onOpenBackupRestore,
                onOpenCodexSettings: onOpenCodexSettings
            )
        }
        .padding(16)
        .frame(maxHeight: .infinity, alignment: .top)
        .foregroundStyle(theme.foreground.opacity(0.9))
        .background(theme.panel, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(theme.foreground.opacity(0.11)))
        .shadow(color: .black.opacity(0.28), radius: 18, y: 8)
        .onChange(of: pad.id) { _, _ in
            appRegistrationRequestID = UUID()
            editingSecondAction = false
        }
        .onChange(of: editingSecondAction) { _, _ in
            appRegistrationRequestID = UUID()
        }
    }

    private var locationTitle: String {
        if pad.id.hasPrefix("side_") { return "우측 버튼 [\(pad.id.dropFirst(5))]" }
        return "메인 그리드 [\(pad.id.replacingOccurrences(of: "grid_", with: ""))]"
    }

    private var inspectorTitle: String {
        guard let pageIndex = selectedPageLEDIndex else { return locationTitle }
        return "상단 P\(pageIndex + 1) 버튼"
    }

    @ViewBuilder private func fieldSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(theme.foreground.opacity(0.76))
            content()
        }
    }

    private var sectionDivider: some View { Divider().overlay(theme.foreground.opacity(0.18)).padding(.vertical, 1) }

    private func sideButtonRoleSection(_ descriptor: PadDefaults.SideButtonDescriptor) -> some View {
        let usesDefault = descriptor.defaultAction == pad.action
        return VStack(alignment: .leading, spacing: 7) {
            if let description = descriptor.defaultDescription, usesDefault {
                Label("기본 macOS 기능", systemImage: "macwindow")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.green)
                Text(description)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(theme.foreground.opacity(0.82))
                Text("아래에서 앱·단축키·웹 동작으로 바꾸면 사용자 지정 버튼이 됩니다.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Button("사용자 지정 기능으로 변경") {
                    pad.action = PadAction()
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(theme.accent)
                .buttonStyle(.plain)
                .help("기본 macOS 기능을 해제합니다. 아래에서 앱 실행, 단축키, 웹 동작을 새로 지정할 수 있습니다.")
            } else {
                Label("사용자 지정 버튼", systemImage: "slider.horizontal.3")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(theme.accent)
                Text(descriptor.isCustomOnly ? "이 표기는 앱마다 의미가 달라 원하는 동작을 직접 정할 수 있습니다." : "기본 기능 대신 직접 지정한 동작을 사용 중입니다.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                if let defaultAction = descriptor.defaultAction, !usesDefault {
                    Button("기본 macOS 기능 복원") {
                        pad.action = defaultAction
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.green)
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background((usesDefault ? Color.green : theme.accent).opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke((usesDefault ? Color.green : theme.accent).opacity(0.26)))
    }

    private func actionButton(_ kind: ActionKind) -> some View {
        Button {
            let changedKind = selectedAction.kind != kind
            if changedKind {
                appRegistrationRequestID = UUID()
            }
            updateSelectedAction {
                $0.kind = kind
                if changedKind || $0.value.isEmpty { $0.value = defaultValue(for: kind) }
            }
        } label: {
            Text(kind.title).font(.system(size: 13, weight: .semibold)).frame(maxWidth: .infinity).padding(.vertical, 12)
                .foregroundStyle(selectedAction.kind == kind ? theme.accentForeground : theme.foreground.opacity(0.72))
                .background(selectedAction.kind == kind ? theme.accent : theme.foreground.opacity(0.075), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(selectedAction.kind == kind ? theme.accent : theme.foreground.opacity(0.22)))
                .frame(minHeight: 42)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var actionRegistration: some View {
        switch selectedAction.kind {
        case .app, .appFolder:
            VStack(alignment: .leading, spacing: 8) {
                Button("앱 등록") { registerApplication() }
                    .font(.system(size: 12, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .foregroundStyle(theme.foreground)
                    .background(theme.foreground.opacity(0.09), in: RoundedRectangle(cornerRadius: 8))
                    .buttonStyle(.plain)
                registrationValue(
                    title: selectedAction.value.isEmpty ? "등록된 앱 없음" : (AppRegistrationService.displayName(for: selectedAction.value) ?? "등록된 앱"),
                    detail: selectedAction.value
                )
            }
        case .shortcut:
            ShortcutComposerView(
                value: selectedActionBinding(for: \.value),
                targetAppBundleIdentifier: selectedActionBinding(for: \.targetAppBundleIdentifier),
                launchTargetAppIfNeeded: selectedActionBinding(for: \.launchTargetAppIfNeeded)
            )
        case .terminalCommand:
            DarkTextField(text: selectedActionBinding(for: \.value), placeholder: "예: open -a Safari")
            Toggle("터미널 창 표시", isOn: selectedActionBinding(for: \.showTerminalWindow))
                .toggleStyle(.checkbox)
        case .url:
            DarkTextField(text: selectedActionBinding(for: \.value), placeholder: "https://example.com")
            URLTabPicker(openInCurrentTab: selectedActionBinding(for: \.openURLInCurrentTab))
        case .clipboardText:
            TextEditor(text: selectedActionBinding(for: \.value))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(theme.foreground)
                .scrollContentBackground(.hidden)
                .padding(7)
                .frame(minHeight: 92, maxHeight: 140)
                .background(theme.input, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.foreground.opacity(0.18)))
        case .none:
            EmptyView()
        }
    }

    private func registrationValue(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
            if !detail.isEmpty { Text(detail).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1) }
            if !registrationError.isEmpty { Text(registrationError).font(.system(size: 10)).foregroundStyle(.red).lineLimit(2) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .background(theme.input, in: RoundedRectangle(cornerRadius: 8))
    }

    private func registerApplication() {
        registrationError = ""
        let targetPadID = pad.id
        let targetEditsSecondAction = editingSecondAction
        let requestID = UUID()
        appRegistrationRequestID = requestID
        AppRegistrationService.chooseApplication { result in
            guard appRegistrationRequestID == requestID,
                  pad.id == targetPadID,
                  editingSecondAction == targetEditsSecondAction,
                  selectedAction.kind == .app else { return }
            switch result {
            case .success(let application):
                updateSelectedAction { $0.value = application.bundleIdentifier }
                if editingSecondAction {
                    if pad.secondTitle?.isEmpty ?? true { pad.secondTitle = application.name }
                } else if pad.title.isEmpty {
                    pad.title = application.name
                }
            case .failure(let error):
                registrationError = error.localizedDescription
            }
        }
    }

    private func updateSelectedAction(_ update: (inout PadAction) -> Void) {
        if editingSecondAction {
            var action = pad.secondAction ?? PadAction()
            update(&action)
            pad.secondAction = action
        } else {
            update(&pad.action)
        }
    }

    private func selectedActionBinding<Value>(for keyPath: WritableKeyPath<PadAction, Value>) -> Binding<Value> {
        Binding(
            get: { selectedAction[keyPath: keyPath] },
            set: { value in updateSelectedAction { $0[keyPath: keyPath] = value } }
        )
    }

    private func palette(title: String, selection: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 11)).foregroundStyle(.secondary)
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(31), spacing: 8), count: 4), spacing: 8) {
                ForEach(PadColor.launchpadPalette) { color in
                    Button { selection.wrappedValue = color.rawValue } label: {
                        RoundedRectangle(cornerRadius: 4).fill(color.color).frame(width: 31, height: 31)
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(selection.wrappedValue == color.rawValue ? Color.white : theme.foreground.opacity(0.32), lineWidth: selection.wrappedValue == color.rawValue ? 3 : 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(9)
            .background(theme.input, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.foreground.opacity(0.16)))
        }
    }

    private func pagePalette(title: String, selection: String, selected: Bool, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 11)).foregroundStyle(.secondary)
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(31), spacing: 8), count: 4), spacing: 8) {
                ForEach(PadColor.launchpadPalette) { color in
                    Button { onUpdatePageColor(index, color.rawValue, selected) } label: {
                        RoundedRectangle(cornerRadius: 4).fill(color.color).frame(width: 31, height: 31)
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(selection == color.rawValue ? Color.white : theme.foreground.opacity(0.32), lineWidth: selection == color.rawValue ? 3 : 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(9)
            .background(theme.input, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.foreground.opacity(0.16)))
        }
    }

    private func defaultValue(for kind: ActionKind) -> String {
        switch kind {
        case .app, .appFolder, .shortcut, .terminalCommand, .clipboardText: ""
        case .url: "https://chatgpt.com"
        case .none: ""
        }
    }
}

private struct LaunchpadIconPicker: View {
    @Environment(\.colorScheme) private var colorScheme
    private var theme: MacAppearance { MacAppearance(scheme: colorScheme) }
    @Binding var selection: String
    let isSideButton: Bool
    @State private var isShowingPicker = false

    private let icons = [
        "sparkles", "plus.bubble", "message", "mic", "paperplane", "globe",
        "safari", "folder", "note.text", "calendar", "magnifyingglass", "camera.viewfinder",
        "lock", "play.fill", "pause.fill", "stop.fill", "record.circle", "speaker.wave.2", "speaker.wave.1",
        "speaker.slash", "headphones", "slider.horizontal.3", "gearshape", "terminal", "bolt.fill",
        "app.fill", "doc", "doc.text", "doc.on.doc", "photo", "video", "film", "camera",
        "tray.full", "archivebox", "externaldrive", "icloud", "link", "bookmark", "house",
        "building.2", "person", "person.2", "person.crop.circle", "envelope", "phone", "bell",
        "clock", "timer", "checkmark", "xmark", "exclamationmark.triangle", "questionmark.circle",
        "info.circle", "arrow.triangle.2.circlepath", "arrow.clockwise", "arrow.up.right.square",
        "square.and.arrow.up", "scissors", "pencil", "paintbrush", "wand.and.stars", "puzzlepiece",
        "command", "keyboard", "computermouse", "display", "laptopcomputer", "desktopcomputer",
        "cpu", "memorychip", "network", "wifi", "antenna.radiowaves.left.and.right", "battery.100",
        "power", "lightbulb", "moon", "sun.max", "flame", "heart.fill", "star.fill", "flag.fill",
        "cart.fill", "creditcard", "map", "location.fill", "car.fill", "airplane", "leaf.fill"
    ]

    private struct IconCategory: Identifiable {
        let title: String
        let icons: [String]
        var id: String { title }
    }

    private var iconCategories: [IconCategory] {
        guard isSideButton else { return [IconCategory(title: "아이콘", icons: icons)] }

        let volume = ["speaker.wave.2", "speaker.wave.1", "speaker.slash"]
        let media = ["play.fill", "pause.fill", "stop.fill", "record.circle", "headphones", "video", "film", "camera"]
        let macControls = ["command", "keyboard", "computermouse", "display", "desktopcomputer", "gearshape", "power", "moon", "sun.max"]
        let grouped = Set(volume + media + macControls)
        let remaining = icons.filter { !grouped.contains($0) }
        return [
            IconCategory(title: "볼륨", icons: volume),
            IconCategory(title: "미디어", icons: media),
            IconCategory(title: "macOS 제어", icons: macControls),
            IconCategory(title: "기타", icons: remaining)
        ]
    }

    var body: some View {
        Button {
            isShowingPicker.toggle()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: selection.isEmpty ? "square.dashed" : selection)
                    .font(.system(size: 16, weight: .medium))
                    .frame(width: 25, height: 25)
                    .foregroundStyle(selection.isEmpty ? Color.secondary : theme.accent)
                    .background(theme.foreground.opacity(0.07), in: RoundedRectangle(cornerRadius: 6))
                Text(selection.isEmpty ? "아이콘 없음" : iconTitle(for: selection))
                    .font(.system(size: 13, weight: .medium))
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(theme.foreground)
            .padding(.horizontal, 9)
            .frame(height: 38)
            .background(theme.input, in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(theme.foreground.opacity(0.22)))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isShowingPicker, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("아이콘 선택").font(.system(size: 13, weight: .bold))
                    Spacer()
                    Button("없음") {
                        selection = ""
                        isShowingPicker = false
                    }
                    .buttonStyle(.bordered)
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 13) {
                        ForEach(iconCategories) { category in
                            if isSideButton {
                                Text(category.title)
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(theme.accent)
                            }
                            LazyVGrid(columns: Array(repeating: GridItem(.fixed(42), spacing: 8), count: 6), spacing: 8) {
                                ForEach(category.icons, id: \.self) { icon in
                                    iconButton(icon)
                                }
                            }
                        }
                    }
                }
                .frame(maxHeight: 300)
            }
            .padding(14)
            .frame(width: 322)
            .background(theme.panel)
        }
    }

    private func iconButton(_ icon: String) -> some View {
        Button {
            selection = icon
            isShowingPicker = false
        } label: {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .medium))
                .frame(width: 42, height: 38)
                .foregroundStyle(selection == icon ? theme.accentForeground : theme.foreground)
                .background(selection == icon ? theme.accent : theme.control, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(selection == icon ? theme.accent : theme.foreground.opacity(0.15)))
        }
        .buttonStyle(.plain)
        .help(iconTitle(for: icon))
    }

    private func iconTitle(for icon: String) -> String {
        switch icon {
        case "sparkles": "반짝임"
        case "plus.bubble": "새 대화"
        case "message": "메시지"
        case "mic": "마이크"
        case "paperplane": "전송"
        case "globe": "웹"
        case "safari": "Safari"
        case "folder": "폴더"
        case "note.text": "메모"
        case "calendar": "캘린더"
        case "magnifyingglass": "검색"
        case "camera.viewfinder": "캡처"
        case "lock": "잠금"
        case "play.fill": "재생"
        case "pause.fill": "일시 정지"
        case "stop.fill": "중지"
        case "record.circle": "녹화"
        case "speaker.wave.2": "볼륨"
        case "speaker.wave.1": "볼륨 내리기"
        case "speaker.slash": "음소거"
        case "headphones": "헤드폰"
        case "slider.horizontal.3": "조절"
        case "gearshape": "설정"
        case "terminal": "터미널"
        case "bolt.fill": "빠른 실행"
        default: icon
        }
    }

}

struct DarkTextField: View {
    @Environment(\.colorScheme) private var colorScheme
    private var theme: MacAppearance { MacAppearance(scheme: colorScheme) }
    @Binding var text: String
    var placeholder = ""

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(theme.foreground)
            .padding(.horizontal, 13)
            .frame(height: 34)
            .background(theme.input, in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(theme.foreground.opacity(0.22)))
    }
}
