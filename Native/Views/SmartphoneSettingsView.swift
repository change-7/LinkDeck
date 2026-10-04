import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SmartphoneSettingsView: View {
    @Environment(\.colorScheme) private var colorScheme
    private var theme: MacAppearance { MacAppearance(scheme: colorScheme) }
    private let editorPanelWidth: CGFloat = 270
    private let editorPanelPadding: CGFloat = 13
    private let actionGridSpacing: CGFloat = 6

    @Bindable var store: LaunchpadStore
    let runner: MacActionRunner
    @Binding var selectedMainScreen: MainScreen
    let codexIsConnected: Bool
    let midiIsConnected: Bool
    let onOpenBackupRestore: () -> Void
    let onOpenCodexSettings: () -> Void
    @State private var pageIndex = 0
    @State private var buttonIndex = 0
    @State private var dropTargetButtonID: String?
    @State private var dropTargetPageIndex: Int?
    @State private var registrationError = ""
    @State private var folderButtonID: String?
    @State private var folderUsesLongPress = false
    @State private var editingLongPress = false
    @State private var isCustomIconDropTargeted = false
    @State private var customIconError = ""
    @State private var isSymbolPickerPresented = false
    @State private var symbolSearchText = ""

    private let symbolChoices = [
        // 아이콘 없음
        "",

        // 실행 및 탐색
        "play.fill", "pause.fill", "stop.fill", "forward.fill", "backward.fill",
        "play.circle.fill", "pause.circle.fill", "stop.circle.fill", "forward.end.fill", "backward.end.fill",
        "arrow.left", "arrow.right", "arrow.up", "arrow.down", "chevron.left", "chevron.right",
        "chevron.up", "chevron.down", "arrow.clockwise", "arrow.counterclockwise", "arrow.uturn.backward",

        // 앱 및 기기
        "terminal", "terminal.fill", "macwindow", "macwindow.on.rectangle", "display", "laptopcomputer",
        "iphone", "ipad", "applelogo", "command", "option", "control", "power", "computermouse",
        "keyboard", "printer", "externaldrive", "server.rack", "cpu", "wrench.and.screwdriver",

        // 파일 및 생산성
        "globe", "globe.americas", "safari", "folder", "folder.fill", "doc", "doc.text", "doc.richtext",
        "doc.plaintext", "newspaper", "archivebox", "tray", "tray.full", "paperclip", "link",
        "bookmark", "bookmark.fill", "tag", "tag.fill", "calendar", "clock", "checklist",
        "list.bullet", "list.number", "pencil", "highlighter", "square.and.pencil", "note.text",

        // 검색, 통신 및 공유
        "magnifyingglass", "scope", "at", "envelope", "envelope.fill", "message", "message.fill",
        "bubble.left", "bubble.left.and.bubble.right", "phone", "phone.fill", "video", "video.fill",
        "person.fill", "person.2.fill", "person.crop.circle", "bell", "bell.fill", "qrcode",
        "square.and.arrow.up", "square.and.arrow.down", "arrow.down.circle", "arrow.up.circle",

        // 미디어
        "camera.viewfinder", "doc.on.clipboard", "music.note", "speaker.wave.2", "moon",
        "camera.fill", "photo", "photo.fill", "photo.on.rectangle", "film", "tv", "play.rectangle.fill",
        "headphones", "mic", "mic.fill", "speaker.slash", "speaker.wave.1", "speaker.wave.3",
        "gamecontroller", "record.circle", "shuffle", "repeat", "rectangle.on.rectangle",

        // 웹, 네트워크 및 클라우드
        "wifi", "wifi.exclamationmark", "antenna.radiowaves.left.and.right", "network", "cloud",
        "cloud.fill", "icloud.and.arrow.up", "icloud.and.arrow.down", "bolt.horizontal.circle", "externaldrive.connected.to.line.below",
        "lock.shield", "key", "key.fill", "lock.open", "lock.fill", "eye", "eye.slash",

        // 시스템 및 상태
        "gearshape", "gear", "slider.horizontal.3", "ellipsis", "ellipsis.circle", "plus", "minus",
        "xmark", "checkmark", "checkmark.circle", "checkmark.circle.fill", "xmark.circle", "xmark.circle.fill",
        "questionmark", "questionmark.circle", "info.circle", "exclamationmark.triangle", "exclamationmark.circle",
        "bolt", "bolt.fill", "wand.and.stars", "sparkles", "flame", "sun.max", "moon.stars", "cloud.sun",
        "house", "house.fill", "heart", "heart.fill", "star", "star.fill", "flag", "flag.fill",
        "pin", "pin.fill", "location", "location.fill", "map", "mappin", "cart", "creditcard",

        // 숫자 및 개발 도구
        "1.circle.fill", "2.circle.fill", "3.circle.fill", "4.circle.fill", "5.circle.fill", "6.circle.fill",
        "7.circle.fill", "8.circle.fill", "9.circle.fill", "10.circle.fill", "number", "percent",
        "chevron.left.forwardslash.chevron.right", "curlybraces", "function", "sum", "hammer", "shippingbox",
        "chart.bar", "chart.line.uptrend.xyaxis", "gauge.with.dots.needle.67percent", "speedometer"
    ]

    private var page: SmartphonePage { store.smartphonePages[pageIndex] }
    private var selectedButton: SmartphoneButton { page.buttons[buttonIndex] }
    private var selectedAction: PadAction { editingLongPress ? selectedButton.longPressAction : selectedButton.action }
    private var imageIconBacking: Color {
        colorScheme == .light ? Color(red: 0.54, green: 0.60, blue: 0.70) : .clear
    }

    var body: some View {
        GeometryReader { geometry in
            HStack(alignment: .top, spacing: 12) {
                pageList
                buttonGrids
                ScrollView(.vertical) {
                    editor
                }
                .frame(width: editorPanelWidth, height: max(0, geometry.size.height - 28))
                .scrollIndicators(.visible)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(14)
        }
        .foregroundStyle(theme.foreground)
        .background(theme.canvas)
        .overlay {
            if let folderButtonID {
                ZStack {
                    Color.black.opacity(0.34)
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture { self.folderButtonID = nil }

                    SmartphoneFolderEditorView(
                        store: store,
                        pageIndex: pageIndex,
                        folderButtonID: folderButtonID,
                        folderUsesLongPress: folderUsesLongPress
                    )
                    .contentShape(Rectangle())
                    .onTapGesture { }
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(theme.foreground.opacity(0.14)))
                    .shadow(color: .black.opacity(0.55), radius: 28, y: 12)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
                .zIndex(100)
            }
        }
    }

    private var pageList: some View {
        VStack(alignment: .leading, spacing: 9) {
            MainScreenSidebarNavigation(
                selection: $selectedMainScreen,
                midiIsConnected: midiIsConnected
            )
            .padding(.bottom, 5)
            Text("스마트폰 페이지").font(.system(size: 12, weight: .bold)).foregroundStyle(.secondary)
            Text("현재 페이지 이름")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(theme.foreground.opacity(0.72))
            DarkTextField(text: pageNameBinding, placeholder: "페이지 이름")
            ForEach(Array(store.smartphonePages.enumerated()), id: \.element.id) { index, page in
                VStack(spacing: 0) {
                    Button {
                        pageIndex = index
                        buttonIndex = 0
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("PAGE \(String(format: "%02d", index + 1))")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(index == pageIndex ? theme.accent : .secondary)
                            Text(page.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(index == dropTargetPageIndex ? theme.accent.opacity(0.24) : index == pageIndex ? theme.accent.opacity(0.18) : theme.control, in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(index == dropTargetPageIndex || index == pageIndex ? theme.accent : theme.foreground.opacity(0.22)))
                    }
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .dropDestination(for: String.self) { items, _ in
                    guard let source = items.first,
                          let sourceLocation = smartphoneDragLocation(source),
                          sourceLocation.pageIndex != index else { return false }
                    dropTargetPageIndex = nil
                    pageIndex = index
                    buttonIndex = 0
                    return true
                } isTargeted: { isTargeted in
                    if isTargeted {
                        dropTargetPageIndex = index
                        pageIndex = index
                        buttonIndex = 0
                    } else if dropTargetPageIndex == index {
                        dropTargetPageIndex = nil
                    }
                }
                .help("버튼을 든 채 이 페이지 이름 위에 올리면 페이지가 열립니다. 원하는 버튼 칸에 놓으세요.")
            }
            Spacer(minLength: 8)
            MainSidebarFooter(
                codexIsConnected: codexIsConnected,
                midiIsConnected: midiIsConnected,
                onOpenBackupRestore: onOpenBackupRestore,
                onOpenCodexSettings: onOpenCodexSettings
            )
        }
        .frame(width: 150, alignment: .leading)
        .padding(10)
        .background(theme.panel, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(theme.border))
    }

    private var buttonGrids: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(store.smartphonePages.enumerated()), id: \.element.id) { index, page in
                buttonGrid(page: page, at: index)
                    .opacity(index == pageIndex ? 1 : 0)
                    .zIndex(index == pageIndex ? 1 : 0)
                    .allowsHitTesting(index == pageIndex)
                    .accessibilityHidden(index != pageIndex)
            }
        }
    }

    private func buttonGrid(page: SmartphonePage, at gridPageIndex: Int) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("\(page.name) · 버튼 선택").font(.system(size: 12, weight: .bold)).foregroundStyle(.secondary)
                Spacer()
                Label("드래그로 위치 교환", systemImage: "arrow.left.arrow.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(theme.accent.opacity(0.9))
                    .help("같은 페이지 버튼 위에 놓거나, 다른 페이지 이름에 올려 페이지를 연 뒤 원하는 칸에 놓습니다.")
                Text("\(page.buttons.filter { $0.action.kind != .none || $0.longPressAction.kind != .none }.count)/16 동작 지정")
                    .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                ForEach(Array(page.buttons.enumerated()), id: \.element.id) { index, button in
                    buttonCell(index: index, button: button, pageIndex: gridPageIndex)
                }
            }
            Spacer()
        }
        .frame(minWidth: 350, maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(theme.panel, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(theme.border))
    }

    private func buttonCell(index: Int, button: SmartphoneButton, pageIndex buttonPageIndex: Int) -> some View {
        ZStack(alignment: .topTrailing) {
            Button {
                pageIndex = buttonPageIndex
                buttonIndex = index
                if button.action.kind == .appFolder || button.longPressAction.kind == .appFolder {
                    folderUsesLongPress = button.action.kind != .appFolder || (editingLongPress && button.longPressAction.kind == .appFolder)
                    folderButtonID = button.id
                }
            } label: {
                VStack(spacing: 6) {
                    buttonIcon(for: button, isSelected: buttonPageIndex == pageIndex && index == buttonIndex)
                    if !button.title.isEmpty {
                        Text(button.title)
                            .font(.system(size: 11, weight: .medium))
                            .lineLimit(1)
                    }
                    if button.action.kind != .none || button.longPressAction.kind != .none {
                        Text(button.longPressAction.kind == .none ? button.action.kind.title : (button.action.kind == .none ? "길게 · \(button.longPressAction.kind.title)" : "짧게 / 길게"))
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 78)
                .padding(7)
                .background(buttonPageIndex == pageIndex && index == buttonIndex ? theme.accent.opacity(0.2) : theme.control, in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(buttonPageIndex == pageIndex && index == buttonIndex ? theme.accent : theme.foreground.opacity(0.22), lineWidth: buttonPageIndex == pageIndex && index == buttonIndex ? 1.5 : 1))
                .overlay {
                    RoundedRectangle(cornerRadius: 9)
                        .stroke(theme.accent, lineWidth: 2)
                        .opacity(dropTargetButtonID == button.id ? 1 : 0)
                }
            }
            .buttonStyle(.plain)
            .focusEffectDisabled()
            .accessibilityLabel(button.title.isEmpty ? "비어 있는 스마트폰 버튼 슬롯" : button.title)
            .accessibilityHint("선택하여 버튼을 편집합니다.")

            Image(systemName: "line.3.horizontal")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(theme.foreground.opacity(0.55))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
                .draggable("\(buttonPageIndex)|\(button.id)") {
                    Label(button.title.isEmpty ? "빈 버튼" : button.title, systemImage: button.symbol.isEmpty ? "square" : button.symbol)
                        .padding(8)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                }
                .accessibilityLabel("\(button.title.isEmpty ? "빈 버튼" : button.title) 이동")
                .accessibilityHint("같은 페이지 버튼에 놓거나, 다른 페이지 이름 위에 올려 페이지를 연 뒤 원하는 칸에 놓습니다.")
                .help("이 손잡이를 같은 페이지 버튼 위로 드래그하거나, 다른 페이지 이름 위에 올려 페이지를 연 뒤 원하는 칸에 놓습니다.")
        }
        .dropDestination(for: String.self) { items, _ in
            guard let source = items.first,
                  let sourceLocation = smartphoneDragLocation(source) else { return false }
            dropTargetButtonID = nil
            let didSwap: Bool
            if sourceLocation.pageIndex == buttonPageIndex {
                didSwap = sourceLocation.buttonID != button.id && store.swapSmartphoneButtonConfigurations(
                    pageIndex: buttonPageIndex,
                    from: sourceLocation.buttonID,
                    to: button.id
                )
            } else {
                didSwap = store.swapSmartphoneButtonConfigurations(
                    fromPageIndex: sourceLocation.pageIndex,
                    from: sourceLocation.buttonID,
                    toPageIndex: buttonPageIndex,
                    to: button.id
                )
            }
            guard didSwap else {
                return false
            }
            pageIndex = buttonPageIndex
            buttonIndex = index
            return true
        } isTargeted: { isTargeted in
            if isTargeted {
                dropTargetButtonID = button.id
            } else if dropTargetButtonID == button.id {
                dropTargetButtonID = nil
            }
        }
    }

    private func smartphoneDragLocation(_ value: String) -> (pageIndex: Int, buttonIndex: Int, buttonID: String)? {
        let components = value.split(separator: "|", maxSplits: 1).map(String.init)
        guard components.count == 2,
              let sourcePageIndex = Int(components[0]),
              store.smartphonePages.indices.contains(sourcePageIndex),
              let sourceButtonIndex = store.smartphonePages[sourcePageIndex].buttons.firstIndex(where: { $0.id == components[1] }) else {
            return nil
        }
        return (sourcePageIndex, sourceButtonIndex, components[1])
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("버튼 편집").font(.system(size: 12, weight: .bold)).foregroundStyle(.secondary)
                Spacer()
                Button(role: .destructive) { store.clearSmartphoneButton(pageIndex: pageIndex, buttonIndex: buttonIndex) } label: {
                    Image(systemName: "trash").frame(width: 28, height: 26)
                }
                .buttonStyle(.plain)
                .help("이 스마트폰 버튼의 이름, 아이콘, 기능을 비웁니다.")
            }
            DarkTextField(text: buttonTextBinding, placeholder: "버튼 라벨")
            field("아이콘 선택") { symbolPicker }
            customIconPicker
            Divider().overlay(theme.foreground.opacity(0.16))
            Picker("누르기 방식", selection: $editingLongPress) {
                Text("짧게 누르기").tag(false)
                Text("길게 누르기").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .onChange(of: editingLongPress) { registrationError = "" }
            field("실행 동작") {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: actionGridSpacing) {
                    actionButton(.app)
                    actionButton(.shortcut)
                    actionButton(.terminalCommand)
                    actionButton(.url)
                    actionButton(.clipboardText)
                    actionButton(.appFolder)
                }
            }
            actionRegistration
            if selectedAction.kind != .none {
                Button("Mac에서 이 동작 실행") { runSelectedAction() }
                    .font(.system(size: 11, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .foregroundStyle(theme.accent)
                    .background(theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                    .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(editorPanelPadding)
        .frame(width: editorPanelWidth, alignment: .leading)
        .background(theme.panel, in: RoundedRectangle(cornerRadius: 13))
        .overlay(RoundedRectangle(cornerRadius: 13).stroke(theme.foreground.opacity(0.16)))
    }

    private var symbolPicker: some View {
        Button {
            symbolSearchText = ""
            isSymbolPickerPresented.toggle()
        } label: {
            HStack(spacing: 8) {
                symbolGlyph(selectedButton.symbol, size: 15)
                    .frame(width: 22, height: 22)
                Text(selectedButton.symbol.isEmpty ? "아이콘 없음" : selectedButton.symbol)
                    .font(.system(size: 10, design: .monospaced))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Image(systemName: isSymbolPickerPresented ? "chevron.up" : "chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 9)
            .frame(maxWidth: .infinity, minHeight: 32)
            .foregroundStyle(theme.foreground.opacity(0.86))
            .background(theme.foreground.opacity(0.055), in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(theme.foreground.opacity(0.18)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("아이콘 선택: \(selectedButton.symbol.isEmpty ? "아이콘 없음" : selectedButton.symbol)")
        .overlay(alignment: .topLeading) {
            if isSymbolPickerPresented {
                symbolPopover
                    .offset(y: 39)
                    .zIndex(100)
            }
        }
        .zIndex(isSymbolPickerPresented ? 100 : 0)
    }

    private var symbolPopover: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                DarkTextField(text: $symbolSearchText, placeholder: "아이콘 검색")
            }
            ScrollView(.vertical) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
                    ForEach(filteredSymbolChoices, id: \.self) { symbol in
                        symbolChoiceButton(symbol)
                    }
                }
            }
            .frame(height: 220)
            Text("\(filteredSymbolChoices.count)개 아이콘")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(11)
        .frame(width: 250)
        .foregroundStyle(theme.foreground)
        .background(theme.panel, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.foreground.opacity(0.16)))
        .shadow(color: .black.opacity(0.48), radius: 16, y: 8)
    }

    private var filteredSymbolChoices: [String] {
        let choices = symbolChoices.contains(selectedButton.symbol)
            ? symbolChoices
            : [selectedButton.symbol] + symbolChoices
        let query = symbolSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return choices }
        return choices.filter { symbol in
            let title = symbol.isEmpty ? "아이콘 없음" : symbol
            return title.localizedCaseInsensitiveContains(query)
        }
    }

    private func symbolChoiceButton(_ symbol: String) -> some View {
        Button {
            var button = selectedButton
            button.symbol = symbol
            update(button)
            isSymbolPickerPresented = false
        } label: {
            symbolGlyph(symbol, size: 17)
                .frame(maxWidth: .infinity, minHeight: 34)
                .foregroundStyle(selectedButton.symbol == symbol ? theme.accentForeground : theme.foreground.opacity(0.78))
                .background(
                    selectedButton.symbol == symbol ? theme.accent : theme.foreground.opacity(0.06),
                    in: RoundedRectangle(cornerRadius: 6)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(selectedButton.symbol == symbol ? theme.accent : theme.foreground.opacity(0.2))
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(symbol.isEmpty ? "아이콘 없음" : symbol)
        .help(symbol.isEmpty ? "아이콘 없음" : symbol)
    }

    @ViewBuilder
    private func symbolGlyph(_ symbol: String, size: CGFloat) -> some View {
        if symbol.isEmpty {
            RoundedRectangle(cornerRadius: 4)
                .stroke(theme.foreground.opacity(0.36), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                .padding(7)
        } else {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .medium))
        }
    }

    @ViewBuilder
    private var customIconPicker: some View {
        HStack(spacing: 8) {
            Group {
                if let customIconData = selectedButton.customIconData,
                   let image = NSImage(data: customIconData) {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .padding(4)
                } else {
                    Image(systemName: "photo")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 38, height: 38)
            .background(theme.foreground.opacity(0.055), in: RoundedRectangle(cornerRadius: 7))
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(isCustomIconDropTargeted ? theme.accent : theme.foreground.opacity(0.18), lineWidth: isCustomIconDropTargeted ? 1.5 : 1)
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(selectedButton.customIconData == nil ? "PNG 없음" : "PNG 적용됨")
                    .font(.system(size: 10, weight: .semibold))
                Text("복사 후 붙여넣기 또는 드래그")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 2)
            Button("선택") { chooseCustomIcon() }
                .font(.system(size: 10, weight: .semibold))
                .buttonStyle(.plain)
                .foregroundStyle(theme.accent)
            Button("붙여넣기") { pasteCustomIcon() }
                .font(.system(size: 10, weight: .semibold))
                .buttonStyle(.plain)
                .foregroundStyle(theme.accent)
            if selectedButton.customIconData != nil {
                Button("제거") { clearCustomIcon() }
                    .font(.system(size: 10, weight: .semibold))
                    .buttonStyle(.plain)
                    .foregroundStyle(.red.opacity(0.9))
            }
        }
        .padding(7)
        .background(theme.foreground.opacity(0.045), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.foreground.opacity(0.18)))
        .onDrop(
            of: [UTType.fileURL.identifier, UTType.png.identifier],
            isTargeted: $isCustomIconDropTargeted,
            perform: importDroppedIcon
        )
        .onPasteCommand(of: [UTType.png, UTType.fileURL]) { _ in
            pasteCustomIcon()
        }
        if !customIconError.isEmpty {
            Text(customIconError)
                .font(.system(size: 9))
                .foregroundStyle(.red.opacity(0.9))
        }
    }

    private var folderShortcutEditor: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("폴더 안 단축키")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(theme.foreground.opacity(0.72))
                Spacer()
                Button {
                    addFolderShortcut()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .foregroundStyle(theme.accent)
                .help("앱 폴더에 단축키를 추가합니다.")
            }
            if selectedButton.folderShortcuts.isEmpty {
                Text("등록된 단축키가 없습니다.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            } else {
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(selectedButton.folderShortcuts) { shortcut in
                            folderShortcutRow(shortcut)
                        }
                    }
                }
                .frame(maxHeight: 260)
            }
        }
        .padding(9)
        .background(theme.foreground.opacity(0.045), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.foreground.opacity(0.16)))
    }

    private func folderShortcutRow(_ shortcut: SmartphoneFolderShortcut) -> some View {
        let binding = folderShortcutBinding(id: shortcut.id)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                TextField("단축키 이름", text: binding.title)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 5)
                    .background(theme.foreground.opacity(0.07), in: RoundedRectangle(cornerRadius: 6))
                Button(role: .destructive) {
                    removeFolderShortcut(id: shortcut.id)
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(.plain)
                .help("이 단축키를 삭제합니다.")
            }
            HStack(spacing: 6) {
                Image(systemName: binding.wrappedValue.symbol.isEmpty ? "command" : binding.wrappedValue.symbol)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(theme.accent)
                TextField("SF Symbol", text: binding.symbol)
                    .textFieldStyle(.plain)
                    .font(.system(size: 10, design: .monospaced))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 5)
                    .background(theme.foreground.opacity(0.07), in: RoundedRectangle(cornerRadius: 6))
            }
            Text("짧게: \(shortcut.action.kind.title) · 길게: \(shortcut.longPressAction.kind.title)")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Button("짧게·길게 동작 편집") {
                folderUsesLongPress = editingLongPress
                folderButtonID = selectedButton.id
            }
            .buttonStyle(.plain)
            .foregroundStyle(theme.accent)
        }
        .padding(7)
        .background(theme.foreground.opacity(0.055), in: RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(theme.foreground.opacity(0.16)))
    }

    @ViewBuilder
    private func buttonIcon(for button: SmartphoneButton, isSelected: Bool) -> some View {
        let iconAction = button.action.kind == .none ? button.longPressAction : button.action
        let appBundleIdentifier: String? = switch iconAction.kind {
        case .app, .appFolder: iconAction.value
        case .shortcut: iconAction.targetAppBundleIdentifier
        case .terminalCommand, .url, .clipboardText, .none: nil
        }

        if let customIconData = button.customIconData,
           let customIcon = NSImage(data: customIconData) {
            Image(nsImage: customIcon)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 24, height: 24)
                .background(imageIconBacking, in: RoundedRectangle(cornerRadius: 5))
                .opacity(isSelected ? 1 : 0.82)
        } else if button.symbol.isEmpty {
            Color.clear
                .frame(width: 24, height: 24)
        } else if let appBundleIdentifier,
           !appBundleIdentifier.isEmpty,
           let appIcon = AppRegistrationService.icon(for: appBundleIdentifier) {
            Image(nsImage: appIcon)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 24, height: 24)
                .background(imageIconBacking, in: RoundedRectangle(cornerRadius: 5))
                .opacity(isSelected ? 1 : 0.82)
        } else {
            Image(systemName: button.symbol)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(isSelected ? theme.accent : theme.foreground.opacity(0.72))
        }
    }

    private func field<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(theme.foreground.opacity(0.72))
            content()
        }
        .zIndex(title == "아이콘 선택" && isSymbolPickerPresented ? 100 : 0)
    }

    private func actionButton(_ kind: ActionKind) -> some View {
        Button(kind.title) {
            var button = selectedButton
            var action = selectedAction
            let previousKind = action.kind
            action.kind = kind
            if previousKind != kind {
                action.value = kind == .url ? "https://chatgpt.com" : ""
                action.targetAppBundleIdentifier = ""
            }
            if kind != .shortcut { action.targetAppBundleIdentifier = "" }
            if editingLongPress { button.longPressAction = action } else { button.action = action }
            if button.action.kind != .appFolder && button.longPressAction.kind != .appFolder { button.folderShortcuts = [] }
            update(button)
        }
        .font(.system(size: 10, weight: .semibold))
        .padding(.horizontal, 7)
        .frame(maxWidth: .infinity, minHeight: 38)
        .foregroundStyle(selectedAction.kind == kind ? theme.accentForeground : theme.foreground.opacity(0.72))
        .background(selectedAction.kind == kind ? theme.accent : theme.foreground.opacity(0.075), in: RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(selectedAction.kind == kind ? theme.accent : theme.foreground.opacity(0.2)))
        .buttonStyle(.plain)
    }

    @ViewBuilder private var actionRegistration: some View {
        switch selectedAction.kind {
        case .app, .appFolder:
            Button(selectedAction.kind == .appFolder ? "앱 폴더 등록" : "앱 등록") {
                registerApplication(kind: selectedAction.kind)
            }
                .font(.system(size: 11, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(theme.foreground.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
                .buttonStyle(.plain)
            if !selectedAction.value.isEmpty {
                Text(AppRegistrationService.displayName(for: selectedAction.value) ?? selectedAction.value)
                    .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1)
            }
            if selectedAction.kind == .appFolder {
                folderShortcutEditor
            }
        case .shortcut:
            ShortcutComposerView(value: actionValueBinding, targetAppBundleIdentifier: targetAppBinding, launchTargetAppIfNeeded: launchTargetBinding)
                .id("\(selectedButton.id)-\(editingLongPress)")
        case .terminalCommand:
            DarkTextField(text: actionValueBinding, placeholder: "예: open -a Safari")
            Toggle("터미널 창 표시", isOn: selectedActionBinding.showTerminalWindow)
                .toggleStyle(.checkbox)
        case .url:
            DarkTextField(text: actionValueBinding, placeholder: "https://example.com")
            URLTabPicker(openInCurrentTab: selectedActionBinding.openURLInCurrentTab)
        case .clipboardText:
            VStack(alignment: .leading, spacing: 6) {
                Text("버튼을 누르면 현재 활성 앱에 붙여넣습니다.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                TextEditor(text: actionValueBinding)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(theme.foreground)
                    .scrollContentBackground(.hidden)
                    .padding(7)
                    .frame(minHeight: 92, maxHeight: 140)
                    .background(theme.input, in: RoundedRectangle(cornerRadius: 9))
                    .overlay(RoundedRectangle(cornerRadius: 9).stroke(theme.foreground.opacity(0.22)))
            }
        case .none:
            Text(editingLongPress ? "길게 눌렀을 때 실행할 동작이 없습니다." : "짧게 눌렀을 때 실행할 동작이 없습니다.")
                .font(.system(size: 10)).foregroundStyle(.secondary)
        }
        if !registrationError.isEmpty { Text(registrationError).font(.system(size: 10)).foregroundStyle(.red) }
    }

    private var buttonTextBinding: Binding<String> { Binding(get: { selectedButton.title }, set: { var button = selectedButton; button.title = $0; update(button) }) }
    private var pageNameBinding: Binding<String> { Binding(get: { page.name }, set: { store.updateSmartphonePageName($0, at: pageIndex) }) }
    private var selectedActionBinding: Binding<PadAction> {
        Binding(get: { selectedAction }, set: { action in
            var button = selectedButton
            if editingLongPress { button.longPressAction = action } else { button.action = action }
            update(button)
        })
    }
    private var actionValueBinding: Binding<String> { selectedActionBinding.value }
    private var targetAppBinding: Binding<String> { selectedActionBinding.targetAppBundleIdentifier }
    private var launchTargetBinding: Binding<Bool> { selectedActionBinding.launchTargetAppIfNeeded }

    private func folderShortcutBinding(id: String) -> Binding<SmartphoneFolderShortcut> {
        Binding(
            get: {
                selectedButton.folderShortcuts.first(where: { $0.id == id })
                    ?? SmartphoneFolderShortcut(id: id)
            },
            set: { shortcut in
                var button = selectedButton
                guard let index = button.folderShortcuts.firstIndex(where: { $0.id == id }) else { return }
                button.folderShortcuts[index] = shortcut
                update(button)
            }
        )
    }

    private func update(_ button: SmartphoneButton) { store.updateSmartphoneButton(button, at: pageIndex) }

    private func chooseCustomIcon() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let data = try? Data(contentsOf: url) else {
            customIconError = "PNG 파일을 읽지 못했습니다."
            return
        }
        applyCustomIcon(data)
    }

    private func pasteCustomIcon() {
        if let data = SmartphoneIconData.dataFromPasteboard() {
            applyCustomIcon(data)
        } else {
            customIconError = "클립보드에서 PNG 이미지를 찾지 못했습니다."
        }
    }

    private func importDroppedIcon(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        customIconError = ""
        let targetButtonID = selectedButton.id
        let targetPageIndex = pageIndex

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
                Task { @MainActor in applyCustomIcon(data, buttonID: targetButtonID, page: targetPageIndex) }
            }
            return true
        }

        provider.loadDataRepresentation(forTypeIdentifier: UTType.png.identifier) { data, _ in
            guard let data else {
                Task { @MainActor in customIconError = "PNG 이미지를 읽지 못했습니다." }
                return
            }
            Task { @MainActor in applyCustomIcon(data, buttonID: targetButtonID, page: targetPageIndex) }
        }
        return true
    }

    private func applyCustomIcon(_ data: Data, buttonID: String? = nil, page: Int? = nil) {
        guard let normalized = SmartphoneIconData.normalizedPNGData(from: data) else {
            customIconError = "유효한 PNG 이미지만 추가할 수 있습니다."
            return
        }
        let targetPage = page ?? pageIndex
        let targetID = buttonID ?? selectedButton.id
        guard store.smartphonePages.indices.contains(targetPage),
              var button = store.smartphonePages[targetPage].buttons.first(where: { $0.id == targetID }) else { return }
        button.customIconData = normalized
        store.updateSmartphoneButton(button, at: targetPage)
        customIconError = ""
    }

    private func clearCustomIcon() {
        var button = selectedButton
        button.customIconData = nil
        update(button)
        customIconError = ""
    }

    private func addFolderShortcut() {
        var button = selectedButton
        let shortcut = SmartphoneFolderShortcut(
            id: "\(button.id)_folder_\(UUID().uuidString)",
            title: "단축키 \(button.folderShortcuts.count + 1)",
            symbol: "command",
            action: PadAction(kind: .shortcut, targetAppBundleIdentifier: selectedAction.value)
        )
        button.folderShortcuts.append(shortcut)
        update(button)
    }

    private func removeFolderShortcut(id: String) {
        var button = selectedButton
        button.folderShortcuts.removeAll { $0.id == id }
        update(button)
    }

    private func registerApplication(kind: ActionKind = .app) {
        registrationError = ""
        AppRegistrationService.chooseApplication { result in
            switch result {
            case .success(let application):
                var button = selectedButton
                let previousApp = selectedAction.value
                var action = selectedAction
                action.kind = kind
                action.value = application.bundleIdentifier
                action.targetAppBundleIdentifier = ""
                if editingLongPress { button.longPressAction = action } else { button.action = action }
                if button.title.isEmpty { button.title = application.name }
                if kind == .appFolder {
                    button.folderShortcuts = button.folderShortcuts.map { shortcut in
                        var updatedShortcut = shortcut
                        if updatedShortcut.action.targetAppBundleIdentifier == previousApp {
                            updatedShortcut.action.targetAppBundleIdentifier = application.bundleIdentifier
                        }
                        if updatedShortcut.longPressAction.targetAppBundleIdentifier == previousApp {
                            updatedShortcut.longPressAction.targetAppBundleIdentifier = application.bundleIdentifier
                        }
                        return updatedShortcut
                    }
                } else if button.action.kind != .appFolder && button.longPressAction.kind != .appFolder {
                    button.folderShortcuts = []
                }
                update(button)
            case .failure(let error): registrationError = error.localizedDescription
            }
        }
    }

    private func runSelectedAction() {
        do { store.statusMessage = try runner.execute(selectedAction, commandFileID: selectedButton.id + (editingLongPress ? "_long_press" : "")) }
        catch { store.statusMessage = error.localizedDescription }
    }
}
