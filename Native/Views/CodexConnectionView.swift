import AppKit
import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

struct CodexConnectionView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case display
        case motion
        case presets
        case theme
        case completionSound

        var id: Self { self }

        var title: String {
            switch self {
            case .display: "표시 설정"
            case .motion: "상태별 모션"
            case .presets: "모션 프리셋"
            case .theme: "휴대폰 스킨"
            case .completionSound: "완료 사운드"
            }
        }

        var symbol: String {
            switch self {
            case .display: "display"
            case .motion: "waveform.path"
            case .presets: "square.grid.3x3"
            case .theme: "paintpalette"
            case .completionSound: "speaker.wave.2"
            }
        }
    }

    static var availableTabTitles: [String] { Tab.allCases.map(\.title) }

    @Bindable var store: LaunchpadStore
    let midi: LaunchpadMIDIManager
    let codex: CodexAppServerClient

    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab: Tab = .display
    @State private var showingCompletionSoundError = false
    @State private var completionSoundError = ""
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
                case .display:
                    displayPane
                case .motion:
                    motionRulesPane
                case .presets:
                    MotionPresetView(store: store, midi: midi, isEmbedded: true)
                case .theme:
                    phoneThemePane
                case .completionSound:
                    completionSoundPane
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
            Section("Codex 연결") {
                connectionCard
            }

            Section("LED 표시") {
                motionDisplayLocation
                weeklyUsageDisplaySetting
            }

            Section("말풍선") {
                launchpadLEDBubbleSetting
            }

            Section("LED 화면보호기") {
                idleScreensaverSetting
            }

            Section {
                Text("이 앱에서 시작한 Codex 작업만 상태·모션으로 추적합니다. 기존 ChatGPT 앱 작업은 포함되지 않습니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var phoneThemePane: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Codex 화면 스킨을 선택하면 연결된 휴대폰 앱에 바로 적용됩니다.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 280, maximum: 420), alignment: .top)],
                    alignment: .leading,
                    spacing: 14
                ) {
                    ForEach(CodexPhoneTheme.allCases) { theme in
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
                    }
                }

                Label("선택한 스킨은 Mac에 저장되며, 휴대폰이 다시 연결되면 자동으로 동기화됩니다.", systemImage: "iphone.and.arrow.forward")
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

                            Button {
                                toggleCompletionSoundPreview(option.id)
                            } label: {
                                Image(systemName: previewingSoundID == option.id ? "stop.fill" : "play.fill")
                                    .frame(width: 30, height: 30)
                            }
                            .buttonStyle(.bordered)
                            .accessibilityLabel(previewingSoundID == option.id ? "미리듣기 중지" : "\(option.title) 미리듣기")
                            .accessibilityIdentifier("completion-sound-preview-\(option.id)")
                        }
                        .padding(8)
                        .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 9))
                    }
                }

                Button(action: importCompletionSound) {
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
        .alert("완료 사운드 오류", isPresented: $showingCompletionSoundError) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(completionSoundError)
        }
        .onDisappear {
            previewMonitor?.cancel()
            previewPlayer?.stop()
            previewPlayer = nil
            previewingSoundID = nil
        }
    }

    private func toggleCompletionSoundPreview(_ id: String) {
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
            completionSoundError = "미리 들을 수 있는 오디오 파일을 찾지 못했습니다."
            showingCompletionSoundError = true
            return
        }

        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.volume = Float(store.codexCompletionSounds.volumePercent) / 100
            previewPlayer = player
            previewingSoundID = id
            guard player.play() else {
                previewPlayer = nil
                previewingSoundID = nil
                completionSoundError = "이 오디오 파일을 재생할 수 없습니다."
                showingCompletionSoundError = true
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
            completionSoundError = error.localizedDescription
            showingCompletionSoundError = true
        }
    }

    private func importCompletionSound() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try store.codexCompletionSounds.importSound(from: url)
            codex.publishRemoteState()
        } catch {
            completionSoundError = error.localizedDescription
            showingCompletionSoundError = true
        }
    }

    @ViewBuilder
    private func phoneThemePreview(_ theme: CodexPhoneTheme) -> some View {
        switch theme {
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

    private var motionRulesPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text("상태").frame(width: 74, alignment: .leading)
                Text("모션").frame(width: 104, alignment: .leading)
                Text("").frame(width: 58)
                Text("종료 방식").frame(width: 108, alignment: .leading)
                Text("조건").frame(width: 70, alignment: .leading)
                Text("옵션").frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.bottom, 7)

            GroupBox {
                VStack(spacing: 0) {
                    ForEach(Array(motionActivities.enumerated()), id: \.element.id) { index, activity in
                        CodexMotionRuleCard(store: store, midi: midi, activity: activity)
                        if index < motionActivities.count - 1 {
                            Divider()
                        }
                    }
                }
                .padding(.horizontal, 12)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var motionActivities: [CodexActivity] {
        [.connecting, .running, .waitingForApproval, .completed, .failed]
    }

    private var motionDisplayLocation: some View {
        VStack(alignment: .leading, spacing: 8) {
            LabeledContent("상태 모션 페이지") {
                Picker("Codex 상태 모션 표시 페이지", selection: motionDisplayPageBinding) {
                    ForEach(Array(store.pages.enumerated()), id: \.element.id) { index, page in
                        Text("P\(index + 1) · \(page.name)").tag(page.id)
                    }
                }
                .labelsHidden()
                .frame(width: 180)
            }
            Toggle("모션 재생 중에도 기존 패드 LED 유지", isOn: preservesPadLEDsBinding)
                .accessibilityIdentifier("codex-motion-preserve-pad-leds-toggle")
        }
    }

    private var launchpadLEDBubbleSetting: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Launchpad LED 말풍선 표시", isOn: launchpadLEDBubbleBinding)
                .accessibilityIdentifier("launchpad-led-bubble-toggle")
            LabeledContent("크기") {
                Picker("Launchpad LED 말풍선 크기", selection: launchpadLEDBubbleSizeBinding) {
                    ForEach(LaunchpadLEDBubbleSize.allCases) { size in
                        Text(size.title).tag(size)
                    }
                }
                .labelsHidden()
                .frame(width: 120)
                .accessibilityIdentifier("launchpad-led-bubble-size-picker")
            }
            .disabled(!store.codexMotionDisplaySettings.showsLaunchpadLEDBubble)
        }
    }

    private var idleScreensaverSetting: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("사용", isOn: idleScreensaverEnabledBinding)
                .accessibilityIdentifier("idle-screensaver-toggle")

            LabeledContent("입력 기준") {
                Picker("화면보호기 입력 기준", selection: idleScreensaverInputScopeBinding) {
                    ForEach(LaunchpadIdleInputScope.allCases) { scope in
                        Text(scope.title).tag(scope)
                    }
                }
                .labelsHidden()
                .frame(width: 160)
            }

            LabeledContent("시작 및 재생 시간") {
                HStack(spacing: 6) {
                TextField("초", value: idleScreensaverDelayBinding, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 58)
                    .multilineTextAlignment(.trailing)
                    .accessibilityLabel("화면보호기 시작 대기 시간(초)")
                Text("초 후")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)

                TextField("초", value: idleScreensaverDurationBinding, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 58)
                    .multilineTextAlignment(.trailing)
                    .accessibilityLabel("화면보호기 지속 시간(초)")
                Text("초 재생")
                    .foregroundStyle(.secondary)
                }
            }

            LabeledContent("재생 모션") {
                Picker("화면보호기 모션", selection: idleScreensaverPresetBinding) {
                    Text("모션 선택").tag(UUID?.none)
                    ForEach(store.motionPresets) { preset in
                        Text(preset.name).tag(Optional(preset.id))
                    }
                }
                .labelsHidden()
                .frame(width: 180)
            }
            .disabled(!store.codexMotionDisplaySettings.idleScreensaver.isEnabled)
        }
    }

    private var weeklyUsageDisplaySetting: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("주간 잔여량 표시", isOn: weeklyUsageEnabledBinding)
                .accessibilityIdentifier("weekly-usage-display-toggle")

            LabeledContent("표시 방식") {
                Picker("주간 잔여량 표시 방식", selection: weeklyUsageStyleBinding) {
                    ForEach(CodexWeeklyUsageDisplayStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }
                .labelsHidden()
                .frame(width: 140)
            }

            LabeledContent("표시 페이지") {
                Picker("주간 잔여량 표시 페이지", selection: weeklyUsagePageBinding) {
                    ForEach(Array(store.pages.enumerated()), id: \.element.id) { index, page in
                        Text("P\(index + 1) · \(page.name)").tag(page.id)
                    }
                }
                .labelsHidden()
                .frame(width: 180)
            }
            .disabled(!store.codexMotionDisplaySettings.weeklyUsageDisplay.isEnabled)
            Text(store.codexMotionDisplaySettings.weeklyUsageDisplay.style == .level
                ? "평소 사용량 표시 · 모션 종료 후 자동 복귀"
                : "0%=0 · 100%=00 · 모션 종료 후 자동 복귀")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var motionDisplayPageBinding: Binding<UUID> {
        Binding(
            get: { store.codexMotionDisplaySettings.pageID ?? store.pages[0].id },
            set: { store.setCodexMotionDisplayPageID($0) }
        )
    }

    private var preservesPadLEDsBinding: Binding<Bool> {
        Binding(
            get: { store.codexMotionDisplaySettings.preservesPadLEDsDuringMotion },
            set: { store.setCodexMotionPreservesPadLEDsDuringMotion($0) }
        )
    }

    private var launchpadLEDBubbleBinding: Binding<Bool> {
        Binding(
            get: { store.codexMotionDisplaySettings.showsLaunchpadLEDBubble },
            set: { store.setLaunchpadLEDBubbleVisible($0) }
        )
    }

    private var launchpadLEDBubbleSizeBinding: Binding<LaunchpadLEDBubbleSize> {
        Binding(
            get: { store.codexMotionDisplaySettings.launchpadLEDBubbleSize },
            set: { store.setLaunchpadLEDBubbleSize($0) }
        )
    }

    private var idleScreensaverEnabledBinding: Binding<Bool> {
        Binding(
            get: { store.codexMotionDisplaySettings.idleScreensaver.isEnabled },
            set: { store.setIdleScreensaverEnabled($0) }
        )
    }

    private var idleScreensaverInputScopeBinding: Binding<LaunchpadIdleInputScope> {
        Binding(
            get: { store.codexMotionDisplaySettings.idleScreensaver.inputScope },
            set: { store.setIdleScreensaverInputScope($0) }
        )
    }

    private var idleScreensaverDelayBinding: Binding<Int> {
        Binding(
            get: { store.codexMotionDisplaySettings.idleScreensaver.delaySeconds },
            set: { store.setIdleScreensaverDelaySeconds($0) }
        )
    }

    private var idleScreensaverPresetBinding: Binding<UUID?> {
        Binding(
            get: { store.codexMotionDisplaySettings.idleScreensaver.presetID },
            set: { store.setIdleScreensaverPresetID($0) }
        )
    }

    private var idleScreensaverDurationBinding: Binding<Int> {
        Binding(
            get: { store.codexMotionDisplaySettings.idleScreensaver.durationSeconds },
            set: { store.setIdleScreensaverDurationSeconds($0) }
        )
    }

    private var weeklyUsageEnabledBinding: Binding<Bool> {
        Binding(
            get: { store.codexMotionDisplaySettings.weeklyUsageDisplay.isEnabled },
            set: { store.setWeeklyUsageDisplayEnabled($0) }
        )
    }

    private var weeklyUsagePageBinding: Binding<UUID> {
        Binding(
            get: { store.codexMotionDisplaySettings.weeklyUsageDisplay.pageID ?? store.pages[0].id },
            set: { store.setWeeklyUsageDisplayPageID($0) }
        )
    }

    private var weeklyUsageStyleBinding: Binding<CodexWeeklyUsageDisplayStyle> {
        Binding(
            get: { store.codexMotionDisplaySettings.weeklyUsageDisplay.style },
            set: { store.setWeeklyUsageDisplayStyle($0) }
        )
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
