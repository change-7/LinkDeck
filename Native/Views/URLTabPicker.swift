import SwiftUI

struct URLTabPicker: View {
    @Binding var openInCurrentTab: Bool

    var body: some View {
        Picker("웹페이지 열기", selection: $openInCurrentTab) {
            Text("새 탭에서 열기").tag(false)
            Text("현재 탭에서 열기").tag(true)
        }
        .pickerStyle(.menu)
        .help("기본 브라우저의 현재 탭을 사용합니다. 열린 창이 없으면 새 창을 엽니다.")
    }
}
