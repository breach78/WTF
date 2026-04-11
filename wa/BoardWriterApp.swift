import SwiftUI

private struct BoardWriterCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(after: .windowArrangement) {
            Button("BWR Spike Lab") {
                openWindow(id: BWRSpikeLabConstants.windowID)
            }
            .keyboardShortcut("9", modifiers: [.command, .option])
        }
    }
}

@main
struct BoardWriterApp: App {
    init() {
#if DEBUG
        if ProcessInfo.processInfo.environment["WA_RUN_BWR_M0_HARNESS"] == "1" {
            let success = BWRPhase0Harness.runAll()
            exit(success ? 0 : 1)
        }
        if ProcessInfo.processInfo.environment["WA_RUN_BWR_M1_HARNESS"] == "1" {
            let success = BWRMilestone1Harness.runAll()
            exit(success ? 0 : 1)
        }
        if ProcessInfo.processInfo.environment["WA_RUN_BWR_M2_HARNESS"] == "1" {
            let success = BWRMilestone2Harness.runAll()
            exit(success ? 0 : 1)
        }
        if ProcessInfo.processInfo.environment["WA_RUN_BWR_R3_HARNESS"] == "1" {
            let success = BWRRealignmentR3Harness.runAll()
            exit(success ? 0 : 1)
        }
        if ProcessInfo.processInfo.environment["WA_RUN_BWR_R4_HARNESS"] == "1" {
            let success = BWRRealignmentR4Harness.runAll()
            exit(success ? 0 : 1)
        }
        if ProcessInfo.processInfo.environment["WA_RUN_BWR_R5_HARNESS"] == "1" {
            let success = BWRRealignmentR5Harness.runAll()
            exit(success ? 0 : 1)
        }
        if ProcessInfo.processInfo.environment["WA_RUN_BWR_R6_HARNESS"] == "1" {
            let success = BWRRealignmentR6Harness.runAll()
            exit(success ? 0 : 1)
        }
        if ProcessInfo.processInfo.environment["WA_RUN_BWR_M3_HARNESS"] == "1" {
            let success = BWRMilestone3Harness.runAll()
            exit(success ? 0 : 1)
        }
        if ProcessInfo.processInfo.environment["WA_RUN_BWR_M4_HARNESS"] == "1" {
            let success = BWRMilestone4Harness.runAll()
            exit(success ? 0 : 1)
        }
        if ProcessInfo.processInfo.environment["WA_RUN_BWR_M5_HARNESS"] == "1" {
            let success = BWRMilestone5Harness.runAll()
            exit(success ? 0 : 1)
        }
        if ProcessInfo.processInfo.environment["WA_RUN_BWR_CARDBUDDY_PHASEB_HARNESS"] == "1" {
            let success = BWRCardBuddySurfaceAuditHarness.runAll()
            exit(success ? 0 : 1)
        }
        if ProcessInfo.processInfo.environment["WA_RUN_BWR_CARDBUDDY_PHASEC_HARNESS"] == "1" {
            let success = BWRCardBuddyPhaseCHarness.runAll()
            exit(success ? 0 : 1)
        }
        if ProcessInfo.processInfo.environment["WA_RUN_BWR_CARDBUDDY_PHASED_HARNESS"] == "1" {
            let success = BWRCardBuddyPhaseDHarness.runAll()
            exit(success ? 0 : 1)
        }
        if ProcessInfo.processInfo.environment["WA_RUN_BWR_CARDBUDDY_PHASEE_HARNESS"] == "1" {
            let success = BWRCardBuddyPhaseEHarness.runAll()
            exit(success ? 0 : 1)
        }
        if ProcessInfo.processInfo.environment["WA_RUN_BWR_CARDBUDDY_PHASEF_HARNESS"] == "1" {
            let success = BWRCardBuddyPhaseFHarness.runAll()
            exit(success ? 0 : 1)
        }
        if ProcessInfo.processInfo.environment["WA_RUN_BWR_CARDBUDDY_PHASEG_HARNESS"] == "1" {
            let success = BWRCardBuddyPhaseGHarness.runAll()
            exit(success ? 0 : 1)
        }
        if ProcessInfo.processInfo.environment["WA_RUN_BWR_CARDBUDDY_PHASEH_HARNESS"] == "1" {
            let success = BWRCardBuddyPhaseHHarness.runAll()
            exit(success ? 0 : 1)
        }
        if ProcessInfo.processInfo.environment["WA_RUN_BWR_CARDBUDDY_PHASEI_HARNESS"] == "1" {
            let success = BWRCardBuddyPhaseIHarness.runAll()
            exit(success ? 0 : 1)
        }
#endif
    }

    var body: some Scene {
        DocumentGroup(newDocument: { BWRReferenceDocument() }) { file in
            BWRDocumentShellView(document: file.document, fileURL: file.fileURL)
        }
        .commands {
            BoardWriterCommands()
        }

        Window("BWR Spike Lab", id: BWRSpikeLabConstants.windowID) {
            BWRSpikeLabView()
        }
        .windowResizability(.contentSize)
        .commandsRemoved()
    }
}
