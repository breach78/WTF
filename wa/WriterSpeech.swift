import SwiftUI
import AVFoundation
import Speech
import FoundationModels

enum SpeechDictationError: LocalizedError {
    case noActiveCard
    case microphonePermissionDenied
    case speechRecognitionPermissionDenied
    case speechRecognizerUnavailable
    case recorderUnavailable
    case transcriptionFailed(String)
    case emptyTranscript
    case summaryFailed
    case parentCardMissing
    case appleIntelligenceUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .noActiveCard:
            return "받아쓰기를 시작하려면 먼저 카드 하나를 선택해 주세요."
        case .microphonePermissionDenied:
            return "마이크 권한이 없어 받아쓰기를 시작할 수 없습니다."
        case .speechRecognitionPermissionDenied:
            return "음성 인식 권한이 없어 받아쓰기를 시작할 수 없습니다."
        case .speechRecognizerUnavailable:
            return "이 Mac에서 음성 인식을 시작할 수 없습니다."
        case .recorderUnavailable:
            return "받아쓰기 녹음기를 준비하지 못했습니다."
        case .transcriptionFailed(let message):
            return "받아쓰기 전사 처리에 실패했습니다. \(message)"
        case .emptyTranscript:
            return "받아쓰기 결과가 비어 있습니다. 조금 더 길게 말해 주세요."
        case .summaryFailed:
            return "Apple Intelligence 요약을 만들지 못했습니다."
        case .parentCardMissing:
            return "적용 대상 카드가 없어 받아쓰기 결과를 반영하지 못했습니다."
        case .appleIntelligenceUnavailable(let reason):
            return "Apple Intelligence 요약을 사용할 수 없습니다. \(reason)"
        }
    }
}

enum SpeechDictationService {
    static func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    static func requestSpeechRecognitionPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }
}

final class LiveSpeechDictationRecorder {
    private let audioEngine = AVAudioEngine()
    private let lock = NSLock()

    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    private var committedText: String = ""
    private var draftText: String = ""
    private var lastPartialText: String = ""
    private var isStoppingInternal: Bool = false

    var onCommittedText: ((String) -> Void)?
    var onDraftText: ((String) -> Void)?
    var onError: ((Error) -> Void)?

    func start(locale: Locale) async throws {
        let selectedLocale = resolvedLocale(preferred: locale)
        guard let recognizer = SFSpeechRecognizer(locale: selectedLocale), recognizer.isAvailable else {
            throw SpeechDictationError.speechRecognizerUnavailable
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }

        speechRecognizer = recognizer
        recognitionRequest = request

        withLockedState {
            committedText = ""
            draftText = ""
            lastPartialText = ""
            isStoppingInternal = false
        }

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }

            if let result {
                let text = normalizeText(result.bestTranscription.formattedString)
                if result.isFinal {
                    let committed: String = self.withLockedState {
                        let finalized = text.isEmpty ? self.lastPartialText : text
                        self.committedText = self.mergeTranscript(current: self.committedText, incoming: finalized)
                        self.draftText = ""
                        self.lastPartialText = ""
                        return self.committedText
                    }
                    DispatchQueue.main.async { [weak self] in
                        self?.onCommittedText?(committed)
                    }
                } else {
                    let liveDraft: String = self.withLockedState {
                        if self.isLikelyRecognitionReset(previous: self.lastPartialText, current: text) {
                            self.committedText = self.mergeTranscript(
                                current: self.committedText,
                                incoming: self.lastPartialText
                            )
                        }
                        self.lastPartialText = text
                        let merged = self.mergeTranscript(current: self.committedText, incoming: text)
                        self.draftText = merged
                        return merged
                    }
                    DispatchQueue.main.async { [weak self] in
                        self?.onDraftText?(liveDraft)
                    }
                }
            }

