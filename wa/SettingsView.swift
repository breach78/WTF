import SwiftUI

struct SettingsView: View {
    private struct ShortcutItem: Identifiable {
        let keys: String
        let action: String
        var id: String { "\(keys)|\(action)" }
    }

    private struct ShortcutSection: Identifiable {
        let title: String
        let items: [ShortcutItem]
        var id: String { title }
    }

    private struct GeminiModelOption: Identifiable {
        let value: String
        let title: String
        var id: String { value }
    }

    private enum ColorThemePreset: String, CaseIterable, Identifiable {
        case warmPaper
        case mintFog
        case blueGray
        case sepiaCalm
        case sageSlate
        case quietSlate
        case mellowOlive

        var id: String { rawValue }

        var title: String {
            switch self {
            case .warmPaper: return "Warm Paper"
            case .mintFog: return "Mint Fog"
            case .blueGray: return "Blue Gray"
            case .sepiaCalm: return "Sepia Calm"
            case .sageSlate: return "Sage Slate"
            case .quietSlate: return "Quiet Slate"
            case .mellowOlive: return "Mellow Olive"
            }
        }

        var lightBackground: String {
            switch self {
            case .warmPaper: return "F6F1E6"
            case .mintFog: return "EDF5F0"
            case .blueGray: return "EFF3F6"
            case .sepiaCalm: return "F5ECE0"
            case .sageSlate: return "F0F3EE"
            case .quietSlate: return "4B4F56"
            case .mellowOlive: return "50534C"
            }
        }

        var lightCardBase: String {
            switch self {
            case .warmPaper: return "FFFCF5"
            case .mintFog: return "F9FFFC"
            case .blueGray: return "FBFDFE"
            case .sepiaCalm: return "FFF8EF"
            case .sageSlate: return "FBFEF9"
            case .quietSlate: return "777D86"
            case .mellowOlive: return "7D8178"
            }
        }

        var lightCardActive: String {
            switch self {
            case .warmPaper: return "F2D8B4"
            case .mintFog: return "CCE9DD"
            case .blueGray: return "CDDDEA"
            case .sepiaCalm: return "E8CFAF"
            case .sageSlate: return "D4DEC9"
            case .quietSlate: return "D7E9FB"
            case .mellowOlive: return "E0EDCF"
            }
        }

        var lightCardRelated: String {
            switch self {
            case .warmPaper: return "F7E7CF"
            case .mintFog: return "E0F2EA"
            case .blueGray: return "E1ECF3"
            case .sepiaCalm: return "F1DFC8"
            case .sageSlate: return "E5ECDD"
            case .quietSlate: return "C4DCF3"
            case .mellowOlive: return "D0E2BE"
            }
        }

        var darkBackground: String {
            switch self {
            case .warmPaper: return "141516"
            case .mintFog: return "111A18"
            case .blueGray: return "10161C"
            case .sepiaCalm: return "19140F"
            case .sageSlate: return "121814"
            case .quietSlate: return "141920"
            case .mellowOlive: return "171A14"
            }
        }

        var darkCardBase: String {
            switch self {
            case .warmPaper: return "212220"
            case .mintFog: return "1A2623"
            case .blueGray: return "1A2430"
            case .sepiaCalm: return "2A221A"
            case .sageSlate: return "1D2822"
            case .quietSlate: return "242B35"
            case .mellowOlive: return "282D23"
            }
        }

        var darkCardActive: String {
            switch self {
            case .warmPaper: return "5A4631"
            case .mintFog: return "2F4D46"
            case .blueGray: return "33495E"
            case .sepiaCalm: return "5A4633"
            case .sageSlate: return "3A5147"
            case .quietSlate: return "41546B"
            case .mellowOlive: return "4B5D3D"
            }
        }

        var darkCardRelated: String {
            switch self {
            case .warmPaper: return "3A332B"
            case .mintFog: return "243A35"
            case .blueGray: return "273845"
            case .sepiaCalm: return "413428"
            case .sageSlate: return "2A3B34"
            case .quietSlate: return "374659"
            case .mellowOlive: return "405035"
            }
        }
    }

    private struct SavedColorThemePreset: Identifiable, Codable {
        let id: String
        let title: String
        let lightBackground: String
        let lightCardBase: String
        let lightCardActive: String
        let lightCardRelated: String
        let darkBackground: String
        let darkCardBase: String
        let darkCardActive: String
        let darkCardRelated: String
    }

