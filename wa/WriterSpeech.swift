import SwiftUI
import AVFoundation
import AVFAudio

enum SpeechDictationError: LocalizedError {
    case noActiveCard
    case microphonePermissionDenied
    case recorderUnavailable
    case emptyTranscript
    case summaryFailed
    case parentCardMissing
    case whisperBinaryMissing(String)
    case whisperModelMissing(String)
    case whisperExecutionFailed(String)

    var errorDescription: String? {
        switch self {
        case .noActiveCard:
            return "받아쓰기를 시작하려면 먼저 카드 하나를 선택해 주세요."
        case .microphonePermissionDenied:
            return "마이크 권한이 없어 받아쓰기를 시작할 수 없습니다."
        case .recorderUnavailable:
            return "받아쓰기 녹음기를 준비하지 못했습니다."
        case .emptyTranscript:
            return "받아쓰기 결과가 비어 있습니다. 조금 더 길게 말해 주세요."
        case .summaryFailed:
            return "받아쓰기 요약을 만들지 못했습니다."
        case .parentCardMissing:
            return "적용 대상 카드가 없어 받아쓰기 요약을 반영하지 못했습니다."
        case .whisperBinaryMissing(let path):
            return "whisper-cli 실행 파일을 찾을 수 없습니다: \(path)"
        case .whisperModelMissing(let path):
            return "Whisper 모델 파일을 찾을 수 없습니다: \(path)"
        case .whisperExecutionFailed(let message):
            return "Whisper 전사 실행에 실패했습니다. \(message)"
        }
    }
}

final class LiveSpeechDictationRecorder {
    let outputURL: URL
    private let audioEngine: AVAudioEngine
    private var outputFile: AVAudioFile?

    init() {
        self.outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("wa-dictation-\(UUID().uuidString)")
            .appendingPathExtension("wav")
        self.audioEngine = AVAudioEngine()
    }

    func start() throws {
        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        outputFile = try AVAudioFile(forWriting: outputURL, settings: inputFormat.settings)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 2048, format: inputFormat) { [weak self] buffer, _ in
            guard let self, let outputFile = self.outputFile else { return }
            try? outputFile.write(from: buffer)
        }
        audioEngine.prepare()
        try audioEngine.start()
    }

    func stop() {
        let inputNode = audioEngine.inputNode
        inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        outputFile = nil
    }
}