            if let error {
                let shouldIgnore = self.withLockedState { self.isStoppingInternal }
                if !shouldIgnore {
                    DispatchQueue.main.async { [weak self] in
                        self?.onError?(SpeechDictationError.transcriptionFailed(error.localizedDescription))
                    }
                }
            }
        }

        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()
    }

    func stop() async {
        withLockedState {
            isStoppingInternal = true
        }

        audioEngine.inputNode.removeTap(onBus: 0)
        if audioEngine.isRunning {
            audioEngine.stop()
        }

        recognitionRequest?.endAudio()
        try? await Task.sleep(nanoseconds: 200_000_000)

        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        speechRecognizer = nil
    }

    func transcriptSnapshot() -> String {
        let snapshot = withLockedState { (committedText, draftText) }
        return resolvedTranscript(committed: snapshot.0, draft: snapshot.1)
    }

    private func resolvedLocale(preferred: Locale) -> Locale {
        let supported = SFSpeechRecognizer.supportedLocales()
        guard !supported.isEmpty else { return preferred }

        if supported.contains(where: { sameLocale($0, preferred) }) {
            return preferred
        }
        if let current = supported.first(where: { sameLocale($0, Locale.current) }) {
            return current
        }
        if let korean = supported.first(where: { $0.identifier.lowercased().hasPrefix("ko") }) {
            return korean
        }
        return supported.first ?? preferred
    }

    private func sameLocale(_ lhs: Locale, _ rhs: Locale) -> Bool {
        lhs.identifier.replacingOccurrences(of: "_", with: "-").lowercased()
            == rhs.identifier.replacingOccurrences(of: "_", with: "-").lowercased()
    }

    private func normalizeText(_ text: String) -> String {
        text
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func resolvedTranscript(committed: String, draft: String) -> String {
        let left = committed.trimmingCharacters(in: .whitespacesAndNewlines)
        let right = draft.trimmingCharacters(in: .whitespacesAndNewlines)

        if left.isEmpty { return right }
        if right.isEmpty { return left }
        if right.hasPrefix(left) { return right }
        if left.hasPrefix(right) { return left }
        return right.count >= left.count ? right : left
    }

    private func mergeTranscript(current: String, incoming: String) -> String {
        let left = current.trimmingCharacters(in: .whitespacesAndNewlines)
        let right = incoming.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !right.isEmpty else { return left }
        guard !left.isEmpty else { return right }
        if left == right { return left }
        if right.hasPrefix(left) { return right }
        if left.hasSuffix(right) { return left }

        let maxOverlap = min(160, left.count, right.count)
        if maxOverlap > 0 {
            for size in stride(from: maxOverlap, through: 1, by: -1) {
                let leftStart = left.index(left.endIndex, offsetBy: -size)
                let leftSlice = left[leftStart...]
                let rightEnd = right.index(right.startIndex, offsetBy: size)
                let rightSlice = right[..<rightEnd]
                if leftSlice == rightSlice {
                    let suffixStart = right.index(right.startIndex, offsetBy: size)
                    return left + right[suffixStart...]
                }
            }
        }

        return left + " " + right
    }

    private func isLikelyRecognitionReset(previous: String, current: String) -> Bool {
        let prev = previous.trimmingCharacters(in: .whitespacesAndNewlines)
        let curr = current.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prev.isEmpty, !curr.isEmpty else { return false }
        if curr.hasPrefix(prev) || prev.hasPrefix(curr) { return false }

        let sharedPrefixCount = zip(prev, curr).prefix { $0 == $1 }.count
        return sharedPrefixCount < 3
    }

    private func withLockedState<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}

extension ScenarioWriterView {
    @MainActor
    func startDictationMode(from card: SceneCard) {
        guard !dictationIsRecording, !dictationIsProcessing else { return }
        guard !aiIsGenerating else {
            setAIStatusError("AI 생성 중에는 전사 모드를 시작할 수 없습니다.")
            return
        }

        if editingCardID == card.id, let textView = NSApp.keyWindow?.firstResponder as? NSTextView {
            dictationSourceTextViewBox.textView = textView
        } else if focusModeEditorCardID == card.id, let textView = NSApp.keyWindow?.firstResponder as? NSTextView {
            dictationSourceTextViewBox.textView = textView
        } else {
            dictationSourceTextViewBox.textView = nil
        }

        selectedCardIDs = [card.id]
        changeActiveCard(to: card)
        dictationPopupLiveText = ""
        dictationPopupStatusText = "전사 준비 중입니다..."
        dictationPopupPresented = true
        startDictationRecording(targetCardID: card.id)
    }

    @MainActor
    func cancelDictationMode() {
        stopDictationRecording(discardAudio: true)
        dictationPopupPresented = false
        dictationPopupLiveText = ""
        dictationPopupStatusText = ""
        dictationSourceTextViewBox.textView = nil
    }

