import SwiftUI

extension SettingsView {
    @ViewBuilder
    var appearanceCards: some View {
        if cardMatches(title: "보드뷰 테마", keywords: ["보드", "board", "캔버스", "canvas", "테마"]) {
            indexBoardThemeCard
        }
        if cardMatches(title: "색상 테마 프리셋", keywords: ["색상", "테마", "프리셋", "palette", "theme"]) {
            colorThemePresetCard
        }
        if cardMatches(title: "색상 설정", keywords: ["라이트", "다크", "배경", "카드", "custom color"]) {
            colorSettingsCard
        }
        if cardMatches(title: "색상 초기화", keywords: ["기본값", "reset", "restore default"]) {
            colorResetCard
        }
    }

    var colorThemePresetCard: some View {
        settingsCard(title: "색상 테마 프리셋") {
            Picker("프리셋", selection: $selectedColorThemePresetID) {
                ForEach(ColorThemePreset.allCases) { preset in
                    Text(preset.title)
                        .tag(preset.rawValue)
                }
                ForEach(customColorThemePresets) { preset in
                    Text("사용자: \(preset.title)")
                        .tag(preset.id)
                }
            }
            .pickerStyle(.menu)

            HStack(spacing: 8) {
                Button("선택한 프리셋 적용") {
                    applySelectedColorThemePreset()
                }

                Button("프리셋으로 저장") {
                    newColorPresetName = ""
                    saveColorPresetError = nil
                    showSaveColorPresetSheet = true
                }
            }

            Text("라이트/다크 모드는 유지하고 카드/배경 팔레트만 교체합니다.")
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(2)
        }
    }

    var indexBoardThemeCard: some View {
        settingsCard(title: "보드뷰 테마") {
            Picker("보드 테마", selection: storage.$indexBoardThemePresetID) {
                ForEach(IndexBoardThemePreset.allCases) { preset in
                    Text(preset.title)
                        .tag(preset.rawValue)
                }
            }
            .pickerStyle(.menu)

            if let preset = IndexBoardThemePreset(rawValue: storage.indexBoardThemePresetID) {
                HStack(spacing: 8) {
                    ForEach(Array(preset.previewHexes.enumerated()), id: \.offset) { entry in
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(colorFromHex(entry.element) ?? Color.clear)
                            .frame(width: 34, height: 22)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .stroke(Color.black.opacity(0.10), lineWidth: 0.8)
                            )
                    }
                    Spacer(minLength: 0)
                }

                Text(preset.subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }

            Text("인덱스 보드 캔버스에만 적용되고, 작업창/포커스 뷰 색은 바꾸지 않습니다.")
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(2)
        }
    }

    var colorSettingsCard: some View {
        settingsCard(title: "색상 설정") {
            themedColorPickerRow(
                title: "앱 배경 색",
                lightHex: storage.$backgroundColorHex,
                darkHex: storage.$darkBackgroundColorHex,
                lightFallback: Color(red: 0.96, green: 0.95, blue: 0.93),
                darkFallback: Color(red: 0.07, green: 0.08, blue: 0.10)
            )
            themedColorPickerRow(
                title: "카드 기본 색",
                lightHex: storage.$cardBaseColorHex,
                darkHex: storage.$darkCardBaseColorHex,
                lightFallback: Color.white,
                darkFallback: Color(red: 0.10, green: 0.13, blue: 0.16)
            )
            themedColorPickerRow(
                title: "선택 카드 색",
                lightHex: storage.$cardActiveColorHex,
                darkHex: storage.$darkCardActiveColorHex,
                lightFallback: Color(red: 0.75, green: 0.84, blue: 1.0),
                darkFallback: Color(red: 0.16, green: 0.23, blue: 0.31)
            )
            themedColorPickerRow(
                title: "연결 카드 색",
                lightHex: storage.$cardRelatedColorHex,
                darkHex: storage.$darkCardRelatedColorHex,
                lightFallback: Color(red: 0.87, green: 0.92, blue: 1.0),
                darkFallback: Color(red: 0.14, green: 0.18, blue: 0.25)
            )
        }
    }

    var colorResetCard: some View {
        settingsCard(title: "색상 초기화") {
            Button("카드/배경 색 기본값으로", role: .destructive) {
                pendingConfirmation = .resetColors
            }
        }
    }

    var saveColorPresetSheet: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("색상 프리셋 저장")
                .font(.headline)

            Text("현재 카드/배경 색 조합을 프리셋 메뉴에 추가합니다.")
                .font(.caption)
                .foregroundColor(.secondary)

