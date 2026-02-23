# Focus Mode Live Monitor Window

## TL;DR
> **Summary**: Add a persistent focus-mode diagnostics window that can start/stop monitoring, clear logs, and copy logs, while passively capturing all layout-affecting signals (width/height/container/caret/normalization) without changing editor behavior.
> **Deliverables**:
> - Non-activating monitor window with `Start/Stop`, `Clear`, `Copy`
> - In-memory ring-buffer recorder with throttled UI rendering
> - Focus-mode instrumentation at existing high-signal callsites
> - Deterministic smoke hooks and evidence outputs for log integrity and non-perturbation
> **Effort**: Large
> **Parallel**: YES - 2 waves
> **Critical Path**: Task 1 -> Task 2 -> Task 3 -> Task 4 -> Task 6 -> Task 7

## Context
### Original Request
User reports severe regression after recent focus-mode patches: short cards also expand unexpectedly. User explicitly requests monitor-first workflow: an always-visible window with clear/copy and monitor start/stop controls, logging all factors that influence focus-mode layout, then sharing copied logs back for diagnosis.

### Interview Summary
- This wave is diagnostics-first, not layout-fix-first.
- Monitor must be always available and useful during live reproduction.
- Logs must capture all relevant focus-mode sizing/wrap/gap influences and be copyable as plain text.
- Low-risk architecture is required to avoid changing current editor behavior while observing.

### Metis Review (gaps addressed)
- Add strict non-perturbation guardrails (monitor must not steal key window/responder role).
- Add bounded recorder design (ring buffer + coalescing + throttled UI refresh).
- Add deterministic, agent-executable smoke validation for monitor behavior and privacy constraints.
- Explicitly separate diagnostics scope from algorithmic layout fixes.

## Work Objectives
### Core Objective
Ship an always-available focus diagnostics window that records and exposes all focus-mode layout decision signals in real time, enabling reproducible log capture without introducing behavioral side effects.

### Deliverables
- `FocusMonitorRecorder` subsystem with start/stop gate and bounded in-memory log buffer.
- Monitor window/panel UI with `Start/Stop`, `Clear`, `Copy` controls and rolling log view.
- Instrumentation in focus-mode width/height/normalization/caret pipelines with structured log schema.
- Command/menu entry to open monitor window and smoke hooks for automated verification.

### Definition of Done (verifiable conditions with commands)
- `xcodebuild -project wa.xcodeproj -target wa -configuration Debug -destination 'platform=macOS' build` reports `BUILD SUCCEEDED`.
- `WA_LAYOUT_SMOKETEST=1 ./build/Debug/WTF.app/Contents/MacOS/WTF` outputs `FOCUS_MODE_LAYOUT_SMOKETEST_OK`.
- `WA_FOCUS_MONITOR_SMOKETEST=1 ./build/Debug/WTF.app/Contents/MacOS/WTF` outputs `FOCUS_MONITOR_SMOKETEST_OK`.
- `WA_FOCUS_MONITOR_SMOKETEST=1 WA_FOCUS_MONITOR_PRIVACY_SENTINEL=DO_NOT_LEAK ./build/Debug/WTF.app/Contents/MacOS/WTF` does not emit `DO_NOT_LEAK`.
- `.sisyphus/evidence/task-7-scope-check.txt` is `PASS`.

### Must Have
- Monitor window remains available during focus-mode reproduction and supports start/stop capture, clear, copy.
- Logged fields include deterministic/observed height decisions, width budgets, text-container geometry, normalization/caret reasons, active editor identifiers.
- Monitor path is passive and does not mutate focus logic outcomes.
- Logs are copyable in stable, plain-text format suitable for user sharing.

### Must NOT Have (guardrails, AI slop patterns, scope boundaries)
- No automatic layout fix logic in this diagnostics wave.
- No file/disk/network log persistence.
- No additional global event monitors beyond existing focus-mode monitors.
- No monitor window behavior that steals key/main window from editor.
- No instrumentation of unrelated main-mode sizing paths.