    @AppStorage("backgroundColorHex") private var backgroundColorHex: String = "F4F2EE"
    @AppStorage("darkBackgroundColorHex") private var darkBackgroundColorHex: String = "111418"
    @AppStorage("cardBaseColorHex") private var cardBaseColorHex: String = "FFFFFF"
    @AppStorage("cardActiveColorHex") private var cardActiveColorHex: String = "BFD7FF"
    @AppStorage("cardRelatedColorHex") private var cardRelatedColorHex: String = "DDE9FF"
    @AppStorage("darkCardBaseColorHex") private var darkCardBaseColorHex: String = "1A2029"
    @AppStorage("darkCardActiveColorHex") private var darkCardActiveColorHex: String = "2A3A4E"
    @AppStorage("darkCardRelatedColorHex") private var darkCardRelatedColorHex: String = "242F3F"
    @AppStorage("customColorThemePresetsJSON") private var customColorThemePresetsJSON: String = ""
    @AppStorage("autoBackupEnabledOnQuit") private var autoBackupEnabledOnQuit: Bool = true
    @AppStorage("autoBackupDirectoryPath") private var autoBackupDirectoryPath: String = ""
    @AppStorage("storageBookmark") private var storageBookmark: Data?
    @AppStorage("forceWorkspaceReset") private var forceWorkspaceReset: Bool = false
    @AppStorage("exportCenteredFontSize") private var exportCenteredFontSize: Double = 12.0
    @AppStorage("exportCenteredCharacterBold") private var exportCenteredCharacterBold: Bool = true
    @AppStorage("exportCenteredSceneHeadingBold") private var exportCenteredSceneHeadingBold: Bool = true
    @AppStorage("exportCenteredShowRightSceneNumber") private var exportCenteredShowRightSceneNumber: Bool = false
    @AppStorage("exportKoreanFontSize") private var exportKoreanFontSize: Double = 11.0
    @AppStorage("exportKoreanSceneBold") private var exportKoreanSceneBold: Bool = true
    @AppStorage("exportKoreanCharacterBold") private var exportKoreanCharacterBold: Bool = true
    @AppStorage("exportKoreanCharacterAlignment") private var exportKoreanCharacterAlignment: String = "right"
    @AppStorage("focusTypewriterEnabled") private var focusTypewriterEnabled: Bool = false
    @AppStorage("focusTypewriterBaseline") private var focusTypewriterBaseline: Double = 0.60
    @AppStorage("mainCardLineSpacingValueV2") private var mainCardLineSpacingValue: Double = 5.0
    @AppStorage("mainCardVerticalGap") private var mainCardVerticalGap: Double = 0.0
    @AppStorage("focusModeLineSpacingValueTemp") private var focusModeLineSpacingValue: Double = 4.5
    @AppStorage("geminiModelID") private var geminiModelID: String = "gemini-3.1-pro-preview"

    @State private var geminiAPIKeyInput: String = ""
    @State private var hasGeminiAPIKey: Bool = false
    @State private var aiSettingsStatusMessage: String? = nil
    @State private var aiSettingsStatusIsError: Bool = false
    @State private var selectedColorThemePresetID: String = ColorThemePreset.warmPaper.rawValue
    @State private var customColorThemePresets: [SavedColorThemePreset] = []
    @State private var showSaveColorPresetSheet: Bool = false
    @State private var newColorPresetName: String = ""
    @State private var saveColorPresetError: String? = nil
    @State private var selectedGeminiModelOption: String = "gemini-3.1-pro-preview"
    @State private var autoBackupStatusMessage: String? = nil
    @State private var autoBackupStatusIsError: Bool = false

    private let customGeminiModelToken = "__custom__"
    private let geminiModelOptions: [GeminiModelOption] = [
        GeminiModelOption(value: "gemini-3.1-pro-preview", title: "Gemini 3.1 Pro (Preview)"),
        GeminiModelOption(value: "gemini-3-pro-preview", title: "Gemini 3 Pro (Preview)"),
        GeminiModelOption(value: "gemini-3-flash", title: "Gemini 3 Flash"),
        GeminiModelOption(value: "gemini-2.5-pro", title: "Gemini 2.5 Pro"),
        GeminiModelOption(value: "gemini-2.5-flash", title: "Gemini 2.5 Flash"),
        GeminiModelOption(value: "gemini-2.0-flash", title: "Gemini 2.0 Flash")
    ]
    private let oflFontFiles: [String] = [
        "Sans Mono CJK Final Draft.otf",
        "Sans Mono CJK Final Draft Bold.otf"
    ]
    private let oflLicenseURL = URL(string: "https://openfontlicense.org/open-font-license-official-text/")!
    
    var onUpdateStore: () -> Void
    
    private var currentStoragePath: String {
        guard let bookmark = storageBookmark else { return "설정되지 않음" }
        var isStale = false
        if let url = try? URL(resolvingBookmarkData: bookmark, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale) {
            return url.path
        }
        return "알 수 없는 경로"
    }

