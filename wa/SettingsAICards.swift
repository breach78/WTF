import SwiftUI

extension SettingsView {
    @ViewBuilder
    var aiCards: some View {
        if cardMatches(title: "AI 설정", keywords: ["gemini", "모델", "API 키", "keychain", "ai"]) {
            aiSettingsCard
        }
    }

    var aiSettingsCard: some View {
        settingsCard(title: "AI 설정") {
            Text("Gemini 모델")
                .font(.caption)
                .foregroundColor(.secondary)
            Picker("모델 선택", selection: $selectedGeminiModelOption) {
                ForEach(geminiModelOptions) { option in
                    Text(option.title)
                        .tag(option.value)
                }
                Text("직접 입력")
                    .tag(customGeminiModelToken)
            }
            .pickerStyle(.menu)
            .onChange(of: selectedGeminiModelOption) { _, newValue in
                guard newValue != customGeminiModelToken else { return }
                storage.geminiModelID = newValue
            }

            TextField("예: gemini-3.1-pro-preview", text: storage.$geminiModelID)
                .textFieldStyle(.roundedBorder)
                .onChange(of: storage.geminiModelID) { _, _ in
                    syncGeminiModelOptionSelection()
                }

            Text("Gemini 3.1 Pro의 API 모델 ID는 gemini-3.1-pro-preview 입니다. 404가 뜨면 다른 모델을 선택하세요.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .lineLimit(2)

            Text("Gemini API 키")
                .font(.caption)
                .foregroundColor(.secondary)
            SecureField(hasGeminiAPIKey ? "새 키를 입력하면 덮어씁니다" : "API 키 입력", text: $geminiAPIKeyInput)
                .textFieldStyle(.roundedBorder)

            HStack(spacing: 8) {
                Button(hasGeminiAPIKey ? "키 업데이트" : "키 저장") {
                    saveGeminiAPIKey()
                }
                .disabled(geminiAPIKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button("키 삭제", role: .destructive) {
                    pendingConfirmation = .deleteAPIKey
                }
                .disabled(!hasGeminiAPIKey)
            }

            Text(hasGeminiAPIKey ? "현재 API 키가 저장되어 있습니다." : "현재 저장된 API 키가 없습니다.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .lineLimit(2)

            if let message = aiSettingsStatusMessage {
                Text(message)
                    .font(.system(size: 11))
                    .foregroundColor(aiSettingsStatusIsError ? .red : .secondary)
                    .lineLimit(2)
            }
        }
    }

    func syncGeminiModelOptionSelection() {
        let normalized = normalizeGeminiModelID(storage.geminiModelID)
        if normalized != storage.geminiModelID {
            storage.geminiModelID = normalized
        }
        let trimmedModel = normalized.trimmingCharacters(in: .whitespacesAndNewlines)
        if geminiModelOptions.contains(where: { $0.value == trimmedModel }) {
            selectedGeminiModelOption = trimmedModel
        } else {
            selectedGeminiModelOption = customGeminiModelToken
        }
    }

    func normalizeGeminiModelID(_ raw: String) -> String {
        normalizeGeminiModelIDValue(raw)
    }
}
