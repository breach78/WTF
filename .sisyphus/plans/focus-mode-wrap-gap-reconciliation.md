# Focus Mode Wrap/Bottom-Gap Reconciliation

## TL;DR
> **Summary**: Resolve the shared root cause behind long-card bottom blank space and premature right-edge wrapping by restoring runtime layout parity between deterministic measurement and real `NSTextView` geometry in Focus Mode.
> **Deliverables**:
> - Focus-mode text container geometry normalization path (width/inset/padding parity)
> - Minimal active-card observed reconciliation with debounce + threshold guardrails
> - Width-budget parity between measurement and rendered editor
> - Automated non-interactive layout smoke verification + build evidence
> **Effort**: Medium
> **Parallel**: YES - 2 waves
> **Critical Path**: Task 1 -> Task 2 -> Task 3 -> Task 4 -> Task 6

## Context
### Original Request
User confirms wobble is gone, but reports two remaining regressions in Focus Mode: (1) very long cards keep extra bottom blank space even after click, and (2) lines wrap before reaching visual right edge. User expects both to be solved together as one shared cause.

### Interview Summary
- Focus is regression correction only (no visual redesign).
- Two symptoms are treated as one shared-cause class.
- Prior deterministic-only fix removed wobble but likely over-removed runtime reconciliation.

### Metis Review (gaps addressed)
- Missing acceptance depth for visual regressions: add automated non-interactive smoke verification.
- Avoid broad redesign; use minimal-risk normalization and guarded reconciliation.
- Guard against feedback loops by debouncing/thresholding runtime correction updates.
- Validate against width/inset parity to prevent early-wrap drift.

## Work Objectives
### Core Objective
Restore Focus Mode layout correctness for long-card bottom space and right-edge wrapping by aligning deterministic measurement assumptions with real runtime `NSTextView` geometry and adding minimal guarded reconciliation where needed.

### Deliverables
- Focus-mode text-view normalization helper modeled after proven main-editor pattern.
- Focus-mode measurement/render width parity updates in `wa/WriterCardViews.swift`.
- Minimal active-card observed-height reconciliation pipeline in `wa/WriterFocusMode.swift` + `wa/WriterViews.swift`.
- Automated evidence outputs under `.sisyphus/evidence/` including build and layout-smoke checks.

### Definition of Done (verifiable conditions with commands)
- `xcodebuild -project wa.xcodeproj -target wa -configuration Debug -destination 'platform=macOS' build` reports `BUILD SUCCEEDED`.
- `FOCUS_MODE_LAYOUT_SMOKETEST_OK` is emitted by a non-interactive debug smoke path and captured in evidence.
- `.sisyphus/evidence/task-6-invariants.txt` reports all checks `PASS`.
- `.sisyphus/evidence/task-7-scope-check.txt` reports `PASS`.

### Must Have
- Long focus cards no longer keep persistent extra bottom blank area after focus/click transitions.
- Focus-mode lines no longer wrap prematurely before visual right edge.
- Wobble fix remains stable (no reintroduction of active/inactive vertical jump loop).
- Runtime reconciliation path is bounded (debounce + threshold), not continuous churn.

### Must NOT Have (guardrails, AI slop patterns, scope boundaries)
- No replacement of `TextEditor` with custom editor architecture.
- No redesign of Focus Mode visuals/theme.
- No broad refactor outside focus-mode sizing/offset/caret-flow files.
- No unbounded observed-height feedback loop.

## Verification Strategy
> ZERO HUMAN INTERVENTION - all verification is agent-executed.
- Test decision: tests-after + build + debug smoke verification.
- QA policy: every task includes happy + failure/edge checks.
- Evidence: `.sisyphus/evidence/task-{N}-{slug}.{ext}`.

## Execution Strategy
### Parallel Execution Waves
> Target: 5-8 tasks per wave. <3 per wave (except final) = under-splitting.
> Shared dependencies are front-loaded for safe parallelization.