## Verification Strategy
> ZERO HUMAN INTERVENTION - all verification is agent-executed.
- Test decision: tests-after (build + smoke + static invariants + scope gates).
- QA policy: every task includes happy + failure/edge scenario.
- Evidence: `.sisyphus/evidence/task-{N}-{slug}.{ext}`.

## Execution Strategy
### Parallel Execution Waves
> Target: 5-8 tasks per wave. <3 per wave (except final) = under-splitting.
> Shared dependencies are front-loaded.

Wave 1: Baseline capture, recorder architecture, monitor window UI, command routing, core instrumentation (Tasks 1-5)
Wave 2: Smoke hooks, verification bundle, final scope gate (Tasks 6-7)

### Dependency Matrix (full, all tasks)
- Task 1: Blocked By [] | Blocks [2,3,4,5,7]
- Task 2: Blocked By [1] | Blocks [3,4,5,6]
- Task 3: Blocked By [1,2] | Blocks [5,6]
- Task 4: Blocked By [1,2] | Blocks [5,6,7]
- Task 5: Blocked By [2,3,4] | Blocks [6,7]
- Task 6: Blocked By [2,3,4,5] | Blocks [7]
- Task 7: Blocked By [1,5,6] | Blocks []

### Agent Dispatch Summary (wave -> task count -> categories)
- Wave 1 -> 5 tasks -> `unspecified-high`, `visual-engineering`, `quick`
- Wave 2 -> 2 tasks -> `quick`, `unspecified-high`

## TODOs
> Implementation + Test = ONE task. Never separate.
> EVERY task MUST have: Agent Profile + Parallelization + QA Scenarios.

