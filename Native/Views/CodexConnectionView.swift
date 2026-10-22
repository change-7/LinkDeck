import AppKit
import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

struct CodexConnectionView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case connection
        case registeredAppAPIs
        case display
        case theme
        case completionSound
        case approvalSound

        var id: Self { self }

        var title: String {
            switch self {
            case .connection: "연결 설정"
            case .registeredAppAPIs: "등록된 앱 API"
            case .display: "표시 설정"
            case .theme: "휴대폰 스킨"
            case .completionSound: "완료 사운드"
            case .approvalSound: "승인 사운드"
            }
        }

        var symbol: String {
            switch self {
            case .connection: "network"
            case .registeredAppAPIs: "app.connected.to.app.below.fill"
            case .display: "display"
            case .theme: "paintpalette"
            case .completionSound: "speaker.wave.2"
            case .approvalSound: "bell.badge.waveform"
            }
        }
    }

    static var availableTabTitles: [String] { Tab.allCases.map(\.title) }

    @Bindable var store: LaunchpadStore
    let folderSyncStore: FolderPairStore
    let codex: CodexAppServerClient
    let chatGPTTunnel: ChatGPTTunnelController

    @Environment(\.dismiss) private var dismiss
    @AppStorage("macDarkModeEnabled") private var macDarkModeEnabled = true
    @State private var selectedTab: Tab = .connection
    @State private var copiedSkinInstructions = false
    @State private var showingSoundError = false
    @State private var soundError = ""
    @State private var previewPlayer: AVAudioPlayer?
    @State private var previewingSoundID: String?
    @State private var previewMonitor: Task<Void, Never>?

    var body: some View {
        HStack(spacing: 0) {
            settingsSidebar
            .frame(width: 190)
            .layoutPriority(1)

            Divider()

            VStack(spacing: 0) {
                HStack {
                    Text(selectedTab.title)
                        .font(.title3.weight(.semibold))
                    Spacer()
                    Button("완료") { dismiss() }
                        .keyboardShortcut(.defaultAction)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)

                Divider()

                switch selectedTab {
                case .connection:
                    connectionPane
                case .registeredAppAPIs:
                    ChatGPTTunnelView(tunnel: chatGPTTunnel, store: store, folderSyncStore: folderSyncStore, showsRegisteredAppAPIsOnly: true)
                case .display:
                    displayPane
                case .theme:
                    phoneThemePane
                case .completionSound:
                    completionSoundPane
                case .approvalSound:
                    approvalSoundPane
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 820, height: 560)
    }

    private var settingsSidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Tab.allCases) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    Label(tab.title, systemImage: tab.symbol)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .frame(height: 32)
                        .background(
                            selectedTab == tab ? Color.accentColor.opacity(0.22) : .clear,
                            in: RoundedRectangle(cornerRadius: 7)
                        )
                }
                .buttonStyle(.plain)
                .focusEffectDisabled()
            }
            Spacer()
        }
        .padding(10)
        .background(.regularMaterial)
    }

    private var connectionCard: some View {
        LabeledContent {
            Button(codex.isConnected ? "연결 종료" : "연결") {
                if codex.isConnected {
                    codex.disconnect()
                } else {
                    codex.connect()
                }
            }
            .tint(codex.isConnected ? .red : .accentColor)
        } label: {
            HStack(spacing: 8) {
                Circle().fill(statusColor).frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 2) {
                    Text(codex.isConnected ? "연결됨" : "연결 안 됨")
                    Text(codex.message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }

    private var displayPane: some View {
        Form {
            Section("Mac 화면 모드") {
                Picker("화면 모드", selection: $macDarkModeEnabled) {
                    Text("다크 모드").tag(true)
                    Text("라이트 모드").tag(false)
                }
                .pickerStyle(.segmented)
            }

        }
        .formStyle(.grouped)
    }

    private var connectionPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            GroupBox("Codex 연결") {
                connectionCard.padding(8)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            ChatGPTTunnelView(tunnel: chatGPTTunnel, store: store, folderSyncStore: folderSyncStore)
        }
    }

    private var phoneThemePane: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Codex 화면 스킨을 선택하면 연결된 휴대폰 앱에 바로 적용됩니다.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                DisclosureGroup("스킨 제작 요구사항") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("요구사항을 복사해 붙여 넣은 후, 마지막 ‘디자인 요청:’에 원하는 디자인을 적으세요.")
                            .font(.callout).foregroundStyle(.secondary)
                        Button(copiedSkinInstructions ? "복사됨" : "스킨 제작 요구사항 복사") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(CodexPhoneTheme.authoringInstructions, forType: .string)
                            copiedSkinInstructions = true
                        }
                        Text(CodexPhoneTheme.authoringInstructions)
                            .font(.system(.callout, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }

                Divider()
                Text("스킨 선택").font(.headline)
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 280, maximum: 420), alignment: .top)],
                    alignment: .leading,
                    spacing: 14
                ) {
                    ForEach(store.availableCodexPhoneThemes) { theme in
                        let isSelected = store.codexPhoneTheme == theme
                        Button {
                            store.setCodexPhoneTheme(theme)
                        } label: {
                            VStack(alignment: .leading, spacing: 9) {
                                phoneThemePreview(theme)
                                    .frame(height: 150)
                                    .frame(maxWidth: .infinity)
                                    .clipped()
                                    .clipShape(RoundedRectangle(cornerRadius: 8))

                                HStack(spacing: 6) {
                                    Text(theme.title).font(.headline)
                                    Spacer(minLength: 0)
                                    if isSelected {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(Color.accentColor)
                                    }
                                }
                                Text(theme.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                                    .frame(height: 30, alignment: .topLeading)
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                isSelected ? Color.accentColor.opacity(0.10) : Color.secondary.opacity(0.06),
                                in: RoundedRectangle(cornerRadius: 12)
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: 12)
                                    .strokeBorder(isSelected ? Color.accentColor : Color.secondary.opacity(0.18), lineWidth: isSelected ? 2 : 1)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("codex-phone-theme-\(theme.rawValue)")
                        .overlay(alignment: .topTrailing) {
                            if theme != .classic {
                                Button(role: .destructive) { store.deleteCodexPhoneTheme(theme) } label: {
                                    Image(systemName: "trash")
                                        .padding(7)
                                        .background(.regularMaterial, in: Circle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("\(theme.title) 스킨 삭제")
                                .help("스킨 삭제")
                                .padding(15)
                            }
                        }
                    }
                }

                if !store.deletedCodexPhoneThemes.isEmpty {
                    Button("삭제한 스킨 복원") { store.restoreCodexPhoneThemes() }
                }
                Divider()
                Label("사용 중인 스킨을 삭제하면 기본 스킨으로 전환됩니다. 삭제한 스킨은 복원할 수 있습니다.", systemImage: "iphone.and.arrow.forward")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
    }

    private var completionSoundPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Codex 작업 완료음을 재생할 기기와 소리를 선택합니다.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Divider()
                Text("재생 설정").font(.headline)
                Picker("재생 기기", selection: Binding(
                    get: { store.codexCompletionSounds.outputTarget },
                    set: { target in
                        store.codexCompletionSounds.setOutputTarget(target)
                        codex.publishRemoteState()
                    }
                )) {
                    ForEach(CodexCompletionSoundOutputTarget.allCases) { target in
                        Text(target.title).tag(target)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("completion-sound-output-target")

                HStack(spacing: 12) {
                    Text("볼륨")
                    Slider(value: Binding(
                        get: { Double(store.codexCompletionSounds.volumePercent) },
                        set: { value in
                            store.codexCompletionSounds.setVolumePercent(Int(value.rounded()))
                            codex.publishRemoteState()
                        }
                    ), in: 0...100, step: 1)
                    .accessibilityLabel("완료음 볼륨")
                    .accessibilityIdentifier("completion-sound-volume-slider")
                    Text("\(store.codexCompletionSounds.volumePercent)%")
                        .monospacedDigit()
                        .frame(width: 44, alignment: .trailing)
                        .foregroundStyle(.secondary)
                }
                .onChange(of: store.codexCompletionSounds.volumePercent) { _, value in
                    previewPlayer?.volume = Float(value) / 100
                }

                Divider()
                Text("사운드 선택·미리듣기").font(.headline)
                VStack(spacing: 8) {
                    ForEach(store.codexCompletionSounds.options) { option in
                        HStack(spacing: 8) {
                            Button {
                                store.codexCompletionSounds.select(option.id)
                                codex.publishRemoteState()
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: store.codexCompletionSounds.selectedSoundID == option.id
                                        ? "largecircle.fill.circle"
                                        : "circle")
                                        .foregroundStyle(store.codexCompletionSounds.selectedSoundID == option.id
                                            ? Color.accentColor
                                            : Color.secondary)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(option.title).font(.headline)
                                        Text(option.detail)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer(minLength: 0)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("completion-sound-select-\(option.id)")

                            if option.id != CodexCompletionSoundLibrary.noSoundID {
                                Button {
                                    toggleSoundPreview(option.id)
                                } label: {
                                    Image(systemName: previewingSoundID == option.id ? "stop.fill" : "play.fill")
                                        .frame(width: 30, height: 30)
                                }
                                .buttonStyle(.bordered)
                                .accessibilityLabel(previewingSoundID == option.id ? "미리듣기 중지" : "\(option.title) 미리듣기")
                                .accessibilityIdentifier("completion-sound-preview-\(option.id)")
                            }
                        }
                        .padding(8)
                        .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 9))
                    }
                }

                Divider()
                Text("사용자 사운드").font(.headline)
                Button { importCompletionSound() } label: {
                    Label("음성 파일 추가…", systemImage: "plus")
                }
                Text("WAV, MP3, M4A, OGG 파일을 추가할 수 있습니다. 휴대폰을 선택하면 연결된 휴대폰으로 소리를 전송합니다. (파일당 최대 10MB)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
        .alert("사운드 오류", isPresented: $showingSoundError) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(soundError)
        }
        .onDisappear {
            previewMonitor?.cancel()
            previewPlayer?.stop()
            previewPlayer = nil
            previewingSoundID = nil
        }
    }

    private var approvalSoundPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("항상 허용·이 대화에서만 허용·거부 등의 선택이 필요한 Codex 승인 요청에도 이 소리를 사용합니다. 선택한 기기에서 재생하며, 미리듣기는 Mac에서 재생됩니다.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Divider()
                Text("재생 설정").font(.headline)
                Picker("재생 기기", selection: Binding(
                    get: { store.codexCompletionSounds.approvalSoundOutputTarget },
                    set: { target in
                        store.codexCompletionSounds.setApprovalSoundOutputTarget(target)
                        codex.publishRemoteState()
                    }
                )) {
                    ForEach(CodexApprovalSoundOutputTarget.allCases) { target in
                        Text(target.title).tag(target)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("approval-sound-output-target")

                HStack(spacing: 12) {
                    Text("볼륨")
                    Slider(value: Binding(
                        get: { Double(store.codexCompletionSounds.approvalVolumePercent) },
                        set: { value in
                            store.codexCompletionSounds.setApprovalVolumePercent(Int(value.rounded()))
                            codex.publishRemoteState()
                        }
                    ), in: 0...100, step: 1)
                    .accessibilityLabel("승인음 볼륨")
                    .accessibilityIdentifier("approval-sound-volume-slider")
                    Text("\(store.codexCompletionSounds.approvalVolumePercent)%")
                        .monospacedDigit()
                        .frame(width: 44, alignment: .trailing)
                        .foregroundStyle(.secondary)
                }
                .onChange(of: store.codexCompletionSounds.approvalVolumePercent) { _, value in
                    previewPlayer?.volume = Float(value) / 100
                }

                Divider()
                Text("사운드 선택·미리듣기").font(.headline)
                VStack(spacing: 8) {
                    ForEach(store.codexCompletionSounds.options) { option in
                        HStack(spacing: 8) {
                            Button {
                                store.codexCompletionSounds.selectApprovalSound(option.id)
                                codex.publishRemoteState()
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: store.codexCompletionSounds.selectedApprovalSoundID == option.id
                                        ? "largecircle.fill.circle"
                                        : "circle")
                                        .foregroundStyle(store.codexCompletionSounds.selectedApprovalSoundID == option.id
                                            ? Color.accentColor
                                            : Color.secondary)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(approvalSoundTitle(for: option)).font(.headline)
                                        Text(option.detail)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer(minLength: 0)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("approval-sound-select-\(option.id)")

                            if option.id != CodexCompletionSoundLibrary.noSoundID {
                                Button {
                                    toggleSoundPreview(option.id)
                                } label: {
                                    Image(systemName: previewingSoundID == option.id ? "stop.fill" : "play.fill")
                                        .frame(width: 30, height: 30)
                                }
                                .buttonStyle(.bordered)
                                .accessibilityLabel(previewingSoundID == option.id ? "미리듣기 중지" : "\(approvalSoundTitle(for: option)) 미리듣기")
                                .accessibilityIdentifier("approval-sound-preview-\(option.id)")
                            }
                        }
                        .padding(8)
                        .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 9))
                    }
                }

                Divider()
                Text("사용자 사운드").font(.headline)
                Button { importCompletionSound(selectForApproval: true) } label: {
                    Label("승인 사운드 파일 추가…", systemImage: "plus")
                }
                Text("WAV, MP3, M4A, OGG 파일을 선택할 수 있습니다. 기본음을 선택하면 휴대폰은 기본 승인 알림음을 사용합니다. (파일당 최대 10MB)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
        .alert("사운드 오류", isPresented: $showingSoundError) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(soundError)
        }
        .onDisappear {
            previewMonitor?.cancel()
            previewPlayer?.stop()
            previewPlayer = nil
            previewingSoundID = nil
        }
    }

    private func toggleSoundPreview(_ id: String) {
        if previewingSoundID == id {
            previewMonitor?.cancel()
            previewPlayer?.stop()
            previewPlayer = nil
            previewingSoundID = nil
            return
        }

        previewMonitor?.cancel()
        previewPlayer?.stop()
        previewPlayer = nil
        previewingSoundID = nil
        guard let url = store.codexCompletionSounds.previewURL(for: id) else {
            soundError = "미리 들을 수 있는 오디오 파일을 찾지 못했습니다."
            showingSoundError = true
            return
        }

        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.volume = Float(selectedTab == .approvalSound
                ? store.codexCompletionSounds.approvalVolumePercent
                : store.codexCompletionSounds.volumePercent) / 100
            previewPlayer = player
            previewingSoundID = id
            guard player.play() else {
                previewPlayer = nil
                previewingSoundID = nil
                soundError = "이 오디오 파일을 재생할 수 없습니다."
                showingSoundError = true
                return
            }
            previewMonitor = Task { @MainActor in
                while player.isPlaying && !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 100_000_000)
                }
                guard !Task.isCancelled, previewingSoundID == id else { return }
                previewPlayer = nil
                previewingSoundID = nil
            }
        } catch {
            soundError = error.localizedDescription
            showingSoundError = true
        }
    }

    private func approvalSoundTitle(for option: CodexCompletionSoundOption) -> String {
        if option.id == CodexCompletionSoundLibrary.builtInID { return "기본 알림음" }
        if option.id == CodexCompletionSoundLibrary.bundledVoiceID { return "완료 음성" }
        return option.title
    }

    private func importCompletionSound(selectForApproval: Bool = false) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let importedID = try store.codexCompletionSounds.importSound(
                from: url,
                selectForCompletion: !selectForApproval
            )
            if selectForApproval { store.codexCompletionSounds.selectApprovalSound(importedID) }
            codex.publishRemoteState()
        } catch {
            soundError = error.localizedDescription
            showingSoundError = true
        }
    }

    @ViewBuilder
    private func phoneThemePreview(_ theme: CodexPhoneTheme) -> some View {
        switch theme {
        case .dotConsole:
            ZStack {
                Color(red: 0.025, green: 0.04, blue: 0.065)
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 9) {
                        Text("DOT CONSOLE").font(.system(size: 8, weight: .bold, design: .monospaced))
                        dotMatrixCompletionMark
                        Text("RUNNING").font(.system(size: 12, weight: .bold, design: .monospaced))
                    }
                    .foregroundStyle(.cyan)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    VStack(spacing: 8) {
                        ForEach(["5-HOUR", "1-WEEK"], id: \.self) { label in
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(label)  76%").font(.system(size: 8, weight: .bold, design: .monospaced))
                                HStack(spacing: 2) {
                                    ForEach(0..<12) { index in
                                        Circle().fill(index < 9 ? Color.cyan : Color.cyan.opacity(0.15)).frame(width: 4, height: 4)
                                    }
                                }
                                Text(label == "5-HOUR" ? "03:15  ·  3시간 4분" : "10월 27일 15:35  ·  6일+15시간")
                                    .font(.system(size: 6, design: .monospaced))
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                            .background(Color.cyan.opacity(0.06), in: RoundedRectangle(cornerRadius: 5))
                            .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.cyan.opacity(0.4)))
                        }
                    }
                    .foregroundStyle(.white)
                }
                .padding(14)
            }
        case .controlCabinet:
            ZStack {
                if let url = Bundle.module.url(forResource: "ControlCabinetBackground", withExtension: "png"),
                   let image = NSImage(contentsOf: url) {
                    Image(nsImage: image).resizable().scaledToFill()
                } else {
                    Color.black
                }
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("CODEX").font(.system(size: 16, weight: .bold, design: .monospaced))
                        Label("CONNECTED", systemImage: "circle.fill")
                            .font(.system(size: 7, design: .monospaced))
                            .foregroundStyle(.green)
                        Text("5H 97%  /  WEEK 76%")
                            .font(.system(size: 7, design: .monospaced))
                    }
                    Spacer(minLength: 0)
                    VStack(spacing: 8) {
                        Image(systemName: "fanblades.fill").font(.system(size: 27))
                        Text("RUNNING").font(.system(size: 10, weight: .bold, design: .monospaced))
                        HStack(spacing: 5) {
                            ForEach(0..<5) { _ in Circle().frame(width: 4, height: 4) }
                        }
                    }
                    .foregroundStyle(.orange)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 25)
                .padding(.vertical, 18)
            }
        case .classic:
            ZStack {
                Color(red: 0.025, green: 0.035, blue: 0.065)
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Circle().fill(.green).frame(width: 7, height: 7)
                        Text("CODEX CONNECTED")
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.white)
                        Spacer()
                        Text("RUNNING")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(.green)
                    }
                    Spacer()
                    HStack(alignment: .bottom, spacing: 20) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("5-HOUR").font(.system(size: 8, design: .monospaced)).foregroundStyle(.secondary)
                            Text("97%").font(.system(size: 25, weight: .bold, design: .monospaced)).foregroundStyle(.green)
                            RoundedRectangle(cornerRadius: 2).fill(.green.opacity(0.8)).frame(height: 5)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("1-WEEK").font(.system(size: 8, design: .monospaced)).foregroundStyle(.secondary)
                            Text("76%").font(.system(size: 25, weight: .bold, design: .monospaced)).foregroundStyle(.cyan)
                            RoundedRectangle(cornerRadius: 2).fill(.cyan.opacity(0.8)).frame(height: 5)
                        }
                    }
                }
                .padding(14)
            }
        case .pixelSpace:
            if let imageURL = Bundle.module.url(forResource: "PixelSpaceBackground", withExtension: "png"),
               let image = NSImage(contentsOf: imageURL) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Color.black
            }
        case .dotMatrix:
            ZStack {
                Color(red: 0.025, green: 0.035, blue: 0.075)
                Canvas { context, size in
                    for x in stride(from: CGFloat(6), through: size.width, by: 12) {
                        for y in stride(from: CGFloat(6), through: size.height, by: 12) {
                            let highlighted = (Int(x / 12) * 7 + Int(y / 12) * 11) % 19 == 0
                            let dot = CGRect(x: x, y: y, width: 2, height: 2)
                            context.fill(
                                Path(ellipseIn: dot),
                                with: .color(highlighted ? Color.cyan.opacity(0.55) : Color.white.opacity(0.12))
                            )
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 6) {
                        Circle().fill(.green).frame(width: 6, height: 6)
                        Text("CODEX NODE")
                            .font(.system(size: 8, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.white)
                        Spacer()
                        Text("LINK // OK")
                            .font(.system(size: 7, weight: .bold, design: .monospaced))
                            .foregroundStyle(.cyan)
                    }
                    Spacer(minLength: 6)
                    HStack(spacing: 10) {
                        dotMatrixCompletionMark
                        VStack(alignment: .leading, spacing: 3) {
                            Text("COMPLETED")
                                .font(.system(size: 17, weight: .heavy, design: .monospaced))
                                .foregroundStyle(Color(red: 0.73, green: 1, blue: 0.42))
                            Text("TASK SYNCHRONIZED")
                                .font(.system(size: 7, weight: .medium, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.7))
                        }
                    }
                    Spacer(minLength: 6)
                    HStack(alignment: .bottom, spacing: 16) {
                        dotMatrixMeter(label: "5-HOUR", value: "97%", tint: .cyan, filled: 10)
                        dotMatrixMeter(label: "1-WEEK", value: "76%", tint: .purple, filled: 8)
                    }
                }
                .padding(12)
            }
        case .pixelQuest:
            ZStack {
                Color(red: 0.035, green: 0.045, blue: 0.13)
                VStack(spacing: 4) {
                    HStack {
                        Text("PIXEL QUEST")
                        Spacer()
                        Text("WORLD 1-1")
                    }
                    .font(.system(size: 7, weight: .black, design: .monospaced))
                    .foregroundStyle(Color(red: 0.55, green: 0.92, blue: 1))
                    .padding(.horizontal, 7)
                    .frame(height: 14)
                    .background(Color(red: 0.08, green: 0.11, blue: 0.27))
                    .overlay(Rectangle().strokeBorder(Color.cyan.opacity(0.8), lineWidth: 1))

                    ZStack {
                        pixelQuestStageArt
                        HStack(alignment: .center) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("STAGE 08")
                                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                                    .foregroundStyle(Color(red: 1, green: 0.73, blue: 0.32))
                                Text("RUNNING")
                                    .font(.system(size: 17, weight: .black, design: .monospaced))
                                    .foregroundStyle(Color(red: 0.69, green: 1, blue: 0.42))
                                    .minimumScaleFactor(0.7)
                                    .lineLimit(1)
                                Text("QUEST IN PROGRESS")
                                    .font(.system(size: 6, weight: .bold, design: .monospaced))
                                    .foregroundStyle(.white.opacity(0.75))
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 5)
                            .background(Color(red: 0.035, green: 0.045, blue: 0.13).opacity(0.92))

                            Spacer(minLength: 0)
                        }
                        .padding(5)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(red: 0.055, green: 0.08, blue: 0.2))
                    .overlay(Rectangle().strokeBorder(Color(red: 0.55, green: 0.92, blue: 1), lineWidth: 2))

                    HStack(spacing: 4) {
                        pixelQuestUsage(label: "5H QUEST", value: "97%", tint: Color(red: 0.69, green: 1, blue: 0.42), filled: 7)
                        pixelQuestUsage(label: "WEEKLY XP", value: "76%", tint: Color(red: 1, green: 0.63, blue: 0.31), filled: 6)
                    }
                    .frame(height: 27)
                }
                .padding(7)
            }
        }
    }

    private var pixelQuestStageArt: some View {
        Canvas { context, size in
            let cell = min(size.width / 32, size.height / 16)
            let originX = (size.width - cell * 32) / 2
            let originY = (size.height - cell * 16) / 2
            for row in 0..<16 {
                for column in 0..<32 {
                    let tile = CGRect(
                        x: originX + CGFloat(column) * cell,
                        y: originY + CGFloat(row) * cell,
                        width: cell,
                        height: cell
                    )
                    let shade = (row + column).isMultiple(of: 2) ? 0.075 : 0.045
                    context.fill(
                        Path(tile),
                        with: .color(Color(red: shade, green: shade + 0.025, blue: shade + 0.11))
                    )
                }
            }

            var circuit = Path()
            circuit.move(to: CGPoint(x: originX + 18.5 * cell, y: originY + 4.5 * cell))
            circuit.addLine(to: CGPoint(x: originX + 29.5 * cell, y: originY + 4.5 * cell))
            circuit.addLine(to: CGPoint(x: originX + 29.5 * cell, y: originY + 12.5 * cell))
            circuit.addLine(to: CGPoint(x: originX + 22.5 * cell, y: originY + 12.5 * cell))
            circuit.addLine(to: CGPoint(x: originX + 22.5 * cell, y: originY + 8.5 * cell))
            circuit.addLine(to: CGPoint(x: originX + 27.5 * cell, y: originY + 8.5 * cell))
            context.stroke(
                circuit,
                with: .color(Color.cyan.opacity(0.18)),
                style: StrokeStyle(lineWidth: cell * 4, lineCap: .square, lineJoin: .miter)
            )
            context.stroke(
                circuit,
                with: .color(Color(red: 0.12, green: 0.42, blue: 0.68)),
                style: StrokeStyle(lineWidth: cell * 2.4, lineCap: .square, lineJoin: .miter)
            )
            context.stroke(
                circuit,
                with: .color(Color(red: 0.4, green: 0.92, blue: 1)),
                style: StrokeStyle(lineWidth: cell * 0.55, lineCap: .square, lineJoin: .miter)
            )

            for (column, row, color) in [
                (18, 4, Color(red: 0.7, green: 1, blue: 0.39)),
                (29, 12, Color(red: 1, green: 0.61, blue: 0.25)),
                (22, 8, Color(red: 0.7, green: 1, blue: 0.39))
            ] {
                let node = CGRect(
                    x: originX + CGFloat(column) * cell,
                    y: originY + CGFloat(row) * cell,
                    width: cell,
                    height: cell
                )
                context.fill(Path(node), with: .color(color))
            }
        }
    }

    private func pixelQuestUsage(label: String, value: String, tint: Color, filled: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label)
                Spacer(minLength: 2)
                Text(value).foregroundStyle(tint)
            }
            .font(.system(size: 6, weight: .black, design: .monospaced))
            .foregroundStyle(.white.opacity(0.86))
            HStack(spacing: 2) {
                ForEach(0..<8, id: \.self) { index in
                    Rectangle().fill(index < filled ? tint : Color.white.opacity(0.13))
                }
            }
            .frame(height: 4)
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(red: 0.08, green: 0.11, blue: 0.27))
        .overlay(Rectangle().strokeBorder(tint.opacity(0.8), lineWidth: 1))
    }

    private var dotMatrixCompletionMark: some View {
        Canvas { context, _ in
            let pixels: [(Int, Int)] = [(0, 2), (1, 3), (2, 2), (3, 1), (4, 0)]
            for (column, row) in pixels {
                let rect = CGRect(
                    x: CGFloat(4 + column * 5),
                    y: CGFloat(4 + row * 5),
                    width: 4,
                    height: 4
                )
                context.fill(Path(rect), with: .color(Color(red: 0.73, green: 1, blue: 0.42)))
            }
        }
        .frame(width: 32, height: 32)
        .background(Color.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 5))
        .overlay {
            RoundedRectangle(cornerRadius: 5).strokeBorder(Color.cyan.opacity(0.5), lineWidth: 1)
        }
    }

    private func dotMatrixMeter(label: String, value: String, tint: Color, filled: Int) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(label)
                Spacer(minLength: 4)
                Text(value).foregroundStyle(tint)
            }
            .font(.system(size: 7, weight: .semibold, design: .monospaced))
            .foregroundStyle(.white.opacity(0.75))
            HStack(spacing: 2) {
                ForEach(0..<12, id: \.self) { index in
                    Rectangle()
                        .fill(index < filled ? tint : Color.white.opacity(0.14))
                }
            }
            .frame(height: 4)
        }
    }

    private var statusColor: Color {
        switch codex.activity {
        case .idle: .gray
        case .connecting: .yellow
        case .running: .green
        case .waitingForApproval: .orange
        case .completed: .green
        case .failed: .red
        }
    }
}