    private var currentAutoBackupPath: String {
        let trimmed = autoBackupDirectoryPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return WorkspaceAutoBackupService.defaultBackupDirectoryURL().path
        }
        return NSString(string: trimmed).expandingTildeInPath
    }

    private var shortcutSections: [ShortcutSection] {
        [
            ShortcutSection(
                title: "공통",
                items: [
                    ShortcutItem(keys: "Cmd + Z", action: "실행 취소"),
                    ShortcutItem(keys: "Cmd + Shift + Z", action: "다시 실행"),
                    ShortcutItem(keys: "Cmd + Shift + F", action: "포커스 모드 토글"),
                    ShortcutItem(keys: "Cmd + F", action: "검색창 열기/닫기"),
                    ShortcutItem(keys: "Cmd + Shift + ]", action: "전체 카드(타임라인) 패널 토글")
                ]
            ),
            ShortcutSection(
                title: "메인 작업 모드",
                items: [
                    ShortcutItem(keys: "Arrow ↑ ↓ ← →", action: "카드 이동"),
                    ShortcutItem(keys: "Right (자식 없음 시 빠르게 2회)", action: "인접 부모의 자식 카드로 점프"),
                    ShortcutItem(keys: "Return", action: "선택 카드 편집 시작"),
                    ShortcutItem(keys: "Esc", action: "편집/검색 종료 (상황별)"),
                    ShortcutItem(keys: "Tab + Tab (편집 중)", action: "자식 카드 추가 후 바로 편집"),
                    ShortcutItem(keys: "Tab", action: "자식 카드 추가"),
                    ShortcutItem(keys: "Cmd + ↑", action: "위에 형제 카드 추가"),
                    ShortcutItem(keys: "Cmd + ↓", action: "아래에 형제 카드 추가"),
                    ShortcutItem(keys: "Cmd + Return", action: "편집 종료 후 아래에 형제 카드 추가"),
                    ShortcutItem(keys: "Cmd + →", action: "자식 카드 추가"),
                    ShortcutItem(keys: "Cmd + Shift + Delete", action: "선택 카드(또는 선택 묶음) 삭제"),
                    ShortcutItem(keys: "Cmd + Shift + Arrow", action: "카드 계층 이동(상/하/좌/우)")
                ]
            ),
            ShortcutSection(
                title: "포커스 모드",
                items: [
                    ShortcutItem(keys: "Arrow ↑ / ↓", action: "경계에서 이전/다음 카드로 이동"),
                    ShortcutItem(keys: "Cmd + Shift + T", action: "타이프라이터 모드 토글"),
                    ShortcutItem(keys: "Cmd + Return", action: "아래에 형제 카드 추가"),
                    ShortcutItem(keys: "Cmd + Option + ↑ / ↓", action: "위/아래 형제 카드 추가"),
                    ShortcutItem(keys: "Cmd + Shift + Delete", action: "현재 카드 삭제")
                ]
            ),
            ShortcutSection(
                title: "히스토리 모드",
                items: [
                    ShortcutItem(keys: "Arrow ← / →", action: "타임라인 이전/다음 시점 이동"),
                    ShortcutItem(keys: "Cmd + Arrow ← / →", action: "이전/다음 네임드 스냅샷 이동"),
                    ShortcutItem(keys: "Esc", action: "검색 포커스 해제/노트 편집 종료/히스토리 닫기")
                ]
            )
        ]
    }

    private enum SettingsTab: String, CaseIterable, Identifiable {
        case settings
        case shortcuts

        var id: String { rawValue }
    }

    @State private var selectedSettingsTab: SettingsTab = .settings

    private enum SettingsLayout {
        static let windowWidth: CGFloat = 1120
        static let windowHeight: CGFloat = 700
        static let contentPadding: CGFloat = 12
        static let columnSpacing: CGFloat = 10
        static let cardSpacing: CGFloat = 12
        static let cardContentSpacing: CGFloat = 6
        static let cardPadding: CGFloat = 10
        static let cardCornerRadius: CGFloat = 12
        static let titleCornerRadius: CGFloat = 8
        static let cardTitleFontSize: CGFloat = 14
    }

    private var shortcutLeftSections: [ShortcutSection] {
        Array(shortcutSections.prefix(2))
    }

    private var shortcutRightSections: [ShortcutSection] {
        Array(shortcutSections.dropFirst(2))
    }

    private var oflLicenseText: String {
        """
        SIL OPEN FONT LICENSE Version 1.1 - 26 February 2007

        PREAMBLE
        The goals of the Open Font License (OFL) are to stimulate worldwide development
        of collaborative font projects, to support the font creation efforts of academic
        and linguistic communities, and to provide a free and open framework in which
        fonts may be shared and improved in partnership with others.

        The OFL allows the licensed fonts to be used, studied, modified and redistributed
        freely as long as they are not sold by themselves. The fonts, including any
        derivative works, can be bundled, embedded, redistributed and/or sold with any
        software provided that any reserved names are not used by derivative works. The
        fonts and derivatives, however, cannot be released under any other type of
        license. The requirement for fonts to remain under this license does not apply
        to any document created using the fonts or their derivatives.

        DEFINITIONS
        "Font Software" refers to the set of files released by the Copyright Holder(s)
        under this license and clearly marked as such. This may include source files,
        build scripts and documentation.

        "Reserved Font Name" refers to any names specified as such after the copyright
        statement(s).

        "Original Version" refers to the collection of Font Software components as
        distributed by the Copyright Holder(s).

        "Modified Version" refers to any derivative made by adding to, deleting, or
        substituting -- in part or in whole -- any of the components of the Original
        Version, by changing formats or by porting the Font Software to a new environment.

        "Author" refers to any designer, engineer, programmer, technical writer or other
        person who contributed to the Font Software.

        PERMISSION & CONDITIONS
        Permission is hereby granted, free of charge, to any person obtaining a copy
        of the Font Software, to use, study, copy, merge, embed, modify, redistribute,
        and sell modified and unmodified copies of the Font Software, subject to the
        following conditions:

        1) Neither the Font Software nor any of its individual components, in Original
           or Modified Versions, may be sold by itself.

        2) Original or Modified Versions of the Font Software may be bundled,
           redistributed and/or sold with any software, provided that each copy contains
           the above copyright notice and this license. These can be included either as
           stand-alone text files, human-readable headers or in the appropriate
           machine-readable metadata fields within text or binary files as long as those
           fields can be easily viewed by the user.

        3) No Modified Version of the Font Software may use the Reserved Font Name(s)
           unless explicit written permission is granted by the corresponding Copyright
           Holder. This restriction only applies to the primary font name as presented
           to the users.

        4) The name(s) of the Copyright Holder(s) or the Author(s) of the Font Software
           shall not be used to promote, endorse or advertise any Modified Version,
           except to acknowledge the contribution(s) of the Copyright Holder(s) and the
           Author(s) or with their explicit written permission.

        5) The Font Software, modified or unmodified, in part or in whole, must be
           distributed entirely under this license, and must not be distributed under any
           other license. The requirement for fonts to remain under this license does not
           apply to any document created using the Font Software.

        TERMINATION
        This license becomes null and void if any of the above conditions are not met.

        DISCLAIMER
        THE FONT SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
        IMPLIED, INCLUDING BUT NOT LIMITED TO ANY WARRANTIES OF MERCHANTABILITY, FITNESS
        FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT OF COPYRIGHT, PATENT, TRADEMARK, OR
        OTHER RIGHT. IN NO EVENT SHALL THE COPYRIGHT HOLDER BE LIABLE FOR ANY CLAIM,
        DAMAGES OR OTHER LIABILITY, INCLUDING ANY GENERAL, SPECIAL, INDIRECT, INCIDENTAL,
        OR CONSEQUENTIAL DAMAGES, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE,
        ARISING FROM, OUT OF THE USE OR INABILITY TO USE THE FONT SOFTWARE OR FROM OTHER
        DEALINGS IN THE FONT SOFTWARE.
        """
    }

    @ViewBuilder
    private func oflFontLicenseCard() -> some View {
        settingsCard(title: "폰트 라이선스 (OFL)") {
            Text("앱에 포함된 아래 폰트 파일은 SIL Open Font License 1.1 조건으로 배포됩니다.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(oflFontFiles, id: \.self) { fileName in
                    Text(fileName)
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                }
            }

            Link("OFL 공식 전문 열기", destination: oflLicenseURL)
                .font(.system(size: 11))

            DisclosureGroup("라이선스 전문 보기") {
                ScrollView(.vertical, showsIndicators: true) {
                    Text(oflLicenseText)
                        .font(.system(size: 10, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 130, maxHeight: 220)
                .padding(.top, 4)
            }
            .font(.system(size: 11))
        }
    }

    var body: some View {
        TabView(selection: $selectedSettingsTab) {
            threeColumnContent(
                first: {
                    settingsCard(title: "편집기 설정") {
                        Text("메인 모드 행간 (임시): \(String(format: "%.2f", mainCardLineSpacingValue))")
                        Slider(value: $mainCardLineSpacingValue, in: 1.0...8.0, step: 0.05)

                        Text("카드 위아래 간격: \(Int(mainCardVerticalGap.rounded()))")
                        Slider(value: $mainCardVerticalGap, in: 0.0...28.0, step: 1.0)
                        Text("기본값은 0이며, 필요할 때만 행 간격을 넓혀 보이게 합니다.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(2)

                        Text("포커스 모드 행간 (임시): \(String(format: "%.2f", focusModeLineSpacingValue))")
                        Slider(value: $focusModeLineSpacingValue, in: 0.0...6.0, step: 0.05)
                    }

                    settingsCard(title: "포커스 모드 설정") {
                        Text("타이프라이터 토글은 상단 메뉴 > 화면에서 변경합니다.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(2)

                        Picker("타이프라이터 기준선", selection: $focusTypewriterBaseline) {
                            Text("중앙 50%").tag(0.50)
                            Text("기본 60%").tag(0.60)
                            Text("아래 66%").tag(0.66)
                        }
                        .pickerStyle(.segmented)
                        .disabled(!focusTypewriterEnabled)

                        Text(focusTypewriterEnabled ? "현재 타이프라이터 모드가 켜져 있습니다." : "현재 타이프라이터 모드가 꺼져 있습니다.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }

                    settingsCard(title: "데이터 저장소") {
                        Text("현재 저장 경로:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(currentStoragePath)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                            .truncationMode(.middle)

                        Button("기존 작업 파일 열기...") {
                            openWorkspaceFile()
                        }

                        Button("새 작업 파일 만들기...") {
                            createWorkspaceFile()
                        }

                        Button("작업 파일 초기화 (다시 선택)") {
                            storageBookmark = nil
                            forceWorkspaceReset = true
                        }
                    }

                    settingsCard(title: "자동 백업") {
                        Toggle("앱 종료 시 자동 백업", isOn: $autoBackupEnabledOnQuit)

                        Text("백업 폴더")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(currentAutoBackupPath)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                            .truncationMode(.middle)

                        HStack(spacing: 8) {
                            Button("백업 폴더 선택...") {
                                selectAutoBackupDirectory()
                            }
                            Button("기본 위치로") {
                                autoBackupDirectoryPath = WorkspaceAutoBackupService.defaultBackupDirectoryURL().path
                                setAutoBackupStatus("기본 백업 경로를 적용했습니다.", isError: false)
                            }
                        }

                        Text("보관 정책: 최신 10개 + 이후 일 1개(7일) + 주 1개(4주까지) + 이후 월 1개")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineLimit(3)

                        Text("백업 파일명: 작업이름-YYYY-MM-DD-HH-mm-ss.wtf.zip")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                        Text("압축 해제 시 작업이름.wtf 컨테이너로 복원됩니다.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineLimit(2)

                        if let message = autoBackupStatusMessage {
                            Text(message)
                                .font(.system(size: 11))
                                .foregroundColor(autoBackupStatusIsError ? .red : .secondary)
                                .lineLimit(2)
                        }
                    }

                    oflFontLicenseCard()
                },
                second: {
                    settingsCard(title: "출력 설정") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("중앙정렬식 PDF")
                                .font(.subheadline.weight(.semibold))
                            Text("폰트 크기: \(String(format: "%.1f", exportCenteredFontSize))pt")
                            Slider(value: $exportCenteredFontSize, in: 8...20, step: 0.5)
                            Toggle("헤딩 볼드", isOn: $exportCenteredSceneHeadingBold)
                            Toggle("캐릭터 볼드", isOn: $exportCenteredCharacterBold)
                            Toggle("오른쪽 씬 번호 표시", isOn: $exportCenteredShowRightSceneNumber)

                            Divider()

                            Text("한국식 PDF")
                                .font(.subheadline.weight(.semibold))
                            Text("폰트 크기: \(String(format: "%.1f", exportKoreanFontSize))pt")
                            Slider(value: $exportKoreanFontSize, in: 8...20, step: 0.5)
                            Toggle("씬 헤딩 볼드", isOn: $exportKoreanSceneBold)
                            Toggle("캐릭터 볼드", isOn: $exportKoreanCharacterBold)
                            Picker("캐릭터 정렬", selection: $exportKoreanCharacterAlignment) {
                                Text("오른쪽").tag("right")
                                Text("왼쪽").tag("left")
                            }
                            .pickerStyle(.segmented)
                        }
                    }

                    settingsCard(title: "AI 설정") {
                        Text("Gemini 모델")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Picker("모델 선택", selection: $selectedGeminiModelOption) {
                            ForEach(geminiModelOptions) { option in
                                Text(option.title).tag(option.value)
                            }
                            Text("직접 입력").tag(customGeminiModelToken)
                        }
                        .pickerStyle(.menu)
                        .onChange(of: selectedGeminiModelOption) { _, newValue in
                            guard newValue != customGeminiModelToken else { return }
                            geminiModelID = newValue
                        }

                        TextField("예: gemini-3.1-pro-preview", text: $geminiModelID)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: geminiModelID) { _, _ in
                                syncGeminiModelOptionSelection()
                            }

                        Text("Gemini 3.1 Pro의 API 모델 ID는 gemini-3.1-pro-preview 입니다. 404가 뜨면 상단 메뉴에서 다른 모델을 선택하세요.")
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
                                deleteGeminiAPIKey()
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
                },
                third: {
                    settingsCard(title: "색상 테마 프리셋") {
                        Picker("프리셋", selection: $selectedColorThemePresetID) {
                            ForEach(ColorThemePreset.allCases) { preset in
                                Text(preset.title).tag(preset.rawValue)
                            }
                            ForEach(customColorThemePresets) { preset in
                                Text("사용자: \(preset.title)").tag(preset.id)
                            }
                        }
                        .pickerStyle(.menu)

                        Button("선택한 프리셋 적용") {
                            applySelectedColorThemePreset()
                        }

                        Text("라이트/다크 모드는 그대로 유지하며 카드/배경 색 팔레트만 교체합니다.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }

                    settingsCard(title: "색상 설정") {
                        HStack {
                            Text("현재 색상을 이름 있는 프리셋으로 저장할 수 있습니다.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Button("프리셋으로 저장") {
                                newColorPresetName = ""
                                saveColorPresetError = nil
                                showSaveColorPresetSheet = true
                            }
                        }
                        themedColorPickerRow(
                            title: "앱 배경 색",
                            lightHex: $backgroundColorHex,
                            darkHex: $darkBackgroundColorHex,
                            lightFallback: Color(red: 0.96, green: 0.95, blue: 0.93),
                            darkFallback: Color(red: 0.07, green: 0.08, blue: 0.10)
                        )
                        themedColorPickerRow(
                            title: "카드 기본 색",
                            lightHex: $cardBaseColorHex,
                            darkHex: $darkCardBaseColorHex,
                            lightFallback: Color.white,
                            darkFallback: Color(red: 0.10, green: 0.13, blue: 0.16)
                        )
                        themedColorPickerRow(
                            title: "선택 카드 색",
                            lightHex: $cardActiveColorHex,
                            darkHex: $darkCardActiveColorHex,
                            lightFallback: Color(red: 0.75, green: 0.84, blue: 1.0),
                            darkFallback: Color(red: 0.16, green: 0.23, blue: 0.31)
                        )
                        themedColorPickerRow(
                            title: "연결 카드 색",
                            lightHex: $cardRelatedColorHex,
                            darkHex: $darkCardRelatedColorHex,
                            lightFallback: Color(red: 0.87, green: 0.92, blue: 1.0),
                            darkFallback: Color(red: 0.14, green: 0.18, blue: 0.25)
                        )
                    }

                    settingsCard(title: "색상 초기화") {
                        Button("카드/배경 색 기본값으로") { resetColorsToDefaults() }
                    }
                }
            )
            .padding(SettingsLayout.contentPadding)
            .controlSize(.small)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .tabItem { Label("설정", systemImage: "gearshape.2") }
            .tag(SettingsTab.settings)

            twoColumnContent(
                left: {
                    ForEach(shortcutLeftSections) { section in
                        settingsCard(title: section.title) {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(section.items) { item in
                                    shortcutRow(item)
                                }
                            }
                        }
                    }
                },
                right: {
                    ForEach(shortcutRightSections) { section in
                        settingsCard(title: section.title) {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(section.items) { item in
                                    shortcutRow(item)
                                }
                            }
                        }
                    }
                }
            )
            .padding(SettingsLayout.contentPadding)
            .controlSize(.small)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .tabItem { Label("단축키", systemImage: "keyboard") }
            .tag(SettingsTab.shortcuts)
        }
        .frame(width: SettingsLayout.windowWidth, height: SettingsLayout.windowHeight)
        .onAppear {
            refreshGeminiAPIKeyStatus()
            syncGeminiModelOptionSelection()
            loadCustomColorThemePresets()
            initializeAutoBackupSettingsIfNeeded()
        }
        .sheet(isPresented: $showSaveColorPresetSheet) {
            saveColorPresetSheet
        }
    }

    @ViewBuilder
    private func settingsCard<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: SettingsLayout.cardContentSpacing) {
            Text(title)
                .font(.system(size: SettingsLayout.cardTitleFontSize, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: SettingsLayout.titleCornerRadius, style: .continuous)
                        .fill(Color.primary.opacity(0.10))
                )

            VStack(alignment: .leading, spacing: SettingsLayout.cardContentSpacing) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(SettingsLayout.cardPadding)
        .background(
            RoundedRectangle(cornerRadius: SettingsLayout.cardCornerRadius, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: SettingsLayout.cardCornerRadius, style: .continuous)
                .stroke(Color.primary.opacity(0.14), lineWidth: 1)
        )
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func threeColumnContent<First: View, Second: View, Third: View>(
        @ViewBuilder first: () -> First,
        @ViewBuilder second: () -> Second,
        @ViewBuilder third: () -> Third
    ) -> some View {
        HStack(alignment: .top, spacing: SettingsLayout.columnSpacing) {
            VStack(alignment: .leading, spacing: SettingsLayout.cardSpacing) {
                first()
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)

            VStack(alignment: .leading, spacing: SettingsLayout.cardSpacing) {
                second()
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)

            VStack(alignment: .leading, spacing: SettingsLayout.cardSpacing) {
                third()
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    @ViewBuilder
    private func twoColumnContent<Left: View, Right: View>(
        @ViewBuilder left: () -> Left,
        @ViewBuilder right: () -> Right
    ) -> some View {
        HStack(alignment: .top, spacing: SettingsLayout.columnSpacing) {
            VStack(alignment: .leading, spacing: SettingsLayout.cardSpacing) {
                left()
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)

            VStack(alignment: .leading, spacing: SettingsLayout.cardSpacing) {
                right()
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    @ViewBuilder
    private func shortcutRow(_ item: ShortcutItem) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(item.action)
                .font(.system(size: 11))
                .lineLimit(2)
            Spacer(minLength: 8)
            Text(item.keys)
                .font(.system(size: 10, design: .monospaced))
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Color.secondary.opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
    }

    private var saveColorPresetSheet: some View {
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

    private func colorBinding(hex: Binding<String>, fallback: Color) -> Binding<Color> {
        Binding(
            get: { colorFromHex(hex.wrappedValue) ?? fallback },
            set: { newColor in
                hex.wrappedValue = hexFromColor(newColor)
            }
        )
    }

    @ViewBuilder
    private func themedColorPickerRow(
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

    private func colorFromHex(_ hex: String) -> Color? {
        guard let rgb = parseHexRGB(hex) else { return nil }
        return Color(red: rgb.0, green: rgb.1, blue: rgb.2)
    }

    private func hexFromColor(_ color: Color) -> String {
        let ns = NSColor(color)
        let rgb = ns.usingColorSpace(.deviceRGB) ?? ns
        let r = Int(round(rgb.redComponent * 255))
        let g = Int(round(rgb.greenComponent * 255))
        let b = Int(round(rgb.blueComponent * 255))
        return String(format: "%02X%02X%02X", r, g, b)
    }

    private func resetColorsToDefaults() {
        backgroundColorHex = "F4F2EE"
        darkBackgroundColorHex = "111418"
        cardBaseColorHex = "FFFFFF"
        cardActiveColorHex = "BFD7FF"
        cardRelatedColorHex = "DDE9FF"
        darkCardBaseColorHex = "1A2029"
        darkCardActiveColorHex = "2A3A4E"
        darkCardRelatedColorHex = "242F3F"
    }

    private func loadCustomColorThemePresets() {
        guard !customColorThemePresetsJSON.isEmpty else {
            customColorThemePresets = []
            return
        }
        guard let data = customColorThemePresetsJSON.data(using: .utf8) else {
            customColorThemePresets = []
            return
        }
        do {
            customColorThemePresets = try JSONDecoder().decode([SavedColorThemePreset].self, from: data)
        } catch {
            customColorThemePresets = []
        }
    }

    private func persistCustomColorThemePresets() {
        guard let data = try? JSONEncoder().encode(customColorThemePresets),
              let json = String(data: data, encoding: .utf8) else {
            return
        }
        customColorThemePresetsJSON = json
    }

    private func saveCurrentColorsAsPreset() {
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
            lightBackground: backgroundColorHex,
            lightCardBase: cardBaseColorHex,
            lightCardActive: cardActiveColorHex,
            lightCardRelated: cardRelatedColorHex,
            darkBackground: darkBackgroundColorHex,
            darkCardBase: darkCardBaseColorHex,
            darkCardActive: darkCardActiveColorHex,
            darkCardRelated: darkCardRelatedColorHex
        )
        customColorThemePresets.append(preset)
        persistCustomColorThemePresets()
        selectedColorThemePresetID = preset.id
        saveColorPresetError = nil
        showSaveColorPresetSheet = false
    }

    private func applySelectedColorThemePreset() {
        if let preset = ColorThemePreset(rawValue: selectedColorThemePresetID) {
            applyColorThemePreset(preset)
            return
        }
        guard let customPreset = customColorThemePresets.first(where: { $0.id == selectedColorThemePresetID }) else {
            return
        }
        applyColorThemePreset(customPreset)
    }

    private func applyColorThemeValues(
        lightBackground: String,
        lightCardBase: String,
        lightCardActive: String,
        lightCardRelated: String,
        darkBackground: String,
        darkCardBase: String,
        darkCardActive: String,
        darkCardRelated: String
    ) {
        backgroundColorHex = lightBackground
        darkBackgroundColorHex = darkBackground
        cardBaseColorHex = lightCardBase
        cardActiveColorHex = lightCardActive
        cardRelatedColorHex = lightCardRelated
        darkCardBaseColorHex = darkCardBase
        darkCardActiveColorHex = darkCardActive
        darkCardRelatedColorHex = darkCardRelated
    }

    private func applyColorThemePreset(_ preset: ColorThemePreset) {
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

    private func applyColorThemePreset(_ preset: SavedColorThemePreset) {
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

    private func syncGeminiModelOptionSelection() {
        let normalized = normalizeGeminiModelID(geminiModelID)
        if normalized != geminiModelID {
            geminiModelID = normalized
        }
        let trimmedModel = normalized.trimmingCharacters(in: .whitespacesAndNewlines)
        if geminiModelOptions.contains(where: { $0.value == trimmedModel }) {
            selectedGeminiModelOption = trimmedModel
        } else {
            selectedGeminiModelOption = customGeminiModelToken
        }
    }

    private func normalizeGeminiModelID(_ raw: String) -> String {
        normalizeGeminiModelIDValue(raw)
    }

    private func refreshGeminiAPIKeyStatus() {
        do {
            hasGeminiAPIKey = try KeychainStore.loadGeminiAPIKey() != nil
        } catch {
            hasGeminiAPIKey = false
            setAISettingsStatus(error.localizedDescription, isError: true)
        }
    }

    private func saveGeminiAPIKey() {
        let trimmed = geminiAPIKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            setAISettingsStatus("저장할 API 키를 입력해 주세요.", isError: true)
            return
        }
        do {
            try KeychainStore.saveGeminiAPIKey(trimmed)
            geminiAPIKeyInput = ""
            refreshGeminiAPIKeyStatus()
            setAISettingsStatus("Gemini API 키를 저장했습니다.", isError: false)
        } catch {
            setAISettingsStatus(error.localizedDescription, isError: true)
        }
    }

    private func deleteGeminiAPIKey() {
        do {
            try KeychainStore.deleteGeminiAPIKey()
            geminiAPIKeyInput = ""
            refreshGeminiAPIKeyStatus()
            setAISettingsStatus("저장된 Gemini API 키를 삭제했습니다.", isError: false)
        } catch {
            setAISettingsStatus(error.localizedDescription, isError: true)
        }
    }

    private func setAISettingsStatus(_ message: String, isError: Bool) {
        aiSettingsStatusMessage = message
        aiSettingsStatusIsError = isError
    }

    private func initializeAutoBackupSettingsIfNeeded() {
        autoBackupDirectoryPath = resolvedInitialAutoBackupDirectoryPath(
            currentPath: autoBackupDirectoryPath,
            expandTilde: true
        )
    }

    private func selectAutoBackupDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "선택"
        panel.message = "자동 백업 파일을 저장할 폴더를 선택하세요."
        let current = URL(fileURLWithPath: currentAutoBackupPath, isDirectory: true)
        if FileManager.default.fileExists(atPath: current.path) {
            panel.directoryURL = current
        }

        guard panel.runModal() == .OK, let selected = panel.url else { return }
        autoBackupDirectoryPath = selected.path
        setAutoBackupStatus("자동 백업 폴더를 변경했습니다.", isError: false)
    }

    private func setAutoBackupStatus(_ message: String, isError: Bool) {
        autoBackupStatusMessage = message
        autoBackupStatusIsError = isError
    }

    private func openWorkspaceFile() {
        if let bookmark = selectWorkspaceBookmark(
            mode: .open,
            message: "기존 작업 파일(.wtf)을 선택하세요."
        ) {
            storageBookmark = bookmark
            onUpdateStore()
        }
    }

    private func createWorkspaceFile() {
        if let bookmark = selectWorkspaceBookmark(mode: .create, message: nil) {
            storageBookmark = bookmark
            onUpdateStore()
        }
    }
}
