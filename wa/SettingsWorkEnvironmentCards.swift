import SwiftUI

extension SettingsView {
    @ViewBuilder
    var workEnvironmentCards: some View {
        if cardMatches(
            title: "빠른 설정",
            keywords: ["행간", "자동 백업", "타이프라이터", "자주", "빠른", "quick"]
        ) {
            quickSettingsCard
        }
        if cardMatches(title: "편집기 설정", keywords: ["메인", "행간", "카드 간격", "editor"]) {
            editorSettingsCard
        }
        if cardMatches(title: "포커스 모드 설정", keywords: ["포커스", "타이프라이터", "기준선", "focus"]) {
            focusModeSettingsCard
        }

        ForEach(shortcutSections) { section in
            if shortcutSectionMatches(section) {
                shortcutSectionCard(section)
            }
        }
    }

    var quickSettingsCard: some View {
        settingsCard(title: "빠른 설정") {
            Text("자주 변경하는 항목을 한곳에서 조정합니다.")
                .font(.caption)
                .foregroundColor(.secondary)

            Toggle("앱 종료 시 자동 백업", isOn: storage.$autoBackupEnabledOnQuit)
            Toggle("포커스 타이프라이터 모드", isOn: storage.$focusTypewriterEnabled)

            Text("메인 모드 행간: \(String(format: "%.2f", storage.mainCardLineSpacingValue))")
            Slider(value: storage.$mainCardLineSpacingValue, in: 1.0...8.0, step: 0.05)

            Text("포커스 모드 행간: \(String(format: "%.2f", storage.focusModeLineSpacingValue))")
            Slider(value: storage.$focusModeLineSpacingValue, in: 0.0...6.0, step: 0.05)
        }
    }

    var editorSettingsCard: some View {
        settingsCard(title: "편집기 설정") {
            Text("메인 모드 행간 (임시): \(String(format: "%.2f", storage.mainCardLineSpacingValue))")
            Slider(value: storage.$mainCardLineSpacingValue, in: 1.0...8.0, step: 0.05)

            Text("카드 위아래 간격: \(Int(storage.mainCardVerticalGap.rounded()))")
            Slider(value: storage.$mainCardVerticalGap, in: 0.0...28.0, step: 1.0)

            Text("기본값은 0이며, 필요할 때만 행 간격을 넓혀 보이게 합니다.")
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(2)
        }
    }

    var focusModeSettingsCard: some View {
        settingsCard(title: "포커스 모드 설정") {
            Toggle("타이프라이터 모드 사용", isOn: storage.$focusTypewriterEnabled)

            Picker("타이프라이터 기준선", selection: storage.$focusTypewriterBaseline) {
                Text("중앙 50%")
                    .tag(0.50)
                Text("기본 60%")
                    .tag(0.60)
                Text("아래 66%")
                    .tag(0.66)
            }
            .pickerStyle(.segmented)
            .disabled(!storage.focusTypewriterEnabled)

            if !storage.focusTypewriterEnabled {
                Text("기준선 조정은 타이프라이터 모드가 켜져 있을 때만 적용됩니다.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }

            Text(storage.focusTypewriterEnabled ? "현재 타이프라이터 모드가 켜져 있습니다." : "현재 타이프라이터 모드가 꺼져 있습니다.")
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(2)
        }
    }

    func shortcutSectionCard(_ section: ShortcutSection) -> some View {
        settingsCard(title: "단축키 - \(section.title)") {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(section.items) { item in
                    shortcutRow(item)
                }
            }
        }
    }
}