Wave 1: Baseline capture + geometry normalization + width parity + guarded reconciliation (Tasks 1-4)
Wave 2: Trigger integration + verification bundle + scope gate (Tasks 5-7)

### Dependency Matrix (full, all tasks)
- Task 1: Blocked By [] | Blocks [2,3,4,7]
- Task 2: Blocked By [1] | Blocks [3,4,5,6]
- Task 3: Blocked By [1,2] | Blocks [4,6]
- Task 4: Blocked By [1,2,3] | Blocks [5,6,7]
- Task 5: Blocked By [2,4] | Blocks [6,7]
- Task 6: Blocked By [2,3,4,5] | Blocks [7]
- Task 7: Blocked By [1,4,5,6] | Blocks []

### Agent Dispatch Summary (wave -> task count -> categories)
- Wave 1 -> 4 tasks -> `quick`, `unspecified-low`, `unspecified-high`
- Wave 2 -> 3 tasks -> `quick`, `unspecified-high`

## TODOs
> Implementation + Test = ONE task. Never separate.
> EVERY task MUST have: Agent Profile + Parallelization + QA Scenarios.

- [x] 1. Baseline + Regression Capture for Focus Layout Paths

  **What to do**: Snapshot current focus-layout source files and generate baseline evidence for the new regression-fix wave.
  - Copy source snapshots to `.sisyphus/evidence/baseline-wrap-gap/`:
    - `wa/WriterCardViews.swift`
    - `wa/WriterFocusMode.swift`
    - `wa/WriterViews.swift`
    - `wa/WriterCaretAndScroll.swift` (reference pattern guard)
    - `wa/WriterSharedTypes.swift`
  - Generate SHA256 manifest.

  **Must NOT do**: Modify source files in this task.

  **Recommended Agent Profile**:
  - Category: `quick` - Reason: deterministic evidence setup.
  - Skills: [`karpathy-guidelines`] - strict reproducibility discipline.
  - Omitted: [`git-master`] - no git workflow needed.

  **Parallelization**: Can Parallel: NO | Wave 1 | Blocks: [2,3,4,7] | Blocked By: []

  **References** (executor has NO interview context - be exhaustive):
  - Pattern: `wa/WriterCardViews.swift:191` - focus width budget input (`textEditorMeasureWidth`).
  - Pattern: `wa/WriterCardViews.swift:224` - focus horizontal padding applied to `TextEditor`.
  - Pattern: `wa/WriterFocusMode.swift:409` - offset normalization path currently reset-only.
  - Pattern: `wa/WriterCaretAndScroll.swift:150` - proven runtime text-container normalization pattern.

  **Acceptance Criteria** (agent-executable only):
  - [ ] `.sisyphus/evidence/baseline-wrap-gap/` contains 5 snapshot files.
  - [ ] `.sisyphus/evidence/task-1-wrap-gap-baseline-sha256.txt` exists with 5 entries.

  **QA Scenarios** (MANDATORY - task incomplete without these):
  ```
  Scenario: Baseline capture succeeds
    Tool: Bash
    Steps: run `mkdir -p .sisyphus/evidence/baseline-wrap-gap && cp wa/WriterCardViews.swift wa/WriterFocusMode.swift wa/WriterViews.swift wa/WriterCaretAndScroll.swift wa/WriterSharedTypes.swift .sisyphus/evidence/baseline-wrap-gap/ && shasum -a 256 .sisyphus/evidence/baseline-wrap-gap/*.swift > .sisyphus/evidence/task-1-wrap-gap-baseline-sha256.txt`
    Expected: snapshot directory and SHA manifest created
    Evidence: .sisyphus/evidence/task-1-wrap-gap-baseline-sha256.txt

  Scenario: Baseline completeness guard
    Tool: Bash
    Steps: run `python3 - <<'PY'
from pathlib import Path
expected={'WriterCardViews.swift','WriterFocusMode.swift','WriterViews.swift','WriterCaretAndScroll.swift','WriterSharedTypes.swift'}
actual={p.name for p in Path('.sisyphus/evidence/baseline-wrap-gap').glob('*.swift')}
missing=sorted(expected-actual)
Path('.sisyphus/evidence/task-1-wrap-gap-baseline-check.txt').write_text('PASS' if not missing else '\n'.join(missing), encoding='utf-8')
raise SystemExit(0 if not missing else 1)
PY`
    Expected: script exits 0 and writes `PASS`
    Evidence: .sisyphus/evidence/task-1-wrap-gap-baseline-check.txt
  ```

  **Commit**: NO | Message: `n/a` | Files: [`.sisyphus/evidence/*`]

- [x] 2. Add Focus-Mode NSTextView Geometry Normalization (Width/Inset/Padding Parity)

  **What to do**: Introduce a focus-mode runtime normalization helper (active responder scoped) to align real `NSTextView` geometry with measurement assumptions.
  - In `wa/WriterFocusMode.swift`, add helper(s) to:
    - Ensure focus `NSTextView` uses expected line break mode.
    - Normalize `textContainerInset` and `lineFragmentPadding` parity assumptions.
    - Set deterministic container width using current viewport/card width budget.
    - Reset inner scroll offsets only when needed (preserve current behavior intent).
  - Reuse logic shape from main editor pattern in `wa/WriterCaretAndScroll.swift` while keeping focus scope minimal.

  **Must NOT do**: Introduce continuous all-textview scanning on every keystroke.

  **Recommended Agent Profile**:
  - Category: `unspecified-high` - Reason: TextKit geometry changes are regression-prone.
  - Skills: [`karpathy-guidelines`] - avoid overreach and preserve behavior contracts.
  - Omitted: [`frontend-ui-ux`] - no visual redesign required.

  **Parallelization**: Can Parallel: NO | Wave 1 | Blocks: [3,4,5,6] | Blocked By: [1]

  **References** (executor has NO interview context - be exhaustive):
  - Pattern: `wa/WriterCaretAndScroll.swift:150` - main-editor normalization entrypoint.
  - Pattern: `wa/WriterCaretAndScroll.swift:179` - `textContainerInset = .zero` normalization.
  - Pattern: `wa/WriterCaretAndScroll.swift:187` - lineFragmentPadding parity set.
  - Pattern: `wa/WriterCaretAndScroll.swift:200` - container width assignment (`containerSize.width`).
  - Integration site: `wa/WriterFocusMode.swift:595` - caret ensure request flow.
  - Integration site: `wa/WriterFocusMode.swift:409` - existing focus normalization function.

  **Acceptance Criteria** (agent-executable only):
  - [ ] Focus-mode source includes active-responder geometry normalization helper.
  - [ ] Helper is called from at least one stable focus transition path (entry/caret/panel-width change).
  - [ ] Build succeeds after the change.

  **QA Scenarios** (MANDATORY - task incomplete without these):
  ```
  Scenario: Focus geometry helper and callsites exist
    Tool: Bash
    Steps: run `python3 - <<'PY'
from pathlib import Path
text=Path('wa/WriterFocusMode.swift').read_text(encoding='utf-8')
checks={
  'has_focus_geometry_helper':'textContainerInset' in text and 'lineFragmentPadding' in text,
  'has_focus_geometry_callsite':'requestFocusModeCaretEnsure' in text and 'requestFocusModeOffsetNormalization' in text,
}
Path('.sisyphus/evidence/task-2-focus-geometry-check.txt').write_text('\n'.join(f"{k}={'PASS' if v else 'FAIL'}" for k,v in checks.items()), encoding='utf-8')
raise SystemExit(0 if all(checks.values()) else 1)
PY`
    Expected: all checks PASS
    Evidence: .sisyphus/evidence/task-2-focus-geometry-check.txt

  Scenario: Failure guard for main-editor normalization regression
    Tool: Bash
    Steps: run `python3 - <<'PY'
from pathlib import Path
text=Path('wa/WriterCaretAndScroll.swift').read_text(encoding='utf-8')
ok='func applyMainEditorLineSpacingIfNeeded' in text and 'textView.textContainerInset = .zero' in text
Path('.sisyphus/evidence/task-2-main-pattern-guard.txt').write_text('PASS' if ok else 'FAIL', encoding='utf-8')
raise SystemExit(0 if ok else 1)
PY`
    Expected: guard remains PASS
    Evidence: .sisyphus/evidence/task-2-main-pattern-guard.txt
  ```

  **Commit**: NO | Message: `n/a` | Files: [`wa/WriterFocusMode.swift`]

- [x] 3. Reconcile Focus Width Budget to Eliminate Premature Wrap Drift

  **What to do**: Align focus-mode measurement width and rendered text width assumptions.
  - Update `wa/WriterCardViews.swift` so measurement width budget and rendered editor padding/inset semantics match.
  - If needed, define explicit focus-mode layout metrics (similar to `MainEditorLayoutMetrics`) in `wa/WriterSharedTypes.swift` for single-source-of-truth values.
  - Preserve current visual intent (no perceptible design change).

  **Must NOT do**: Increase/decrease visible side margins as a UX redesign.

  **Recommended Agent Profile**:
  - Category: `unspecified-low` - Reason: targeted metric reconciliation.
  - Skills: [`karpathy-guidelines`] - strict width budget parity.
  - Omitted: [`playwright`] - native view layout change verified via build/smoke checks.

  **Parallelization**: Can Parallel: NO | Wave 1 | Blocks: [4,6] | Blocked By: [1,2]

  **References** (executor has NO interview context - be exhaustive):
  - Pattern: `wa/WriterCardViews.swift:191` - current width computation.
  - Pattern: `wa/WriterCardViews.swift:224` - current horizontal padding.
  - Pattern: `wa/WriterCardViews.swift:119` - lineFragmentPadding constant in measurement path.
  - Pattern: `wa/WriterSharedTypes.swift:6` - main-editor split metric pattern (`contentPadding - lineFragmentPadding`).

  **Acceptance Criteria** (agent-executable only):
  - [ ] Focus measurement and rendered width budgets are explicitly reconciled in source.
  - [ ] No hardcoded “magic drift” compensation without named rationale/metric.
  - [ ] Build succeeds after change.

  **QA Scenarios** (MANDATORY - task incomplete without these):
  ```
  Scenario: Width budget reconciliation present
    Tool: Bash
    Steps: run `python3 - <<'PY'
from pathlib import Path
card=Path('wa/WriterCardViews.swift').read_text(encoding='utf-8')
checks={
  'has_text_editor_measure_width':'textEditorMeasureWidth' in card,
  'has_explicit_padding_budget':'padding(.horizontal' in card,
}
Path('.sisyphus/evidence/task-3-width-budget-check.txt').write_text('\n'.join(f"{k}={'PASS' if v else 'FAIL'}" for k,v in checks.items()), encoding='utf-8')
raise SystemExit(0 if all(checks.values()) else 1)
PY`
    Expected: PASS checks
    Evidence: .sisyphus/evidence/task-3-width-budget-check.txt

  Scenario: Failure guard for accidental focus-style drift
    Tool: Bash
    Steps: run `python3 - <<'PY'
from pathlib import Path
text=Path('wa/WriterCardViews.swift').read_text(encoding='utf-8')
ok='background(isActive ? Color.accentColor.opacity(0.06) : Color.clear)' in text
Path('.sisyphus/evidence/task-3-style-guard.txt').write_text('PASS' if ok else 'FAIL', encoding='utf-8')
raise SystemExit(0 if ok else 1)
PY`
    Expected: style guard PASS
    Evidence: .sisyphus/evidence/task-3-style-guard.txt
  ```

  **Commit**: NO | Message: `n/a` | Files: [`wa/WriterCardViews.swift`, `wa/WriterSharedTypes.swift`]

- [x] 4. Reintroduce Minimal Active-Card Runtime Reconciliation (Debounced + Thresholded)

  **What to do**: Re-add only the minimal observed runtime correction needed to prevent persistent deterministic drift for long cards.
  - Restore focus observed state in `wa/WriterViews.swift` for active/focused card reconciliation.
  - In `wa/WriterFocusMode.swift`, collect observed body height from active/focused responder using stable mapping and update cache only when drift exceeds threshold.
  - In `wa/WriterCardViews.swift`, accept optional observed body and clamp deterministic height upward (`max(deterministic, observed)`) with bounded updates.
  - On panel-width change, clear observed cache to prevent stale carryover.

  **Must NOT do**: Reintroduce unbounded, all-card continuous observed feedback loop.

  **Recommended Agent Profile**:
  - Category: `unspecified-high` - Reason: high regression risk if loop/churn returns.
  - Skills: [`karpathy-guidelines`] - enforce bounded correction policy.
  - Omitted: [`frontend-ui-ux`] - behavioral/layout correctness task only.

  **Parallelization**: Can Parallel: NO | Wave 1 | Blocks: [5,6,7] | Blocked By: [1,2,3]

  **References** (executor has NO interview context - be exhaustive):
  - Baseline pattern: `.sisyphus/evidence/baseline-wrap-gap/WriterViews.swift` - observed state location reference snapshot.
  - Baseline pattern: `.sisyphus/evidence/baseline-wrap-gap/WriterFocusMode.swift` - observed sampling path reference snapshot.
  - Baseline pattern: `.sisyphus/evidence/baseline-wrap-gap/WriterCardViews.swift` - active clamp reference snapshot.
  - Current integration: `wa/WriterFocusMode.swift:113` - panel width-change hook.
  - Current mapping basis: `wa/WriterViews.swift:93` - `focusResponderCardByObjectID`.

  **Acceptance Criteria** (agent-executable only):
  - [ ] Observed reconciliation exists but is bounded (threshold/debounce/active-scoped).
  - [ ] Panel width changes clear or invalidate observed cache.
  - [ ] Build succeeds after change.

  **QA Scenarios** (MANDATORY - task incomplete without these):
  ```
  Scenario: Minimal observed reconciliation path restored with bounds
    Tool: Bash
    Steps: run `python3 - <<'PY'
from pathlib import Path
views=Path('wa/WriterViews.swift').read_text(encoding='utf-8')
focus=Path('wa/WriterFocusMode.swift').read_text(encoding='utf-8')
card=Path('wa/WriterCardViews.swift').read_text(encoding='utf-8')
checks={
  'has_observed_state':'focusObservedBodyHeightByCardID' in views,
  'has_observed_sampling':'focusObservedBodyHeightByCardID' in focus and 'usedRect(for: textContainer)' in focus,
  'has_clamp_logic':'max(' in card and 'observed' in card,
}
Path('.sisyphus/evidence/task-4-observed-reconcile-check.txt').write_text('\n'.join(f"{k}={'PASS' if v else 'FAIL'}" for k,v in checks.items()), encoding='utf-8')
raise SystemExit(0 if all(checks.values()) else 1)
PY`
    Expected: all checks PASS
    Evidence: .sisyphus/evidence/task-4-observed-reconcile-check.txt

  Scenario: Failure guard for stale-cache carryover on panel width change
    Tool: Bash
    Steps: run `python3 - <<'PY'
from pathlib import Path
focus=Path('wa/WriterFocusMode.swift').read_text(encoding='utf-8')
ok='panel-width-change' in focus and 'focusObservedBodyHeightByCardID.removeAll()' in focus
Path('.sisyphus/evidence/task-4-cache-invalidate-guard.txt').write_text('PASS' if ok else 'FAIL', encoding='utf-8')
raise SystemExit(0 if ok else 1)
PY`
    Expected: guard PASS
    Evidence: .sisyphus/evidence/task-4-cache-invalidate-guard.txt
  ```

  **Commit**: NO | Message: `n/a` | Files: [`wa/WriterViews.swift`, `wa/WriterFocusMode.swift`, `wa/WriterCardViews.swift`]

- [x] 5. Integrate Stable Trigger Policy (No Churn, No Sticky Gap)

  **What to do**: Connect normalization/reconciliation triggers to stable lifecycle points only.
  - Ensure focus entry, panel-width change, and caret ensure paths invoke the right combination of:
    - geometry normalization
    - offset normalization
    - bounded reconciliation
  - Reduce duplicate/burst trigger overlap that can reintroduce visual jump.
  - Keep scroll-end normalization behavior intact.

  **Must NOT do**: Remove caret visibility logic or typewriter behavior.

  **Recommended Agent Profile**:
  - Category: `unspecified-low` - Reason: trigger orchestration with bounded risk.
  - Skills: [`karpathy-guidelines`] - preserve existing interaction contracts.
  - Omitted: [`playwright`] - validated by deterministic checks + build.

  **Parallelization**: Can Parallel: NO | Wave 2 | Blocks: [6,7] | Blocked By: [2,4]

  **References** (executor has NO interview context - be exhaustive):
  - Pattern: `wa/WriterFocusMode.swift:468` - normalization burst schedule.
  - Pattern: `wa/WriterFocusMode.swift:595` - caret ensure scheduling entry.
  - Pattern: `wa/WriterFocusMode.swift:408` - offset normalization function.
  - Pattern: `wa/WriterFocusMode.swift:396` - scroll-ended normalization trigger.

  **Acceptance Criteria** (agent-executable only):
  - [ ] Trigger graph avoids redundant churn loops in steady typing/selection.
  - [ ] Scroll-end normalization trigger remains present.
  - [ ] Build succeeds.

  **QA Scenarios** (MANDATORY - task incomplete without these):
  ```
  Scenario: Trigger policy contains required paths without missing core hooks
    Tool: Bash
    Steps: run `python3 - <<'PY'
from pathlib import Path
text=Path('wa/WriterFocusMode.swift').read_text(encoding='utf-8')
checks={
  'has_scroll_end_trigger':'requestFocusModeOffsetNormalization(reason: "scroll-ended")' in text,
  'has_caret_ensure_flow':'requestFocusModeCaretEnsure' in text and 'ensureFocusModeCaretVisible' in text,
  'has_burst_scheduler':'scheduleFocusModeOffsetNormalizationBurst' in text,
}
Path('.sisyphus/evidence/task-5-trigger-policy-check.txt').write_text('\n'.join(f"{k}={'PASS' if v else 'FAIL'}" for k,v in checks.items()), encoding='utf-8')
raise SystemExit(0 if all(checks.values()) else 1)
PY`
    Expected: all checks PASS
    Evidence: .sisyphus/evidence/task-5-trigger-policy-check.txt

  Scenario: Failure guard for unrelated main-scroll behavior edits
    Tool: Bash
    Steps: run `diff -u .sisyphus/evidence/baseline-wrap-gap/WriterCaretAndScroll.swift wa/WriterCaretAndScroll.swift > .sisyphus/evidence/task-5-main-scroll-guard.diff || true`
    Expected: diff is empty
    Evidence: .sisyphus/evidence/task-5-main-scroll-guard.diff
  ```

  **Commit**: NO | Message: `n/a` | Files: [`wa/WriterFocusMode.swift`]

- [x] 6. Build + Non-Interactive Layout Smoke + Invariant Bundle

  **What to do**: Add a deterministic smoke-check path and execute full verification bundle.
  - Implement a DEBUG-only non-interactive layout smoke entry path that outputs `FOCUS_MODE_LAYOUT_SMOKETEST_OK` on success.
  - Run full build and capture output.
  - Run static invariants for wrap/gap reconciliation contracts.

  **Must NOT do**: Use manual-only visual checks as completion criteria.

  **Recommended Agent Profile**:
  - Category: `quick` - Reason: verification-heavy with bounded code touch.
  - Skills: [`karpathy-guidelines`] - binary pass/fail evidence discipline.
  - Omitted: [`frontend-ui-ux`] - no design work.

  **Parallelization**: Can Parallel: YES | Wave 2 | Blocks: [7] | Blocked By: [2,3,4,5]

  **References** (executor has NO interview context - be exhaustive):
  - App entry candidate: `wa/waApp.swift` (debug launch/environment hooks).
  - Focus-mode sizing path: `wa/WriterCardViews.swift:200`.
  - Focus-mode normalization path: `wa/WriterFocusMode.swift:409`.
  - Build target: `wa.xcodeproj`, target `wa`.

  **Acceptance Criteria** (agent-executable only):
  - [ ] `.sisyphus/evidence/task-6-build.log` contains `BUILD SUCCEEDED`.
  - [ ] `.sisyphus/evidence/task-6-layout-smoketest.txt` contains `FOCUS_MODE_LAYOUT_SMOKETEST_OK`.
  - [ ] `.sisyphus/evidence/task-6-invariants.txt` contains all PASS.

  **QA Scenarios** (MANDATORY - task incomplete without these):
  ```
  Scenario: Build succeeds after reconciliation changes
    Tool: Bash
    Steps: run `xcodebuild -project wa.xcodeproj -target wa -configuration Debug -destination 'platform=macOS' build | tee .sisyphus/evidence/task-6-build.log`
    Expected: build log contains `BUILD SUCCEEDED`
    Evidence: .sisyphus/evidence/task-6-build.log

  Scenario: Non-interactive layout smoke emits success token
    Tool: Bash
    Steps: run `WA_LAYOUT_SMOKETEST=1 ./build/Debug/WTF.app/Contents/MacOS/WTF > .sisyphus/evidence/task-6-layout-smoketest.txt`
    Expected: file contains exactly `FOCUS_MODE_LAYOUT_SMOKETEST_OK`
    Evidence: .sisyphus/evidence/task-6-layout-smoketest.txt

  Scenario: Static invariants for wrap/gap contracts
    Tool: Bash
    Steps: run `python3 - <<'PY'
from pathlib import Path
card=Path('wa/WriterCardViews.swift').read_text(encoding='utf-8')
focus=Path('wa/WriterFocusMode.swift').read_text(encoding='utf-8')
views=Path('wa/WriterViews.swift').read_text(encoding='utf-8')
checks={
  'focus_observed_state_present':'focusObservedBodyHeightByCardID' in views,
  'focus_uses_runtime_reconcile':'focusObservedBodyHeightByCardID' in focus,
  'card_has_measurement_path':'textEditorMeasureWidth' in card and 'measureBodyHeight' in card,
}
Path('.sisyphus/evidence/task-6-invariants.txt').write_text('\n'.join(f"{k}={'PASS' if v else 'FAIL'}" for k,v in checks.items()), encoding='utf-8')
raise SystemExit(0 if all(checks.values()) else 1)
PY`
    Expected: all checks PASS
    Evidence: .sisyphus/evidence/task-6-invariants.txt
  ```

  **Commit**: NO | Message: `n/a` | Files: [`.sisyphus/evidence/*`, `wa/waApp.swift`]

- [x] 7. Final Scope Gate + Changed-File Manifest (Wrap/Gap Wave)

  **What to do**: Enforce source-scope boundaries and produce final changed-file evidence.
  - Allowed source edit set:
    - `wa/WriterCardViews.swift`
    - `wa/WriterFocusMode.swift`
    - `wa/WriterViews.swift`
    - `wa/WriterSharedTypes.swift` (only if metric constants added)
    - `wa/waApp.swift` (only if smoke entry hook added)
  - `wa/WriterCaretAndScroll.swift` must remain unchanged.

  **Must NOT do**: Complete if out-of-scope source edits exist.

  **Recommended Agent Profile**:
  - Category: `quick` - Reason: deterministic closure gate.
  - Skills: [`karpathy-guidelines`] - strict scope fidelity.
  - Omitted: [`git-master`] - hash/diff scope validation only.

  **Parallelization**: Can Parallel: NO | Wave 2 | Blocks: [] | Blocked By: [1,4,5,6]

  **References** (executor has NO interview context - be exhaustive):
  - Baseline snapshots: `.sisyphus/evidence/baseline-wrap-gap/*.swift`.
  - Guard file: `.sisyphus/evidence/task-5-main-scroll-guard.diff`.

  **Acceptance Criteria** (agent-executable only):
  - [ ] `.sisyphus/evidence/task-7-changed-files.txt` exists.
  - [ ] `.sisyphus/evidence/task-7-scope-check.txt` contains `PASS`.

  **QA Scenarios** (MANDATORY - task incomplete without these):
  ```
  Scenario: Changed-file manifest generated vs baseline
    Tool: Bash
    Steps: run `python3 - <<'PY'
from pathlib import Path
import hashlib
pairs=[
 ('WriterCardViews.swift','wa/WriterCardViews.swift'),
 ('WriterFocusMode.swift','wa/WriterFocusMode.swift'),
 ('WriterViews.swift','wa/WriterViews.swift'),
 ('WriterSharedTypes.swift','wa/WriterSharedTypes.swift'),
 ('waApp.swift','wa/waApp.swift'),
 ('WriterCaretAndScroll.swift','wa/WriterCaretAndScroll.swift'),
]
base=Path('.sisyphus/evidence/baseline-wrap-gap')
changed=[]
for b,c in pairs:
  hb=hashlib.sha256((base/b).read_bytes()).hexdigest()
  hc=hashlib.sha256(Path(c).read_bytes()).hexdigest()
  if hb!=hc:
    changed.append(c)
Path('.sisyphus/evidence/task-7-changed-files.txt').write_text('\n'.join(changed), encoding='utf-8')
PY`
    Expected: changed manifest lists touched source files
    Evidence: .sisyphus/evidence/task-7-changed-files.txt

  Scenario: Out-of-scope edit guard
    Tool: Bash
    Steps: run `python3 - <<'PY'
from pathlib import Path
allowed={'wa/WriterCardViews.swift','wa/WriterFocusMode.swift','wa/WriterViews.swift','wa/WriterSharedTypes.swift','wa/waApp.swift'}
changed=[l.strip() for l in Path('.sisyphus/evidence/task-7-changed-files.txt').read_text(encoding='utf-8').splitlines() if l.strip()]
bad=[f for f in changed if f not in allowed]
Path('.sisyphus/evidence/task-7-scope-check.txt').write_text('PASS' if not bad else '\n'.join(bad), encoding='utf-8')
raise SystemExit(0 if not bad else 1)
PY`
    Expected: script exits 0 and writes `PASS`
    Evidence: .sisyphus/evidence/task-7-scope-check.txt
  ```

  **Commit**: NO | Message: `n/a` | Files: [`.sisyphus/evidence/*`]

## Final Verification Wave (4 parallel agents, ALL must APPROVE)
- [x] F1. Plan Compliance Audit - oracle
- [x] F2. Code Quality Review - unspecified-high
- [x] F3. Real Manual QA - unspecified-high (+ playwright if UI)
- [x] F4. Scope Fidelity Check - deep

## Commit Strategy
- Current workspace has no git metadata; no commit action in this run.
- If run in a git checkout later, use one atomic commit after Task 7:
  `fix(focus-mode): reconcile runtime layout parity for wrap and bottom-gap regressions`

## Success Criteria
- Focus Mode no longer shows persistent long-card bottom blank gap after activation/click.
- Focus Mode no longer wraps lines before visual right-edge expectation.
- Previous wobble fix remains intact with no visible jump reintroduced.
