# Focus Mode Vertical Spacing Stability (No Wobble, No Inactive Bottom Gap)

## TL;DR
> **Summary**: Stabilize focus-mode card vertical layout by removing unsafe observed-height feedback into inactive sizing, unifying active/inactive content height basis, and reducing normalization-driven height churn that causes perceived card movement.
> **Deliverables**:
> - Deterministic card-height source for active/inactive focus cards
> - Safe observed-height usage policy (active-only or pruned mapping)
> - Decoupled offset-normalization vs observed-height sampling path
> - Regression guards for duplicate-content cards and long inactive cards
> **Effort**: Medium
> **Parallel**: YES - 2 waves
> **Critical Path**: Task 1 -> Task 2 -> Task 3 -> Task 4 -> Task 6

## Context
### Original Request
Focus mode currently shows vertical wobble where active card top/bottom spacing appears different from inactive cards, and long inactive cards can show extra bottom gap. User wants the previous stable, paper-like behavior restored.

### Interview Summary
- Fix should preserve existing focus-mode interaction feel.
- Root concern is vertical spacing stability, not stylistic redesign.
- Planning-first requested; implementation should be minimal-risk and measured.

### Metis Review (gaps addressed)
- Conflicting height signals must be resolved (deterministic + observed + cached).
- Content-keyed observed mapping is unsafe with duplicate texts.
- High-frequency normalization/caret loops can amplify visible jumps.
- Acceptance must include duplicate-content and trailing-newline edge coverage.

## Work Objectives
### Core Objective
Make focus-mode vertical spacing stable across active/inactive transitions and long-card states by converging to consistent height computation and eliminating unsafe observed-height churn.

### Deliverables
- Focus-mode height policy update in `wa/WriterCardViews.swift`.
- Observed-height collection policy hardening in `wa/WriterFocusMode.swift`.
- Focus observed cache lifecycle alignment in `wa/WriterViews.swift` / focus-mode transition paths.
- Build + invariant + scope-gate evidence files under `.sisyphus/evidence/`.

### Definition of Done (verifiable conditions with commands)
- `xcodebuild -project wa.xcodeproj -target wa -configuration Debug -destination 'platform=macOS' build` reports `BUILD SUCCEEDED`.
- `.sisyphus/evidence/task-6-invariants.txt` reports all checks `PASS`.
- `.sisyphus/evidence/task-7-scope-check.txt` reports `PASS`.
- No remaining `remainingCardIDsByContent` mapping path in focus-mode observed-height flow.

### Must Have
- Active/inactive focus cards no longer appear to jump vertically due to height-source conflicts.
- Long inactive cards no longer inherit inflated bottom gap from stale/misattributed observed heights.
- Duplicate-content cards do not cross-contaminate observed height assignment.
- Existing focus-mode caret visibility behavior remains functionally intact.

### Must NOT Have (guardrails, AI slop patterns, scope boundaries)
- No redesign of focus-mode color/theme/spacing language.
- No keyboard shortcut mapping changes.
- No broad refactor outside `wa/WriterCardViews.swift`, `wa/WriterFocusMode.swift`, `wa/WriterViews.swift` unless compile coupling requires minimal touch.
- No changes to main-mode card height system.

## Verification Strategy
> ZERO HUMAN INTERVENTION - all verification is agent-executed.
- Test decision: tests-after (project currently validated via build + deterministic source invariants).
- QA policy: every task includes happy + failure guard checks.
- Evidence: `.sisyphus/evidence/task-{N}-{slug}.{ext}`

## Execution Strategy
### Parallel Execution Waves
> Target: 5-8 tasks per wave. <3 per wave (except final) = under-splitting.
> Shared dependencies extracted into Wave 1 for safe parallelism.

Wave 1: Baseline + height-policy convergence + observed-mapping hardening (Tasks 1-4)
Wave 2: Normalization tuning + verification + scope gate (Tasks 5-7)

### Dependency Matrix (full, all tasks)
- Task 1: Blocked By [] | Blocks [2,3,4,7]
- Task 2: Blocked By [1] | Blocks [3,5,6]
- Task 3: Blocked By [1,2] | Blocks [4,6,7]
- Task 4: Blocked By [1,2,3] | Blocks [5,6]
- Task 5: Blocked By [2,4] | Blocks [6,7]
- Task 6: Blocked By [2,3,4,5] | Blocks [7]
- Task 7: Blocked By [1,3,5,6] | Blocks []

