import AppKit
import SwiftUI

struct ChatGPTTunnelView: View {
    @Bindable var tunnel: ChatGPTTunnelController
    let store: LaunchpadStore
    private let runner = MacActionRunner()

    @State private var logError: String?
    @State private var diagnosticSummary: LinkDeckDiagnosticSummary?
    @State private var isLoadingDiagnostics = false
    @State private var diagnosticsChangeDate = Date()
    @AppStorage(LinkDeckDiagnosticLog.enabledKey) private var diagnosticsEnabled = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("ChatGPT에서 LinkDeck 버튼을 조회하고 실행합니다.")
                Label(tunnel.message, systemImage: tunnel.isReady ? "checkmark.circle.fill" : "network")
                    .foregroundStyle(tunnel.isReady ? Color.green : Color.secondary)
                VStack(alignment: .leading, spacing: 8) {
                    Text("터널 ID").font(.headline)
                    TextField("tunnel_…", text: $tunnel.tunnelID)
                        .textFieldStyle(.roundedBorder)
                    Text("런타임 API 키").font(.headline)
                    SecureField("OpenAI 터널 런타임 키", text: $tunnel.apiKey)
                        .textFieldStyle(.roundedBorder)
                    Text("키는 이 앱을 실행하는 동안만 보관합니다. 관리자 키는 사용하지 마세요.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .disabled(tunnel.isActive)
                Button(tunnel.isActive ? "연결 해제" : "터널 연결") {
                    if tunnel.isActive { tunnel.disconnect() }
                    else { tunnel.connect(store: store, runner: runner) }
                }
                .buttonStyle(.borderedProminent)
                if !tunnel.lastAction.isEmpty {
                    Text("최근 실행: " + tunnel.lastAction).font(.caption)
                }
                diagnosticsContent
                Divider()
                Text("처음 연결하기").font(.headline)
                Text("1. OpenAI에서 터널을 만들고, Tunnels Read·Use 권한이 있는 런타임 키를 발급합니다.\n2. 위에 ID와 키를 입력하고 연결합니다.\n3. ChatGPT 개발자 모드에서 앱을 만들고 해당 터널을 선택합니다. 인증은 ‘없음’을 선택합니다.")
                    .font(.callout)
                HStack {
                    Link("터널 관리", destination: URL(string: "https://platform.openai.com/settings/organization/tunnels")!)
                    Link("키 발급", destination: URL(string: "https://platform.openai.com/settings/organization/api-keys")!)
                    Link("ChatGPT 앱 설정", destination: URL(string: "https://chatgpt.com/#settings/Connectors")!)
                }
                Text("ChatGPT에 “LinkDeck 버튼 목록 보여줘”, “LinkDeck의 잠자기 방지 버튼 실행해줘”처럼 요청하세요. 등록된 버튼만 실행하며, 연결을 해제하면 제어도 중단됩니다.")
                    .font(.callout)
                if ChatGPTTunnelController.executable == nil {
                    Text("터미널에서 한 번 설치하세요:").font(.caption)
                    Text("brew install openai/tools/tunnel-client")
                        .font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                }
                Link("공식 연결 안내", destination: URL(string: "https://developers.openai.com/api/docs/guides/secure-mcp-tunnels")!)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .alert("진단 로그", isPresented: Binding(get: { logError != nil }, set: { if !$0 { logError = nil } })) {
            Button("확인") { logError = nil }
        } message: { Text(logError ?? "") }
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

}
