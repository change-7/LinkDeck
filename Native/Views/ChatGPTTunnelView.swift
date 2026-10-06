import AppKit
import SwiftUI

struct ChatGPTTunnelView: View {
    @Bindable var tunnel: ChatGPTTunnelController
    let store: LaunchpadStore
    let folderSyncStore: FolderPairStore
    private let runner = MacActionRunner()

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
                    else { tunnel.connect(store: store, folderSyncStore: folderSyncStore, runner: runner) }
                }
                .buttonStyle(.borderedProminent)
                if !tunnel.lastAction.isEmpty {
                    Text("최근 실행: " + tunnel.lastAction).font(.caption)
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
    }
}