### Agent Dispatch Summary (wave -> task count -> categories)
- Wave 1 -> 4 tasks -> `quick`, `unspecified-low`
- Wave 2 -> 3 tasks -> `quick`, `unspecified-high`

## TODOs
> Implementation + Test = ONE task. Never separate.
> EVERY task MUST have: Agent Profile + Parallelization + QA Scenarios.

- [x] 1. Create Baseline Evidence for Focus-Mode Spacing Files

  **What to do**: Create baseline snapshots for all files involved in focus-mode vertical spacing behavior.
  - Snapshot files into `.sisyphus/evidence/baseline/`:
    - `wa/WriterCardViews.swift`
    - `wa/WriterFocusMode.swift`
    - `wa/WriterViews.swift`
    - `wa/WriterCaretAndScroll.swift` (guardrail, should remain unchanged)
  - Generate SHA256 manifest.

  **Must NOT do**: Modify source code in this task.

  **Recommended Agent Profile**:
  - Category: `quick` - Reason: deterministic setup.
  - Skills: [`karpathy-guidelines`] - why needed: strict baseline discipline.
  - Omitted: [`git-master`] - why not needed: non-git hash workflow.

  **Parallelization**: Can Parallel: NO | Wave 1 | Blocks: [2,3,4,7] | Blocked By: []

  **References** (executor has NO interview context - be exhaustive):
  - Pattern: `wa/WriterCardViews.swift:186-190` target height selection.
  - Pattern: `wa/WriterCardViews.swift:261-269` observed-height merge path.
  - Pattern: `wa/WriterFocusMode.swift:421-435` content-key mapping path.
  - Pattern: `wa/WriterFocusMode.swift:469-470` observed cache writeback.

  **Acceptance Criteria** (agent-executable only):
  - [ ] `.sisyphus/evidence/baseline/` contains 4 snapshot files.
  - [ ] `.sisyphus/evidence/task-1-baseline-sha256.txt` exists with 4 lines.

  **QA Scenarios** (MANDATORY - task incomplete without these):
  ```
  Scenario: Baseline snapshot creation succeeds
    Tool: Bash
    Steps: run `mkdir -p .sisyphus/evidence/baseline && cp wa/WriterCardViews.swift wa/WriterFocusMode.swift wa/WriterViews.swift wa/WriterCaretAndScroll.swift .sisyphus/evidence/baseline/ && shasum -a 256 .sisyphus/evidence/baseline/*.swift > .sisyphus/evidence/task-1-baseline-sha256.txt`
    Expected: baseline files and hash manifest are created
    Evidence: .sisyphus/evidence/task-1-baseline-sha256.txt

  Scenario: Failure guard for missing baseline assets
    Tool: Bash
    Steps: run `python3 - <<'PY'
from pathlib import Path
expected={'WriterCardViews.swift','WriterFocusMode.swift','WriterViews.swift','WriterCaretAndScroll.swift'}
actual={p.name for p in Path('.sisyphus/evidence/baseline').glob('*.swift')}
missing=sorted(expected-actual)
Path('.sisyphus/evidence/task-1-baseline-check.txt').write_text('PASS' if not missing else '\n'.join(missing), encoding='utf-8')
raise SystemExit(0 if not missing else 1)
PY`
    Expected: script exits 0 and writes `PASS`
    Evidence: .sisyphus/evidence/task-1-baseline-check.txt
  ```

  **Commit**: NO | Message: `n/a` | Files: [`.sisyphus/evidence/*`]

- [x] 2. Converge Active/Inactive Height Basis in FocusModeCardEditor

  **What to do**: Remove active/inactive text-basis mismatch that causes vertical jumps.
  - In `wa/WriterCardViews.swift`, align inactive sizing basis with active sizing semantics for trailing-newline handling.
  - Update `refreshMeasuredHeights` so observed-body influence does not inflate inactive state from unrelated/stale runtime observations.
  - Preserve `verticalInset` and existing visual styling.

  **Must NOT do**: Change focus-mode accent/background styling (`isActive ? Color.accentColor.opacity(0.06) : Color.clear`).

  **Recommended Agent Profile**:
  - Category: `unspecified-low` - Reason: sizing logic correction with low visual-risk scope.
  - Skills: [`karpathy-guidelines`] - why needed: avoid style drift.
  - Omitted: [`frontend-ui-ux`] - why not needed: no redesign.

  **Parallelization**: Can Parallel: NO | Wave 1 | Blocks: [3,5,6] | Blocked By: [1]

  **References** (executor has NO interview context - be exhaustive):
  - Pattern: `wa/WriterCardViews.swift:199-213` active/inactive content basis difference.
  - Pattern: `wa/WriterCardViews.swift:248-253` inactive inflation via `max(cached, activeBody)`.
  - Pattern: `wa/WriterCardViews.swift:261-269` observed + measured merge logic.
  - Pattern: `wa/WriterCardViews.swift:340` active background (must preserve).

  **Acceptance Criteria** (agent-executable only):
  - [ ] `WriterCardViews.swift` no longer uses a divergent trailing-newline trimming basis that changes active/inactive root height unexpectedly.
  - [ ] Active/inactive root-height computation path remains deterministic and compile-safe.
  - [ ] `xcodebuild -project wa.xcodeproj -target wa -configuration Debug -destination 'platform=macOS' build` succeeds.

  **QA Scenarios** (MANDATORY - task incomplete without these):
  ```
  Scenario: Height-basis convergence exists in source
    Tool: Bash
    Steps: run `python3 - <<'PY'
from pathlib import Path
text=Path('wa/WriterCardViews.swift').read_text(encoding='utf-8')
checks={
  'inactive_inflation_path_removed': 'max(cached, activeBody)' not in text,
  'observed_merge_still_present': 'resolvedActiveBody' in text and 'resolvedInactiveBody' in text,
}
Path('.sisyphus/evidence/task-2-height-basis-check.txt').write_text('\n'.join(f"{k}={'PASS' if v else 'FAIL'}" for k,v in checks.items()), encoding='utf-8')
raise SystemExit(0 if all(checks.values()) else 1)
PY`
    Expected: script exits 0 with PASS checks
    Evidence: .sisyphus/evidence/task-2-height-basis-check.txt

  Scenario: Failure guard for active-style regression
    Tool: Bash
    Steps: run `python3 - <<'PY'
from pathlib import Path
text=Path('wa/WriterCardViews.swift').read_text(encoding='utf-8')
ok='background(isActive ? Color.accentColor.opacity(0.06) : Color.clear)' in text
Path('.sisyphus/evidence/task-2-style-guard.txt').write_text('PASS' if ok else 'FAIL', encoding='utf-8')
raise SystemExit(0 if ok else 1)
PY`
    Expected: script exits 0 and style guard PASS
    Evidence: .sisyphus/evidence/task-2-style-guard.txt
  ```

  **Commit**: NO | Message: `n/a` | Files: [`wa/WriterCardViews.swift`]

- [x] 3. Replace Content-Keyed Observed-Height Mapping with Stable Attribution

  **What to do**: Remove fragile `card.content` keyed mapping in focus-mode normalization pass.
  - In `wa/WriterFocusMode.swift`, eliminate `remainingCardIDsByContent` matching.
  - Attribute observed body height using stable card identity only (active responder mapping and/or explicit editor-card ID association), not raw text equality.
  - Ensure duplicate card contents cannot cross-assign observed heights.

  **Must NOT do**: broaden scanner scope beyond focus-mode card contexts.

  **Recommended Agent Profile**:
  - Category: `unspecified-high` - Reason: identity attribution logic is bug-prone.
  - Skills: [`karpathy-guidelines`] - why needed: strict correctness over cleverness.
  - Omitted: [`git-master`] - why not needed: no history ops.

  **Parallelization**: Can Parallel: NO | Wave 1 | Blocks: [4,6,7] | Blocked By: [1,2]

  **References** (executor has NO interview context - be exhaustive):
  - Pattern: `wa/WriterFocusMode.swift:421-435` content-key map path to remove.
  - Pattern: `wa/WriterFocusMode.swift:550`, `wa/WriterFocusMode.swift:557-560` responder/card tracking signals.
  - Pattern: `wa/WriterFocusMode.swift:621-626` `focusResponderCardByObjectID` mapping source.

  **Acceptance Criteria** (agent-executable only):
  - [ ] No `remainingCardIDsByContent` content-key matching remains in `WriterFocusMode.swift`.
  - [ ] Observed-height assignment requires stable card identity mapping.
  - [ ] `xcodebuild -project wa.xcodeproj -target wa -configuration Debug -destination 'platform=macOS' build` succeeds.

  **QA Scenarios** (MANDATORY - task incomplete without these):
  ```
  Scenario: Content-key mapping removed
    Tool: Bash
    Steps: run `python3 - <<'PY'
from pathlib import Path
text=Path('wa/WriterFocusMode.swift').read_text(encoding='utf-8')
checks={
  'no_remainingCardIDsByContent':'remainingCardIDsByContent' not in text,
  'has_responder_card_mapping':'focusResponderCardByObjectID' in text,
}
Path('.sisyphus/evidence/task-3-mapping-check.txt').write_text('\n'.join(f"{k}={'PASS' if v else 'FAIL'}" for k,v in checks.items()), encoding='utf-8')
raise SystemExit(0 if all(checks.values()) else 1)
PY`
    Expected: script exits 0 with both PASS
    Evidence: .sisyphus/evidence/task-3-mapping-check.txt

  Scenario: Failure guard for duplicate-content hazard keywords
    Tool: Bash
    Steps: run `grep -n "textView.string\].*first\|remainingCardIDsByContent" wa/WriterFocusMode.swift > .sisyphus/evidence/task-3-duplicate-hazard.txt || true`
    Expected: output file is empty
    Evidence: .sisyphus/evidence/task-3-duplicate-hazard.txt
  ```

  **Commit**: NO | Message: `n/a` | Files: [`wa/WriterFocusMode.swift`]

- [x] 4. Prune Stale Observed-Height Cache and Gate Inactive Height Injection

  **What to do**: Ensure observed-height cache cannot keep stale inflated values.
  - Update writeback logic to prune entries for cards that are not reliably observed in the current pass.
  - Restrict observed-height injection for inactive cards where measurement confidence is low.
  - Preserve active-card live responder measurement support.

  **Must NOT do**: remove active-card live measurement (`liveResponderBodyHeight`) entirely.

  **Recommended Agent Profile**:
  - Category: `unspecified-low` - Reason: cache policy hardening.
  - Skills: [`karpathy-guidelines`] - why needed: low-blast-radius updates.
  - Omitted: [`frontend-ui-ux`] - why not needed: behavior-layer fix.

  **Parallelization**: Can Parallel: NO | Wave 1 | Blocks: [5,6] | Blocked By: [1,2,3]

  **References** (executor has NO interview context - be exhaustive):
  - Pattern: `wa/WriterFocusMode.swift:425` observed cache starts from previous map.
  - Pattern: `wa/WriterFocusMode.swift:469-470` observed cache writeback.
  - Pattern: `wa/WriterCardViews.swift:215-226` active live measurement path to preserve.

  **Acceptance Criteria** (agent-executable only):
  - [ ] Stale observed-height entries do not persist indefinitely between normalization passes.
  - [ ] Inactive cards are not inflated by uncertain observed-height samples.
  - [ ] `xcodebuild -project wa.xcodeproj -target wa -configuration Debug -destination 'platform=macOS' build` succeeds.

  **QA Scenarios** (MANDATORY - task incomplete without these):
  ```
  Scenario: Observed cache writeback includes prune/controlled assignment path
    Tool: Bash
    Steps: run `python3 - <<'PY'
from pathlib import Path
text=Path('wa/WriterFocusMode.swift').read_text(encoding='utf-8')
checks={
  'has_controlled_writeback':'focusObservedBodyHeightByCardID = ' in text,
  'no_unbounded_seed_from_previous':'var observedBodyByCard = focusObservedBodyHeightByCardID' not in text,
}
Path('.sisyphus/evidence/task-4-cache-prune-check.txt').write_text('\n'.join(f"{k}={'PASS' if v else 'FAIL'}" for k,v in checks.items()), encoding='utf-8')
raise SystemExit(0 if all(checks.values()) else 1)
PY`
    Expected: script exits 0 and checks PASS
    Evidence: .sisyphus/evidence/task-4-cache-prune-check.txt

  Scenario: Failure guard for active-live-measure regression
    Tool: Bash
    Steps: run `python3 - <<'PY'
from pathlib import Path
text=Path('wa/WriterCardViews.swift').read_text(encoding='utf-8')
ok='func liveResponderBodyHeight() -> CGFloat?' in text and 'guard isActive else { return nil }' in text
Path('.sisyphus/evidence/task-4-live-measure-guard.txt').write_text('PASS' if ok else 'FAIL', encoding='utf-8')
raise SystemExit(0 if ok else 1)
PY`
    Expected: script exits 0 and writes `PASS`
    Evidence: .sisyphus/evidence/task-4-live-measure-guard.txt
  ```

  **Commit**: NO | Message: `n/a` | Files: [`wa/WriterFocusMode.swift`, `wa/WriterCardViews.swift`]

- [x] 5. Decouple Caret/Offset Normalization from Height Re-Sampling Churn

  **What to do**: Reduce normalization-triggered layout churn while preserving caret visibility behavior.
  - Keep offset normalization, but gate observed-height sampling updates during high-frequency caret/selection passes.
  - Limit forced normalization bursts for steady-state selection changes.
  - Preserve scroll-end normalization path.

  **Must NOT do**: remove `ensureFocusModeCaretVisible` behavior or typewriter baseline logic.

  **Recommended Agent Profile**:
  - Category: `unspecified-low` - Reason: timing/loop stabilization in existing flow.
  - Skills: [`karpathy-guidelines`] - why needed: prevent unintended interaction regressions.
  - Omitted: [`playwright`] - why not needed: native app path + deterministic checks.

  **Parallelization**: Can Parallel: NO | Wave 2 | Blocks: [6,7] | Blocked By: [2,4]

  **References** (executor has NO interview context - be exhaustive):
  - Pattern: `wa/WriterFocusMode.swift:501-507` normalization burst scheduling.
  - Pattern: `wa/WriterFocusMode.swift:628-665` caret ensure + normalization request coupling.
  - Pattern: `wa/WriterFocusMode.swift:390-399` scroll-end monitor path (preserve).

  **Acceptance Criteria** (agent-executable only):
  - [ ] High-frequency caret ensure path no longer repeatedly mutates observed-height cache in steady typing/selection flow.
  - [ ] Scroll-end normalization remains active.
  - [ ] `xcodebuild -project wa.xcodeproj -target wa -configuration Debug -destination 'platform=macOS' build` succeeds.

  **QA Scenarios** (MANDATORY - task incomplete without these):
  ```
  Scenario: Burst/ensure coupling reduced for observed-height churn
    Tool: Bash
    Steps: run `python3 - <<'PY'
from pathlib import Path
text=Path('wa/WriterFocusMode.swift').read_text(encoding='utf-8')
checks={
  'scroll_end_path_present':'requestFocusModeOffsetNormalization(reason: "scroll-ended")' in text,
  'caret_ensure_still_present':'func requestFocusModeCaretEnsure' in text and 'ensureFocusModeCaretVisible' in text,
}
Path('.sisyphus/evidence/task-5-normalization-coupling-check.txt').write_text('\n'.join(f"{k}={'PASS' if v else 'FAIL'}" for k,v in checks.items()), encoding='utf-8')
raise SystemExit(0 if all(checks.values()) else 1)
PY`
    Expected: script exits 0 and checks PASS
    Evidence: .sisyphus/evidence/task-5-normalization-coupling-check.txt

  Scenario: Failure guard for unrelated main-mode scroll code edits
    Tool: Bash
    Steps: run `diff -u .sisyphus/evidence/baseline/WriterCaretAndScroll.swift wa/WriterCaretAndScroll.swift > .sisyphus/evidence/task-5-main-scroll-guard.diff || true`
    Expected: diff is empty
    Evidence: .sisyphus/evidence/task-5-main-scroll-guard.diff
  ```

  **Commit**: NO | Message: `n/a` | Files: [`wa/WriterFocusMode.swift`]

- [x] 6. Build + Invariant Verification Bundle

  **What to do**: Run deterministic verification and persist evidence outputs.
  - Execute project build.
  - Validate source invariants for mapping removal, stable routing, and preserved key behavior.

  **Must NOT do**: rely on manual-only visual validation as completion gate.

  **Recommended Agent Profile**:
  - Category: `quick` - Reason: command + static invariant checks.
  - Skills: [`karpathy-guidelines`] - why needed: binary pass/fail validation.
  - Omitted: [`frontend-ui-ux`] - why not needed: no design iteration task.

  **Parallelization**: Can Parallel: YES | Wave 2 | Blocks: [7] | Blocked By: [2,3,4,5]

  **References** (executor has NO interview context - be exhaustive):
  - Build command source: `wa.xcodeproj`, target `wa`.
  - Pattern: `wa/WriterFocusMode.swift:421-435` mapping path expected to change.
  - Pattern: `wa/WriterCardViews.swift:340` active style path expected unchanged.

  **Acceptance Criteria** (agent-executable only):
  - [ ] `.sisyphus/evidence/task-6-build.log` contains `BUILD SUCCEEDED`.
  - [ ] `.sisyphus/evidence/task-6-invariants.txt` contains all PASS.

  **QA Scenarios** (MANDATORY - task incomplete without these):
  ```
  Scenario: Build succeeds after focus-mode spacing stabilization changes
    Tool: Bash
    Steps: run `xcodebuild -project wa.xcodeproj -target wa -configuration Debug -destination 'platform=macOS' build | tee .sisyphus/evidence/task-6-build.log`
    Expected: build log contains `BUILD SUCCEEDED`
    Evidence: .sisyphus/evidence/task-6-build.log

  Scenario: Static invariants for spacing-stability fix
    Tool: Bash
    Steps: run `python3 - <<'PY'
from pathlib import Path
card=Path('wa/WriterCardViews.swift').read_text(encoding='utf-8')
focus=Path('wa/WriterFocusMode.swift').read_text(encoding='utf-8')
checks={
  'mapping_by_content_removed':'remainingCardIDsByContent' not in focus,
  'active_background_preserved':'background(isActive ? Color.accentColor.opacity(0.06) : Color.clear)' in card,
  'focus_observed_cache_used':'focusObservedBodyHeightByCardID' in focus,
}
Path('.sisyphus/evidence/task-6-invariants.txt').write_text('\n'.join(f"{k}={'PASS' if v else 'FAIL'}" for k,v in checks.items()), encoding='utf-8')
raise SystemExit(0 if all(checks.values()) else 1)
PY`
    Expected: script exits 0 and writes all PASS
    Evidence: .sisyphus/evidence/task-6-invariants.txt
  ```

  **Commit**: NO | Message: `n/a` | Files: [`.sisyphus/evidence/*`]

- [x] 7. Final Scope Gate and Changed-File Manifest

  **What to do**: Generate changed-file manifest vs baseline and enforce source scope.
  - Allowed source edits:
    - `wa/WriterCardViews.swift`
    - `wa/WriterFocusMode.swift`
    - `wa/WriterViews.swift`
  - `wa/WriterCaretAndScroll.swift` must remain unchanged.

  **Must NOT do**: complete if out-of-scope source files changed.

  **Recommended Agent Profile**:
  - Category: `quick` - Reason: deterministic final gate.
  - Skills: [`karpathy-guidelines`] - why needed: strict scope fidelity.
  - Omitted: [`git-master`] - why not needed: hash-based scope validation.

  **Parallelization**: Can Parallel: NO | Wave 2 | Blocks: [] | Blocked By: [1,3,5,6]

  **References** (executor has NO interview context - be exhaustive):
  - Baseline snapshots from Task 1 in `.sisyphus/evidence/baseline/`.
  - Scope boundaries in this plan.

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
 ('WriterCardViews.swift','wa/WriterCardViews.swift'),
 ('WriterFocusMode.swift','wa/WriterFocusMode.swift'),
 ('WriterViews.swift','wa/WriterViews.swift'),
 ('WriterCaretAndScroll.swift','wa/WriterCaretAndScroll.swift'),
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
    Expected: manifest lists changed source files
    Evidence: .sisyphus/evidence/task-7-changed-files.txt

  Scenario: Out-of-scope guard
    Tool: Bash
    Steps: run `python3 - <<'PY'
from pathlib import Path
allowed={'wa/WriterCardViews.swift','wa/WriterFocusMode.swift','wa/WriterViews.swift'}
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
- No commit step in this plan because current workspace has no git metadata.
- If execution is moved into a git checkout, create one atomic commit after Task 7 with: `fix(focus-mode): stabilize card vertical spacing and remove inactive bottom-gap wobble`.

## Success Criteria
- Focus-mode cards maintain consistent paper-like vertical rhythm during active/inactive transitions.
- Long inactive cards do not display inflated bottom blank area.
- Duplicate-content scenarios no longer cause observed-height misassignment side effects.
