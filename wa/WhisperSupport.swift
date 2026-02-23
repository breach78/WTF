import Foundation

struct WhisperPaths {
    let installRootPath: String
    let cliPath: String
    let modelPath: String
}

struct WhisperEnvironmentStatus {
    let paths: WhisperPaths
    let isCLIAvailable: Bool
    let isModelAvailable: Bool

    var isReady: Bool {
        isCLIAvailable && isModelAvailable
    }

    var message: String {
        if isReady {
            return "Whisper 준비 완료 (CLI/모델 확인됨)"
        }
        if !isCLIAvailable && !isModelAvailable {
            return "whisper-cli와 모델 파일이 모두 없습니다. 자동 설치를 실행해 주세요."
        }
        if !isCLIAvailable {
            return "whisper-cli 실행 파일을 찾을 수 없습니다."
        }
        return "Whisper 모델 파일을 찾을 수 없습니다."
    }
}

enum WhisperInstallError: LocalizedError {
    case invalidInstallRoot(String)
    case commandFailed(command: String, details: String)
    case downloadFailed(String)
    case missingBuiltBinary(String)
    case missingModel(String)

    var errorDescription: String? {
        switch self {
        case .invalidInstallRoot(let path):
            return "Whisper 설치 경로가 올바르지 않습니다: \(path)"
        case .commandFailed(let command, let details):
            let trimmed = details.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                return "명령 실행 실패: \(command)"
            }
            return "명령 실행 실패: \(command)\n\(trimmed)"
        case .downloadFailed(let message):
            return "Whisper 모델 다운로드에 실패했습니다. \(message)"
        case .missingBuiltBinary(let path):
            return "빌드 후 whisper-cli를 찾지 못했습니다: \(path)"
        case .missingModel(let path):
            return "다운로드 후 모델 파일을 찾지 못했습니다: \(path)"
        }
    }
}

enum WhisperConfiguration {
    static let installRootKey = "whisperInstallRootPath"
    static let cliPathKey = "whisperCLIPath"
    static let modelPathKey = "whisperModelPath"

    static let language = "ko"
    static let modelFileName = "ggml-large-v3-q5_0.bin"

    private static let legacyInstallRootPath = "/Users/three/Developer/whisper.cpp"