- [x] 1. Baseline Capture + Monitor Schema Contract

  **What to do**:
  - Capture baseline snapshots for focus-mode and app window integration files:
    - `wa/WriterCardViews.swift`
    - `wa/WriterFocusMode.swift`
    - `wa/WriterViews.swift`
    - `wa/WriterSharedTypes.swift`
    - `wa/waApp.swift`
  - Create SHA manifest and a schema contract file documenting required monitor event fields.
  - Schema must include: base metadata (`seq`, `ts`, `event`, `reason`), width inputs, deterministic/observed heights, text container geometry, normalization run summary, caret selection/ensure metadata, active card IDs.

  **Must NOT do**:
  - Do not change application source code in this task.

  **Recommended Agent Profile**:
  - Category: `quick` — Reason: deterministic setup task.
  - Skills: [`karpathy-guidelines`] — keep artifacts reproducible and minimal.
  - Omitted: [`git-master`] — no git operation required.

  **Parallelization**: Can Parallel: NO | Wave 1 | Blocks: [2,3,4,5,7] | Blocked By: []

  **References** (executor has NO interview context — be exhaustive):
  - `wa/WriterCardViews.swift:200` — focus measured height decision path.
  - `wa/WriterFocusMode.swift:562` — normalization entrypoint with reason.
  - `wa/WriterFocusMode.swift:622` — selection monitor event source.
  - `wa/WriterViews.swift:116` — observed height state map.
  - `wa/waApp.swift:108` — menu command integration pattern.

  **Acceptance Criteria** (agent-executable only):
  - [ ] `.sisyphus/evidence/baseline-focus-monitor/` contains all 5 snapshots.
  - [ ] `.sisyphus/evidence/task-1-focus-monitor-sha256.txt` exists and has 5 entries.
  - [ ] `.sisyphus/evidence/task-1-focus-monitor-schema.md` exists and lists required fields/events.

  **QA Scenarios** (MANDATORY — task incomplete without these):
  ```
  Scenario: Baseline artifacts are created
    Tool: Bash
    Steps: run `mkdir -p .sisyphus/evidence/baseline-focus-monitor && cp wa/WriterCardViews.swift wa/WriterFocusMode.swift wa/WriterViews.swift wa/WriterSharedTypes.swift wa/waApp.swift .sisyphus/evidence/baseline-focus-monitor/ && shasum -a 256 .sisyphus/evidence/baseline-focus-monitor/*.swift > .sisyphus/evidence/task-1-focus-monitor-sha256.txt`
    Expected: snapshot directory and sha manifest exist
    Evidence: .sisyphus/evidence/task-1-focus-monitor-sha256.txt

  Scenario: Baseline completeness guard
    Tool: Bash
    Steps: run `python3 - <<'PY'
from pathlib import Path
expected={'WriterCardViews.swift','WriterFocusMode.swift','WriterViews.swift','WriterSharedTypes.swift','waApp.swift'}
actual={p.name for p in Path('.sisyphus/evidence/baseline-focus-monitor').glob('*.swift')}
missing=sorted(expected-actual)
Path('.sisyphus/evidence/task-1-focus-monitor-check.txt').write_text('PASS' if not missing else '\n'.join(missing), encoding='utf-8')
raise SystemExit(0 if not missing else 1)
PY`
    Expected: script exits 0 and writes `PASS`
    Evidence: .sisyphus/evidence/task-1-focus-monitor-check.txt
  ```

  **Commit**: NO | Message: `n/a` | Files: [`.sisyphus/evidence/*`]

- [x] 2. Implement Passive Recorder Core (Ring Buffer + Start/Stop + Redaction)

  **What to do**:
  - Add a recorder type (e.g., `FocusMonitorRecorder`) in `wa/` that supports:
    - `isRecording` gate (cheap early return when false)
    - bounded ring buffer (fixed max entries)
    - monotonic sequence IDs
    - `clear()`, `snapshotText()`, `copyToClipboard()` helper or view-bound action
  - Add privacy redaction policy: never log full card text; log only lengths/hash-like metadata.
  - Add event model with explicit types and dictionaries/struct payloads covering agreed schema.
  - Add recorder state to app state container (`WriterViews` or adjacent state object) without changing layout logic.

  **Must NOT do**:
  - Do not add file persistence or network upload.
  - Do not compute expensive payload fields when recording is off.

  **Recommended Agent Profile**:
  - Category: `unspecified-high` — Reason: shared runtime utility with correctness/perf constraints.
  - Skills: [`karpathy-guidelines`] — enforce non-perturbing design and bounded memory.
  - Omitted: [`frontend-ui-ux`] — this task is core data plumbing.

  **Parallelization**: Can Parallel: NO | Wave 1 | Blocks: [3,4,5,6] | Blocked By: [1]

  **References** (executor has NO interview context — be exhaustive):
  - `wa/WriterViews.swift:57` — focus-mode state container location.
  - `wa/WriterViews.swift:147` — existing normalization timing states.
  - `wa/WriterCardManagement.swift:787` — clipboard action pattern via `NSPasteboard`.
  - `wa/waApp.swift:5` — notification-based command routing style.

  **Acceptance Criteria** (agent-executable only):
  - [ ] Recorder supports start/stop, clear, snapshot export, and bounded capacity.
  - [ ] Redaction guard exists and blocks raw content logging.
  - [ ] Recorder append path is no-op when `isRecording == false`.

  **QA Scenarios** (MANDATORY — task incomplete without these):
  ```
  Scenario: Recorder API contract exists
    Tool: Bash
    Steps: run `python3 - <<'PY'
from pathlib import Path
matches=[]
for p in Path('wa').glob('*.swift'):
  t=p.read_text(encoding='utf-8')
  if 'FocusMonitorRecorder' in t:
    matches.append(p.as_posix())
Path('.sisyphus/evidence/task-2-recorder-presence.txt').write_text('\n'.join(matches), encoding='utf-8')
raise SystemExit(0 if matches else 1)
PY`
    Expected: at least one source file defines recorder
    Evidence: .sisyphus/evidence/task-2-recorder-presence.txt

  Scenario: Redaction guard is present
    Tool: Bash
    Steps: run `python3 - <<'PY'
from pathlib import Path
blob='\n'.join(Path(p).read_text(encoding='utf-8') for p in Path('wa').glob('*.swift'))
ok=('redact' in blob.lower() or 'textLength' in blob) and 'FocusMonitorRecorder' in blob
Path('.sisyphus/evidence/task-2-redaction-guard.txt').write_text('PASS' if ok else 'FAIL', encoding='utf-8')
raise SystemExit(0 if ok else 1)
PY`
    Expected: writes `PASS`
    Evidence: .sisyphus/evidence/task-2-redaction-guard.txt
  ```

  **Commit**: NO | Message: `n/a` | Files: [`wa/*`]

- [x] 3. Build Non-Activating Monitor Window with Start/Stop, Clear, Copy Controls

  **What to do**:
  - Implement a dedicated monitor window/panel UI that is always available while app runs.
  - Window must be non-activating and not steal editor key/main status.
  - UI controls:
    - `Start/Stop` toggle bound to recorder `isRecording`
    - `Clear` button to clear buffer
    - `Copy` button to copy current snapshot text to clipboard
  - Add log viewport (read-only) that refreshes on throttled cadence.

  **Must NOT do**:
  - Do not add text-editable controls that can become first responder.
  - Do not force monitor window to key window.

  **Recommended Agent Profile**:
  - Category: `visual-engineering` — Reason: panel/window UI construction in SwiftUI/AppKit bridge.
  - Skills: [`karpathy-guidelines`] — preserve behavior with minimal UI surface.
  - Omitted: [`playwright`] — native app UI path not browser-based.

  **Parallelization**: Can Parallel: NO | Wave 1 | Blocks: [5,6] | Blocked By: [1,2]

  **References** (executor has NO interview context — be exhaustive):
  - `wa/waApp.swift:37` — existing `WindowGroup` root.
  - `wa/waApp.swift:307` — window configuration loop; note `NSPanel` skip branch.
  - `wa/waApp.swift:312` — explicit `window is NSPanel` handling.
  - `wa/WriterCardManagement.swift:787` — clipboard copy pattern.

  **Acceptance Criteria** (agent-executable only):
  - [ ] Monitor UI source contains Start/Stop, Clear, Copy controls.
  - [ ] Monitor panel declares non-activating/non-key safety behavior.
  - [ ] Copy action uses `NSPasteboard` and exports snapshot text.

  **QA Scenarios** (MANDATORY — task incomplete without these):
  ```
  Scenario: Monitor controls exist in source
    Tool: Bash
    Steps: run `python3 - <<'PY'
from pathlib import Path
blob='\n'.join(Path(p).read_text(encoding='utf-8') for p in Path('wa').glob('*.swift'))
checks={
  'has_start_stop': ('Start' in blob and 'Stop' in blob) or 'isRecording' in blob,
  'has_clear': 'Clear' in blob or 'clear()' in blob,
  'has_copy': 'Copy' in blob or 'NSPasteboard' in blob,
}
Path('.sisyphus/evidence/task-3-monitor-controls.txt').write_text('\n'.join(f"{k}={'PASS' if v else 'FAIL'}" for k,v in checks.items()), encoding='utf-8')
raise SystemExit(0 if all(checks.values()) else 1)
PY`
    Expected: all checks PASS
    Evidence: .sisyphus/evidence/task-3-monitor-controls.txt

  Scenario: Non-activating panel guard present
    Tool: Bash
    Steps: run `python3 - <<'PY'
from pathlib import Path
blob='\n'.join(Path(p).read_text(encoding='utf-8') for p in Path('wa').glob('*.swift'))
ok=('NSPanel' in blob) and ('canBecomeKey' in blob or 'nonactivating' in blob.lower() or 'becomesKeyOnlyIfNeeded' in blob)
Path('.sisyphus/evidence/task-3-panel-safety.txt').write_text('PASS' if ok else 'FAIL', encoding='utf-8')
raise SystemExit(0 if ok else 1)
PY`
    Expected: writes `PASS`
    Evidence: .sisyphus/evidence/task-3-panel-safety.txt
  ```

  **Commit**: NO | Message: `n/a` | Files: [`wa/waApp.swift`, `wa/*Monitor*.swift`]

- [x] 4. Integrate Open/Close Command Routing and Window Lifecycle Safety

  **What to do**:
  - Add app command/menu entry and optional shortcut for opening/focusing the monitor window.
  - Reuse existing notification/command style in `wa/waApp.swift` rather than introducing a separate routing mechanism.
  - Ensure monitor window lifecycle does not interfere with existing `configureWindows()` behavior.
  - Ensure monitor is excluded from main window chrome/background mutation paths when needed.

  **Must NOT do**:
  - Do not repurpose undo/redo/focus toggle commands.
  - Do not alter settings window behavior.

  **Recommended Agent Profile**:
  - Category: `unspecified-low` — Reason: targeted command integration.
  - Skills: [`karpathy-guidelines`] — avoid side effects in global command map.
  - Omitted: [`frontend-ui-ux`] — no visual redesign.

  **Parallelization**: Can Parallel: NO | Wave 1 | Blocks: [5,6,7] | Blocked By: [1,2]

  **References** (executor has NO interview context — be exhaustive):
  - `wa/waApp.swift:108` — command group replacement pattern.
  - `wa/waApp.swift:119` — command insertion after text editing.
  - `wa/waApp.swift:307` — window loop + skip logic.
  - `wa/waApp.swift:312` — `NSPanel` skip branch.

  **Acceptance Criteria** (agent-executable only):
  - [ ] Source contains command/menu trigger for monitor window.
  - [ ] Existing undo/redo/focus commands remain present and unchanged.
  - [ ] Monitor window is explicitly covered by lifecycle safety checks.

  **QA Scenarios** (MANDATORY — task incomplete without these):
  ```
  Scenario: Command integration present and legacy commands preserved
    Tool: Bash
    Steps: run `python3 - <<'PY'
from pathlib import Path
t=Path('wa/waApp.swift').read_text(encoding='utf-8')
checks={
  'has_monitor_command': ('monitor' in t.lower()) or ('diagnostic' in t.lower()),
  'has_undo_command': 'waUndoRequested' in t,
  'has_redo_command': 'waRedoRequested' in t,
  'has_focus_toggle_command': 'waToggleFocusModeRequested' in t,
}
Path('.sisyphus/evidence/task-4-command-routing.txt').write_text('\n'.join(f"{k}={'PASS' if v else 'FAIL'}" for k,v in checks.items()), encoding='utf-8')
raise SystemExit(0 if all(checks.values()) else 1)
PY`
    Expected: all checks PASS
    Evidence: .sisyphus/evidence/task-4-command-routing.txt

  Scenario: Window lifecycle safety check remains explicit
    Tool: Bash
    Steps: run `python3 - <<'PY'
from pathlib import Path
t=Path('wa/waApp.swift').read_text(encoding='utf-8')
ok='window is NSPanel' in t and 'configureWindows' in t
Path('.sisyphus/evidence/task-4-window-safety.txt').write_text('PASS' if ok else 'FAIL', encoding='utf-8')
raise SystemExit(0 if ok else 1)
PY`
    Expected: writes `PASS`
    Evidence: .sisyphus/evidence/task-4-window-safety.txt
  ```

  **Commit**: NO | Message: `n/a` | Files: [`wa/waApp.swift`]

- [x] 5. Instrument Focus-Mode Decision Hotspots with Structured Events

  **What to do**:
  - Add recorder hooks at these exact focus-mode paths:
    - width/height measurement decisions in `FocusModeCardEditor.refreshMeasuredHeights`
    - geometry normalization in `applyFocusModeTextViewGeometryIfNeeded`
    - normalization request/run in `requestFocusModeOffsetNormalization` + `normalizeInactiveFocusModeTextEditorOffsets`
    - caret/selection scheduler in `startFocusModeCaretMonitor` + `requestFocusModeCaretEnsure`
    - caret visibility resolution in `ensureFocusModeCaretVisible`
    - panel frame change and active-card transitions in `focusModeCanvas` onChange handlers
  - Emit log events with consistent names + payload keys from Task 1 schema.
  - Ensure instrumentation does not alter existing logic paths (log-only side effects).

  **Must NOT do**:
  - Do not emit full card content.
  - Do not add new event monitors or timers beyond existing flows.

  **Recommended Agent Profile**:
  - Category: `unspecified-high` — Reason: high-density instrumentation around sensitive behavior.
  - Skills: [`karpathy-guidelines`] — surgical insertion with no behavior changes.
  - Omitted: [`playwright`] — source/evidence based verification is sufficient here.

  **Parallelization**: Can Parallel: NO | Wave 1 | Blocks: [6,7] | Blocked By: [2,3,4]

  **References** (executor has NO interview context — be exhaustive):
  - `wa/WriterCardViews.swift:200` — measurement refresh entrypoint.
  - `wa/WriterFocusMode.swift:410` — target container width computation.
  - `wa/WriterFocusMode.swift:562` — normalization request with reason.
  - `wa/WriterFocusMode.swift:588` — normalization burst scheduler.
  - `wa/WriterFocusMode.swift:622` — selection monitor hook.
  - `wa/WriterFocusMode.swift:716` — caret ensure scheduler.
  - `wa/WriterFocusMode.swift:759` — caret visible resolver.
  - `wa/WriterViews.swift:116` — observed body cache state map.

  **Acceptance Criteria** (agent-executable only):
  - [ ] Every hotspot emits at least one structured event when recording is enabled.
  - [ ] Recording disabled path avoids payload assembly and event append.
  - [ ] Text content is not logged in raw form.

  **QA Scenarios** (MANDATORY — task incomplete without these):
  ```
  Scenario: Hotspot instrumentation coverage exists
    Tool: Bash
    Steps: run `python3 - <<'PY'
from pathlib import Path
focus=Path('wa/WriterFocusMode.swift').read_text(encoding='utf-8')
card=Path('wa/WriterCardViews.swift').read_text(encoding='utf-8')
checks={
  'has_measurement_logging': 'refreshMeasuredHeights' in card and ('monitor' in card.lower() or 'record(' in card),
  'has_normalization_logging': 'requestFocusModeOffsetNormalization' in focus and ('monitor' in focus.lower() or 'record(' in focus),
  'has_caret_logging': 'requestFocusModeCaretEnsure' in focus and ('monitor' in focus.lower() or 'record(' in focus),
}
Path('.sisyphus/evidence/task-5-hotspot-coverage.txt').write_text('\n'.join(f"{k}={'PASS' if v else 'FAIL'}" for k,v in checks.items()), encoding='utf-8')
raise SystemExit(0 if all(checks.values()) else 1)
PY`
    Expected: all checks PASS
    Evidence: .sisyphus/evidence/task-5-hotspot-coverage.txt

  Scenario: Privacy guard prevents raw content capture
    Tool: Bash
    Steps: run `python3 - <<'PY'
from pathlib import Path
blob='\n'.join(Path(p).read_text(encoding='utf-8') for p in Path('wa').glob('*.swift'))
ok=('FOCUS_MONITOR_PRIVACY_SENTINEL' in blob) or ('textLength' in blob and 'content' in blob)
Path('.sisyphus/evidence/task-5-privacy-guard.txt').write_text('PASS' if ok else 'FAIL', encoding='utf-8')
raise SystemExit(0 if ok else 1)
PY`
    Expected: writes `PASS`
    Evidence: .sisyphus/evidence/task-5-privacy-guard.txt
  ```

  **Commit**: NO | Message: `n/a` | Files: [`wa/WriterCardViews.swift`, `wa/WriterFocusMode.swift`, `wa/WriterViews.swift`]

- [x] 6. Add Monitor Smoke Hooks and Execute Verification Bundle

  **What to do**:
  - Add `WA_FOCUS_MONITOR_SMOKETEST=1` startup path in `wa/waApp.swift` that:
    - boots recorder in deterministic mode,
    - appends representative sample events,
    - validates sequence monotonicity + non-empty snapshot,
    - validates privacy sentinel exclusion,
    - prints `FOCUS_MONITOR_SMOKETEST_OK` and exits 0 on pass.
  - Preserve existing `WA_LAYOUT_SMOKETEST=1` flow.
  - Run full build + both smoke hooks and static invariant checks.

  **Must NOT do**:
  - Do not require manual UI interaction for smoke tests.
  - Do not remove existing smoke outputs used in previous plans.

  **Recommended Agent Profile**:
  - Category: `quick` — Reason: deterministic validation and evidence generation.
  - Skills: [`karpathy-guidelines`] — binary pass/fail checks.
  - Omitted: [`git-master`] — no git operations.

  **Parallelization**: Can Parallel: NO | Wave 2 | Blocks: [7] | Blocked By: [2,3,4,5]

  **References** (executor has NO interview context — be exhaustive):
  - `wa/waApp.swift:32` — existing env-driven smoke hook style.
  - `wa/waApp.swift:133` — existing `runLayoutSmokeTestAndTerminate()`.
  - `wa/waApp.swift:149` — current layout smoke assertions.

  **Acceptance Criteria** (agent-executable only):
  - [ ] Build log contains `BUILD SUCCEEDED`.
  - [ ] Layout smoke log contains `FOCUS_MODE_LAYOUT_SMOKETEST_OK`.
  - [ ] Monitor smoke log contains `FOCUS_MONITOR_SMOKETEST_OK`.
  - [ ] Privacy smoke log does not contain sentinel value.

  **QA Scenarios** (MANDATORY — task incomplete without these):
  ```
  Scenario: Build and layout smoke pass
    Tool: Bash
    Steps: run `xcodebuild -project wa.xcodeproj -target wa -configuration Debug -destination 'platform=macOS' build | tee .sisyphus/evidence/task-6-build.log && WA_LAYOUT_SMOKETEST=1 ./build/Debug/WTF.app/Contents/MacOS/WTF > .sisyphus/evidence/task-6-layout-smoketest.txt`
    Expected: build log has `BUILD SUCCEEDED`, layout smoke log has `FOCUS_MODE_LAYOUT_SMOKETEST_OK`
    Evidence: .sisyphus/evidence/task-6-build.log

  Scenario: Focus monitor smoke and privacy guard pass
    Tool: Bash
    Steps: run `WA_FOCUS_MONITOR_SMOKETEST=1 ./build/Debug/WTF.app/Contents/MacOS/WTF > .sisyphus/evidence/task-6-monitor-smoketest.txt && WA_FOCUS_MONITOR_SMOKETEST=1 WA_FOCUS_MONITOR_PRIVACY_SENTINEL=DO_NOT_LEAK ./build/Debug/WTF.app/Contents/MacOS/WTF > .sisyphus/evidence/task-6-monitor-privacy.txt`
    Expected: monitor smoke log has `FOCUS_MONITOR_SMOKETEST_OK`; privacy log excludes `DO_NOT_LEAK`
    Evidence: .sisyphus/evidence/task-6-monitor-smoketest.txt

  Scenario: Static monitor invariants pass
    Tool: Bash
    Steps: run `python3 - <<'PY'
from pathlib import Path
blob='\n'.join(Path(p).read_text(encoding='utf-8') for p in Path('wa').glob('*.swift'))
checks={
  'has_monitor_smoke_hook':'WA_FOCUS_MONITOR_SMOKETEST' in blob,
  'has_monitor_ok_token':'FOCUS_MONITOR_SMOKETEST_OK' in blob,
  'has_layout_smoke_hook':'WA_LAYOUT_SMOKETEST' in blob,
}
Path('.sisyphus/evidence/task-6-monitor-invariants.txt').write_text('\n'.join(f"{k}={'PASS' if v else 'FAIL'}" for k,v in checks.items()), encoding='utf-8')
raise SystemExit(0 if all(checks.values()) else 1)
PY`
    Expected: all checks PASS
    Evidence: .sisyphus/evidence/task-6-monitor-invariants.txt
  ```

  **Commit**: NO | Message: `n/a` | Files: [`wa/waApp.swift`, `.sisyphus/evidence/*`]

- [x] 7. Final Scope Gate + Evidence Integrity Bundle

  **What to do**:
  - Produce final changed-file manifest vs Task 1 baseline.
  - Enforce allowed source scope:
    - `wa/waApp.swift`
    - `wa/WriterViews.swift`
    - `wa/WriterFocusMode.swift`
    - `wa/WriterCardViews.swift`
    - `wa/WriterSharedTypes.swift`
    - optional new monitor-specific files under `wa/` only
  - Reject any changes to unrelated files.
  - Produce final evidence summary for user copy/paste handoff.

  **Must NOT do**:
  - Do not complete if out-of-scope file changes remain.

  **Recommended Agent Profile**:
  - Category: `quick` — Reason: deterministic closure checks.
  - Skills: [`karpathy-guidelines`] — strict scope fidelity.
  - Omitted: [`playwright`] — scope audit is static.

  **Parallelization**: Can Parallel: NO | Wave 2 | Blocks: [] | Blocked By: [1,5,6]

  **References** (executor has NO interview context — be exhaustive):
  - Baseline: `.sisyphus/evidence/baseline-focus-monitor/*.swift`
  - Build/smoke logs: `.sisyphus/evidence/task-6-*.txt`, `.sisyphus/evidence/task-6-build.log`

  **Acceptance Criteria** (agent-executable only):
  - [ ] `.sisyphus/evidence/task-7-changed-files.txt` exists and lists changed files.
  - [ ] `.sisyphus/evidence/task-7-scope-check.txt` is `PASS`.
  - [ ] `.sisyphus/evidence/task-7-handoff-summary.txt` exists with key evidence pointers.

  **QA Scenarios** (MANDATORY — task incomplete without these):
  ```
  Scenario: Changed-file manifest and scope check generated
    Tool: Bash
    Steps: run `python3 - <<'PY'
from pathlib import Path
import hashlib
base=Path('.sisyphus/evidence/baseline-focus-monitor')
pairs=[]
for p in sorted(base.glob('*.swift')):
  pairs.append((p.name, Path('wa')/p.name))
changed=[]
for b,c in pairs:
  hb=hashlib.sha256((base/b).read_bytes()).hexdigest()
  hc=hashlib.sha256(c.read_bytes()).hexdigest()
  if hb!=hc:
    changed.append(c.as_posix())
Path('.sisyphus/evidence/task-7-changed-files.txt').write_text('\n'.join(changed), encoding='utf-8')
allowed={
  'wa/waApp.swift','wa/WriterViews.swift','wa/WriterFocusMode.swift','wa/WriterCardViews.swift','wa/WriterSharedTypes.swift'
}
bad=[f for f in changed if f not in allowed and 'Monitor' not in f]
Path('.sisyphus/evidence/task-7-scope-check.txt').write_text('PASS' if not bad else '\n'.join(bad), encoding='utf-8')
raise SystemExit(0 if not bad else 1)
PY`
    Expected: scope check is PASS
    Evidence: .sisyphus/evidence/task-7-scope-check.txt

  Scenario: Handoff evidence summary generated
    Tool: Bash
    Steps: run `python3 - <<'PY'
from pathlib import Path
lines=[
  'build=.sisyphus/evidence/task-6-build.log',
  'layout_smoke=.sisyphus/evidence/task-6-layout-smoketest.txt',
  'monitor_smoke=.sisyphus/evidence/task-6-monitor-smoketest.txt',
  'privacy=.sisyphus/evidence/task-6-monitor-privacy.txt',
  'scope=.sisyphus/evidence/task-7-scope-check.txt',
]
Path('.sisyphus/evidence/task-7-handoff-summary.txt').write_text('\n'.join(lines), encoding='utf-8')
PY`
    Expected: handoff summary file exists with references
    Evidence: .sisyphus/evidence/task-7-handoff-summary.txt
  ```

  **Commit**: NO | Message: `n/a` | Files: [`.sisyphus/evidence/*`]

## Final Verification Wave (4 parallel agents, ALL must APPROVE)
- [x] F1. Plan Compliance Audit - oracle
- [x] F2. Code Quality Review - unspecified-high
- [x] F3. Real Manual QA - unspecified-high (+ playwright if UI)
- [x] F4. Scope Fidelity Check - deep

## Commit Strategy
- Single atomic commit after Task 7:
  - `feat(focus-mode): add live diagnostics monitor window for layout signal capture`

## Success Criteria
- User can reproduce regression while monitor runs, copy logs, and share directly.
- Captured logs are sufficient to explain short-card expansion path (inputs, decisions, triggers).
- Existing focus-mode behavior remains functionally unchanged except added observability.
