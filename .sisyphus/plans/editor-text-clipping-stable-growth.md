# Main Editor Right-Edge Clipping Fix (No Growth Regression)

## TL;DR
> **Summary**: Remove right-edge clipping in main edit mode by aligning AppKit container-width math with current card padding/measurement rules, while keeping row/card growth sequencing unchanged.
> **Deliverables**:
> - Shared main-editor layout metrics used by both SwiftUI and AppKit sizing paths
> - Main editor container-width clamp fix in `applyMainEditorLineSpacingIfNeeded`
> - Active-edit width-change reapply hook for resize stability
> - Baseline-diff and invariant evidence bundle under `.sisyphus/evidence/`
> **Effort**: Short
> **Parallel**: YES - 2 waves
> **Critical Path**: Task 1 -> Task 2 -> Task 3 -> Task 4 -> Task 6

## Context
### Original Request
Main work window edit mode clips text at the right edge. Fix only clipping inside the card's right padding area, and keep the current natural behavior when lines are added (no row/card timing regressions).

### Interview Summary
- Scope is main workspace edit mode (not focus-mode redesign, not animation rewrite).
- User explicitly prioritizes preserving existing row/card growth feel.
- Prior regressions to avoid: row appears before card growth, card grows before row appears, row drops below then pops in.

### Metis Review (gaps addressed)
- Confirmed mismatch risk: `wa/WriterCaretAndScroll.swift:6` padding assumptions diverge from `wa/WriterCardViews.swift:375` main editor padding derivation.
- Added strict guardrail to avoid touching insertion/animation/zoom-clipping paths.
- Replaced git-dependent verification with baseline snapshot + hash/invariant checks (workspace is not a git repo).

## Work Objectives
### Core Objective
Fix right-edge clipping in main edit mode by changing only container-width synchronization logic and supporting metrics alignment.

### Deliverables
- `MainEditorLayoutMetrics` constants in shared types.
- Updated width candidate/clamp logic in `applyMainEditorLineSpacingIfNeeded`.
- Width-change reapply hook in `MainCardWidthPreferenceKey` handling for active edit card.
- Evidence artifacts proving scope fidelity and build success.

### Definition of Done (verifiable conditions with commands)
- `xcodebuild -project wa.xcodeproj -target wa -configuration Debug -destination 'platform=macOS' build` outputs `BUILD SUCCEEDED`.
- `.sisyphus/evidence/task-7-changed-files.txt` contains only:
  - `wa/WriterSharedTypes.swift`
  - `wa/WriterCardViews.swift`
  - `wa/WriterCaretAndScroll.swift`
  - `wa/WriterCardManagement.swift`
- `.sisyphus/evidence/task-5-writerviews.diff` is empty (zoom `.clipped()` path unchanged).
- `.sisyphus/evidence/task-6-invariants.txt` reports all checks `PASS`.

### Must Have
- Main editor no longer clips text at right edge in edit mode.
- Existing growth-sequencing behavior remains unchanged.
- Width math never allows text container width to exceed viewport width.
- Fix applies only to main editor path; focus mode behavior remains unchanged.

### Must NOT Have (guardrails, AI slop patterns, scope boundaries)
- No changes to insertion API behavior (`insertSibling`, `addChildCard`, `addFloatingCard`).
- No changes to `quickEaseAnimation` or zoom wrapper/clipping structure.
- No card-style redesign, spacing redesign, or typography changes.
- No test-target bootstrap in this patch.

## Verification Strategy
> ZERO HUMAN INTERVENTION - all verification is agent-executed.
- Test decision: tests-after (no XCTest targets in this project).
- QA policy: every task includes happy + failure/edge checks.
- Evidence: `.sisyphus/evidence/task-{N}-{slug}.{ext}`

## Execution Strategy
### Parallel Execution Waves
> Target: 5-8 tasks per wave. <3 per wave (except final) = under-splitting.
> Shared dependencies extracted into Wave 1 for safe parallelism.

Wave 1: Baseline capture + metrics alignment + width fix + width-sync hook (Tasks 1-4)
Wave 2: Regression audit + build/invariants + changed-file manifest (Tasks 5-7)

### Dependency Matrix (full, all tasks)
- Task 1: Blocked By [] | Blocks [2,3,4,5,7]
- Task 2: Blocked By [1] | Blocks [3,6]
- Task 3: Blocked By [1,2] | Blocks [5,6]
- Task 4: Blocked By [1,2] | Blocks [5,6]
- Task 5: Blocked By [1,3,4] | Blocks [7]
- Task 6: Blocked By [3,4] | Blocks [7]
- Task 7: Blocked By [1,5,6] | Blocks []

