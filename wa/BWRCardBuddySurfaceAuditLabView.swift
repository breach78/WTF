import SwiftUI

@MainActor
struct BWRCardBuddySurfaceAuditLabView: View {
    @State private var harnessStatus: String = "아직 실행하지 않음"
    @State private var harnessReport: String = ""
    @State private var harnessRunning = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Text("Card Buddy Surface Audit")
                    .font(.system(size: 20, weight: .semibold))
                Spacer()
                Button(harnessRunning ? "Running…" : "Run Audit Harness") {
                    runHarness()
                }
                .disabled(harnessRunning)
            }

            Text("Phase B는 현재 BWR 표면과 Card Buddy 목표 표면을 같은 캔버스에서 비교하고, 복사할 값을 숫자로 잠그는 단계입니다.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            HSplitView {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        BWRCardBuddySurfaceAuditMetricTable(
                            title: "Card Shell Metrics",
                            rows: BWRCardBuddySurfaceAuditTableFactory.shellMetrics
                        )
                        BWRCardBuddySurfaceAuditMetricTable(
                            title: "Selection Metrics",
                            rows: BWRCardBuddySurfaceAuditTableFactory.selectionMetrics
                        )
                        BWRCardBuddyOverlayAuditTable(
                            rows: BWRCardBuddySurfaceAuditTableFactory.overlayRows
                        )
                        BWRCardBuddySurfaceAuditMetricTable(
                            title: "Current vs Target Diff",
                            rows: BWRCardBuddySurfaceAuditTableFactory.currentVsTargetRows
                        )
                        BWRCardBuddySurfaceAuditCanvasView()
                    }
                    .padding(.trailing, 8)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(harnessStatus)
                        .font(.system(size: 13, weight: .medium))
                    Text("sampled selection blue: rgb(\(BWRCardBuddySurfaceAuditLock.sampledSelectionBlueRGB.r), \(BWRCardBuddySurfaceAuditLock.sampledSelectionBlueRGB.g), \(BWRCardBuddySurfaceAuditLock.sampledSelectionBlueRGB.b))")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                    ScrollView {
                        Text(harnessReport.isEmpty ? "리포트가 아직 없습니다." : harnessReport)
                            .font(.system(size: 11, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                    Text(BWRCardBuddySurfaceAuditHarness.reportMarkdownURL.path)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .frame(minWidth: 320, idealWidth: 400, maxWidth: 440, maxHeight: .infinity)
            }
        }
        .padding(16)
        .onAppear {
            loadExistingReport()
        }
    }

    private func runHarness() {
        guard !harnessRunning else { return }
        harnessRunning = true
        harnessStatus = "surface audit harness를 실행하는 중…"

        DispatchQueue.global(qos: .userInitiated).async {
            let success = BWRCardBuddySurfaceAuditHarness.runAll()
            let report = (try? String(contentsOf: BWRCardBuddySurfaceAuditHarness.reportMarkdownURL, encoding: .utf8)) ?? ""
            DispatchQueue.main.async {
                harnessReport = report
                harnessStatus = success
                    ? "완료: failures 0"
                    : "실패 존재: \(BWRCardBuddySurfaceAuditHarness.reportMarkdownURL.path) 확인"
                harnessRunning = false
            }
        }
    }

    private func loadExistingReport() {
        harnessReport = (try? String(contentsOf: BWRCardBuddySurfaceAuditHarness.reportMarkdownURL, encoding: .utf8)) ?? ""
    }
}