    static func defaultInstallRootPath() -> String {
        let fm = FileManager.default
        if let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            return appSupport
                .appendingPathComponent("wa", isDirectory: true)
                .appendingPathComponent("whisper.cpp", isDirectory: true)
                .path
        }
        let fallback = (NSHomeDirectory() as NSString)
            .appendingPathComponent("Library/Application Support/wa/whisper.cpp")
        return fallback
    }

    static func paths(forInstallRoot installRootPath: String) -> WhisperPaths {
        let root = trimmed(installRootPath)
        let normalizedRoot = root.isEmpty ? defaultInstallRootPath() : root
        let rootURL = URL(fileURLWithPath: normalizedRoot, isDirectory: true)
        let cliPath = rootURL
            .appendingPathComponent("build", isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
            .appendingPathComponent("whisper-cli", isDirectory: false)
            .path
        let modelPath = rootURL
            .appendingPathComponent("models", isDirectory: true)
            .appendingPathComponent(modelFileName, isDirectory: false)
            .path
        return WhisperPaths(installRootPath: normalizedRoot, cliPath: cliPath, modelPath: modelPath)
    }

    static func resolvedPaths() -> WhisperPaths {
        let defaults = UserDefaults.standard
        let storedRoot = trimmed(defaults.string(forKey: installRootKey))
        let storedCLI = trimmed(defaults.string(forKey: cliPathKey))
        let storedModel = trimmed(defaults.string(forKey: modelPathKey))

        if !storedCLI.isEmpty || !storedModel.isEmpty {
            let inferredRoot =
                !storedRoot.isEmpty
                ? storedRoot
                : (inferInstallRoot(cliPath: storedCLI, modelPath: storedModel) ?? defaultInstallRootPath())
            let defaultsForRoot = paths(forInstallRoot: inferredRoot)
            return WhisperPaths(
                installRootPath: inferredRoot,
                cliPath: storedCLI.isEmpty ? defaultsForRoot.cliPath : storedCLI,
                modelPath: storedModel.isEmpty ? defaultsForRoot.modelPath : storedModel
            )
        }

        let fm = FileManager.default
        let legacyPaths = paths(forInstallRoot: legacyInstallRootPath)
        if fm.fileExists(atPath: legacyPaths.cliPath) || fm.fileExists(atPath: legacyPaths.modelPath) {
            return legacyPaths
        }

        let root = storedRoot.isEmpty ? defaultInstallRootPath() : storedRoot
        return paths(forInstallRoot: root)
    }

    static func save(paths: WhisperPaths) {
        let defaults = UserDefaults.standard
        defaults.set(paths.installRootPath, forKey: installRootKey)
        defaults.set(paths.cliPath, forKey: cliPathKey)
        defaults.set(paths.modelPath, forKey: modelPathKey)
    }

    static func inferInstallRoot(cliPath: String, modelPath: String) -> String? {
        let trimmedCLI = trimmed(cliPath)
        if !trimmedCLI.isEmpty {
            let cliURL = URL(fileURLWithPath: trimmedCLI)
            let rootFromCLI = cliURL
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .path
            if !trimmed(rootFromCLI).isEmpty {
                return rootFromCLI
            }
        }

        let trimmedModel = trimmed(modelPath)
        if !trimmedModel.isEmpty {
            let modelURL = URL(fileURLWithPath: trimmedModel)
            let rootFromModel = modelURL
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .path
            if !trimmed(rootFromModel).isEmpty {
                return rootFromModel
            }
        }
        return nil
    }

    static func trimmed(_ raw: String?) -> String {
        raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}

enum WhisperInstallService {
    private struct CommandResult {
        let terminationStatus: Int32
        let output: String
    }

    private static let repositoryURL = "https://github.com/ggerganov/whisper.cpp.git"
    private static let modelDownloadURLString = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-q5_0.bin"

    static func inspectEnvironment(paths: WhisperPaths = WhisperConfiguration.resolvedPaths()) -> WhisperEnvironmentStatus {
        let fm = FileManager.default
        let hasCLI = fm.fileExists(atPath: paths.cliPath) && fm.isExecutableFile(atPath: paths.cliPath)
        let hasModel = fm.fileExists(atPath: paths.modelPath)
        return WhisperEnvironmentStatus(paths: paths, isCLIAvailable: hasCLI, isModelAvailable: hasModel)
    }

    static func installOrUpdate(
        installRootPath: String,
        progress: @escaping @Sendable (String) -> Void
    ) async throws -> WhisperPaths {
        let normalizedRoot = WhisperConfiguration.trimmed(installRootPath)
        guard !normalizedRoot.isEmpty else {
            throw WhisperInstallError.invalidInstallRoot(installRootPath)
        }

        let rootURL = URL(fileURLWithPath: normalizedRoot, isDirectory: true)
        let fm = FileManager.default

        let parentURL = rootURL.deletingLastPathComponent()
        try fm.createDirectory(at: parentURL, withIntermediateDirectories: true)

        if !fm.fileExists(atPath: rootURL.path) {
            progress("whisper.cpp 저장소를 내려받는 중입니다...")
            _ = try await runCommand(
                executable: "/usr/bin/env",
                arguments: ["git", "clone", repositoryURL, rootURL.path]
            )
        } else {
            let gitPath = rootURL.appendingPathComponent(".git", isDirectory: true).path
            let cmakeListsPath = rootURL.appendingPathComponent("CMakeLists.txt", isDirectory: false).path
            guard fm.fileExists(atPath: gitPath) || fm.fileExists(atPath: cmakeListsPath) else {
                throw WhisperInstallError.invalidInstallRoot(rootURL.path)
            }

            if fm.fileExists(atPath: gitPath) {
                progress("whisper.cpp 최신 코드를 확인하는 중입니다...")
                _ = try? await runCommand(
                    executable: "/usr/bin/env",
                    arguments: ["git", "-C", rootURL.path, "pull", "--ff-only"]
                )
            }
        }

        let buildDirectory = rootURL.appendingPathComponent("build", isDirectory: true).path

        progress("whisper-cli 빌드 환경을 구성 중입니다...")
        _ = try await runCommand(
            executable: "/usr/bin/env",
            arguments: ["cmake", "-S", rootURL.path, "-B", buildDirectory]
        )

        progress("whisper-cli를 빌드하는 중입니다... (수 분 소요될 수 있습니다)")
        let jobs = max(2, ProcessInfo.processInfo.activeProcessorCount)
        _ = try await runCommand(
            executable: "/usr/bin/env",
            arguments: ["cmake", "--build", buildDirectory, "--config", "Release", "-j", "\(jobs)"]
        )

        let paths = WhisperConfiguration.paths(forInstallRoot: rootURL.path)
        guard fm.fileExists(atPath: paths.cliPath), fm.isExecutableFile(atPath: paths.cliPath) else {
            throw WhisperInstallError.missingBuiltBinary(paths.cliPath)
        }

        if !fm.fileExists(atPath: paths.modelPath) {
            progress("Whisper 모델을 다운로드하는 중입니다... (대용량 파일)")
            try await downloadModel(to: URL(fileURLWithPath: paths.modelPath))
        }

        guard fm.fileExists(atPath: paths.modelPath) else {
            throw WhisperInstallError.missingModel(paths.modelPath)
        }

        WhisperConfiguration.save(paths: paths)
        progress("Whisper 설치가 완료되었습니다.")
        return paths
    }

    private static func runCommand(
        executable: String,
        arguments: [String]
    ) async throws -> CommandResult {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = arguments

                let outputPipe = Pipe()
                let errorPipe = Pipe()
                process.standardOutput = outputPipe
                process.standardError = errorPipe

                do {
                    try process.run()
                    process.waitUntilExit()
                } catch {
                    continuation.resume(
                        throwing: WhisperInstallError.commandFailed(
                            command: ([executable] + arguments).joined(separator: " "),
                            details: error.localizedDescription
                        )
                    )
                    return
                }

                let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let stdout = String(data: outputData, encoding: .utf8) ?? ""
                let stderr = String(data: errorData, encoding: .utf8) ?? ""
                let combined = [stdout, stderr]
                    .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                    .joined(separator: "\n")

                if process.terminationStatus != 0 {
                    continuation.resume(
                        throwing: WhisperInstallError.commandFailed(
                            command: ([executable] + arguments).joined(separator: " "),
                            details: combined
                        )
                    )
                    return
                }

                continuation.resume(returning: CommandResult(terminationStatus: process.terminationStatus, output: combined))
            }
        }
    }

    private static func downloadModel(to destinationURL: URL) async throws {
        guard let modelURL = URL(string: modelDownloadURLString) else {
            throw WhisperInstallError.downloadFailed("모델 URL이 올바르지 않습니다.")
        }

        do {
            let (temporaryURL, response) = try await URLSession.shared.download(from: modelURL)
            if let http = response as? HTTPURLResponse,
               !(200...299).contains(http.statusCode) {
                throw WhisperInstallError.downloadFailed("HTTP \(http.statusCode)")
            }

            let fm = FileManager.default
            try fm.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            if fm.fileExists(atPath: destinationURL.path) {
                try fm.removeItem(at: destinationURL)
            }
            try fm.moveItem(at: temporaryURL, to: destinationURL)
        } catch let error as WhisperInstallError {
            throw error
        } catch {
            throw WhisperInstallError.downloadFailed(error.localizedDescription)
        }
    }
}
