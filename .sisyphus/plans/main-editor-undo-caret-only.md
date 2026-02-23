# Main Editor Undo: Text Rollback Instead of Caret Jump

## TL;DR
> **Summary**: Fix main edit-mode undo so Cmd+Z/Cmd+Shift+Z perform real text rollback while keeping edit mode active, by mirroring focus-mode typing-coalesced undo flow and removing fragile NSTextView-undo consumption behavior.
> **Deliverables**:
> - Main-mode typing undo/redo coalescing state and stack flow
> - Undo/redo command routing that never calls `finishEditing()` during active main editing
> - IME-safe coalescing guards and reentrancy protection
> - Build + invariant + scope-gate evidence bundle
> **Effort**: Medium
> **Parallel**: YES - 2 waves
> **Critical Path**: Task 1 -> Task 2 -> Task 3 -> Task 4 -> Task 6

## Context
### Original Request
Main edit mode undo currently moves caret to the start (or exits edit mode to snapshot restore) instead of undoing typed text. User wants normal text undo behavior and explicitly requests planning-first execution.

### Interview Summary
- Keep main edit mode active during undo/redo.
- Undo must rollback typed text (not just caret movement).
- Reuse focus-mode undo pattern as the authoritative reference.
- Do not redesign focus mode, shortcut mapping, or global history architecture.

### Metis Review (gaps addressed)
- Guard against command consumption when no real undo step exists.
- Prevent fallback into scenario undo path that calls `finishEditing()` while editing.
- Add IME/marked-text safety and anti-reentrancy for programmatic restore.
- Prevent double-stack behavior between custom typing undo and NSTextView undo manager.

## Work Objectives
### Core Objective
Implement deterministic, text-first undo/redo in main edit mode by using a main typing coalesced stack (focus-mode parity) and command routing that avoids edit-mode exit.

### Deliverables
- Main typing coalescing state + stacks in main mode.
- Main typing undo/redo executors that restore text + caret context without `finishEditing()`.
- Updated command routing for `.waUndoRequested`/`.waRedoRequested` in non-focus mode.
- Evidence artifacts in `.sisyphus/evidence/` validating behavior invariants and scope.

### Definition of Done (verifiable conditions with commands)
- `xcodebuild -project wa.xcodeproj -target wa -configuration Debug -destination 'platform=macOS' build` outputs `BUILD SUCCEEDED`.
- `.sisyphus/evidence/task-6-invariants.txt` reports all checks `PASS`.
- `.sisyphus/evidence/task-7-scope-check.txt` reports `PASS`.
- No command path from main edit-mode undo calls `performUndo()`/`performRedo()` while `editingCardID != nil`.

### Must Have
- Cmd+Z during active main editing undoes typed text (if undo step exists).
- Cmd+Shift+Z redoes typed text.
- Active editing context remains active (no `finishEditing()` side effect).
- Coalescing behavior is IME-safe and does not register reentrant undo states.

### Must NOT Have (guardrails, AI slop patterns, scope boundaries)
- No edits to focus-mode undo logic semantics beyond shared helper extraction (if needed).
- No keyboard shortcut remapping in app command definitions.
- No global history redesign or migration of existing snapshot stack semantics.
- No broad refactor outside `WriterViews.swift`, `WriterUndoRedo.swift`, `WriterCaretAndScroll.swift` unless mandatory compile coupling.

## Verification Strategy
> ZERO HUMAN INTERVENTION - all verification is agent-executed.
- Test decision: tests-after (project has no dedicated XCTest target for this path).
- QA policy: each task has happy + failure/edge checks.
- Evidence: `.sisyphus/evidence/task-{N}-{slug}.{ext}`

## Execution Strategy
### Parallel Execution Waves
> Target: 5-8 tasks per wave. <3 per wave (except final) = under-splitting.
> Shared dependencies extracted into Wave 1 for safe parallelism.

Wave 1: Baseline + main typing stack + command-path refactor (Tasks 1-4)
Wave 2: Parity hardening + verification + scope gate (Tasks 5-7)

