import SwiftUI

struct SettingsView: View {
    struct ShortcutItem: Identifiable {
        let keys: String
        let action: String
        var id: String { "\(keys)|\(action)" }
    }

    struct ShortcutSection: Identifiable {
        let title: String
        let items: [ShortcutItem]
        var id: String { title }
    }

    struct GeminiModelOption: Identifiable {
        let value: String
        let title: String
        var id: String { value }
    }

    enum SettingsCategory: String, CaseIterable, Identifiable {
        case workEnvironment
        case appearance
        case ai
        case export
        case dataBackup
        case aboutLegal

        var id: String { rawValue }

        var title: String {
            switch self {
            case .workEnvironment: return "작업 환경"
            case .appearance: return "외관"
            case .ai: return "AI"
            case .export: return "출력"
            case .dataBackup: return "데이터 및 백업"
            case .aboutLegal: return "정보 및 법적"
            }
        }

        var systemImage: String {
            switch self {
            case .workEnvironment: return "slider.horizontal.3"
            case .appearance: return "paintpalette"
            case .ai: return "brain"
            case .export: return "doc.richtext"
            case .dataBackup: return "externaldrive.badge.timemachine"
            case .aboutLegal: return "info.circle"
            }
        }

        var descriptionText: String {
            switch self {
            case .workEnvironment:
                return "편집/포커스/단축키처럼 자주 바꾸는 작업 관련 설정입니다."
            case .appearance:
                return "색상 테마와 카드/배경 팔레트를 관리합니다."
            case .ai:
                return "Gemini 모델과 API 키를 설정합니다."
            case .export:
                return "PDF 출력 포맷별 옵션을 조정합니다."
            case .dataBackup:
                return "작업 파일 경로와 자동 백업 정책을 관리합니다."
            case .aboutLegal:
                return "앱 정보와 폰트 라이선스를 확인합니다."
            }
        }

        static let primary: [SettingsCategory] = [.workEnvironment, .appearance, .ai, .export, .dataBackup]
        static let secondary: [SettingsCategory] = [.aboutLegal]
        static let searchOrder: [SettingsCategory] = primary + secondary
    }

    enum ColorThemePreset: String, CaseIterable, Identifiable {
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

    struct SavedColorThemePreset: Identifiable, Codable {
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

    enum PendingConfirmation: String, Identifiable {
        case resetWorkspace
        case deleteAPIKey
        case resetColors

        var id: String { rawValue }
    }

    var storage = SettingsViewStorage()

    @State var geminiAPIKeyInput: String = ""
    @State var hasGeminiAPIKey: Bool = false
    @State var aiSettingsStatusMessage: String? = nil
    @State var aiSettingsStatusIsError: Bool = false
    @State var selectedColorThemePresetID: String = ColorThemePreset.warmPaper.rawValue
    @State var customColorThemePresets: [SavedColorThemePreset] = []
    @State var showSaveColorPresetSheet: Bool = false
    @State var newColorPresetName: String = ""
    @State var saveColorPresetError: String? = nil
    @State var selectedGeminiModelOption: String = "gemini-3.1-pro-preview"
    @State var autoBackupStatusMessage: String? = nil
    @State var autoBackupStatusIsError: Bool = false
    @State var selectedCategory: SettingsCategory? = .workEnvironment
    @State var settingsSearchQuery: String = ""
    @State var pendingConfirmation: PendingConfirmation?

    let customGeminiModelToken = "__custom__"
    let geminiModelOptions: [GeminiModelOption] = [
        GeminiModelOption(value: "gemini-3.1-pro-preview", title: "Gemini 3.1 Pro (Preview)"),
        GeminiModelOption(value: "gemini-3-pro-preview", title: "Gemini 3 Pro (Preview)"),
        GeminiModelOption(value: "gemini-3-flash", title: "Gemini 3 Flash"),
        GeminiModelOption(value: "gemini-2.5-pro", title: "Gemini 2.5 Pro"),
        GeminiModelOption(value: "gemini-2.5-flash", title: "Gemini 2.5 Flash"),
        GeminiModelOption(value: "gemini-2.0-flash", title: "Gemini 2.0 Flash")
    ]
    let oflFontFiles: [String] = [
        "Sans Mono CJK Final Draft.otf",
        "Sans Mono CJK Final Draft Bold.otf"
    ]
    var oflLicenseURL: URL {
        URL(string: "https://openfontlicense.org/open-font-license-official-text/")
            ?? URL(fileURLWithPath: "/")
    }

    var onUpdateStore: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            detailContent
                .searchable(text: $settingsSearchQuery, placement: .toolbar, prompt: "설정 검색")
        }
        .frame(width: SettingsLayout.windowWidth, height: SettingsLayout.windowHeight)
        .onAppear {
            if selectedCategory == nil {
                selectedCategory = .workEnvironment
            }
            refreshGeminiAPIKeyStatus()
            syncGeminiModelOptionSelection()
            loadCustomColorThemePresets()
            initializeAutoBackupSettingsIfNeeded()
        }
        .sheet(isPresented: $showSaveColorPresetSheet) {
            saveColorPresetSheet
        }
        .alert(item: $pendingConfirmation) { confirmation in
            switch confirmation {
            case .resetWorkspace:
                return Alert(
                    title: Text("작업 파일 초기화"),
                    message: Text("현재 작업 파일 연결을 해제하고 다시 선택하도록 초기화합니다."),
                    primaryButton: .destructive(Text("초기화")) {
                        storage.storageBookmark = nil
                        storage.forceWorkspaceReset = true
                    },
                    secondaryButton: .cancel(Text("취소"))
                )
            case .deleteAPIKey:
                return Alert(
                    title: Text("Gemini API 키 삭제"),
                    message: Text("저장된 키를 삭제하면 AI 기능을 다시 사용하려면 키를 재입력해야 합니다."),
                    primaryButton: .destructive(Text("삭제")) {
                        deleteGeminiAPIKey()
                    },
                    secondaryButton: .cancel(Text("취소"))
                )
            case .resetColors:
                return Alert(
                    title: Text("색상 초기화"),
                    message: Text("현재 카드/배경 색상 값을 기본값으로 되돌립니다."),
                    primaryButton: .destructive(Text("초기화")) {
                        resetColorsToDefaults()
                    },
                    secondaryButton: .cancel(Text("취소"))
                )
            }
        }
    }
}
