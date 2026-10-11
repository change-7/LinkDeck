import SwiftUI

struct PageNameEditor: ViewModifier {
    let name: String
    let save: (String) -> Void
    @State private var isPresented = false
    @State private var editedName = ""

    func body(content: Content) -> some View {
        content
            .contextMenu {
                Button("이름 수정", systemImage: "pencil") {
                    editedName = name
                    isPresented = true
                }
            }
            .alert("페이지 이름 수정", isPresented: $isPresented) {
                TextField("페이지 이름", text: $editedName)
                Button("취소", role: .cancel) {}
                Button("저장") { save(editedName) }
            }
    }
}
