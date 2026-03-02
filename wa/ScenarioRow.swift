import SwiftUI

struct ScenarioRow: View {
    @ObservedObject var scenario: Scenario
    var onRename: () -> Void
    var onDelete: () -> Void
    var onMakeTemplate: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Text(scenario.title.isEmpty ? "제목 없음" : scenario.title)
                .font(.custom("SansMonoCJKFinalDraft", size: 18))
            if scenario.isTemplate {
                Text("템플릿")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.secondary.opacity(0.15))
                    .clipShape(Capsule())
            }
        }
            .padding(.vertical, 2)
            .contextMenu {
                Button("이름 변경") { onRename() }
                Button("템플릿으로 만들기") { onMakeTemplate() }
                Button("삭제", role: .destructive) { onDelete() }
            }
    }
}