            TextField("프리셋 이름", text: $newColorPresetName)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    saveCurrentColorsAsPreset()
                }

            if let message = saveColorPresetError {
                Text(message)
                    .font(.caption)
                    .foregroundColor(.red)
            }

            HStack {
                Spacer()
                Button("취소", role: .cancel) {
                    showSaveColorPresetSheet = false
                }
                Button("저장") {
                    saveCurrentColorsAsPreset()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(newColorPresetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.top, 2)
        }
        .padding(16)
        .frame(width: 360)
    }

    func colorBinding(hex: Binding<String>, fallback: Color) -> Binding<Color> {
        Binding(
            get: { colorFromHex(hex.wrappedValue) ?? fallback },
            set: { newColor in
                hex.wrappedValue = hexFromColor(newColor)
            }
        )
    }

    @ViewBuilder
    func themedColorPickerRow(
        title: String,
        lightHex: Binding<String>,
        darkHex: Binding<String>,
        lightFallback: Color,
        darkFallback: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            HStack(spacing: 10) {
                ColorPicker(
                    "라이트",
                    selection: colorBinding(hex: lightHex, fallback: lightFallback)
                )
                ColorPicker(
                    "다크",
                    selection: colorBinding(hex: darkHex, fallback: darkFallback)
                )
            }
        }
    }

    func colorFromHex(_ hex: String) -> Color? {
        guard let rgb = parseHexRGB(hex) else { return nil }
        return Color(red: rgb.0, green: rgb.1, blue: rgb.2)
    }

    func hexFromColor(_ color: Color) -> String {
        let ns = NSColor(color)
        let rgb = ns.usingColorSpace(.deviceRGB) ?? ns
        let r = Int(round(rgb.redComponent * 255))
        let g = Int(round(rgb.greenComponent * 255))
        let b = Int(round(rgb.blueComponent * 255))
        return String(format: "%02X%02X%02X", r, g, b)
    }

    func resetColorsToDefaults() {
        storage.backgroundColorHex = "F4F2EE"
        storage.darkBackgroundColorHex = "111418"
        storage.cardBaseColorHex = "FFFFFF"
        storage.cardActiveColorHex = "BFD7FF"
        storage.cardRelatedColorHex = "DDE9FF"
        storage.darkCardBaseColorHex = "1A2029"
        storage.darkCardActiveColorHex = "2A3A4E"
        storage.darkCardRelatedColorHex = "242F3F"
    }

    func loadCustomColorThemePresets() {
        guard !storage.customColorThemePresetsJSON.isEmpty else {
            customColorThemePresets = []
            return
        }
        guard let data = storage.customColorThemePresetsJSON.data(using: .utf8) else {
            customColorThemePresets = []
            return
        }
        do {
            customColorThemePresets = try JSONDecoder().decode([SavedColorThemePreset].self, from: data)
        } catch {
            customColorThemePresets = []
        }
    }

    func persistCustomColorThemePresets() {
        guard let data = try? JSONEncoder().encode(customColorThemePresets),
              let json = String(data: data, encoding: .utf8) else {
            return
        }
        storage.customColorThemePresetsJSON = json
    }

    func saveCurrentColorsAsPreset() {
        let trimmedName = newColorPresetName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            saveColorPresetError = "프리셋 이름을 입력해 주세요."
            return
        }
        if customColorThemePresets.contains(where: { $0.title.caseInsensitiveCompare(trimmedName) == .orderedSame }) {
            saveColorPresetError = "같은 이름의 프리셋이 이미 있습니다."
            return
        }

        let preset = SavedColorThemePreset(
            id: UUID().uuidString,
            title: trimmedName,
            lightBackground: storage.backgroundColorHex,
            lightCardBase: storage.cardBaseColorHex,
            lightCardActive: storage.cardActiveColorHex,
            lightCardRelated: storage.cardRelatedColorHex,
            darkBackground: storage.darkBackgroundColorHex,
            darkCardBase: storage.darkCardBaseColorHex,
            darkCardActive: storage.darkCardActiveColorHex,
            darkCardRelated: storage.darkCardRelatedColorHex
        )
        customColorThemePresets.append(preset)
        persistCustomColorThemePresets()
        selectedColorThemePresetID = preset.id
        saveColorPresetError = nil
        showSaveColorPresetSheet = false
    }

    func applySelectedColorThemePreset() {
        if let preset = ColorThemePreset(rawValue: selectedColorThemePresetID) {
            applyColorThemePreset(preset)
            return
        }
        guard let customPreset = customColorThemePresets.first(where: { $0.id == selectedColorThemePresetID }) else {
            return
        }
        applyColorThemePreset(customPreset)
    }

    func applyColorThemeValues(
        lightBackground: String,
        lightCardBase: String,
        lightCardActive: String,
        lightCardRelated: String,
        darkBackground: String,
        darkCardBase: String,
        darkCardActive: String,
        darkCardRelated: String
    ) {
        storage.backgroundColorHex = lightBackground
        storage.darkBackgroundColorHex = darkBackground
        storage.cardBaseColorHex = lightCardBase
        storage.cardActiveColorHex = lightCardActive
        storage.cardRelatedColorHex = lightCardRelated
        storage.darkCardBaseColorHex = darkCardBase
        storage.darkCardActiveColorHex = darkCardActive
        storage.darkCardRelatedColorHex = darkCardRelated
    }

    func applyColorThemePreset(_ preset: ColorThemePreset) {
        applyColorThemeValues(
            lightBackground: preset.lightBackground,
            lightCardBase: preset.lightCardBase,
            lightCardActive: preset.lightCardActive,
            lightCardRelated: preset.lightCardRelated,
            darkBackground: preset.darkBackground,
            darkCardBase: preset.darkCardBase,
            darkCardActive: preset.darkCardActive,
            darkCardRelated: preset.darkCardRelated
        )
    }

    func applyColorThemePreset(_ preset: SavedColorThemePreset) {
        applyColorThemeValues(
            lightBackground: preset.lightBackground,
            lightCardBase: preset.lightCardBase,
            lightCardActive: preset.lightCardActive,
            lightCardRelated: preset.lightCardRelated,
            darkBackground: preset.darkBackground,
            darkCardBase: preset.darkCardBase,
            darkCardActive: preset.darkCardActive,
            darkCardRelated: preset.darkCardRelated
        )
    }
}
