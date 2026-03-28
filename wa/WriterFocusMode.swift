import SwiftUI
import AppKit

extension ScenarioWriterView {

    var isFocusModeExitTeardownActive: Bool {
        Date() < focusModeExitTeardownUntil
    }

    func beginFocusModeExitTeardownWindow() {
        focusModeExitTeardownUntil = Date().addingTimeInterval(0.35)
        focusCaretEnsureWorkItem?.cancel()
        focusCaretEnsureWorkItem = nil
        focusModeCaretRequestID += 1
        focusModeBoundaryTransitionPendingReveal = false
        focusModePendingFallbackRevealCardID = nil
        focusModeFallbackRevealIssuedCardID = nil
        clearFocusModeExcludedResponder()
    }

    var focusTypewriterEnabledLive: Bool {
        if let stored = UserDefaults.standard.object(forKey: "focusTypewriterEnabled") as? Bool {
            return stored
        }
        return focusTypewriterEnabled
    }

    var isReferenceWindowFocused: Bool {
        NSApp.keyWindow?.identifier?.rawValue == ReferenceWindowConstants.windowID
    }

    func isReferenceTextView(_ textView: NSTextView) -> Bool {
        textView.window?.identifier?.rawValue == ReferenceWindowConstants.windowID
    }

    @ViewBuilder
    func focusModeCanvas(size: CGSize) -> some View {
        let cards = focusedColumnCards()
        ZStack {
            focusModeCanvasBackdrop()
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: true) {
                    focusModeCanvasScrollContent(size: size, cards: cards)
                }
                .onChange(of: activeCardID) { _, newID in
                    handleFocusModeCanvasActiveCardChange(newID, proxy: proxy)
                }
                .onAppear {
                    handleFocusModeCanvasAppear(proxy: proxy)
                }
                .onChange(of: focusModeFallbackRevealTick) { _, _ in
                    handleFocusModeFallbackRevealTickChange(proxy: proxy)
                }
                .onChange(of: scenarioCardsVersion) { _, _ in
                    refreshFocusModeSearchResultsIfNeeded()
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            if showFocusModeSearchPopup {
                focusModeSearchPopup
                    .padding(.top, 18)
                    .padding(.trailing, 22)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(20)
            }
        }
        .coordinateSpace(name: "focus-mode-canvas")
        .ignoresSafeArea(.container, edges: .top)
        .onChange(of: size.width) { oldWidth, newWidth in
            handleFocusModeCanvasWidthChange(oldWidth: oldWidth, newWidth: newWidth)
        }
    }
}
