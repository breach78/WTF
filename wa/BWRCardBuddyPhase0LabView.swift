import SwiftUI

@MainActor
struct BWRCardBuddyPhase0LabView: View {
    private let fixtures = BWRCardBuddyVisualSnapshotFactory.fixtures()

    @State private var selectedFixtureID: String = BWRCardBuddyVisualSnapshotFactory.fixtures().first?.id ?? "normal"
    @State private var harnessStatus: String = "아직 실행하지 않음"
    @State private var harnessReport: String = ""
    @State private var harnessRunning = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Text("Card Buddy Phase 0")
                    .font(.system(size: 20, weight: .semibold))
                Spacer()
                Picker("Fixture", selection: $selectedFixtureID) {
                    ForEach(fixtures, id: \.id) { fixture in
                        Text(fixture.title).tag(fixture.id)
                    }
                }
                .frame(width: 220)

                Button(harnessRunning ? "Running…" : "Run Harness") {
                    runHarness()
                }
                .disabled(harnessRunning)
            }

            Text("Phase 0 preflight seam을 snapshot fixture와 report로 잠급니다. 여기서는 cursor / hover / drag / theme injection이 main shell 밖에서 안전하게 재현됩니다.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            HSplitView {
                selectedFixtureView
                    .frame(minWidth: 760, maxWidth: .infinity, maxHeight: .infinity)

                VStack(alignment: .leading, spacing: 8) {
                    Text(harnessStatus)
                        .font(.system(size: 13, weight: .medium))
                    ScrollView {
                        Text(harnessReport.isEmpty ? "리포트가 아직 없습니다." : harnessReport)
                            .font(.system(size: 11, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                    Text(BWRCardBuddyPhase0Harness.reportMarkdownURL.path)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .frame(minWidth: 320, idealWidth: 380, maxWidth: 420, maxHeight: .infinity)
            }
        }
        .padding(16)
        .onAppear {
            loadExistingReport()
        }
    }

    @ViewBuilder
    private var selectedFixtureView: some View {
        if let fixture = fixtures.first(where: { $0.id == selectedFixtureID }) {
            BWRCardBuddyVisualSnapshotHost(fixture: fixture)
                .id(fixture.id)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("Fixture Not Found")
                    .font(.system(size: 16, weight: .semibold))
                Text("선택한 snapshot fixture를 찾지 못했습니다.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }

    private func runHarness() {
        guard !harnessRunning else { return }
        harnessRunning = true
        harnessStatus = "card buddy phase-0 harness를 실행하는 중…"

        DispatchQueue.global(qos: .userInitiated).async {
            let success = BWRCardBuddyPhase0Harness.runAll()
            let report = (try? String(contentsOf: BWRCardBuddyPhase0Harness.reportMarkdownURL, encoding: .utf8)) ?? ""
            DispatchQueue.main.async {
                harnessReport = report
                harnessStatus = success
                    ? "완료: failures 0"
                    : "실패 존재: \(BWRCardBuddyPhase0Harness.reportMarkdownURL.path) 확인"
                harnessRunning = false
            }
        }
    }

    private func loadExistingReport() {
        harnessReport = (try? String(contentsOf: BWRCardBuddyPhase0Harness.reportMarkdownURL, encoding: .utf8)) ?? ""
    }
}