enum SpeechDictationService {
    static func validateWhisperEnvironment() throws -> WhisperPaths {
        let paths = WhisperConfiguration.resolvedPaths()

        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: paths.cliPath), fileManager.isExecutableFile(atPath: paths.cliPath) else {
            throw SpeechDictationError.whisperBinaryMissing(paths.cliPath)
        }
        guard fileManager.fileExists(atPath: paths.modelPath) else {
            throw SpeechDictationError.whisperModelMissing(paths.modelPath)
        }
        return paths
    }

    static func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    static func transcribeAudioFile(at url: URL) async throws -> String {
        let resolvedPaths = try validateWhisperEnvironment()
        let cliPath = resolvedPaths.cliPath
        let modelPath = resolvedPaths.modelPath

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: cliPath)
                process.arguments = [
                    "--model", modelPath,
                    "--language", WhisperConfiguration.language,
                    "--no-timestamps",
                    "--no-prints",
                    "--file", url.path
                ]

                let outputPipe = Pipe()
                let errorPipe = Pipe()
                process.standardOutput = outputPipe
                process.standardError = errorPipe

                do {
                    try process.run()
                    process.waitUntilExit()
                } catch {
                    let message: String = {
                        let raw = error.localizedDescription
                        if raw.localizedCaseInsensitiveContains("operation not permitted") {
                            return "\(raw) (앱 샌드박스에서 외부 바이너리 실행이 제한될 수 있습니다.)"
                        }
                        return raw
                    }()
                    continuation.resume(
                        throwing: SpeechDictationError.whisperExecutionFailed(message)
                    )
                    return
                }

                let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let rawOutput = String(data: outputData, encoding: .utf8) ?? ""
                let stdErr = String(data: errorData, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

                if process.terminationStatus != 0 {
                    var reason = stdErr.isEmpty ? "종료 코드: \(process.terminationStatus)" : stdErr
                    if reason.localizedCaseInsensitiveContains("operation not permitted") {
                        reason += " (앱 샌드박스에서 외부 바이너리 실행이 제한될 수 있습니다.)"
                    }
                    continuation.resume(throwing: SpeechDictationError.whisperExecutionFailed(reason))
                    return
                }

                let normalized = normalizeWhisperOutput(rawOutput)
                continuation.resume(returning: normalized)
            }
        }
    }

    private static func normalizeWhisperOutput(_ raw: String) -> String {
        let merged = raw
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return merged
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension ScenarioWriterView {
    @MainActor
    func toggleDictationRecording() {
        if dictationIsRecording {
            stopDictationRecording(discardAudio: false)
        } else {
            startDictationRecording()
        }
    }

    @MainActor
    func startDictationRecording() {
        guard !dictationIsRecording else { return }
        guard !dictationIsProcessing else { return }
        guard !aiIsGenerating else {
            setAIStatusError("AI 생성 중에는 받아쓰기를 시작할 수 없습니다.")
            return
        }
        guard let parentID = activeCardID else {
            setAIStatusError(SpeechDictationError.noActiveCard.localizedDescription)
            return
        }

        dictationIsRecording = true
        dictationIsProcessing = true
        setAIStatus("받아쓰기 준비 중입니다...")
        Task { @MainActor in
            do {
                _ = try SpeechDictationService.validateWhisperEnvironment()

                let granted = await SpeechDictationService.requestMicrophonePermission()
                guard granted else {
                    throw SpeechDictationError.microphonePermissionDenied
                }

                let recorder = LiveSpeechDictationRecorder()
                try recorder.start()

                dictationRecorder = recorder
                dictationTargetParentID = parentID
                dictationIsProcessing = false
                setAIStatus("받아쓰기 중입니다. 완료되면 마이크 버튼을 다시 누르세요.")
            } catch {
                dictationRecorder = nil
                dictationTargetParentID = nil
                dictationIsRecording = false
                dictationIsProcessing = false
                setAIStatusError(error.localizedDescription)
            }
        }
    }

    @MainActor
    func stopDictationRecording(discardAudio: Bool) {
        guard let recorder = dictationRecorder else {
            dictationIsRecording = false
            dictationTargetParentID = nil
            dictationIsProcessing = false
            return
        }

        recorder.stop()
        dictationRecorder = nil
        dictationIsRecording = false

        let parentID = dictationTargetParentID ?? activeCardID
        dictationTargetParentID = nil
        let recordedURL = recorder.outputURL

        if discardAudio {
            try? FileManager.default.removeItem(at: recordedURL)
            return
        }

        guard let parentID else {
            try? FileManager.default.removeItem(at: recordedURL)
            setAIStatusError(SpeechDictationError.noActiveCard.localizedDescription)
            return
        }

        dictationIsProcessing = true
        setAIStatus("받아쓰기를 정리하고 요약하는 중입니다...")

        Task { @MainActor in
            defer {
                dictationIsProcessing = false
                try? FileManager.default.removeItem(at: recordedURL)
            }

            do {
                guard findCard(by: parentID) != nil else {
                    throw SpeechDictationError.parentCardMissing
                }

                let transcript = try await transcribeDictationAudio(at: recordedURL)
                let trimmedTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmedTranscript.isEmpty else {
                    throw SpeechDictationError.emptyTranscript
                }

                let summary = try await summarizeDictationTranscript(trimmedTranscript)
                try insertDictationResultCards(
                    parentID: parentID,
                    transcript: trimmedTranscript,
                    summary: summary
                )
                setAIStatus("받아쓰기 원문 카드와 요약 카드를 추가했습니다.")
            } catch {
                setAIStatusError(error.localizedDescription)
            }
        }
    }

    func transcribeDictationAudio(at url: URL) async throws -> String {
        return try await SpeechDictationService.transcribeAudioFile(at: url)
    }

    func summarizeDictationTranscript(_ transcript: String) async throws -> String {
        guard let apiKey = try? KeychainStore.loadGeminiAPIKey(),
              !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GeminiServiceError.missingAPIKey
        }

        let prompt = buildDictationGeminiSummaryPrompt(for: transcript)
        let geminiSummary = try await GeminiService.generateText(
            prompt: prompt,
            model: currentGeminiModel(),
            apiKey: apiKey
        )
        let trimmed = geminiSummary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw SpeechDictationError.summaryFailed
        }
        return trimmed
    }

    func buildDictationGeminiSummaryPrompt(for transcript: String) -> String {
        let clamped = clampedDictationText(transcript, maxLength: 5200)
        return """
        [Article]
        \(clamped)

        You will generate increasingly concise, entity-dense summaries of the above Article or webpage. Repeat the following 2 steps 5 times.

        Step 1. Identify 1-3 informative Entities (";" delimited) from the Article which are missing from the previously generated summary.


        Step 2. Write a new, denser summary of identical length which covers every entity and detail from the previous summary plus the Missing Entities.


        A Missing Entity is:
         - Relevant: to the main story.
         - Specific: descriptive yet concise (5 words or fewer).
         - Novel: not in the previous summary.
         - Faithful: present in the Article.
         - Anywhere: located anywhere in the Article.


        Guidelines:
         - The first summary should be long (4-5 sentences, ~80 words) yet highly non-specific, containing little information beyond the entities marked as missing. Use overly verbose language and fillers (e.g., "this article discusses") to reach ~80 words.
         - Make every word count: re-write the previous summary to improve flow and make space for additional entities.
         - Make space with fusion, compression, and removal of uninformative phrases like "the article discusses".
         - The summaries should become highly dense and concise yet self-contained, e.g., easily understood without the Article.
         - Missing entities can appear anywhere in the new summary.
         - Never drop entities from the previous summary. If space cannot be made, add fewer new entities.


        Remember, use the exact same number of words for each summary. Answer only in korean.

        추가 규칙:
        - 중간 과정, 엔티티 목록, 설명은 출력하지 않는다.
        - 5번째 반복의 최종 요약문만 출력한다.
        - 마크다운/코드블록/JSON 없이 순수 텍스트만 출력한다.
        - 한국어 요약문은 4~6문장으로 유지한다.
        - 원문에 없는 사실은 추가하지 않는다.
        """
    }

    func insertDictationResultCards(parentID: UUID, transcript: String, summary: String) throws {
        guard let parent = findCard(by: parentID) else {
            throw SpeechDictationError.parentCardMissing
        }

        let prevState = captureScenarioState()
        let sortedChildren = parent.children.sorted {
            if $0.orderIndex != $1.orderIndex {
                return $0.orderIndex < $1.orderIndex
            }
            return $0.createdAt < $1.createdAt
        }
        let startIndex = (sortedChildren.last?.orderIndex ?? -1) + 1

        let transcriptCard = SceneCard(
            content: "받아쓰기 원문\n\(transcript)",
            orderIndex: startIndex,
            parent: parent,
            scenario: scenario,
            category: parent.category
        )
        let summaryCard = SceneCard(
            content: "받아쓰기 요약\n\(summary)",
            orderIndex: startIndex + 1,
            parent: parent,
            scenario: scenario,
            category: parent.category
        )

        scenario.cards.append(transcriptCard)
        scenario.cards.append(summaryCard)
        scenario.bumpCardsVersion()
        store.saveAll()
        takeSnapshot(force: true)
        pushUndoState(prevState, actionName: "받아쓰기 요약 추가")

        selectedCardIDs = [summaryCard.id]
        changeActiveCard(to: summaryCard)
    }

    func clampedDictationText(_ text: String, maxLength: Int) -> String {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.count > maxLength else { return cleaned }
        let index = cleaned.index(cleaned.startIndex, offsetBy: maxLength)
        return String(cleaned[..<index])
    }
}
