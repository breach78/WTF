import SwiftUI

enum BWRLaunchScene {
    static let windowID = "bwr-launch"
}

struct BWRLaunchView: View {
    @Environment(\.scenePhase) private var scenePhase

    @State private var hasAttemptedResume = false
    @State private var isAttemptingResume = true
    @State private var isImporterPresented = false
    @State private var isCreatingBoard = false
    @State private var statusMessage: String?
    @State private var session: BWRBoardSession?
    @State private var autosaveTask: Task<Void, Never>?

    var body: some View {
        Group {
            if let session {
                BWRWorkspaceView(
                    document: workspaceDocumentBinding,
                    fileURL: session.fileURL
                )
                .frame(minWidth: 980, minHeight: 720)
            } else {
                launchPanel
            }
        }
        .task {
            guard !hasAttemptedResume else {
                return
            }

            hasAttemptedResume = true
            await resumeLastDocumentIfPossible()
        }
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: [.bwrBoard],
            allowsMultipleSelection: false
        ) { result in
            handleImporterResult(result)
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase != .active else {
                return
            }

            saveCurrentSessionSoon(immediate: true)
        }
    }

    private var workspaceDocumentBinding: Binding<BWRDocument> {
        Binding(
            get: { session?.document ?? BWRDocument() },
            set: { newValue in
                guard var session else {
                    return
                }

                session.document = newValue
                self.session = session
                saveCurrentSessionSoon()
            }
        )
    }

    private var launchPanel: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Board Writer")
                    .font(.custom("Avenir Next Demi Bold", size: 28))
                    .foregroundStyle(Color(hex: 0x23201B))

                Text("Open the last board automatically, or start a fresh one.")
                    .font(.custom("Avenir Next", size: 15))
                    .foregroundStyle(Color(hex: 0x625B51))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if isAttemptingResume {
                HStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.regular)
                    Text("Opening your previous board…")
                        .font(.custom("Avenir Next", size: 14))
                        .foregroundStyle(Color(hex: 0x4E493F))
                }
                .padding(.vertical, 4)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    if let statusMessage {
                        Text(statusMessage)
                            .font(.custom("Avenir Next", size: 13))
                            .foregroundStyle(Color(hex: 0x8D4D4D))
                    }

                    Button(isCreatingBoard ? "Creating…" : "New Board") {
                        createNewBoard()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isCreatingBoard)

                    Button("Open Board…") {
                        isImporterPresented = true
                    }
                    .buttonStyle(.bordered)
                    .disabled(isCreatingBoard)
                }
            }
        }
        .padding(28)
        .frame(minWidth: 420, minHeight: 220, alignment: .topLeading)
        .background(
            LinearGradient(
                colors: [Color(hex: 0xEFE7DC), Color(hex: 0xE3D8C8)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private func createNewBoard() {
        Task { @MainActor in
            isCreatingBoard = true
            defer { isCreatingBoard = false }

            do {
                let document = BWRDocument()
                let url = try BWRBoardFileStore.createNewBoard(document: document)
                BWRRecentDocumentStore.remember(url: url)
                session = BWRBoardSession(fileURL: url, document: document)
                statusMessage = nil
            } catch {
                statusMessage = "A new board could not be created."
            }
        }
    }

    @MainActor
    private func resumeLastDocumentIfPossible() async {
        guard let url = BWRRecentDocumentStore.resolve() else {
            isAttemptingResume = false
            return
        }

        do {
            try loadBoard(at: url, remember: false)
            statusMessage = nil
        } catch {
            BWRRecentDocumentStore.clear()
            statusMessage = "The previous board could not be reopened. Choose a board or start a new one."
        }

        isAttemptingResume = false
    }

    private func handleImporterResult(_ result: Result<[URL], Error>) {
        guard case let .success(urls) = result, let url = urls.first else {
            if case .failure = result {
                statusMessage = "The selected board could not be opened."
            }
            return
        }

        Task { @MainActor in
            do {
                try loadBoard(at: url, remember: true)
                statusMessage = nil
            } catch {
                statusMessage = "The selected board could not be opened."
            }
        }
    }

    @MainActor
    private func loadBoard(at url: URL, remember: Bool) throws {
        let document = try withSecurityScopedAccess(to: url) {
            try BWRDocument.open(from: url)
        }

        session = BWRBoardSession(fileURL: url, document: document)

        if remember {
            BWRRecentDocumentStore.remember(url: url)
        }
    }

    private func saveCurrentSessionSoon(immediate: Bool = false) {
        autosaveTask?.cancel()

        guard let session else {
            return
        }

        autosaveTask = Task {
            if !immediate {
                try? await Task.sleep(for: .milliseconds(350))
            }

            guard !Task.isCancelled else {
                return
            }

            await MainActor.run {
                do {
                    try withSecurityScopedAccess(to: session.fileURL) {
                        try session.document.writePackage(to: session.fileURL)
                    }
                } catch {
                    statusMessage = "The current board could not be saved."
                }
            }
        }
    }

    private func withSecurityScopedAccess<T>(
        to url: URL,
        operation: () throws -> T
    ) throws -> T {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                url.stopAccessingSecurityScopedResource()
            }
        }

        return try operation()
    }
}

private struct BWRBoardSession {
    var fileURL: URL
    var document: BWRDocument
}
