import AppKit
import SwiftUI

struct ChatGPTTunnelView: View {
    @Bindable var tunnel: ChatGPTTunnelController
    let store: LaunchpadStore
    let folderSyncStore: FolderPairStore
    var showsRegisteredAppAPIsOnly = false
    private let runner = MacActionRunner()
    @State private var appAPIs: [RegisteredAppAPI] = []
    @State private var logError: String?
    @State private var diagnosticSummary: LinkDeckDiagnosticSummary?
    @State private var isLoadingDiagnostics = false
    @State private var diagnosticsChangeDate = Date()
    @AppStorage(LinkDeckDiagnosticLog.enabledKey) private var diagnosticsEnabled = true
    @State private var copiedInstructions = false
    @State private var manifestErrors: [String] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if showsRegisteredAppAPIsOnly {
                    registeredAppAPIContent
                } else {
                    GroupBox("터널 연결") {
                        connectionContent
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    GroupBox("연결 안내") {
                        connectionHelp
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                diagnosticsContent
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .alert("진단 로그", isPresented: Binding(get: { logError != nil }, set: { if !$0 { logError = nil } })) {
            Button("확인") { logError = nil }
        } message: { Text(logError ?? "") }
        .onAppear {
            if showsRegisteredAppAPIsOnly { refreshAppAPIs() }
        }
    }

    private var diagnosticsContent: some View {
        GroupBox("MCP 진단") {
            VStack(alignment: .leading, spacing: 8) {
                Toggle("진단 기록", isOn: $diagnosticsEnabled)
                HStack {
                    Button("새로고침") { Task { await refreshDiagnostics() } }
                        .disabled(isLoadingDiagnostics)
                    Button("로그 폴더 열기") {
                        do {
                            try LinkDeckDiagnosticLog.shared.prepare()
                            if !NSWorkspace.shared.open(LinkDeckDiagnosticLog.shared.directory) {
                                logError = "로그 폴더를 열지 못했습니다."
                            }
                        } catch {
                            logError = "로그 폴더를 만들지 못했습니다: " + error.localizedDescription
                        }
                    }
                }
                if let summary = diagnosticSummary {
                    diagnosticResults(summary)
                }
                Text("터널 전송은 미측정입니다. Chat view+ 작업 시간에는 앱 준비 및 응답 확인 시간이 포함될 수 있습니다.")
                    .font(.caption).foregroundStyle(.secondary)
                Text("최근 7일 중 남아 있는 기록을 표시합니다. 파일은 최대 5개이며 파일당 2,000건 또는 1MB까지 보관합니다. 기록이 밀리면 일부 이벤트가 누락될 수 있습니다.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task { await refreshDiagnostics() }
    }

    @ViewBuilder
    private func diagnosticResults(_ summary: LinkDeckDiagnosticSummary) -> some View {
        if let coverage = summary.coverage {
            let start = coverage.lowerBound.formatted(date: .abbreviated, time: .shortened)
            let end = coverage.upperBound.formatted(date: .abbreviated, time: .shortened)
            Text("기록 범위: \(start) ~ \(end)")
            Text("터널 재연결 시도 \(summary.reconnects)회")
            if !summary.tools.isEmpty {
                Grid(alignment: .trailing, horizontalSpacing: 12, verticalSpacing: 4) {
                    GridRow {
                        Text("도구").gridColumnAlignment(.leading)
                        Text("p50")
                        Text("p95")
                        Text("최대")
                        Text("실패율")
                    }.font(.caption.bold())
                    ForEach(summary.tools) { tool in
                        GridRow {
                            HStack {
                                Text(tool.id).textSelection(.enabled)
                                if tool.latestSpike {
                                    Label("최근 지연 급증", systemImage: "exclamationmark.triangle")
                                        .foregroundStyle(.orange)
                                        .help("최근 측정값이 이전 최대 20건의 p95보다 2배 이상 높습니다. 이전 기록이 5건 이상일 때 표시합니다.")
                                }
                            }
                            Text(diagnosticDuration(tool.p50))
                            Text(diagnosticDuration(tool.p95))
                            Text(diagnosticDuration(tool.maximum))
                            Text((Double(tool.failures) / Double(tool.count))
                                .formatted(.percent.precision(.fractionLength(1))))
                                .help("결과 확인 \(tool.count)건 중 실패 \(tool.failures)건")
                        }.font(.caption.monospacedDigit())
                    }
                }
            }
            DisclosureGroup("최근 MCP 도구 호출 · \(summary.calls.count)건") {
                if summary.calls.isEmpty {
                    Text("저장된 도구 호출이 없습니다.").foregroundStyle(.secondary)
                }
                ForEach(summary.calls.prefix(50)) { call in
                    DisclosureGroup {
                        Text("LinkDeck 처리 · " + diagnosticDuration(call.elapsedMS, missing: "미측정"))
                        if call.appSteps.isEmpty {
                            Text("연동 앱 호출 · 미측정")
                        }
                        ForEach(call.appSteps.indices, id: \.self) { index in
                            let step = call.appSteps[index]
                            Text("\(step.label) · \(diagnosticDuration(step.elapsedMS)) · \(step.outcome ?? "미측정")")
                        }
                        if call.chatViewTask || call.tool.hasSuffix("__chat_view_start_task")
                            || call.tool.hasSuffix("__chat_view_start_image_task") {
                            Text("Chat view+ 대기 · " + diagnosticDuration(call.queueMS, missing: "미측정"))
                            Text("Chat view+ 작업 실행 · " + diagnosticDuration(call.executionMS, missing: "미측정"))
                        }
                    } label: {
                        HStack(alignment: .firstTextBaseline) {
                            Text(call.time, format: .dateTime.day().month().hour().minute().second())
                            Text(call.tool)
                            Spacer()
                            Text(call.outcome)
                            Text(diagnosticDuration(call.elapsedMS)).monospacedDigit()
                        }
                    }
                    .font(.caption)
                }
                if summary.calls.count > 50 {
                    Text("최신 50건을 표시합니다.").font(.caption).foregroundStyle(.secondary)
                }
            }
            DisclosureGroup("설정 변경 전후 비교") {
                DatePicker("변경 시각", selection: $diagnosticsChangeDate, in: ...Date())
                Text("변경 전후 각 24시간의 성공 호출을 같은 도구끼리 비교합니다. 입력이나 실행 환경 차이가 결과에 영향을 줄 수 있습니다.")
                    .font(.caption).foregroundStyle(.secondary)
                let comparison = summary.compare(at: diagnosticsChangeDate)
                if comparison.isEmpty {
                    Text("비교할 성공 호출이 없습니다.").font(.caption).foregroundStyle(.secondary)
                }
                ForEach(comparison) { row in
                    Text("\(row.id) · 전 p95 \(diagnosticDuration(row.beforeP95)) (\(row.beforeCount)건) → 후 p95 \(diagnosticDuration(row.afterP95)) (\(row.afterCount)건)")
                        .font(.caption.monospacedDigit())
                }
            }
        } else {
            Text("최근 7일에 저장된 진단 기록이 없습니다.").foregroundStyle(.secondary)
        }
    }

    private func diagnosticDuration(_ milliseconds: Int?, missing: String = "—") -> String {
        milliseconds.map { "\($0) ms" } ?? missing
    }

    private func refreshDiagnostics() async {
        guard !isLoadingDiagnostics else { return }
        isLoadingDiagnostics = true
        defer { isLoadingDiagnostics = false }
        do {
            diagnosticSummary = try await LinkDeckDiagnosticLog.shared.summary()
        } catch {
            logError = "진단 기록을 읽지 못했습니다: " + error.localizedDescription
        }
    }

    private var connectionContent: some View {
        VStack(alignment: .leading, spacing: 16) {
                Text("ChatGPT에서 LinkDeck 버튼을 조회하고 실행합니다.")
                Label(tunnel.message, systemImage: tunnel.isReady ? "checkmark.circle.fill" : "network")
                    .foregroundStyle(tunnel.isReady ? Color.green : Color.secondary)
                Divider()
                Text("연결 정보").font(.headline)
                VStack(alignment: .leading, spacing: 8) {
                    Text("터널 ID").font(.headline)
                    TextField("tunnel_…", text: $tunnel.tunnelID)
                        .textFieldStyle(.roundedBorder)
                    Text("런타임 API 키").font(.headline)
                    SecureField("새 API 키 입력 · 비워 두면 저장된 키 사용", text: $tunnel.apiKey)
                        .textFieldStyle(.roundedBorder)
                    Text("연결할 때 키를 macOS 키체인에 저장합니다. 관리자 키는 사용하지 마세요.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .disabled(tunnel.isActive)
                Divider()
                Text("연결 관리").font(.headline)
                Toggle("앱 시작 시 자동 연결", isOn: $tunnel.autoConnect)
                Button(tunnel.isActive ? "연결 해제" : "터널 연결") {
                    if tunnel.isActive { tunnel.disconnect(disableAutoConnect: true) }
                    else { tunnel.connect(store: store, folderSyncStore: folderSyncStore, runner: runner) }
                }
                .buttonStyle(.borderedProminent)
                Button("저장된 API 키 삭제") { tunnel.forgetCredential() }
                    .disabled(tunnel.isActive)
                if !tunnel.lastAction.isEmpty {
                    Text("최근 실행: " + tunnel.lastAction).font(.caption)
                }
        }
    }

    private var registeredAppAPIContent: some View {
        VStack(alignment: .leading, spacing: 16) {
                Text("등록된 앱 API").font(.headline)
                Text("앱에 포함된 linkdeck.json을 자동으로 확인합니다. 현재 MCP 표준 입출력 연결을 지원합니다.")
                    .font(.callout)
                Text("앱 API는 5분 미사용 시 종료하고 다음 요청 때 다시 연결합니다. 챗뷰는 작업과 결과 회수 후 10분 미사용 시 숨겨진 자동화 앱까지 종료합니다. 수동 사용과 진행 중인 작업은 유지합니다.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("등록 앱 다시 확인") { refreshAppAPIs() }
                Divider()
                if appAPIs.isEmpty {
                    Text("등록된 버튼 앱에서 API 안내 파일을 찾지 못했습니다.").font(.caption).foregroundStyle(.secondary)
                }
                ForEach(manifestErrors, id: \.self) { error in
                    Text(error).font(.caption).foregroundStyle(.red)
                }
                ForEach(appAPIs) { api in
                    GroupBox {
                      HStack {
                        VStack(alignment: .leading) {
                            Text(api.manifest.name)
                            Text(api.manifest.tools.joined(separator: ", ")).font(.caption)
                        }
                        Spacer()
                        if api.approved {
                            Text("연결 허용됨").foregroundStyle(.green)
                            Button("허용 해제") {
                                UserDefaults.standard.removeObject(forKey: "linkdeck.app-api." + api.bundleID)
                                refreshAppAPIs()
                            }
                        } else {
                            Button("API 연결 허용") { api.approve(); refreshAppAPIs() }
                        }
                        Button("API 목록에서 제거", role: .destructive) {
                            api.removeFromAPIList()
                            refreshAppAPIs()
                        }
                        .help("버튼은 유지합니다. 다시 추가하려면 앱을 API 목록에 드래그하세요.")
                      }
                      .padding(8)
                      .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                Divider()
                DisclosureGroup("다른 앱에 전달할 API 구현·JSON 작성 요구사항") {
                    Text(AppAPIManifest.authoringInstructions)
                        .font(.system(.callout, design: .monospaced)).textSelection(.enabled)
                    Button(copiedInstructions ? "복사됨" : "API 구현 지시사항과 JSON 예시 복사") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(AppAPIManifest.authoringInstructions, forType: .string)
                        copiedInstructions = true
                    }
                }
        }
    }

    private var connectionHelp: some View {
        VStack(alignment: .leading, spacing: 16) {
                Text("처음 연결하기").font(.headline)
                Text("1. OpenAI에서 터널을 만들고, Tunnels Read·Use 권한이 있는 런타임 키를 발급합니다.\n2. 위에 ID와 키를 입력하고 연결합니다.\n3. ChatGPT 개발자 모드에서 앱을 만들고 해당 터널을 선택합니다. 인증은 ‘없음’을 선택합니다.")
                    .font(.callout)
                HStack {
                    Link("터널 관리", destination: URL(string: "https://platform.openai.com/settings/organization/tunnels")!)
                    Link("키 발급", destination: URL(string: "https://platform.openai.com/settings/organization/api-keys")!)
                    Link("ChatGPT 앱 설정", destination: URL(string: "https://chatgpt.com/#settings/Connectors")!)
                }
                Divider()
                Text("사용 방법").font(.headline)
                Text("ChatGPT에 “LinkDeck 버튼 목록 보여줘”, “선택한 폴더싱크를 시작해줘”, “동기화 상태를 확인해줘”처럼 요청하세요. 폴더싱크는 설정된 방향과 옵션을 사용하고, 연결을 해제하면 제어도 중단됩니다.")
                    .font(.callout)
                if ChatGPTTunnelController.executable == nil {
                    Text("터미널에서 한 번 설치하세요:").font(.caption)
                    Text("brew install openai/tools/tunnel-client")
                        .font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                }
                Link("공식 연결 안내", destination: URL(string: "https://developers.openai.com/api/docs/guides/secure-mcp-tunnels")!)
            }
    }

    private func refreshAppAPIs() {
        let buttons = LinkDeckMCPHandler.buttons(macPages: store.pages, phonePages: store.smartphonePages)
        appAPIs = RegisteredAppAPI.discover(buttons: buttons)
        manifestErrors = []
        for id in Set(buttons.filter { $0.action.kind == .app || $0.action.kind == .appFolder }.map { $0.action.value }).sorted() {
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { continue }
            do { _ = try RegisteredAppAPI.load(appURL: url) }
            catch { manifestErrors.append(url.deletingPathExtension().lastPathComponent + ": " + error.localizedDescription) }
        }
    }
}
