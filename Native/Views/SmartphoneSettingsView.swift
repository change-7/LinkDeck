import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SmartphoneSettingsView: View {
    @Bindable var store: LaunchpadStore
    let runner: MacActionRunner
    @State private var pageIndex = 0
    @State private var buttonIndex = 0
    @State private var dropTargetButtonID: String?
    @State private var registrationError = ""
    @State private var folderButtonID: String?
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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                pageList
                buttonGrid
                editor
            }
        }
        .padding(14)
        .foregroundStyle(.white)
        .background(Color(red: 0.035, green: 0.035, blue: 0.045))
        .onChange(of: pageIndex) { _, _ in buttonIndex = 0 }
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
                        folderButtonID: folderButtonID
                    )
                    .contentShape(Rectangle())
                    .onTapGesture { }
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.14)))
                    .shadow(color: .black.opacity(0.55), radius: 28, y: 12)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
                .zIndex(100)
            }
        }
    }

    private var pageList: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("스마트폰 페이지").font(.system(size: 12, weight: .bold)).foregroundStyle(.secondary)
            Text("현재 페이지 이름")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.72))
            DarkTextField(text: pageNameBinding, placeholder: "페이지 이름")
            ForEach(Array(store.smartphonePages.enumerated()), id: \.element.id) { index, page in
                Button { pageIndex = index } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("PAGE \(String(format: "%02d", index + 1))")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(index == pageIndex ? .orange : .secondary)
                        Text(page.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(index == pageIndex ? Color.orange.opacity(0.14) : Color.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(index == pageIndex ? .orange : .white.opacity(0.10)))
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .frame(width: 150, alignment: .leading)
        .padding(10)
        .background(Color.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.08)))
    }

    private var buttonGrid: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("\(page.name) · 버튼 선택").font(.system(size: 12, weight: .bold)).foregroundStyle(.secondary)
                Spacer()
                Label("드래그로 위치 교환", systemImage: "arrow.left.arrow.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.orange.opacity(0.9))
                    .help("버튼을 다른 버튼 위로 드래그하면 두 버튼의 위치를 교환합니다.")
                Text("\(page.buttons.filter { $0.action.kind != .none }.count)/16 동작 지정")
                    .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                ForEach(Array(page.buttons.enumerated()), id: \.element.id) { index, button in
                    buttonCell(index: index, button: button)
                }
            }
            Spacer()
        }
        .frame(minWidth: 350, maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.08)))
    }

    private func buttonCell(index: Int, button: SmartphoneButton) -> some View {
        ZStack(alignment: .topTrailing) {
            Button {
                buttonIndex = index
                if button.action.kind == .appFolder {
                    folderButtonID = button.id
                }
            } label: {
                VStack(spacing: 6) {
                    buttonIcon(for: button, isSelected: index == buttonIndex)
                    if !button.title.isEmpty {
                        Text(button.title)
                            .font(.system(size: 11, weight: .medium))
                            .lineLimit(1)
                    }
                    if button.action.kind != .none {
                        Text(button.action.kind.title)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 78)
                .padding(7)
                .background(index == buttonIndex ? Color.orange.opacity(0.15) : Color.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(index == buttonIndex ? .orange : .white.opacity(0.12), lineWidth: index == buttonIndex ? 1.5 : 1))
                .overlay {
                    RoundedRectangle(cornerRadius: 9)
                        .stroke(.orange, lineWidth: 2)
                        .opacity(dropTargetButtonID == button.id ? 1 : 0)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(button.title.isEmpty ? "비어 있는 스마트폰 버튼 슬롯" : button.title)
            .accessibilityHint("선택하여 버튼을 편집합니다.")

            Image(systemName: "line.3.horizontal")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(0.55))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
                .draggable(button.id) {
                    Label(button.title.isEmpty ? "빈 버튼" : button.title, systemImage: button.symbol.isEmpty ? "square" : button.symbol)
                        .padding(8)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                }
                .accessibilityLabel("\(button.title.isEmpty ? "빈 버튼" : button.title) 이동")
                .accessibilityHint("다른 버튼 위로 드래그해 위치를 교환합니다.")
                .help("이 손잡이를 드래그하여 버튼 위치를 교환합니다.")
        }
        .dropDestination(for: String.self) { items, _ in
            guard let sourceID = items.first else { return false }
            dropTargetButtonID = nil
            guard sourceID != button.id,
                  store.swapSmartphoneButtonConfigurations(
                    pageIndex: pageIndex,
                    from: sourceID,
                    to: button.id
                  ) else {
                return false
            }
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
            field("버튼 라벨") { DarkTextField(text: buttonTextBinding) }
            field("아이콘 선택") { symbolPicker }
            field("사용자 PNG 아이콘") { customIconPicker }
            Divider().overlay(.white.opacity(0.16))
            field("실행 동작") {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                    actionButton(.app)
                    actionButton(.shortcut)
                    actionButton(.terminalCommand)
                    actionButton(.url)
                    actionButton(.clipboardText)
                    actionButton(.appFolder)
                }
            }
            actionRegistration
            if selectedButton.action.kind != .none {
                Button("Mac에서 이 동작 실행") { runSelectedAction() }
                    .font(.system(size: 11, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .foregroundStyle(.orange)
                    .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                    .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(13)
        .frame(width: 270, alignment: .leading)
        .background(Color(red: 0.065, green: 0.065, blue: 0.08), in: RoundedRectangle(cornerRadius: 13))
        .overlay(RoundedRectangle(cornerRadius: 13).stroke(.white.opacity(0.12)))
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
            .foregroundStyle(.white.opacity(0.86))
            .background(.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(.white.opacity(0.12)))
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
        .foregroundStyle(.white)
        .background(Color(red: 0.075, green: 0.075, blue: 0.09), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.16)))
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
                .foregroundStyle(selectedButton.symbol == symbol ? .black : .white.opacity(0.78))
                .background(
                    selectedButton.symbol == symbol ? Color.orange : Color.black.opacity(0.28),
                    in: RoundedRectangle(cornerRadius: 6)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(selectedButton.symbol == symbol ? .orange : .white.opacity(0.12))
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
                .stroke(.white.opacity(0.36), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
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
            .background(.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 7))
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(isCustomIconDropTargeted ? .orange : .white.opacity(0.12), lineWidth: isCustomIconDropTargeted ? 1.5 : 1)
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(selectedButton.customIconData == nil ? "PNG 없음" : "사용자 PNG 적용")
                    .font(.system(size: 10, weight: .semibold))
                Text("복사 후 붙여넣기 또는 드래그")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 2)
            Button("붙여넣기") { pasteCustomIcon() }
                .font(.system(size: 10, weight: .semibold))
                .buttonStyle(.plain)
                .foregroundStyle(.orange)
            if selectedButton.customIconData != nil {
                Button("제거") { clearCustomIcon() }
                    .font(.system(size: 10, weight: .semibold))
                    .buttonStyle(.plain)
                    .foregroundStyle(.red.opacity(0.9))
            }
        }
        .padding(7)
        .background(.black.opacity(0.24), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.12)))
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
                    .foregroundStyle(.white.opacity(0.72))
                Spacer()
                Button {
                    addFolderShortcut()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.orange)
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
        .background(.black.opacity(0.24), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.12)))
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
                    .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 6))
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
                    .foregroundStyle(.orange)
                TextField("SF Symbol", text: binding.symbol)
                    .textFieldStyle(.plain)
                    .font(.system(size: 10, design: .monospaced))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 5)
                    .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 6))
            }
            ShortcutComposerView(
                value: binding.action.value,
                targetAppBundleIdentifier: binding.action.targetAppBundleIdentifier,
                launchTargetAppIfNeeded: binding.action.launchTargetAppIfNeeded
            )
        }
        .padding(7)
        .background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(.white.opacity(0.08)))
    }

    @ViewBuilder
    private func buttonIcon(for button: SmartphoneButton, isSelected: Bool) -> some View {
        let appBundleIdentifier: String? = switch button.action.kind {
        case .app, .appFolder: button.action.value
        case .shortcut: button.action.targetAppBundleIdentifier
        case .terminalCommand, .url, .clipboardText, .none: nil
        }

        if let customIconData = button.customIconData,
           let customIcon = NSImage(data: customIconData) {
            Image(nsImage: customIcon)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 24, height: 24)
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
                .opacity(isSelected ? 1 : 0.82)
        } else {
            Image(systemName: button.symbol)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(isSelected ? .orange : .white.opacity(0.72))
        }
    }

    private func field<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.72))
            content()
        }
        .zIndex(title == "아이콘 선택" && isSymbolPickerPresented ? 100 : 0)
    }

    private func actionButton(_ kind: ActionKind) -> some View {
        Button(kind.title) {
            var button = selectedButton
            let previousKind = button.action.kind
            button.action.kind = kind
            if previousKind != kind {
                button.action.value = kind == .url ? "https://chatgpt.com" : ""
                button.action.targetAppBundleIdentifier = ""
            }
            if kind != .shortcut { button.action.targetAppBundleIdentifier = "" }
            if kind != .appFolder { button.folderShortcuts = [] }
            update(button)
        }
        .font(.system(size: 10, weight: .semibold))
        .padding(.horizontal, 7)
        .padding(.vertical, 7)
        .foregroundStyle(selectedButton.action.kind == kind ? .black : .white.opacity(0.72))
        .background(selectedButton.action.kind == kind ? Color.orange : Color.black.opacity(0.32), in: RoundedRectangle(cornerRadius: 7))
        .buttonStyle(.plain)
    }

    @ViewBuilder private var actionRegistration: some View {
        switch selectedButton.action.kind {
        case .app, .appFolder:
            Button(selectedButton.action.kind == .appFolder ? "앱 폴더 등록" : "앱 등록") {
                registerApplication(kind: selectedButton.action.kind)
            }
                .font(.system(size: 11, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
                .buttonStyle(.plain)
            if !selectedButton.action.value.isEmpty {
                Text(AppRegistrationService.displayName(for: selectedButton.action.value) ?? selectedButton.action.value)
                    .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1)
            }
            if selectedButton.action.kind == .appFolder {
                folderShortcutEditor
            }
        case .shortcut:
            ShortcutComposerView(value: actionValueBinding, targetAppBundleIdentifier: targetAppBinding, launchTargetAppIfNeeded: launchTargetBinding)
        case .terminalCommand:
            DarkTextField(text: actionValueBinding, placeholder: "예: open -a Safari")
        case .url:
            DarkTextField(text: actionValueBinding, placeholder: "https://example.com")
        case .clipboardText:
            VStack(alignment: .leading, spacing: 6) {
                Text("버튼을 누르면 현재 활성 앱에 붙여넣습니다.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                TextEditor(text: actionValueBinding)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)
                    .scrollContentBackground(.hidden)
                    .padding(7)
                    .frame(minHeight: 92, maxHeight: 140)
                    .background(Color(red: 0.01, green: 0.02, blue: 0.05), in: RoundedRectangle(cornerRadius: 9))
                    .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.white.opacity(0.22)))
            }
        case .none:
            Text("이 버튼은 휴대폰에서 비활성 상태로 표시됩니다.")
                .font(.system(size: 10)).foregroundStyle(.secondary)
        }
        if !registrationError.isEmpty { Text(registrationError).font(.system(size: 10)).foregroundStyle(.red) }
    }

    private var buttonTextBinding: Binding<String> { Binding(get: { selectedButton.title }, set: { var button = selectedButton; button.title = $0; update(button) }) }
    private var pageNameBinding: Binding<String> { Binding(get: { page.name }, set: { store.updateSmartphonePageName($0, at: pageIndex) }) }
    private var actionValueBinding: Binding<String> { Binding(get: { selectedButton.action.value }, set: { var button = selectedButton; button.action.value = $0; update(button) }) }
    private var targetAppBinding: Binding<String> { Binding(get: { selectedButton.action.targetAppBundleIdentifier }, set: { var button = selectedButton; button.action.targetAppBundleIdentifier = $0; update(button) }) }
    private var launchTargetBinding: Binding<Bool> { Binding(get: { selectedButton.action.launchTargetAppIfNeeded }, set: { var button = selectedButton; button.action.launchTargetAppIfNeeded = $0; update(button) }) }

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
                Task { @MainActor in applyCustomIcon(data) }
            }
            return true
        }

        provider.loadDataRepresentation(forTypeIdentifier: UTType.png.identifier) { data, _ in
            guard let data else {
                Task { @MainActor in customIconError = "PNG 이미지를 읽지 못했습니다." }
                return
            }
            Task { @MainActor in applyCustomIcon(data) }
        }
        return true
    }

    private func applyCustomIcon(_ data: Data) {
        guard let normalized = SmartphoneIconData.normalizedPNGData(from: data) else {
            customIconError = "유효한 PNG 이미지만 추가할 수 있습니다."
            return
        }
        var button = selectedButton
        button.customIconData = normalized
        update(button)
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
            action: PadAction(kind: .shortcut, targetAppBundleIdentifier: button.action.value)
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
                button.action.kind = kind
                button.action.value = application.bundleIdentifier
                button.action.targetAppBundleIdentifier = ""
                if button.title.isEmpty { button.title = application.name }
                if kind == .appFolder {
                    button.folderShortcuts = button.folderShortcuts.map { shortcut in
                        var updatedShortcut = shortcut
                        updatedShortcut.action.targetAppBundleIdentifier = application.bundleIdentifier
                        return updatedShortcut
                    }
                } else {
                    button.folderShortcuts = []
                }
                update(button)
            case .failure(let error): registrationError = error.localizedDescription
            }
        }
    }

    private func runSelectedAction() {
        do { store.statusMessage = try runner.execute(selectedButton.action, commandFileID: selectedButton.id) }
        catch { store.statusMessage = error.localizedDescription }
    }
}
