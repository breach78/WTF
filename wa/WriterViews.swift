import SwiftUI
import AppKit

struct MainEditorSessionState: Equatable {
    var requestedCardID: UUID? = nil
    var mountedCardID: UUID? = nil
    var textViewIdentity: Int? = nil
    var caretSeedLocation: Int? = nil
    var isFirstResponderReady: Bool = false
    var liveBodyHeight: CGFloat? = nil
}

enum FinishEditingReason: String {
    case generic
    case explicitExit
    case transition
}

struct ScenarioWriterView: View {
    @Environment(\.openWindow) var openWindow

    @EnvironmentObject var store: FileStore
    @EnvironmentObject var referenceCardStore: ReferenceCardStore
    @EnvironmentObject var appWindowState: AppWindowState

    let scenario: Scenario
    let showWorkspaceTopToolbar: Bool
    let splitModeEnabled: Bool
    let splitPaneID: Int

    @State var workspaceSession: WriterWorkspaceSessionState
    @State var focusSession = WriterFocusSessionState()
    @State var historySession = WriterHistorySessionState()
    @State var boardSession = WriterBoardSessionState()

    @StateObject var mainCanvasViewState = MainCanvasViewState()
    @StateObject var mainCanvasScrollCoordinator = MainCanvasScrollCoordinator()
    @StateObject var focusModeLayoutCoordinator = FocusModeLayoutCoordinator()
    @StateObject var aiFeatureState = WriterAIFeatureState()
    @StateObject var editEndAutoBackupState = WriterEditEndAutoBackupState()
    @StateObject var scenarioObservedState: ScenarioWriterObservedState
    @StateObject var indexBoardCanvasDerivedCache = IndexBoardCanvasDerivedCache()
    @ObservedObject var indexBoardRuntime = IndexBoardRuntime.shared

    init(
        scenario: Scenario,
        showWorkspaceTopToolbar: Bool = true,
        splitModeEnabled: Bool = false,
        splitPaneID: Int = 2
    ) {
        self.scenario = scenario
        self.showWorkspaceTopToolbar = showWorkspaceTopToolbar
        self.splitModeEnabled = splitModeEnabled
        self.splitPaneID = splitPaneID
        self._workspaceSession = State(
            initialValue: WriterWorkspaceSessionState(
                isSplitPaneActive: !splitModeEnabled || splitPaneID == 2
            )
        )
        self._scenarioObservedState = StateObject(
            wrappedValue: ScenarioWriterObservedState(scenario: scenario)
        )
    }