### Dependency Matrix (full, all tasks)
- Task 1: Blocked By [] | Blocks [2,3,4,7]
- Task 2: Blocked By [1] | Blocks [3,4,6]
- Task 3: Blocked By [1,2] | Blocks [4,5,6]
- Task 4: Blocked By [1,2,3] | Blocks [5,6]
- Task 5: Blocked By [3,4] | Blocks [6,7]
- Task 6: Blocked By [2,3,4,5] | Blocks [7]
- Task 7: Blocked By [1,6] | Blocks []

### Agent Dispatch Summary (wave -> task count -> categories)
- Wave 1 -> 4 tasks -> `quick`, `unspecified-low`
- Wave 2 -> 3 tasks -> `quick`, `unspecified-high`

## TODOs
> Implementation + Test = ONE task. Never separate.
> EVERY task MUST have: Agent Profile + Parallelization + QA Scenarios.

- [ ] 1. Create Baseline Evidence for Undo-Routing Files

  **What to do**: Initialize `.sisyphus/evidence/baseline/` and snapshot files that must be protected or edited.
  - Snapshot:
    - `wa/WriterViews.swift`
    - `wa/WriterUndoRedo.swift`
    - `wa/WriterCaretAndScroll.swift`
    - `wa/WriterFocusMode.swift` (reference-only guard)
  - Write SHA256 manifest for these snapshots.

  **Must NOT do**: Modify production source code in this task.

  **Recommended Agent Profile**:
  - Category: `quick` - Reason: deterministic setup only.
  - Skills: [`karpathy-guidelines`] - why needed: strict baseline discipline.
  - Omitted: [`git-master`] - why not needed: hash-based flow (no git repo).

  **Parallelization**: Can Parallel: NO | Wave 1 | Blocks: [2,3,4,7] | Blocked By: []

  **References** (executor has NO interview context - be exhaustive):
  - Pattern: `wa/WriterViews.swift:395` - undo command routing entrypoint.
  - Pattern: `wa/WriterUndoRedo.swift:130` - fragile main text undo helper.
  - Pattern: `wa/WriterUndoRedo.swift:160` - snapshot undo path calling `finishEditing()`.
  - Pattern: `wa/WriterCaretAndScroll.swift:252` - main text-change hook.
  - Pattern: `wa/WriterFocusMode.swift:849` - parity reference for coalescing.

  **Acceptance Criteria** (agent-executable only):
  - [ ] `.sisyphus/evidence/baseline/` contains 4 snapshot files.
  - [ ] `.sisyphus/evidence/task-1-baseline-sha256.txt` exists with 4 lines.

  **QA Scenarios** (MANDATORY - task incomplete without these):
  ```
  Scenario: Baseline snapshots are captured
    Tool: Bash
    Steps: run `mkdir -p .sisyphus/evidence/baseline && cp wa/WriterViews.swift wa/WriterUndoRedo.swift wa/WriterCaretAndScroll.swift wa/WriterFocusMode.swift .sisyphus/evidence/baseline/ && shasum -a 256 .sisyphus/evidence/baseline/*.swift > .sisyphus/evidence/task-1-baseline-sha256.txt`
    Expected: snapshots + sha manifest created
    Evidence: .sisyphus/evidence/task-1-baseline-sha256.txt

  Scenario: Missing-baseline guard
    Tool: Bash
    Steps: run `python3 - <<'PY'
from pathlib import Path
expected={'WriterViews.swift','WriterUndoRedo.swift','WriterCaretAndScroll.swift','WriterFocusMode.swift'}
actual={p.name for p in Path('.sisyphus/evidence/baseline').glob('*.swift')}
missing=sorted(expected-actual)
Path('.sisyphus/evidence/task-1-baseline-check.txt').write_text('PASS' if not missing else '\n'.join(missing), encoding='utf-8')
raise SystemExit(0 if not missing else 1)
PY`
    Expected: script exits 0 and writes `PASS`
    Evidence: .sisyphus/evidence/task-1-baseline-check.txt
  ```

  **Commit**: NO | Message: `n/a` | Files: [`.sisyphus/evidence/*`]

- [ ] 2. Introduce Main Typing Coalescing State (Focus-Mode Parity)

  **What to do**: Add main-mode typing-coalescing state in `wa/WriterViews.swift`, mirroring focus-mode pattern naming/semantics.
  - Add main typing base state, card ID, idle timestamp/work item, and suppression window flags.
  - Reset these states when editing card changes/ends (same lifecycle locations where main selection cache resets).

  **Must NOT do**: Change focus-mode typing state variables or rename existing focus symbols.

  **Recommended Agent Profile**:
  - Category: `quick` - Reason: localized state wiring.
  - Skills: [`karpathy-guidelines`] - why needed: avoid unrelated state coupling.
  - Omitted: [`frontend-ui-ux`] - why not needed: no visual changes.

  **Parallelization**: Can Parallel: NO | Wave 1 | Blocks: [3,4,6] | Blocked By: [1]

  **References** (executor has NO interview context - be exhaustive):
  - Pattern: `wa/WriterViews.swift:127-131` - focus typing state cluster to mirror.
  - Pattern: `wa/WriterViews.swift:332-365` - edit lifecycle reset points.
  - Pattern: `wa/WriterFocusMode.swift:865-883` - parity behavior source.

  **Acceptance Criteria** (agent-executable only):
  - [ ] New main typing state symbols exist in `WriterViews.swift`.
  - [ ] New states are reset on edit-end and edit-switch paths.
  - [ ] `xcodebuild -project wa.xcodeproj -target wa -configuration Debug -destination 'platform=macOS' build` succeeds.

  **QA Scenarios** (MANDATORY - task incomplete without these):
  ```
  Scenario: Main typing state symbols + reset hooks exist
    Tool: Bash
    Steps: run `python3 - <<'PY'
from pathlib import Path
text=Path('wa/WriterViews.swift').read_text(encoding='utf-8')
checks={
  'has_main_typing_base_state':'mainTypingCoalescingBaseState' in text,
  'has_main_typing_card_state':'mainTypingCoalescingCardID' in text,
  'has_main_typing_reset':text.count('mainTypingCoalescingBaseState')>=2,
}
Path('.sisyphus/evidence/task-2-main-typing-state-check.txt').write_text('\n'.join(f"{k}={'PASS' if v else 'FAIL'}" for k,v in checks.items()), encoding='utf-8')
raise SystemExit(0 if all(checks.values()) else 1)
PY`
    Expected: script exits 0 and all checks PASS
    Evidence: .sisyphus/evidence/task-2-main-typing-state-check.txt

  Scenario: Failure guard for focus-mode file drift
    Tool: Bash
    Steps: run `diff -u .sisyphus/evidence/baseline/WriterFocusMode.swift wa/WriterFocusMode.swift > .sisyphus/evidence/task-2-focusmode-guard.diff || true`
    Expected: diff is empty
    Evidence: .sisyphus/evidence/task-2-focusmode-guard.diff
  ```

  **Commit**: NO | Message: `n/a` | Files: [`wa/WriterViews.swift`]

- [ ] 3. Implement Main Text-Change Coalescing and Stack Capture

  **What to do**: Extend `handleMainEditorContentChange` in `wa/WriterCaretAndScroll.swift` and related undo helpers in `wa/WriterUndoRedo.swift` to capture main typing undo states using coalesced boundaries.
  - Add main-mode equivalents of focus typing helpers:
    - schedule idle finalize
    - finalize coalescing
    - strong boundary detection reuse
  - Use committed-old-content override capture pattern (focus parity).
  - Skip coalescing while `isApplyingUndo` or during IME composition (`hasMarkedText`).

  **Must NOT do**: Add `finishEditing()` calls into main typing change flow.

  **Recommended Agent Profile**:
  - Category: `unspecified-low` - Reason: subtle event/coalescing logic.
  - Skills: [`karpathy-guidelines`] - why needed: avoid over-broad changes.
  - Omitted: [`git-master`] - why not needed: no history operations.

  **Parallelization**: Can Parallel: NO | Wave 1 | Blocks: [4,5,6] | Blocked By: [1,2]

  **References** (executor has NO interview context - be exhaustive):
  - Pattern: `wa/WriterCaretAndScroll.swift:252-265` - current main content-change hook.
  - Pattern: `wa/WriterFocusMode.swift:849-895` - coalescing algorithm reference.
  - Pattern: `wa/WriterUndoRedo.swift:173-343` - reusable boundary/delta helpers.

  **Acceptance Criteria** (agent-executable only):
  - [ ] Main content-change path populates coalesced main undo base state.
  - [ ] IME composition branch does not create coalesced snapshots.
  - [ ] `xcodebuild -project wa.xcodeproj -target wa -configuration Debug -destination 'platform=macOS' build` succeeds.

  **QA Scenarios** (MANDATORY - task incomplete without these):
  ```
  Scenario: Main coalescing flow exists in code
    Tool: Bash
    Steps: run `python3 - <<'PY'
from pathlib import Path
caret=Path('wa/WriterCaretAndScroll.swift').read_text(encoding='utf-8')
undo=Path('wa/WriterUndoRedo.swift').read_text(encoding='utf-8')
checks={
  'main_handle_uses_coalescing':'mainTypingCoalescingBaseState' in caret or 'mainTypingCoalescingBaseState' in undo,
  'ime_guard_present':'hasMarkedText' in caret,
  'main_finalize_present':'finalizeMainTypingCoalescing' in undo,
}
Path('.sisyphus/evidence/task-3-main-coalescing-check.txt').write_text('\n'.join(f"{k}={'PASS' if v else 'FAIL'}" for k,v in checks.items()), encoding='utf-8')
raise SystemExit(0 if all(checks.values()) else 1)
PY`
    Expected: script exits 0 and all checks PASS
    Evidence: .sisyphus/evidence/task-3-main-coalescing-check.txt

  Scenario: Failure guard for accidental `finishEditing()` insert in main content-change flow
    Tool: Bash
    Steps: run `python3 - <<'PY'
from pathlib import Path
text=Path('wa/WriterCaretAndScroll.swift').read_text(encoding='utf-8')
bad='finishEditing(' in text[text.find('func handleMainEditorContentChange'):text.find('func requestMainCaretEnsure')]
Path('.sisyphus/evidence/task-3-finishedit-guard.txt').write_text('PASS' if not bad else 'FAIL', encoding='utf-8')
raise SystemExit(0 if not bad else 1)
PY`
    Expected: script exits 0 and writes `PASS`
    Evidence: .sisyphus/evidence/task-3-finishedit-guard.txt
  ```

  **Commit**: NO | Message: `n/a` | Files: [`wa/WriterCaretAndScroll.swift`, `wa/WriterUndoRedo.swift`]

- [ ] 4. Replace Main Undo/Redo Command Routing with Main Typing Stack First-Class Path

  **What to do**: Update `WriterViews.swift` command handlers and `WriterUndoRedo.swift` executors so active main editing uses main typing undo/redo functions (focus parity style), not NSTextView undo-manager consumption nor `performUndo()` fallback.
  - Add/route to `performMainTypingUndo()` / `performMainTypingRedo()` (or equivalent).
  - Ensure command is consumed only when behavior is intentionally handled in main edit mode.
  - Keep non-edit mode fallback to existing `performUndo()`/`performRedo()`.

  **Must NOT do**: Route active main edit mode undo into `performUndo()`/`performRedo()`.

  **Recommended Agent Profile**:
  - Category: `unspecified-low` - Reason: command routing correctness.
  - Skills: [`karpathy-guidelines`] - why needed: preserve global behavior while changing active-edit path.
  - Omitted: [`frontend-ui-ux`] - why not needed: no visual/UI redesign.

  **Parallelization**: Can Parallel: NO | Wave 1 | Blocks: [5,6] | Blocked By: [1,2,3]

  **References** (executor has NO interview context - be exhaustive):
  - Pattern: `wa/WriterViews.swift:395-415` - undo/redo command receive block.
  - Pattern: `wa/WriterUndoRedo.swift:130-181` - current main helper + snapshot undo paths.
  - Pattern: `wa/WriterUndoRedo.swift:418-460` - focus undo/redo restore parity reference.

  **Acceptance Criteria** (agent-executable only):
  - [ ] Active main editing path no longer calls `performUndo()`/`performRedo()` directly.
  - [ ] Main typing undo/redo path does not call `finishEditing()`.
  - [ ] `xcodebuild -project wa.xcodeproj -target wa -configuration Debug -destination 'platform=macOS' build` succeeds.

  **QA Scenarios** (MANDATORY - task incomplete without these):
  ```
  Scenario: Command routing uses main typing undo path
    Tool: Bash
    Steps: run `python3 - <<'PY'
from pathlib import Path
views=Path('wa/WriterViews.swift').read_text(encoding='utf-8')
checks={
  'undo_routes_main_typing':'performMainTypingUndo' in views,
  'redo_routes_main_typing':'performMainTypingRedo' in views,
}
Path('.sisyphus/evidence/task-4-command-routing-check.txt').write_text('\n'.join(f"{k}={'PASS' if v else 'FAIL'}" for k,v in checks.items()), encoding='utf-8')
raise SystemExit(0 if all(checks.values()) else 1)
PY`
    Expected: script exits 0 and all checks PASS
    Evidence: .sisyphus/evidence/task-4-command-routing-check.txt

  Scenario: Failure guard against edit-mode exit side effect
    Tool: Bash
    Steps: run `python3 - <<'PY'
from pathlib import Path
undo=Path('wa/WriterUndoRedo.swift').read_text(encoding='utf-8')
segment=undo[undo.find('func performMainTypingUndo'):undo.find('func performUndo(')] if 'func performMainTypingUndo' in undo and 'func performUndo(' in undo else undo
bad='finishEditing(' in segment
Path('.sisyphus/evidence/task-4-finishedit-guard.txt').write_text('PASS' if not bad else 'FAIL', encoding='utf-8')
raise SystemExit(0 if not bad else 1)
PY`
    Expected: script exits 0 and writes `PASS`
    Evidence: .sisyphus/evidence/task-4-finishedit-guard.txt
  ```

  **Commit**: NO | Message: `n/a` | Files: [`wa/WriterViews.swift`, `wa/WriterUndoRedo.swift`]

- [ ] 5. Harden Main Typing Undo Apply Semantics (Caret + Reentrancy + No-Op Contract)

  **What to do**: Ensure apply/restore path for main typing undo/redo preserves editing context and handles empty-stack contract safely.
  - Implement/align caret hint restoration for main mode (text + caret).
  - Add explicit no-op behavior when stack empty while editing (no snapshot fallback, no mode exit).
  - Ensure reentrancy guard prevents recording new undo entries during apply.

  **Must NOT do**: mutate focus-mode restore semantics.

  **Recommended Agent Profile**:
  - Category: `unspecified-high` - Reason: behavior-sensitive edge handling.
  - Skills: [`karpathy-guidelines`] - why needed: preserve user-facing correctness.
  - Omitted: [`playwright`] - why not needed: no browser surface.

  **Parallelization**: Can Parallel: NO | Wave 2 | Blocks: [6,7] | Blocked By: [3,4]

  **References** (executor has NO interview context - be exhaustive):
  - Pattern: `wa/WriterUndoRedo.swift:434-483` - focus restore context reference.
  - Pattern: `wa/WriterUndoRedo.swift:486-527` - focus caret priming helpers.
  - Pattern: `wa/WriterCardManagement.swift:669-768` - `finishEditing()` behavior to avoid invoking.

  **Acceptance Criteria** (agent-executable only):
  - [ ] Main typing undo/redo keeps `editingCardID` active.
  - [ ] Empty-stack undo in active edit mode is a no-op (no `performUndo` call).
  - [ ] `xcodebuild -project wa.xcodeproj -target wa -configuration Debug -destination 'platform=macOS' build` succeeds.

  **QA Scenarios** (MANDATORY - task incomplete without these):
  ```
  Scenario: Main apply path has reentrancy and no-op guards
    Tool: Bash
    Steps: run `python3 - <<'PY'
from pathlib import Path
text=Path('wa/WriterUndoRedo.swift').read_text(encoding='utf-8')
checks={
  'has_main_apply_guard':'isApplyingUndo' in text,
  'has_main_empty_stack_noop':'guard let previous = mainTypingUndoStack.popLast()' in text or 'mainTypingUndoStack.isEmpty' in text,
}
Path('.sisyphus/evidence/task-5-main-apply-guard-check.txt').write_text('\n'.join(f"{k}={'PASS' if v else 'FAIL'}" for k,v in checks.items()), encoding='utf-8')
raise SystemExit(0 if all(checks.values()) else 1)
PY`
    Expected: script exits 0 and checks PASS
    Evidence: .sisyphus/evidence/task-5-main-apply-guard-check.txt

  Scenario: Failure guard for focus-mode regression edits
    Tool: Bash
    Steps: run `diff -u .sisyphus/evidence/baseline/WriterFocusMode.swift wa/WriterFocusMode.swift > .sisyphus/evidence/task-5-focusmode-guard.diff || true`
    Expected: diff is empty
    Evidence: .sisyphus/evidence/task-5-focusmode-guard.diff
  ```

  **Commit**: NO | Message: `n/a` | Files: [`wa/WriterUndoRedo.swift`, `wa/WriterViews.swift`]

- [ ] 6. Build + Invariant Verification Bundle

  **What to do**: Execute deterministic verification and persist logs/checks.
  - Run project build.
  - Validate invariants:
    - main typing undo route exists
    - active-edit undo path does not call snapshot `performUndo`
    - `performUndo` still contains `finishEditing` (non-edit path unchanged)

  **Must NOT do**: use manual-only QA as completion gate.

  **Recommended Agent Profile**:
  - Category: `quick` - Reason: command execution and binary checks.
  - Skills: [`karpathy-guidelines`] - why needed: deterministic verification.
  - Omitted: [`frontend-ui-ux`] - why not needed: no design task.

  **Parallelization**: Can Parallel: YES | Wave 2 | Blocks: [7] | Blocked By: [2,3,4,5]

  **References** (executor has NO interview context - be exhaustive):
  - Build command source: `xcodebuild -target wa`.
  - Pattern: `wa/WriterViews.swift:395` undo command handler.
  - Pattern: `wa/WriterUndoRedo.swift:160` snapshot undo path baseline.

  **Acceptance Criteria** (agent-executable only):
  - [ ] `.sisyphus/evidence/task-6-build.log` contains `BUILD SUCCEEDED`.
  - [ ] `.sisyphus/evidence/task-6-invariants.txt` contains all PASS.

  **QA Scenarios** (MANDATORY - task incomplete without these):
  ```
  Scenario: Build succeeds after undo-routing fix
    Tool: Bash
    Steps: run `xcodebuild -project wa.xcodeproj -target wa -configuration Debug -destination 'platform=macOS' build | tee .sisyphus/evidence/task-6-build.log`
    Expected: log contains `BUILD SUCCEEDED`
    Evidence: .sisyphus/evidence/task-6-build.log

  Scenario: Invariant guard for active-edit routing
    Tool: Bash
    Steps: run `python3 - <<'PY'
from pathlib import Path
views=Path('wa/WriterViews.swift').read_text(encoding='utf-8')
undo=Path('wa/WriterUndoRedo.swift').read_text(encoding='utf-8')
checks={
  'has_main_typing_undo_route':'performMainTypingUndo' in views,
  'has_main_typing_redo_route':'performMainTypingRedo' in views,
  'snapshot_undo_still_exists':'func performUndo()' in undo and 'finishEditing()' in undo,
}
Path('.sisyphus/evidence/task-6-invariants.txt').write_text('\n'.join(f"{k}={'PASS' if v else 'FAIL'}" for k,v in checks.items()), encoding='utf-8')
raise SystemExit(0 if all(checks.values()) else 1)
PY`
    Expected: script exits 0 and all checks PASS
    Evidence: .sisyphus/evidence/task-6-invariants.txt
  ```

  **Commit**: NO | Message: `n/a` | Files: [`.sisyphus/evidence/*`]

- [ ] 7. Final Scope Gate and Changed-File Manifest

  **What to do**: Generate changed-file manifest vs baseline and fail on out-of-scope source edits.
  - Allowed source edits:
    - `wa/WriterViews.swift`
    - `wa/WriterUndoRedo.swift`
    - `wa/WriterCaretAndScroll.swift`
  - Allowed additional artifacts: `.sisyphus/evidence/*`.

  **Must NOT do**: mark complete if any forbidden source file changed.

  **Recommended Agent Profile**:
  - Category: `quick` - Reason: deterministic closure gate.
  - Skills: [`karpathy-guidelines`] - why needed: strict scope fidelity.
  - Omitted: [`git-master`] - why not needed: hash-based scope checks.

  **Parallelization**: Can Parallel: NO | Wave 2 | Blocks: [] | Blocked By: [1,6]

  **References** (executor has NO interview context - be exhaustive):
  - Baseline snapshots: `.sisyphus/evidence/baseline/` from Task 1.
  - Scope boundaries section of this plan.

  **Acceptance Criteria** (agent-executable only):
  - [ ] `.sisyphus/evidence/task-7-changed-files.txt` exists.
  - [ ] `.sisyphus/evidence/task-7-scope-check.txt` contains `PASS`.

  **QA Scenarios** (MANDATORY - task incomplete without these):
  ```
  Scenario: Changed-file manifest generated
    Tool: Bash
    Steps: run `python3 - <<'PY'
from pathlib import Path
import hashlib
pairs=[
 ('WriterViews.swift','wa/WriterViews.swift'),
 ('WriterUndoRedo.swift','wa/WriterUndoRedo.swift'),
 ('WriterCaretAndScroll.swift','wa/WriterCaretAndScroll.swift'),
 ('WriterFocusMode.swift','wa/WriterFocusMode.swift'),
]
base=Path('.sisyphus/evidence/baseline')
changed=[]
for b,c in pairs:
  hb=hashlib.sha256((base/b).read_bytes()).hexdigest()
  hc=hashlib.sha256(Path(c).read_bytes()).hexdigest()
  if hb!=hc:
    changed.append(c)
Path('.sisyphus/evidence/task-7-changed-files.txt').write_text('\n'.join(changed), encoding='utf-8')
PY`
    Expected: manifest file exists and lists changed source files
    Evidence: .sisyphus/evidence/task-7-changed-files.txt

  Scenario: Out-of-scope change guard
    Tool: Bash
    Steps: run `python3 - <<'PY'
from pathlib import Path
allowed={'wa/WriterViews.swift','wa/WriterUndoRedo.swift','wa/WriterCaretAndScroll.swift'}
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
- [ ] F1. Plan Compliance Audit - oracle
- [ ] F2. Code Quality Review - unspecified-high
- [ ] F3. Real Manual QA - unspecified-high (+ playwright if UI)
- [ ] F4. Scope Fidelity Check - deep

## Commit Strategy
- No commit step in this plan because current workspace has no git metadata.
- If execution is moved into a git checkout, create one atomic commit after Task 7 with: `fix(editor): make main edit undo rollback text without exiting edit mode`.

## Success Criteria
- Main edit mode undo/redo behaves like normal text editing undo/redo.
- No caret-jump-only consumption and no edit-mode exit on active-edit undo.
- All verification artifacts pass and scope boundaries remain intact.
