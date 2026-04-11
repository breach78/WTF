import Foundation
import SwiftUI

@main
struct BWRApp: App {
    init() {
        if ProcessInfo.processInfo.environment["BWR_RUN_PHASE1_HARNESS"] == "1" {
            let success = BWRPhase1Harness.runAll()
            exit(success ? 0 : 1)
        }
        if ProcessInfo.processInfo.environment["BWR_RUN_PHASE2_HARNESS"] == "1" {
            let success = BWRPhase2Harness.runAll()
            exit(success ? 0 : 1)
        }
        if ProcessInfo.processInfo.environment["BWR_RUN_PHASE3_HARNESS"] == "1" {
            let success = BWRPhase3Harness.runAll()
            exit(success ? 0 : 1)
        }
        if ProcessInfo.processInfo.environment["BWR_RUN_PHASE4_HARNESS"] == "1" {
            let success = BWRPhase4Harness.runAll()
            exit(success ? 0 : 1)
        }
        if ProcessInfo.processInfo.environment["BWR_RUN_PHASE5_HARNESS"] == "1" {
            let success = BWRPhase5Harness.runAll()
            exit(success ? 0 : 1)
        }
        if ProcessInfo.processInfo.environment["BWR_RUN_PHASE6_HARNESS"] == "1" {
            let success = BWRPhase6Harness.runAll()
            exit(success ? 0 : 1)
        }
    }

    var body: some Scene {
        WindowGroup("BWR", id: BWRLaunchScene.windowID) {
            BWRLaunchView()
        }

        DocumentGroup(newDocument: BWRDocument()) { file in
            BWRWorkspaceView(
                document: file.$document,
                fileURL: file.fileURL
            )
                .frame(minWidth: 980, minHeight: 720)
        }
    }
}
