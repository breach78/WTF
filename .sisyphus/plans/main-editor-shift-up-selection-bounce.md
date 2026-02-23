# Main Editor Shift+ArrowUp Selection Bounce Stabilization

## TL;DR
> **Summary**: Stabilize main-editor upward range selection auto-scroll by making scroll decisions follow the active selection edge, so upward extension behaves as naturally as downward extension without oscillation.
> **Deliverables**:
> - Active selection-edge tracking for main editor selection changes
> - Single-owner caret auto-scroll decision path in `ensureMainCaretVisible`
> - Inset-aware clamp hardening to avoid top-edge snap jitter
> - Build + invariant evidence proving no scope drift into growth/animation paths
> **Effort**: Short
> **Parallel**: YES - 2 waves
> **Critical Path**: Task 1 -> Task 2 -> Task 3 -> Task 5

## Context
### Original Request
In main workspace edit mode, `Shift + ArrowDown` selection scrolls naturally, but `Shift + ArrowUp` eventually causes violent up/down bouncing. Make upward behavior natural like downward behavior.

### Interview Summary
- Scope is limited to main workspace edit-mode selection auto-scroll behavior.
- Preserve existing smooth downward selection behavior.
- Avoid unrelated edits to row/card growth timing, insertion logic, and animation feel.

### Metis Review (gaps addressed)
- Root risk identified: competing edge ownership in `ensureMainCaretVisible` when selection grows upward and both edges challenge viewport bounds.
- Guardrails added to keep change inside main caret/selection pipeline only.
- Added clamp hardening decision based on known focus-mode anti-jitter pattern.

## Work Objectives
### Core Objective
Remove oscillation during `Shift + ArrowUp` range selection in main editor by preventing opposing scroll corrections inside one selection loop.

### Deliverables
- New main-selection active-edge state model.
- Selection observer updates to infer active edge from range deltas.
- Updated `ensureMainCaretVisible` to use active-edge ownership for non-empty selections.
- Inset-aware Y clamp parity for main mode.

### Definition of Done (verifiable conditions with commands)
- `xcodebuild -project wa.xcodeproj -target wa -configuration Debug -destination 'platform=macOS' build` outputs `BUILD SUCCEEDED`.
- `.sisyphus/evidence/task-6-invariants.txt` reports all PASS checks.
- `.sisyphus/evidence/task-7-scope-check.txt` reports PASS and lists no forbidden file edits.
- `wa/WriterViews.swift` and `wa/WriterCaretAndScroll.swift` contain all planned symbols/guards for active-edge ownership.

### Must Have
- Upward selection extension no longer flips between opposite scroll corrections.
- Downward selection behavior remains unchanged.
- No changes to card growth/insertion/animation timing.
- Main-mode clamp handles potential top inset jitter without snap-back.

### Must NOT Have (guardrails, AI slop patterns, scope boundaries)
- No edits to `wa/WriterCardManagement.swift` insertion/scroll-to-focus logic.
- No edits to `wa/WriterCardViews.swift` measurement/growth pipeline.
- No edits to focus-mode selection behavior except read-only pattern reference.
- No keyboard-navigation remap in `WriterKeyboardHandlers.swift`.

## Verification Strategy
> ZERO HUMAN INTERVENTION - all verification is agent-executed.
- Test decision: tests-after (project has no dedicated test target workflow for this path).
- QA policy: each task includes a deterministic scenario and a regression/failure guard scenario.
- Evidence: `.sisyphus/evidence/task-{N}-{slug}.{ext}`

## Execution Strategy
### Parallel Execution Waves
> Target: 5-8 tasks per wave. <3 per wave (except final) = under-splitting.
> Shared dependencies extracted into Wave 1 for safe parallelism.

Wave 1: Baseline + state model + scroll decision refactor (Tasks 1-4)
Wave 2: Build/invariants/scope gate/package checks (Tasks 5-7)

