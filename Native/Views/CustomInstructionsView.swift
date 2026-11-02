import SwiftUI

struct CustomInstructionsView: View {
    let store: LaunchpadStore
    @State private var draft = ""
    @State private var message = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Toggle("사용자 지정 지침 적용", isOn: Binding(
                    get: { store.customInstructions.isEnabled },
                    set: { enabled in
                        var value = store.customInstructions
                        value.isEnabled = enabled
                        save(value, message: enabled ? "지침 적용을 켰습니다." : "지침 적용을 껐습니다.")
                    }
                ))
                .toggleStyle(.switch)
                Text("연결된 AI가 작업할 때 참고할 공통 규칙을 자유롭게 작성하세요.")
                    .foregroundStyle(.secondary)
                TextEditor(text: $draft)
                    .font(.body)
                    .frame(minHeight: 170)
                    .padding(6)
                    .background(.background, in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(.secondary.opacity(0.3)))
                    .accessibilityLabel("사용자 지정 지침 내용")
                HStack {
                    Button("저장") {
                        var value = store.customInstructions
                        value.text = draft
                        save(value, message: "저장했습니다. AI의 다음 지침 조회부터 반영됩니다.")
                    }
                    .disabled(draft == store.customInstructions.text)
                    Text(draft == store.customInstructions.text ? "저장된 내용" : "저장하지 않은 변경 사항")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if !message.isEmpty {
                    Text(message).font(.caption).accessibilityLabel(message)
                }
                Text("적용 시점과 지원 연결").font(.headline)
                Text("내용은 저장 후, 스위치는 변경 즉시 AI의 다음 조회에 반영됩니다. 앱을 재시작해도 유지됩니다. 꺼도 작성한 내용은 보관하며 AI 조회에는 빈 지침을 반환합니다.")
                Text("ChatGPT의 LinkDeck MCP 연결 및 같은 서버를 사용하는 MCP 클라이언트에서 지원합니다. 새 도구가 보이지 않으면 연결 도구 목록을 새로고침하거나 재연결하세요. AI에 ‘LinkDeck 사용자 지정 지침을 조회해줘’라고 요청하세요. 기존 버튼 목록 조회에도 활성 지침을 함께 전달합니다.")
                Text("LinkDeck 도구를 호출할 때마다 먼저 지침 또는 버튼 목록을 조회하고, 응답의 일회용 instructions_receipt를 전달해야 합니다. 확인값이 없거나 사용됐거나 지침 저장 후 오래된 값이면 서버가 호출을 차단합니다. 새 인수가 보이지 않으면 연결 도구 목록을 새로고침하세요. AI의 이해·준수 자체는 보장하지 않습니다. 이미 전달된 지침은 회수할 수 없으며 Codex 상태 연결만으로는 전달되지 않습니다.")
                Text("저장은 메모 작성이나 도구 실행을 시작하지 않습니다. 지침은 도구 접근 권한과 승인 조건을 변경하지 않습니다. 활성화하면 조회한 AI에 내용이 전달되므로 비밀번호 등 비밀 정보는 입력하지 마세요.")
            }
            .font(.callout)
            .padding(20)
        }
        .onAppear { draft = store.customInstructions.text }
    }

    private func save(_ value: CustomInstructions, message: String) {
        do {
            try store.saveCustomInstructions(value)
            self.message = message
        } catch {
            self.message = "저장하지 못했습니다: \(error.localizedDescription)"
        }
    }
}