### Agent Dispatch Summary (wave -> task count -> categories)
- Wave 1 -> 4 tasks -> `quick`, `unspecified-low`
- Wave 2 -> 3 tasks -> `unspecified-high`, `quick`

## TODOs
> Implementation + Test = ONE task. Never separate.
> EVERY task MUST have: Agent Profile + Parallelization + QA Scenarios.

- [ ] 1. Create Evidence Workspace and Baseline Snapshots

  **What to do**: Initialize `.sisyphus/evidence/` and snapshot baseline copies before any code edits.
  - Create `.sisyphus/evidence/baseline/`.
  - Copy baseline files:
    - `wa/WriterViews.swift`
    - `wa/WriterCardManagement.swift`
    - `wa/WriterCardViews.swift`
    - `wa/WriterCaretAndScroll.swift`
    - `wa/WriterSharedTypes.swift`
  - Generate `sha256` manifest for baseline files.

  **Must NOT do**: Modify production code in this task.

  **Recommended Agent Profile**:
  - Category: `quick` - Reason: setup-only, deterministic.
  - Skills: [`karpathy-guidelines`] - why needed: strict pre-change baseline discipline.
  - Omitted: [`git-master`] - why not needed: workspace has no git metadata.

  **Parallelization**: Can Parallel: NO | Wave 1 | Blocks: [2,3,4,5,7] | Blocked By: []

  **References** (executor has NO interview context - be exhaustive):
  - Pattern: `wa/WriterViews.swift:502` - protected zoom wrapper baseline.
  - Pattern: `wa/WriterCardManagement.swift:202` - upcoming width-handler edit location.
  - Pattern: `wa/WriterCardViews.swift:372` - padding constants baseline.
  - Pattern: `wa/WriterCaretAndScroll.swift:154` - width-calculation baseline.

  **Acceptance Criteria** (agent-executable only):
  - [ ] `.sisyphus/evidence/baseline/` contains all 5 snapshot files.
  - [ ] `.sisyphus/evidence/task-1-baseline-sha256.txt` exists and has 5 lines.

  **QA Scenarios** (MANDATORY - task incomplete without these):
  ```
  Scenario: Baseline snapshot creation succeeds
    Tool: Bash
    Steps: run `mkdir -p .sisyphus/evidence/baseline && cp wa/WriterViews.swift wa/WriterCardManagement.swift wa/WriterCardViews.swift wa/WriterCaretAndScroll.swift wa/WriterSharedTypes.swift .sisyphus/evidence/baseline/ && shasum -a 256 .sisyphus/evidence/baseline/*.swift > .sisyphus/evidence/task-1-baseline-sha256.txt`
    Expected: baseline directory has 5 files and hash manifest is written
    Evidence: .sisyphus/evidence/task-1-baseline-sha256.txt

  Scenario: Failure guard for missing baseline assets
    Tool: Bash
    Steps: run `python3 - <<'PY'
from pathlib import Path
expected = {'WriterViews.swift','WriterCardManagement.swift','WriterCardViews.swift','WriterCaretAndScroll.swift','WriterSharedTypes.swift'}
actual = {p.name for p in Path('.sisyphus/evidence/baseline').glob('*.swift')}
missing = sorted(expected - actual)
Path('.sisyphus/evidence/task-1-baseline-check.txt').write_text('PASS' if not missing else '\n'.join(missing), encoding='utf-8')
raise SystemExit(0 if not missing else 1)
PY`
    Expected: script exits 0 and writes `PASS`
    Evidence: .sisyphus/evidence/task-1-baseline-check.txt
  ```

  **Commit**: NO | Message: `n/a` | Files: [`.sisyphus/evidence/*`]

- [ ] 2. Introduce Shared Main Editor Layout Metrics

  **What to do**: Add shared constants in `wa/WriterSharedTypes.swift` and wire `CardItem` to those constants without behavioral change.
  - Add `MainEditorLayoutMetrics` with values matching current behavior:
    - `mainCardContentPadding = 24`
    - `mainEditorLineFragmentPadding = 5`
    - `mainEditorHorizontalPadding = max(0, mainCardContentPadding - mainEditorLineFragmentPadding)`
    - `mainEditorEffectiveInset = mainEditorHorizontalPadding + mainEditorLineFragmentPadding`
  - Replace local constants in `wa/WriterCardViews.swift` to reference shared metrics.

  **Must NOT do**: Change modifier order, frame logic, line-spacing behavior, or animation.

  **Recommended Agent Profile**:
  - Category: `quick` - Reason: localized refactor.
  - Skills: [`karpathy-guidelines`] - why needed: no accidental behavior drift.
  - Omitted: [`frontend-ui-ux`] - why not needed: no design updates.

  **Parallelization**: Can Parallel: NO | Wave 1 | Blocks: [3,4,6] | Blocked By: [1]

  **References** (executor has NO interview context - be exhaustive):
  - Pattern: `wa/WriterCardViews.swift:372` - existing card content padding value.
  - Pattern: `wa/WriterCardViews.swift:374` - existing line fragment padding value.
  - Pattern: `wa/WriterCardViews.swift:375` - current horizontal padding derivation.
  - Pattern: `wa/WriterCardViews.swift:413` - width measure math using effective inset.
  - API/Type: `wa/WriterSharedTypes.swift` - destination for shared metrics type.

  **Acceptance Criteria** (agent-executable only):
  - [ ] `wa/WriterSharedTypes.swift` includes `MainEditorLayoutMetrics` with exact numeric values above.
  - [ ] `wa/WriterCardViews.swift` no longer duplicates those literals for main editor metrics.
  - [ ] `xcodebuild -project wa.xcodeproj -target wa -configuration Debug -destination 'platform=macOS' build` succeeds.

  **QA Scenarios** (MANDATORY - task incomplete without these):
  ```
  Scenario: Shared metrics are wired into CardItem
    Tool: Bash
    Steps: run `python3 - <<'PY'
from pathlib import Path
shared = Path('wa/WriterSharedTypes.swift').read_text(encoding='utf-8')
card = Path('wa/WriterCardViews.swift').read_text(encoding='utf-8')
checks = {
  'metrics_type_present': 'MainEditorLayoutMetrics' in shared,
  'card_uses_shared_metrics': 'MainEditorLayoutMetrics' in card,
}
Path('.sisyphus/evidence/task-2-metrics-check.txt').write_text('\n'.join(f"{k}={'PASS' if v else 'FAIL'}" for k,v in checks.items()), encoding='utf-8')
raise SystemExit(0 if all(checks.values()) else 1)
PY`
    Expected: script exits 0 and all checks are PASS
    Evidence: .sisyphus/evidence/task-2-metrics-check.txt

  Scenario: Failure guard against baseline drift in protected zoom file
    Tool: Bash
    Steps: run `diff -u .sisyphus/evidence/baseline/WriterViews.swift wa/WriterViews.swift > .sisyphus/evidence/task-2-writerviews.diff || true`
    Expected: diff output is empty
    Evidence: .sisyphus/evidence/task-2-writerviews.diff
  ```

  **Commit**: NO | Message: `n/a` | Files: [`wa/WriterSharedTypes.swift`, `wa/WriterCardViews.swift`]

- [ ] 3. Fix Main Editor Container Width Math and Clamp

  **What to do**: Update `applyMainEditorLineSpacingIfNeeded` in `wa/WriterCaretAndScroll.swift`.
  - Use `MainEditorLayoutMetrics.mainEditorEffectiveInset` for measured-card width conversion.
  - Keep fallback to `viewportWidth` when measured width is unavailable (`<= 1`).
  - Clamp final width: `targetWidth = max(1, min(viewportWidth, candidateWidth))`.
  - Add DEBUG assertion that `targetWidth <= viewportWidth + 0.5`.

  **Must NOT do**: Change paragraph style updates, typing attributes flow, or `widthTracksTextView` policy.

  **Recommended Agent Profile**:
  - Category: `quick` - Reason: single-function bug fix.
  - Skills: [`karpathy-guidelines`] - why needed: narrow safe change.
  - Omitted: [`git-master`] - why not needed: no git operations in this workspace.

  **Parallelization**: Can Parallel: NO | Wave 1 | Blocks: [5,6] | Blocked By: [1,2]

  **References** (executor has NO interview context - be exhaustive):
  - Pattern: `wa/WriterCaretAndScroll.swift:154` - viewport width source.
  - Pattern: `wa/WriterCaretAndScroll.swift:166` - current measured-width branch.
  - Pattern: `wa/WriterCaretAndScroll.swift:168` - container width assignment site.
  - Pattern: `wa/WriterCardViews.swift:413` - matching width-measure behavior.
  - Pattern: `wa/WriterCardViews.swift:509` - main editor horizontal padding remains unchanged.

  **Acceptance Criteria** (agent-executable only):
  - [ ] Source contains clamp expression with `min(viewportWidth, ...)`.
  - [ ] Source contains DEBUG assertion enforcing width <= viewport + tolerance.
  - [ ] `xcodebuild -project wa.xcodeproj -target wa -configuration Debug -destination 'platform=macOS' build` succeeds.

  **QA Scenarios** (MANDATORY - task incomplete without these):
  ```
  Scenario: Clamp and assertion are present
    Tool: Bash
    Steps: run `python3 - <<'PY'
from pathlib import Path
text = Path('wa/WriterCaretAndScroll.swift').read_text(encoding='utf-8')
checks = {
  'has_viewport_clamp': 'min(viewportWidth' in text,
  'has_debug_assert': 'assert(targetWidth <= viewportWidth + 0.5' in text,
}
Path('.sisyphus/evidence/task-3-clamp-check.txt').write_text('\n'.join(f"{k}={'PASS' if v else 'FAIL'}" for k,v in checks.items()), encoding='utf-8')
raise SystemExit(0 if all(checks.values()) else 1)
PY`
    Expected: script exits 0 and all checks are PASS
    Evidence: .sisyphus/evidence/task-3-clamp-check.txt

  Scenario: Failure guard against paragraph-style block edits
    Tool: Bash
    Steps: run `python3 - <<'PY'
from pathlib import Path
base = Path('.sisyphus/evidence/baseline/WriterCaretAndScroll.swift').read_text(encoding='utf-8')
curr = Path('wa/WriterCaretAndScroll.swift').read_text(encoding='utf-8')
tokens = ['typingAttributes', 'defaultParagraphStyle', 'paragraphStyle']
changed = [t for t in tokens if (base.count(t) != curr.count(t))]
Path('.sisyphus/evidence/task-3-spacing-guard.txt').write_text('PASS' if not changed else '\n'.join(changed), encoding='utf-8')
raise SystemExit(0 if not changed else 1)
PY`
    Expected: script exits 0 and writes `PASS`
    Evidence: .sisyphus/evidence/task-3-spacing-guard.txt
  ```

  **Commit**: NO | Message: `n/a` | Files: [`wa/WriterCaretAndScroll.swift`]

- [ ] 4. Reapply Container Sync on Active Width Preference Changes

  **What to do**: Update `onPreferenceChange(MainCardWidthPreferenceKey.self)` in `wa/WriterCardManagement.swift` to re-run main editor line-spacing/container sync when active editing card width changes.
  - Compare previous vs new width for `editingCardID` after merge.
  - Trigger only when delta > 0.25 and `!showFocusMode`.
  - Execute without animation wrappers.

  **Must NOT do**: Modify height preference logic, auto-scroll decisions, or insertion APIs.

  **Recommended Agent Profile**:
  - Category: `unspecified-low` - Reason: small state-aware hook.
  - Skills: [`karpathy-guidelines`] - why needed: preserve sequencing behavior.
  - Omitted: [`frontend-ui-ux`] - why not needed: no UI restyling.

  **Parallelization**: Can Parallel: NO | Wave 1 | Blocks: [5,6] | Blocked By: [1,2]

  **References** (executor has NO interview context - be exhaustive):
  - Pattern: `wa/WriterCardManagement.swift:202` - width preference merge block.
  - Pattern: `wa/WriterCardManagement.swift:189` - nearby height preference logic (must remain unchanged).
  - API/Type: `wa/WriterViews.swift:147` - `mainCardWidths` state source.
  - Pattern: `wa/WriterCaretAndScroll.swift:122` - reapply function.

  **Acceptance Criteria** (agent-executable only):
  - [ ] Width-sync call path triggers only for active edit card width delta > 0.25.
  - [ ] No `withAnimation` added in the edited handler.
  - [ ] `xcodebuild -project wa.xcodeproj -target wa -configuration Debug -destination 'platform=macOS' build` succeeds.

  **QA Scenarios** (MANDATORY - task incomplete without these):
  ```
  Scenario: Width-change hook added correctly
    Tool: Bash
    Steps: run `python3 - <<'PY'
from pathlib import Path
text = Path('wa/WriterCardManagement.swift').read_text(encoding='utf-8')
checks = {
  'has_width_pref_handler': 'MainCardWidthPreferenceKey' in text,
  'has_reapply_call': 'applyMainEditorLineSpacingIfNeeded' in text,
}
Path('.sisyphus/evidence/task-4-width-hook-check.txt').write_text('\n'.join(f"{k}={'PASS' if v else 'FAIL'}" for k,v in checks.items()), encoding='utf-8')
raise SystemExit(0 if all(checks.values()) else 1)
PY`
    Expected: script exits 0 and all checks are PASS
    Evidence: .sisyphus/evidence/task-4-width-hook-check.txt

  Scenario: Failure guard for insertion API edits
    Tool: Bash
    Steps: run `diff -u .sisyphus/evidence/baseline/WriterCardManagement.swift wa/WriterCardManagement.swift > .sisyphus/evidence/task-4-cardmgmt.diff || true`
    Expected: diff shows only width-preference handler changes; no changes in `insertSibling`/`addChildCard`/`addFloatingCard`
    Evidence: .sisyphus/evidence/task-4-cardmgmt.diff
  ```

  **Commit**: NO | Message: `n/a` | Files: [`wa/WriterCardManagement.swift`]

- [ ] 5. Run Regression-Fence Diffs on Protected Paths

  **What to do**: Diff current files against baseline snapshots and fail if protected paths drift.
  - Ensure `wa/WriterViews.swift` is unchanged.
  - Ensure `wa/WriterCardViews.swift` changes are limited to metric-source rewiring.

  **Must NOT do**: Ignore unexpected diffs in protected files.

  **Recommended Agent Profile**:
  - Category: `unspecified-high` - Reason: strict regression containment.
  - Skills: [`karpathy-guidelines`] - why needed: hard guardrails.
  - Omitted: [`playwright`] - why not needed: static diff audit task.

  **Parallelization**: Can Parallel: YES | Wave 2 | Blocks: [7] | Blocked By: [1,3,4]

  **References** (executor has NO interview context - be exhaustive):
  - Pattern: `wa/WriterViews.swift:502` - protected zoom function.
  - Pattern: `wa/WriterViews.swift:516` - protected `.clipped()` call.
  - Pattern: `wa/WriterCardViews.swift:477` - measured-height path that must not be rewritten.

  **Acceptance Criteria** (agent-executable only):
  - [ ] `.sisyphus/evidence/task-5-writerviews.diff` is empty.
  - [ ] `.sisyphus/evidence/task-5-cardviews.diff` contains only metric-constant wiring changes.

  **QA Scenarios** (MANDATORY - task incomplete without these):
  ```
  Scenario: Protected workspace file unchanged
    Tool: Bash
    Steps: run `diff -u .sisyphus/evidence/baseline/WriterViews.swift wa/WriterViews.swift > .sisyphus/evidence/task-5-writerviews.diff || true`
    Expected: diff file is empty
    Evidence: .sisyphus/evidence/task-5-writerviews.diff

  Scenario: Failure guard for CardItem growth-pipeline drift
    Tool: Bash
    Steps: run `diff -u .sisyphus/evidence/baseline/WriterCardViews.swift wa/WriterCardViews.swift > .sisyphus/evidence/task-5-cardviews.diff || true`
    Expected: no edits to `resolvedMainEditingBodyHeight`, `refreshMainEditingMeasuredBodyHeight`, or TextEditor modifier order
    Evidence: .sisyphus/evidence/task-5-cardviews.diff
  ```

  **Commit**: NO | Message: `n/a` | Files: [`.sisyphus/evidence/*`]

- [ ] 6. Execute Build and Invariant Checks

  **What to do**: Run deterministic verification commands and persist outputs.
  - Build app target.
  - Run invariant script ensuring clamp/assert symbols exist.

  **Must NOT do**: Treat manual UI inspection as completion criteria.

  **Recommended Agent Profile**:
  - Category: `quick` - Reason: command execution + binary validation.
  - Skills: [`karpathy-guidelines`] - why needed: strict pass/fail checks.
  - Omitted: [`frontend-ui-ux`] - why not needed: non-design task.

  **Parallelization**: Can Parallel: YES | Wave 2 | Blocks: [7] | Blocked By: [3,4]

  **References** (executor has NO interview context - be exhaustive):
  - Build target: `wa` from `xcodebuild -list -project wa.xcodeproj`.
  - Pattern: `wa/WriterCaretAndScroll.swift:166` - candidate width calculation.
  - Pattern: `wa/WriterCaretAndScroll.swift:168` - final target width write.

  **Acceptance Criteria** (agent-executable only):
  - [ ] `.sisyphus/evidence/task-6-build.log` contains `BUILD SUCCEEDED`.
  - [ ] `.sisyphus/evidence/task-6-invariants.txt` reports all checks PASS.

  **QA Scenarios** (MANDATORY - task incomplete without these):
  ```
  Scenario: Build succeeds after patch
    Tool: Bash
    Steps: run `xcodebuild -project wa.xcodeproj -target wa -configuration Debug -destination 'platform=macOS' build | tee .sisyphus/evidence/task-6-build.log`
    Expected: log contains `BUILD SUCCEEDED`
    Evidence: .sisyphus/evidence/task-6-build.log

  Scenario: Failure guard for missing clamp/assert
    Tool: Bash
    Steps: run `python3 - <<'PY'
from pathlib import Path
text = Path('wa/WriterCaretAndScroll.swift').read_text(encoding='utf-8')
checks = {
  'has_viewport_clamp': 'min(viewportWidth' in text,
  'has_debug_assert': 'assert(targetWidth <= viewportWidth + 0.5' in text,
}
Path('.sisyphus/evidence/task-6-invariants.txt').write_text('\n'.join(f"{k}={'PASS' if v else 'FAIL'}" for k,v in checks.items()), encoding='utf-8')
raise SystemExit(0 if all(checks.values()) else 1)
PY`
    Expected: script exits 0 and writes all PASS lines
    Evidence: .sisyphus/evidence/task-6-invariants.txt
  ```

  **Commit**: NO | Message: `n/a` | Files: [`.sisyphus/evidence/*`]

- [ ] 7. Generate Final Changed-File Manifest and Scope Gate

  **What to do**: Compare current file hashes to baseline hashes and produce a final changed-file list with hard scope validation.
  - Compute changed files among the 5 tracked baseline files.
  - Fail if changed set includes anything outside approved code files.

  **Must NOT do**: Mark complete if scope gate fails.

  **Recommended Agent Profile**:
  - Category: `quick` - Reason: deterministic final gate.
  - Skills: [`karpathy-guidelines`] - why needed: strict completion criteria.
  - Omitted: [`git-master`] - why not needed: hash-based scope gate replaces git checks.

  **Parallelization**: Can Parallel: NO | Wave 2 | Blocks: [] | Blocked By: [1,5,6]

  **References** (executor has NO interview context - be exhaustive):
  - Baseline manifest: `.sisyphus/evidence/task-1-baseline-sha256.txt`
  - Approved change set: `wa/WriterSharedTypes.swift`, `wa/WriterCardViews.swift`, `wa/WriterCaretAndScroll.swift`, `wa/WriterCardManagement.swift`

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
base_dir = Path('.sisyphus/evidence/baseline')
pairs = [
  ('WriterViews.swift','wa/WriterViews.swift'),
  ('WriterCardManagement.swift','wa/WriterCardManagement.swift'),
  ('WriterCardViews.swift','wa/WriterCardViews.swift'),
  ('WriterCaretAndScroll.swift','wa/WriterCaretAndScroll.swift'),
  ('WriterSharedTypes.swift','wa/WriterSharedTypes.swift'),
]
changed = []
for b,c in pairs:
  hb = hashlib.sha256((base_dir / b).read_bytes()).hexdigest()
  hc = hashlib.sha256(Path(c).read_bytes()).hexdigest()
  if hb != hc:
    changed.append(c)
Path('.sisyphus/evidence/task-7-changed-files.txt').write_text('\n'.join(changed), encoding='utf-8')
PY`
    Expected: manifest lists only files that actually changed
    Evidence: .sisyphus/evidence/task-7-changed-files.txt

  Scenario: Failure guard for out-of-scope code changes
    Tool: Bash
    Steps: run `python3 - <<'PY'
from pathlib import Path
allowed = {
  'wa/WriterSharedTypes.swift',
  'wa/WriterCardViews.swift',
  'wa/WriterCaretAndScroll.swift',
  'wa/WriterCardManagement.swift',
}
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
- No commit step in this plan because the current workspace has no git metadata.
- If execution is moved into a git checkout, perform one atomic commit after Task 7 with: `fix(editor): stop right-edge clipping without altering growth timing`.

## Success Criteria
- Main edit-mode right-edge clipping is removed.
- Row/card growth sequencing remains behaviorally unchanged.
- Scope gate passes and all evidence files are present.
