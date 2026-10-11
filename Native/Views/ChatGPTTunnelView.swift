import AppKit
import SwiftUI

struct ChatGPTTunnelView: View {
    @Bindable var tunnel: ChatGPTTunnelController
    let store: LaunchpadStore
    let folderSyncStore: FolderPairStore
    private let runner = MacActionRunner()
    @State private var appAPIs: [RegisteredAppAPI] = []
    @State private var copiedInstructions = false
    @State private var manifestErrors: [String] = []

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
                    SecureField("새 API 키 입력 · 비워 두면 저장된 키 사용", text: $tunnel.apiKey)
                        .textFieldStyle(.roundedBorder)
                    Text("연결할 때 키를 macOS 키체인에 저장합니다. 관리자 키는 사용하지 마세요.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .disabled(tunnel.isActive)
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
                Divider()
                Text("등록된 앱 API").font(.headline)
                Text("앱에 포함된 linkdeck.json을 자동으로 확인합니다. 현재 MCP 표준 입출력 연결을 지원합니다.")
                    .font(.callout)
                Text("앱 API는 5분 미사용 시 종료하고 다음 요청 때 다시 연결합니다. 챗뷰는 작업과 결과 회수 후 10분 미사용 시 숨겨진 자동화 앱까지 종료합니다. 수동 사용과 진행 중인 작업은 유지합니다.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("등록 앱 다시 확인") { refreshAppAPIs() }
                if appAPIs.isEmpty {
                    Text("등록된 버튼 앱에서 API 안내 파일을 찾지 못했습니다.").font(.caption).foregroundStyle(.secondary)
                }
                ForEach(manifestErrors, id: \.self) { error in
                    Text(error).font(.caption).foregroundStyle(.red)
                }
                ForEach(appAPIs) { api in
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
                    }
                }
                DisclosureGroup("다른 앱에 전달할 JSON 작성 요구사항") {
                    Text(AppAPIManifest.authoringInstructions)
                        .font(.system(.callout, design: .monospaced)).textSelection(.enabled)
                    Button(copiedInstructions ? "복사됨" : "작성 요구사항과 JSON 예시 복사") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(AppAPIManifest.authoringInstructions, forType: .string)
                        copiedInstructions = true
                    }
                }
                Divider()
                Text("처음 연결하기").font(.headline)
                Text("1. OpenAI에서 터널을 만들고, Tunnels Read·Use 권한이 있는 런타임 키를 발급합니다.\n2. 위에 ID와 키를 입력하고 연결합니다.\n3. ChatGPT 개발자 모드에서 앱을 만들고 해당 터널을 선택합니다. 인증은 ‘없음’을 선택합니다.")
                    .font(.callout)
                HStack {
                    Link("터널 관리", destination: URL(string: "https://platform.openai.com/settings/organization/tunnels")!)
                    Link("키 발급", destination: URL(string: "https://platform.openai.com/settings/organization/api-keys")!)
                    Link("ChatGPT 앱 설정", destination: URL(string: "https://chatgpt.com/#settings/Connectors")!)
                }
                Text("ChatGPT에 “LinkDeck 버튼 목록 보여줘”, “선택한 폴더싱크를 시작해줘”, “동기화 상태를 확인해줘”처럼 요청하세요. 폴더싱크는 설정된 방향과 옵션을 사용하고, 연결을 해제하면 제어도 중단됩니다.")
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
        .onAppear { refreshAppAPIs() }
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