    @MainActor
    func finishDictationMode() {
        guard let recorder = dictationRecorder else { return }
        guard dictationIsRecording else { return }

        let targetCardID = dictationTargetParentID
        dictationRecorder = nil
        dictationIsRecording = false
        dictationIsProcessing = true
        dictationTargetParentID = nil
        dictationPopupStatusText = "전사를 마무리하는 중입니다..."

        Task { @MainActor in
            await recorder.stop()

            let transcript = recorder.transcriptSnapshot().trimmingCharacters(in: .whitespacesAndNewlines)
            dictationPopupLiveText = transcript
            guard !transcript.isEmpty else {
                dictationIsProcessing = false
                dictationPopupStatusText = SpeechDictationError.emptyTranscript.localizedDescription
                setAIStatusError(SpeechDictationError.emptyTranscript.localizedDescription)
                return
            }
            guard let targetCardID else {
                dictationIsProcessing = false
                dictationPopupStatusText = SpeechDictationError.parentCardMissing.localizedDescription
                setAIStatusError(SpeechDictationError.parentCardMissing.localizedDescription)
                return
            }

            do {
                var summaryText: String?
                var summaryError: Error?
                do {
                    dictationPopupStatusText = "요약 생성 중입니다..."
                    summaryText = try await summarizeDictationTranscript(transcript)
                } catch {
                    summaryError = error
                }

                dictationPopupStatusText = "카드에 반영하는 중입니다..."
                try applyDictationTranscriptToCard(
                    cardID: targetCardID,
                    transcript: transcript,
                    summary: summaryText
                )

                dictationIsProcessing = false
                dictationPopupPresented = false
                dictationPopupLiveText = ""
                dictationPopupStatusText = ""
                scheduleDictationEditorSyncIfNeeded(cardID: targetCardID)
                if let summaryError {
                    setAIStatusError("전사는 반영했지만 요약은 실패했습니다. \(summaryError.localizedDescription)")
                } else {
                    setAIStatus("전사와 요약을 카드에 반영했습니다.")
                }
            } catch {
                dictationIsProcessing = false
                dictationPopupStatusText = error.localizedDescription
                setAIStatusError(error.localizedDescription)
            }
        }
    }

    @MainActor
    private func startDictationRecording(targetCardID: UUID) {
        guard !dictationIsRecording else { return }
        guard !dictationIsProcessing else { return }
        guard !aiIsGenerating else {
            setAIStatusError("AI 생성 중에는 전사 모드를 시작할 수 없습니다.")
            return
        }

        dictationIsRecording = true
        dictationIsProcessing = true
        dictationTargetParentID = targetCardID
        dictationPopupStatusText = "전사 시작 중..."
        setAIStatus("전사 모드를 시작하는 중입니다...")

        Task { @MainActor in
            do {
                let micGranted = await SpeechDictationService.requestMicrophonePermission()
                guard micGranted else {
                    throw SpeechDictationError.microphonePermissionDenied
                }

                let speechGranted = await SpeechDictationService.requestSpeechRecognitionPermission()
                guard speechGranted else {
                    throw SpeechDictationError.speechRecognitionPermissionDenied
                }

                let recorder = LiveSpeechDictationRecorder()
                recorder.onCommittedText = { text in
                    Task { @MainActor in
                        dictationPopupLiveText = text
                    }
                }
                recorder.onDraftText = { text in
                    Task { @MainActor in
                        dictationPopupLiveText = text
                    }
                }
                recorder.onError = { error in
                    Task { @MainActor in
                        dictationPopupStatusText = error.localizedDescription
                        setAIStatusError(error.localizedDescription)
                    }
                }

                try await recorder.start(locale: Locale(identifier: "ko-KR"))

                dictationRecorder = recorder
                dictationIsProcessing = false
                dictationPopupStatusText = "전사 중..."
                setAIStatus("전사 모드가 시작되었습니다.")
            } catch {
                dictationRecorder = nil
                dictationIsRecording = false
                dictationIsProcessing = false
                dictationTargetParentID = nil
                dictationPopupStatusText = error.localizedDescription
                setAIStatusError(error.localizedDescription)
            }
        }
    }

    @MainActor
    func stopDictationRecording(discardAudio: Bool) {
        guard let recorder = dictationRecorder else {
            resetDictationSessionState()
            return
        }

        dictationRecorder = nil
        dictationIsRecording = false
        dictationIsProcessing = true

        let parentID = dictationTargetParentID ?? activeCardID
        dictationTargetParentID = nil

        Task { @MainActor in
            await recorder.stop()

            if discardAudio {
                dictationIsProcessing = false
                resetDictationSessionState()
                setAIStatus("전사 모드를 취소했습니다.")
                return
            }

            guard let parentID else {
                dictationIsProcessing = false
                setAIStatusError(SpeechDictationError.noActiveCard.localizedDescription)
                return
            }

            let transcript = recorder.transcriptSnapshot().trimmingCharacters(in: .whitespacesAndNewlines)
            guard !transcript.isEmpty else {
                dictationIsProcessing = false
                setAIStatusError(SpeechDictationError.emptyTranscript.localizedDescription)
                return
            }

            dictationPopupLiveText = transcript
            dictationTargetParentID = parentID
            dictationIsProcessing = false
            dictationPopupStatusText = "완료를 눌러 반영하세요."
            setAIStatus("전사가 종료되었습니다.")
        }
    }