    @AppStorage("fontSize") var fontSize: Double = 14.0
    @AppStorage("appearance") var appearance: String = "dark"
    @AppStorage("backgroundColorHex") var backgroundColorHex: String = "F4F2EE"
    @AppStorage("darkBackgroundColorHex") var darkBackgroundColorHex: String = "111418"
    @AppStorage("cardBaseColorHex") var cardBaseColorHex: String = "FFFFFF"
    @AppStorage("cardActiveColorHex") var cardActiveColorHex: String = "BFD7FF"
    @AppStorage("cardRelatedColorHex") var cardRelatedColorHex: String = "DDE9FF"
    @AppStorage("darkCardBaseColorHex") var darkCardBaseColorHex: String = "1A2029"
    @AppStorage("darkCardActiveColorHex") var darkCardActiveColorHex: String = "2A3A4E"
    @AppStorage("darkCardRelatedColorHex") var darkCardRelatedColorHex: String = "242F3F"
    @AppStorage("indexBoardThemePresetID") var indexBoardThemePresetID: String = IndexBoardThemePreset.currentDefault.rawValue
    @AppStorage("exportCenteredFontSize") var exportCenteredFontSize: Double = 12.0
    @AppStorage("exportCenteredCharacterBold") var exportCenteredCharacterBold: Bool = true
    @AppStorage("exportCenteredSceneHeadingBold") var exportCenteredSceneHeadingBold: Bool = true
    @AppStorage("exportCenteredShowRightSceneNumber") var exportCenteredShowRightSceneNumber: Bool = false
    @AppStorage("exportKoreanFontSize") var exportKoreanFontSize: Double = 11.0
    @AppStorage("exportKoreanSceneBold") var exportKoreanSceneBold: Bool = true
    @AppStorage("exportKoreanCharacterBold") var exportKoreanCharacterBold: Bool = true
    @AppStorage("exportKoreanCharacterAlignment") var exportKoreanCharacterAlignment: String = "right"
    @AppStorage("focusTypewriterEnabled") var focusTypewriterEnabled: Bool = false
    @AppStorage("focusNavigationAnimationEnabled") var focusNavigationAnimationEnabled: Bool = false
    @AppStorage("focusTypewriterBaseline") var focusTypewriterBaseline: Double = 0.60
    @AppStorage("focusModeLineSpacingValueTemp") var focusModeLineSpacingValue: Double = 4.5
    @AppStorage("mainCardLineSpacingValueV2") var mainCardLineSpacingValue: Double = 5.0
    @AppStorage("mainCardVerticalGap") var mainCardVerticalGap: Double = 0.0
    @AppStorage("mainCanvasHorizontalScrollMode") var mainCanvasHorizontalScrollModeRawValue: Int = MainCanvasHorizontalScrollMode.defaultPolicy.rawValue
    @AppStorage("mainWorkspaceZoomScale") var mainWorkspaceZoomScale: Double = 1.0
    @AppStorage("geminiModelID") var geminiModelID: String = "gemini-3.1-pro-preview"
    @AppStorage("autoBackupEnabledOnQuit") var autoBackupEnabledOnQuit: Bool = true
    @AppStorage("autoBackupDirectoryPath") var autoBackupDirectoryPath: String = ""
    @AppStorage("lastEditedScenarioID") var lastEditedScenarioID: String = ""
    @AppStorage("lastEditedCardID") var lastEditedCardID: String = ""
    @AppStorage("lastFocusedScenarioID") var lastFocusedScenarioID: String = ""
    @AppStorage("lastFocusedCardID") var lastFocusedCardID: String = ""
    @AppStorage("lastFocusedCaretLocation") var lastFocusedCaretLocation: Int = -1
    @AppStorage("lastFocusedWasEditing") var lastFocusedWasEditing: Bool = false
    @AppStorage("lastFocusedWasFocusMode") var lastFocusedWasFocusMode: Bool = false
    @AppStorage("lastFocusedViewportScenarioID") var lastFocusedViewportScenarioID: String = ""
    @AppStorage("lastFocusedViewportOffsetsJSON") var lastFocusedViewportOffsetsJSON: String = ""
    @AppStorage("lastFocusedMainCanvasHorizontalOffsetsJSON") var lastFocusedMainCanvasHorizontalOffsetsJSON: String = ""

    @FocusState var isAIChatInputFocused: Bool
    @FocusState var isSearchFocused: Bool
    @FocusState var isNamedSnapshotSearchFocused: Bool
    @FocusState var focusModeEditorCardID: UUID?
    @FocusState var isFocusModeSearchFieldFocused: Bool
    @FocusState var isNamedSnapshotNoteEditorFocused: Bool
    @FocusState var isMainViewFocused: Bool

    var body: some View {
        GeometryReader { geometry in
            configuredWorkspaceRoot(for: geometry)
                .overlay {
                    if splitModeEnabled && !isSplitPaneActive {
                        Color.black
                            .opacity(0.15)
                            .allowsHitTesting(false)
                    }
                }
        }
    }

    func configuredWorkspaceRoot(for geometry: GeometryProxy) -> some View {
        workspaceCommandBoundRoot(
            workspaceLifecycleBoundRoot(
                workspaceFocusedRoot(for: geometry)
            )
        )
    }

    func workspaceFocusedRoot(for geometry: GeometryProxy) -> some View {
        workspaceLayout(for: geometry)
            .focusable()
            .focused($isMainViewFocused)
            .focusEffectDisabled()
    }
}