### Dependency Matrix (full, all tasks)
- Task 1: Blocked By [] | Blocks [2,3,4,7]
- Task 2: Blocked By [1] | Blocks [3,5]
- Task 3: Blocked By [1,2] | Blocks [4,5,6]
- Task 4: Blocked By [1,3] | Blocks [5,6]
- Task 5: Blocked By [2,3,4] | Blocks [7]
- Task 6: Blocked By [3,4] | Blocks [7]
- Task 7: Blocked By [1,5,6] | Blocks []

### Agent Dispatch Summary (wave -> task count -> categories)
- Wave 1 -> 4 tasks -> `quick`, `unspecified-low`
- Wave 2 -> 3 tasks -> `quick`, `unspecified-high`

## TODOs
> Implementation + Test = ONE task. Never separate.
> EVERY task MUST have: Agent Profile + Parallelization + QA Scenarios.

- [ ] 1. Create Evidence Baseline for Main Selection/Scroll Paths

  **What to do**: Create `.sisyphus/evidence/` baseline snapshots for only the files involved in this fix.
  - Create `.sisyphus/evidence/baseline/`.
  - Snapshot files:
    - `wa/WriterViews.swift`
    - `wa/WriterCaretAndScroll.swift`
    - `wa/WriterFocusMode.swift` (reference-only parity guard)
    - `wa/WriterKeyboardHandlers.swift` (scope contamination guard)
  - Generate SHA256 manifest for baseline snapshots.

  **Must NOT do**: Modify source code in this task.

  **Recommended Agent Profile**:
  - Category: `quick` - Reason: deterministic setup only.
  - Skills: [`karpathy-guidelines`] - why needed: keep baseline exact and minimal.
  - Omitted: [`git-master`] - why not needed: baseline uses file snapshots, not git.

  **Parallelization**: Can Parallel: NO | Wave 1 | Blocks: [2,3,4,7] | Blocked By: []

  **References** (executor has NO interview context - be exhaustive):
  - Pattern: `wa/WriterViews.swift:99` - current main selection tracking state cluster.
  - Pattern: `wa/WriterViews.swift:332` - edit-card change reset path.
  - Pattern: `wa/WriterCaretAndScroll.swift:12` - selection observer entrypoint.
  - Pattern: `wa/WriterCaretAndScroll.swift:249` - main ensure-visible loop.
  - Pattern: `wa/WriterFocusMode.swift:701` - inset-aware clamp parity source.

  **Acceptance Criteria** (agent-executable only):
  - [ ] `.sisyphus/evidence/baseline/` contains exactly 4 snapshot files.
  - [ ] `.sisyphus/evidence/task-1-baseline-sha256.txt` exists with 4 lines.

  **QA Scenarios** (MANDATORY - task incomplete without these):
  ```
  Scenario: Baseline snapshot creation succeeds
    Tool: Bash
    Steps: run `mkdir -p .sisyphus/evidence/baseline && cp wa/WriterViews.swift wa/WriterCaretAndScroll.swift wa/WriterFocusMode.swift wa/WriterKeyboardHandlers.swift .sisyphus/evidence/baseline/ && shasum -a 256 .sisyphus/evidence/baseline/*.swift > .sisyphus/evidence/task-1-baseline-sha256.txt`
    Expected: baseline snapshots and hash manifest created
    Evidence: .sisyphus/evidence/task-1-baseline-sha256.txt

  Scenario: Failure guard for missing baseline files
    Tool: Bash
    Steps: run `python3 - <<'PY'
from pathlib import Path
expected = {'WriterViews.swift','WriterCaretAndScroll.swift','WriterFocusMode.swift','WriterKeyboardHandlers.swift'}
actual = {p.name for p in Path('.sisyphus/evidence/baseline').glob('*.swift')}
missing = sorted(expected - actual)
Path('.sisyphus/evidence/task-1-baseline-check.txt').write_text('PASS' if not missing else '\n'.join(missing), encoding='utf-8')
raise SystemExit(0 if not missing else 1)
PY`
    Expected: script exits 0 and writes `PASS`
    Evidence: .sisyphus/evidence/task-1-baseline-check.txt
  ```

  **Commit**: NO | Message: `n/a` | Files: [`.sisyphus/evidence/*`]

- [ ] 2. Add Main Selection Active-Edge State and Reset Lifecycle

  **What to do**: Introduce explicit state in `wa/WriterViews.swift` for active selection edge tracking in main mode, with deterministic reset points.
  - Add `@State var mainSelectionActiveEdge` (enum/string form) and previous `mainSelectionLastStart/mainSelectionLastEnd` if needed.
  - Reset new state wherever existing selection cache resets:
    - `editingCardID` nil transition path
    - `editingCardID` switch path
    - stop-monitor path if applicable

  **Must NOT do**: Change focus-mode states, unrelated keyboard state, or animation flags.

  **Recommended Agent Profile**:
  - Category: `quick` - Reason: localized state additions + lifecycle reset wiring.
  - Skills: [`karpathy-guidelines`] - why needed: avoid touching unrelated global state.
  - Omitted: [`frontend-ui-ux`] - why not needed: non-visual logic change.

  **Parallelization**: Can Parallel: NO | Wave 1 | Blocks: [3,5] | Blocked By: [1]

  **References** (executor has NO interview context - be exhaustive):
  - Pattern: `wa/WriterViews.swift:99-104` - existing main selection cache fields.
  - Pattern: `wa/WriterViews.swift:332-355` - required reset points.
  - Pattern: `wa/WriterCaretAndScroll.swift:37-44` - current duplicate-selection cache semantics.

  **Acceptance Criteria** (agent-executable only):
  - [ ] New active-edge state exists in `wa/WriterViews.swift` near existing `mainSelectionLast*` states.
  - [ ] New state resets in both edit-end and edit-switch paths.
  - [ ] `xcodebuild -project wa.xcodeproj -target wa -configuration Debug -destination 'platform=macOS' build` succeeds.

  **QA Scenarios** (MANDATORY - task incomplete without these):
  ```
  Scenario: Active-edge state and reset paths are present
    Tool: Bash
    Steps: run `python3 - <<'PY'
from pathlib import Path
text = Path('wa/WriterViews.swift').read_text(encoding='utf-8')
checks = {
  'has_active_edge_state': 'mainSelectionActiveEdge' in text,
  'has_reset_in_edit_nil': text.count('mainSelectionActiveEdge') >= 2,
}
Path('.sisyphus/evidence/task-2-state-check.txt').write_text('\n'.join(f"{k}={'PASS' if v else 'FAIL'}" for k,v in checks.items()), encoding='utf-8')
raise SystemExit(0 if all(checks.values()) else 1)
PY`
    Expected: script exits 0 with all PASS
    Evidence: .sisyphus/evidence/task-2-state-check.txt

  Scenario: Failure guard for focus-mode state contamination
    Tool: Bash
    Steps: run `diff -u .sisyphus/evidence/baseline/WriterFocusMode.swift wa/WriterFocusMode.swift > .sisyphus/evidence/task-2-focusmode-guard.diff || true`
    Expected: diff is empty
    Evidence: .sisyphus/evidence/task-2-focusmode-guard.diff
  ```

  **Commit**: NO | Message: `n/a` | Files: [`wa/WriterViews.swift`]

- [ ] 3. Infer Active Selection Edge in Main Selection Observer

  **What to do**: Update `startMainCaretMonitor` selection callback in `wa/WriterCaretAndScroll.swift` to infer active edge and persist it.
  - Derive previous/new selection bounds (`start/end`).
  - Inference rules:
    - If only start moves toward smaller index while end stable -> active edge = start (Shift+Up extension).
    - If only end moves toward larger index while start stable -> active edge = end (Shift+Down extension).
    - If collapsed selection or ambiguous delta -> set fallback (caret edge based on insertion location) without forcing flips.
  - Keep existing duplicate-event filter semantics.

  **Must NOT do**: Remap keyboard keys, add new monitors, or alter content mutation behavior.

  **Recommended Agent Profile**:
  - Category: `unspecified-low` - Reason: event-state logic with subtle edge inference.
  - Skills: [`karpathy-guidelines`] - why needed: avoid overfitting and branch explosion.
  - Omitted: [`git-master`] - why not needed: no history operations.

  **Parallelization**: Can Parallel: NO | Wave 1 | Blocks: [4,5,6] | Blocked By: [1,2]

  **References** (executor has NO interview context - be exhaustive):
  - Pattern: `wa/WriterCaretAndScroll.swift:12-61` - selection observer callback.
  - Pattern: `wa/WriterCaretAndScroll.swift:37-53` - current duplicate suppression state writes.
  - Pattern: `wa/WriterViews.swift:99-104` - state backing for observer cache.

  **Acceptance Criteria** (agent-executable only):
  - [ ] Observer writes active-edge state from range-delta inference.
  - [ ] Existing duplicate-selection guard remains intact.
  - [ ] `xcodebuild -project wa.xcodeproj -target wa -configuration Debug -destination 'platform=macOS' build` succeeds.

  **QA Scenarios** (MANDATORY - task incomplete without these):
  ```
  Scenario: Active-edge inference paths exist
    Tool: Bash
    Steps: run `python3 - <<'PY'
from pathlib import Path
text = Path('wa/WriterCaretAndScroll.swift').read_text(encoding='utf-8')
checks = {
  'tracks_prev_start_end': ('selStart' in text or 'start' in text) and ('selEnd' in text or 'end' in text),
  'writes_active_edge': 'mainSelectionActiveEdge' in text,
}
Path('.sisyphus/evidence/task-3-edge-inference-check.txt').write_text('\n'.join(f"{k}={'PASS' if v else 'FAIL'}" for k,v in checks.items()), encoding='utf-8')
raise SystemExit(0 if all(checks.values()) else 1)
PY`
    Expected: script exits 0 and all checks are PASS
    Evidence: .sisyphus/evidence/task-3-edge-inference-check.txt

  Scenario: Failure guard for keyboard-remap contamination
    Tool: Bash
    Steps: run `diff -u wa/WriterKeyboardHandlers.swift .sisyphus/evidence/baseline/WriterKeyboardHandlers.swift > .sisyphus/evidence/task-3-keyboard-guard.diff || true`
    Expected: no diff
    Evidence: .sisyphus/evidence/task-3-keyboard-guard.diff
  ```

  **Commit**: NO | Message: `n/a` | Files: [`wa/WriterCaretAndScroll.swift`, `wa/WriterViews.swift`]

- [ ] 4. Refactor Main Caret Ensure to Single-Owner Edge + Inset-Aware Clamp

  **What to do**: Update `ensureMainCaretVisible` in `wa/WriterCaretAndScroll.swift` to prevent opposite-edge tug-of-war.
  - Call `layoutManager.ensureLayout(for: textContainer)` before caret rect reads.
  - For non-empty selections, choose one owner edge based on `mainSelectionActiveEdge`:
    - `start` owner checks only top visibility breach.
    - `end` owner checks only bottom visibility breach.
  - Keep collapsed-selection behavior equivalent to current caret visibility behavior.
  - Port focus-mode clamp style to main mode:
    - derive `effectiveTopInset` using `contentInsets.top` and `inferredTopInset`
    - clamp with `minY/maxY` instead of raw `[0, documentHeight-visible.height]`.

  **Must NOT do**: Change paddings (`topPadding/bottomPadding`) values, adjust animation curves, or touch focus-mode code.

  **Recommended Agent Profile**:
  - Category: `unspecified-low` - Reason: algorithmic scroll decision fix with clamp hardening.
  - Skills: [`karpathy-guidelines`] - why needed: preserve behavior while changing ownership logic.
  - Omitted: [`frontend-ui-ux`] - why not needed: no visual redesign.

  **Parallelization**: Can Parallel: NO | Wave 1 | Blocks: [5,6] | Blocked By: [1,3]

  **References** (executor has NO interview context - be exhaustive):
  - Pattern: `wa/WriterCaretAndScroll.swift:249-301` - current ensure-visible logic.
  - Pattern: `wa/WriterCaretAndScroll.swift:287-292` - current competing edge branch.
  - Pattern: `wa/WriterFocusMode.swift:701-707` - inset-aware clamp implementation pattern.
  - Pattern: `wa/WriterFocusMode.swift:718-723` - edge-specific targetY update style.

  **Acceptance Criteria** (agent-executable only):
  - [ ] Main ensure-visible path uses active-edge ownership when selection length > 0.
  - [ ] Main clamp includes inferred top inset handling.
  - [ ] `xcodebuild -project wa.xcodeproj -target wa -configuration Debug -destination 'platform=macOS' build` succeeds.

  **QA Scenarios** (MANDATORY - task incomplete without these):
  ```
  Scenario: Single-owner edge branch is enforced
    Tool: Bash
    Steps: run `python3 - <<'PY'
from pathlib import Path
text = Path('wa/WriterCaretAndScroll.swift').read_text(encoding='utf-8')
checks = {
  'has_active_edge_usage': 'mainSelectionActiveEdge' in text,
  'has_ensure_layout': 'ensureLayout(for: textContainer)' in text,
  'has_inset_aware_clamp': 'inferredTopInset' in text and 'effectiveTopInset' in text,
}
Path('.sisyphus/evidence/task-4-owner-clamp-check.txt').write_text('\n'.join(f"{k}={'PASS' if v else 'FAIL'}" for k,v in checks.items()), encoding='utf-8')
raise SystemExit(0 if all(checks.values()) else 1)
PY`
    Expected: script exits 0 and all checks are PASS
    Evidence: .sisyphus/evidence/task-4-owner-clamp-check.txt

  Scenario: Failure guard for focus-mode file contamination
    Tool: Bash
    Steps: run `diff -u .sisyphus/evidence/baseline/WriterFocusMode.swift wa/WriterFocusMode.swift > .sisyphus/evidence/task-4-focusmode-guard.diff || true`
    Expected: diff is empty
    Evidence: .sisyphus/evidence/task-4-focusmode-guard.diff
  ```

  **Commit**: NO | Message: `n/a` | Files: [`wa/WriterCaretAndScroll.swift`]

- [ ] 5. Soften Inner Offset Normalization During Selection Expansion

  **What to do**: Adjust `normalizeMainEditorTextViewOffsetIfNeeded` usage so inner-scroll resets do not fight outer-scroll caret ensure while selection is actively expanding.
  - Keep X reset behavior.
  - For Y reset, add a guard tied to `reason == "selection-change"` and selection state (non-empty active range) to avoid immediate counter-resets.
  - Keep current behavior for `reason == "content-change"` and `reason == "edit-change"`.

  **Must NOT do**: Remove normalization entirely or alter focus-mode normalizer.

  **Recommended Agent Profile**:
  - Category: `quick` - Reason: narrow guard adjustment.
  - Skills: [`karpathy-guidelines`] - why needed: avoid broad side effects.
  - Omitted: [`playwright`] - why not needed: native app static verification path.

  **Parallelization**: Can Parallel: NO | Wave 2 | Blocks: [6,7] | Blocked By: [4]

  **References** (executor has NO interview context - be exhaustive):
  - Pattern: `wa/WriterCaretAndScroll.swift:35` - selection-change normalization call site.
  - Pattern: `wa/WriterCaretAndScroll.swift:303-310` - inner offset reset implementation.
  - Pattern: `wa/WriterCaretAndScroll.swift:230` - content-change call site to preserve.
  - Pattern: `wa/WriterViews.swift:362` - edit-change call site to preserve.

  **Acceptance Criteria** (agent-executable only):
  - [ ] Selection-change path avoids aggressive Y reset during active range expansion.
  - [ ] Content-change/edit-change normalization paths remain present.
  - [ ] `xcodebuild -project wa.xcodeproj -target wa -configuration Debug -destination 'platform=macOS' build` succeeds.

  **QA Scenarios** (MANDATORY - task incomplete without these):
  ```
  Scenario: Selection-change Y-reset guard exists
    Tool: Bash
    Steps: run `python3 - <<'PY'
from pathlib import Path
text = Path('wa/WriterCaretAndScroll.swift').read_text(encoding='utf-8')
checks = {
  'has_reason_condition': 'reason' in text and 'selection-change' in text,
  'keeps_content_change_path': 'content-change' in text,
  'keeps_edit_change_path': 'edit-change' in Path('wa/WriterViews.swift').read_text(encoding='utf-8'),
}
Path('.sisyphus/evidence/task-5-normalize-guard-check.txt').write_text('\n'.join(f"{k}={'PASS' if v else 'FAIL'}" for k,v in checks.items()), encoding='utf-8')
raise SystemExit(0 if all(checks.values()) else 1)
PY`
    Expected: script exits 0 and all checks are PASS
    Evidence: .sisyphus/evidence/task-5-normalize-guard-check.txt

  Scenario: Failure guard for keyboard navigation file edits
    Tool: Bash
    Steps: run `diff -u .sisyphus/evidence/baseline/WriterKeyboardHandlers.swift wa/WriterKeyboardHandlers.swift > .sisyphus/evidence/task-5-keyboard-guard.diff || true`
    Expected: diff is empty
    Evidence: .sisyphus/evidence/task-5-keyboard-guard.diff
  ```

  **Commit**: NO | Message: `n/a` | Files: [`wa/WriterCaretAndScroll.swift`]

- [ ] 6. Build and Invariant Verification Bundle

  **What to do**: Run deterministic verification commands and write evidence outputs.
  - Build target `wa`.
  - Validate key invariants in source:
    - active-edge state usage exists
    - ensure-layout call exists
    - inset-aware clamp exists
    - forbidden files unchanged

  **Must NOT do**: Use manual-only visual checks as gate.

  **Recommended Agent Profile**:
  - Category: `quick` - Reason: command execution and binary checks.
  - Skills: [`karpathy-guidelines`] - why needed: strict pass/fail verification.
  - Omitted: [`frontend-ui-ux`] - why not needed: no design task.

  **Parallelization**: Can Parallel: YES | Wave 2 | Blocks: [7] | Blocked By: [3,4,5]

  **References** (executor has NO interview context - be exhaustive):
  - Build command source: `wa.xcodeproj` target `wa`.
  - Pattern: `wa/WriterCaretAndScroll.swift:249` - ensure-visible entrypoint.
  - Pattern: `wa/WriterViews.swift:99` - selection state backing.

  **Acceptance Criteria** (agent-executable only):
  - [ ] `.sisyphus/evidence/task-6-build.log` contains `BUILD SUCCEEDED`.
  - [ ] `.sisyphus/evidence/task-6-invariants.txt` contains all PASS.

  **QA Scenarios** (MANDATORY - task incomplete without these):
  ```
  Scenario: Build succeeds after bounce-fix changes
    Tool: Bash
    Steps: run `xcodebuild -project wa.xcodeproj -target wa -configuration Debug -destination 'platform=macOS' build | tee .sisyphus/evidence/task-6-build.log`
    Expected: log contains `BUILD SUCCEEDED`
    Evidence: .sisyphus/evidence/task-6-build.log

  Scenario: Failure guard for missing active-edge invariants
    Tool: Bash
    Steps: run `python3 - <<'PY'
from pathlib import Path
views = Path('wa/WriterViews.swift').read_text(encoding='utf-8')
caret = Path('wa/WriterCaretAndScroll.swift').read_text(encoding='utf-8')
checks = {
  'has_active_edge_state': 'mainSelectionActiveEdge' in views,
  'has_active_edge_usage': 'mainSelectionActiveEdge' in caret,
  'has_ensure_layout': 'ensureLayout(for: textContainer)' in caret,
  'has_inset_clamp': 'inferredTopInset' in caret and 'effectiveTopInset' in caret,
}
Path('.sisyphus/evidence/task-6-invariants.txt').write_text('\n'.join(f"{k}={'PASS' if v else 'FAIL'}" for k,v in checks.items()), encoding='utf-8')
raise SystemExit(0 if all(checks.values()) else 1)
PY`
    Expected: script exits 0 and all checks are PASS
    Evidence: .sisyphus/evidence/task-6-invariants.txt
  ```

  **Commit**: NO | Message: `n/a` | Files: [`.sisyphus/evidence/*`]

- [ ] 7. Final Scope Gate and Changed-File Manifest

  **What to do**: Generate final changed-file manifest against baseline and fail if out-of-scope source files changed.
  - Compare baseline snapshots to current files.
  - Approved source-file changes for this work:
    - `wa/WriterViews.swift`
    - `wa/WriterCaretAndScroll.swift`
  - Optional: `.sisyphus/evidence/*`.

  **Must NOT do**: Complete task if any forbidden source file changed.

  **Recommended Agent Profile**:
  - Category: `quick` - Reason: deterministic closure gate.
  - Skills: [`karpathy-guidelines`] - why needed: strict scope fidelity.
  - Omitted: [`git-master`] - why not needed: hash-based scope gate used.

  **Parallelization**: Can Parallel: NO | Wave 2 | Blocks: [] | Blocked By: [1,6]

  **References** (executor has NO interview context - be exhaustive):
  - Baseline snapshots from Task 1 in `.sisyphus/evidence/baseline/`.
  - Scope boundaries in this plan `Must NOT Have` section.

  **Acceptance Criteria** (agent-executable only):
  - [ ] `.sisyphus/evidence/task-7-changed-files.txt` exists.
  - [ ] `.sisyphus/evidence/task-7-scope-check.txt` contains `PASS`.

  **QA Scenarios** (MANDATORY - task incomplete without these):
  ```
  Scenario: Changed-file manifest is generated
    Tool: Bash
    Steps: run `python3 - <<'PY'
from pathlib import Path
import hashlib
pairs = [
  ('WriterViews.swift','wa/WriterViews.swift'),
  ('WriterCaretAndScroll.swift','wa/WriterCaretAndScroll.swift'),
  ('WriterFocusMode.swift','wa/WriterFocusMode.swift'),
  ('WriterKeyboardHandlers.swift','wa/WriterKeyboardHandlers.swift'),
]
base = Path('.sisyphus/evidence/baseline')
changed = []
for b,c in pairs:
  hb = hashlib.sha256((base / b).read_bytes()).hexdigest()
  hc = hashlib.sha256(Path(c).read_bytes()).hexdigest()
  if hb != hc:
    changed.append(c)
Path('.sisyphus/evidence/task-7-changed-files.txt').write_text('\n'.join(changed), encoding='utf-8')
PY`
    Expected: changed-file manifest generated
    Evidence: .sisyphus/evidence/task-7-changed-files.txt

  Scenario: Failure guard for out-of-scope file edits
    Tool: Bash
    Steps: run `python3 - <<'PY'
from pathlib import Path
allowed = {'wa/WriterViews.swift','wa/WriterCaretAndScroll.swift'}
changed = [line.strip() for line in Path('.sisyphus/evidence/task-7-changed-files.txt').read_text(encoding='utf-8').splitlines() if line.strip()]
bad = [f for f in changed if f not in allowed]
Path('.sisyphus/evidence/task-7-scope-check.txt').write_text('PASS' if not bad else '\n'.join(bad), encoding='utf-8')
raise SystemExit(0 if not bad else 1)
PY`
    Expected: script exits 0 and writes `PASS`
    Evidence: .sisyphus/evidence/task-7-scope-check.txt
  ```

  **Commit**: NO | Message: `n/a` | Files: [`.sisyphus/evidence/*`]

## Final Verification Wave (4 parallel agents, ALL must APPROVE)
- [ ] F1. Plan Compliance Audit - oracle
- [ ] F2. Code Quality Review - unspecified-high
- [ ] F3. Real Manual QA - unspecified-high (+ playwright if UI)
- [ ] F4. Scope Fidelity Check - deep

## Commit Strategy
- No commit step in this plan because current workspace has no git metadata.
- If execution is moved into a git checkout, create one atomic commit after Task 7 with message: `fix(editor): stabilize shift-up selection auto-scroll`.

## Success Criteria
- Shift+ArrowUp selection auto-scroll is stable and directionally consistent.
- Shift+ArrowDown behavior remains natural and unchanged.
- Build and invariant/scope evidence all pass.