    @MainActor
    private func resetDictationSessionState() {
        dictationRecorder = nil
        dictationIsRecording = false
        dictationIsProcessing = false
        dictationTargetParentID = nil
        dictationSourceTextViewBox.textView = nil
    }

    func summarizeDictationTranscript(_ transcript: String) async throws -> String {
        let model = SystemLanguageModel.default
        guard model.isAvailable else {
            throw SpeechDictationError.appleIntelligenceUnavailable(appleModelAvailabilityReason(model.availability))
        }

        let session = LanguageModelSession(
            model: model,
            instructions: """
            당신은 회의/구술 원문 요약 보조자다.
            원문의 의미를 유지하면서 핵심만 짧고 명확한 한국어 문단으로 요약한다.
            제목, 번호, 불릿, 마크다운 없이 일반 텍스트만 출력한다.
            """
        )

        let clamped = clampedDictationText(transcript, maxLength: 9000)
        let response: LanguageModelSession.Response<String>
        do {
            response = try await session.respond(
                to: """
                아래 원문을 2~4문장으로 요약해라.
                - 핵심 사실만 남긴다.
                - 원문에 없는 정보는 추가하지 않는다.

                원문:
                \(clamped)
                """,
                options: GenerationOptions(temperature: 0.2, maximumResponseTokens: 220)
            )
        } catch {
            throw SpeechDictationError.summaryFailed
        }

        let trimmed = response.content
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)

        guard !trimmed.isEmpty else {
            throw SpeechDictationError.summaryFailed
        }
        return trimmed
    }

    func appleModelAvailabilityReason(_ availability: SystemLanguageModel.Availability) -> String {
        switch availability {
        case .available:
            return ""
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible:
                return "이 기기는 Apple Intelligence를 지원하지 않습니다."
            case .appleIntelligenceNotEnabled:
                return "시스템 설정에서 Apple Intelligence가 비활성화되어 있습니다."
            case .modelNotReady:
                return "Apple Intelligence 모델 준비가 아직 완료되지 않았습니다."
            @unknown default:
                return "Apple Intelligence 상태를 확인할 수 없습니다."
            }
        }
    }

    func clampedDictationText(_ text: String, maxLength: Int) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > maxLength else { return trimmed }
        let headCount = max(1, Int(Double(maxLength) * 0.65))
        let tailCount = max(1, maxLength - headCount)
        let head = trimmed.prefix(headCount)
        let tail = trimmed.suffix(tailCount)
        return "\(head)\n...\n\(tail)"
    }

    func applyDictationTranscriptToCard(cardID: UUID, transcript: String, summary: String?) throws {
        guard let parent = findCard(by: cardID) else {
            throw SpeechDictationError.parentCardMissing
        }

        let prevState = captureScenarioState()
        let trimmedTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTranscript.isEmpty else {
            throw SpeechDictationError.emptyTranscript
        }

        let currentRaw = parent.content
        if currentRaw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parent.content = trimmedTranscript
        } else {
            parent.content = currentRaw + "\n\n---\n" + trimmedTranscript
        }

        if let summary,
           !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parent.content += "\n\n---\n" + summary.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        scenario.bumpCardsVersion()
        commitCardMutation(
            previousState: prevState,
            actionName: "전사 반영",
            forceSnapshot: true
        )

        selectedCardIDs = [parent.id]
        changeActiveCard(to: parent)
    }

    @MainActor
    private func scheduleDictationEditorSyncIfNeeded(cardID: UUID, retries: Int = 10) {
        guard editingCardID == cardID || focusModeEditorCardID == cardID else { return }
        guard let card = findCard(by: cardID) else { return }

        let content = card.content
        mainLastCommittedContentByCard[cardID] = content
        focusLastCommittedContentByCard[cardID] = content
        mainProgrammaticContentSuppressUntil = Date().addingTimeInterval(0.5)
        focusProgrammaticContentSuppressUntil = Date().addingTimeInterval(0.5)

        if let sourceTextView = dictationSourceTextViewBox.textView {
            applyDictationContentToEditor(sourceTextView, content: content)
            return
        }

        guard let textView = NSApp.keyWindow?.firstResponder as? NSTextView else {
            guard retries > 0 else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                scheduleDictationEditorSyncIfNeeded(cardID: cardID, retries: retries - 1)
            }
            return
        }
        applyDictationContentToEditor(textView, content: content)
    }

    @MainActor
    private func applyDictationContentToEditor(_ textView: NSTextView, content: String) {
        if textView.string != content {
            textView.string = content
        }
        let length = (textView.string as NSString).length
        textView.setSelectedRange(NSRange(location: length, length: 0))
        textView.didChangeText()
        if !showFocusMode {
            normalizeMainEditorTextViewOffsetIfNeeded(textView, reason: "dictation-apply")
        }
    }
}
