# Settings Menu No-Scroll Relayout

## TL;DR
> **Summary**: `SettingsView`를 3탭 구조는 유지한 채 탭별 2열 카드형 레이아웃으로 재배치해, `1120x700` 설정 창에서 스크롤 없이 한눈에 보이도록 단순화한다. 기능/스토리지 키/부수효과 동작은 그대로 보존한다.
> **Deliverables**:
> - `wa/waApp.swift`의 `SettingsView` 레이아웃 재구성(3탭 유지, 2열 배치)
> - 탭 내부 `ScrollView` 제거 및 무스크롤 고정 레이아웃 적용
> - Gemini/Whisper/Workspace 액션 및 `@AppStorage` 키 보존 검증
> - 빌드 + 정적 불변조건 + QA 증거 산출
> **Effort**: Medium
> **Parallel**: YES - 2 waves
> **Critical Path**: Task 1 -> (Task 2, Task 3, Task 4) -> Task 5 -> Task 6 -> Task 7 -> Task 8

## Context
### Original Request
- 설정 메뉴가 장황하고 세로로 길게 늘어져 사용성이 낮음.
- 다른 앱들처럼 보기 좋고 쓰기 쉽게 재배치.
- 스크롤 없이 한눈에 들어오게 구성.

### Interview Summary
- 사용자 확정 결정:
  - IA: `3탭 유지 + 탭별 2열 배치`
  - 단축키: `별도 탭 유지`
- 기본값 적용(무응답 tradeoff):
  - 테스트 전략: `tests-after` (추가 테스트 인프라 도입 없이 빌드 + 정적 검증 + 에이전트 QA)
  - 창 크기: 기존 `1120x700` 유지

### Metis Review (gaps addressed)
- 반영한 가드레일:
  - `@AppStorage` 키/기본값/의미 변경 금지
  - Gemini/Whisper/Workspace 부수효과 엔트리포인트 및 disable 조건 유지
  - 변경 범위는 `wa/waApp.swift`의 `SettingsView` 중심으로 제한
  - 무스크롤을 clipping으로 달성하지 않고, 밀도/정렬/행높이 관리로 달성
- 반영한 리스크 통제:
  - 키 rename/삭제로 인한 전역 UI 회귀 방지 정적 체크 추가
  - `onAppear` 초기화 시퀀스(`refreshGeminiAPIKeyStatus`, `syncGeminiModelOptionSelection`, `loadWhisperPathInputsFromResolvedConfig`, `refreshWhisperStatusFromInputs`) 보존 검증 추가

## Work Objectives
### Core Objective
- 설정 화면을 스캔 가능한 고밀도 2열 정보 구조로 재배치해 스크롤 의존성을 제거하면서, 기존 설정 기능과 동작을 100% 유지한다.

### Deliverables
- `SettingsView.body`의 탭별 레이아웃 재구성
- 탭 콘텐츠 컨테이너의 `ScrollView` 제거
- 섹션 카드화/정렬 규칙/간격 규칙 적용
- 보존 불변조건 자동 검증 스크립트 및 증거 파일

### Definition of Done (verifiable conditions with commands)
- `xcodebuild -project "wa.xcodeproj" -scheme "wa" -configuration Debug -destination 'platform=macOS' build` 결과에 `** BUILD SUCCEEDED **` 포함
- `SettingsView` 블록(`struct SettingsView: View` ~ `struct MainContainerView: View`) 내부 문자열에서 `ScrollView` 토큰이 0회
- `SettingsTab`의 3 케이스(`editorAndTheme`, `outputAIStorage`, `shortcuts`) 유지
- 주요 부수효과 함수 선언 유지:
  - `saveGeminiAPIKey`, `deleteGeminiAPIKey`, `installOrUpdateWhisper`, `openWorkspaceFile`, `createWorkspaceFile`
- 핵심 `@AppStorage` 키 사용 유지:
  - `appearance`, `backgroundColorHex`, `darkBackgroundColorHex`, `cardBaseColorHex`, `storageBookmark`, `forceWorkspaceReset`, `geminiModelID`, `whisperInstallRootPath`

### Must Have
- 3탭 유지 + 탭별 2열 카드형 레이아웃
- 무스크롤(기본 창 크기 1120x700 기준)
- 모든 기존 설정 조작 요소 유지(숨김/삭제 금지)
- Gemini/Whisper/Workspace 액션 동작 동일

### Must NOT Have (guardrails, AI slop patterns, scope boundaries)
- `@AppStorage` 키 rename/remove/default 변경 금지
- Keychain/Whisper/storage bookmark 식별자 변경 금지
- 비설정 화면(에디터/포커스/히스토리) 변경 금지
- 새 기능 추가(검색, import/export settings 등) 금지
- 설정 창 크기 확장으로 문제를 회피하는 방식 금지

## Verification Strategy
> ZERO HUMAN INTERVENTION — all verification is agent-executed.
- Test decision: tests-after + existing Xcode build workflow
- QA policy: Every task has agent-executed scenarios
- Evidence: `.sisyphus/evidence/task-{N}-{slug}.{ext}`

## Execution Strategy
### Parallel Execution Waves
> Target: 5-8 tasks per wave. <3 per wave (except final) = under-splitting.
> Extract shared dependencies as Wave-1 tasks for max parallelism.

Wave 1: foundation + per-tab relayout (Tasks 1-5)
- Shared primitives
- Tab 1 relayout
- Tab 2 relayout
- Tab 3 relayout
- ScrollView 제거 + no-scroll 보정

Wave 2: integrity + regression verification (Tasks 6-8)
- Side-effect/state binding integrity
- Layout invariants/static checks + evidence
- Build + regression bundle + commit prep

### Dependency Matrix (full, all tasks)
| Task | Blocks | Blocked By |
|---|---|---|
| 1 | 2,3,4,5 | - |
| 2 | 5 | 1 |
| 3 | 5 | 1 |
| 4 | 5 | 1 |
| 5 | 6,7,8 | 2,3,4 |
| 6 | 8 | 5 |
| 7 | 8 | 5 |
| 8 | Final Verification Wave | 6,7 |

### Agent Dispatch Summary (wave → task count → categories)
| Wave | Task Count | Categories |
|---|---:|---|
| Wave 1 | 5 | visual-engineering, quick |
| Wave 2 | 3 | unspecified-high, quick |
| Final Verification | 4 | oracle, unspecified-high, unspecified-high(+playwright if UI), deep |

## TODOs
> Implementation + Test = ONE task. Never separate.
> EVERY task MUST have: Agent Profile + Parallelization + QA Scenarios.

- [ ] 1. Shared Layout Primitive 도입 (SettingsView 한정)

  **What to do**: `wa/waApp.swift`의 `SettingsView` 내부에 레이아웃 결정값과 재사용 뷰 helper를 추가한다. 정확히 다음 식별자를 도입한다: `SettingsLayout`, `settingsCard(title:content:)`, `twoColumnContent(left:right:)`. 창 크기 상수는 기존과 동일하게 `1120x700`으로 정의하고 `TabView` frame 적용에 재사용한다.
  **Must NOT do**: 기존 상태/액션 함수(`saveGeminiAPIKey`, `installOrUpdateWhisper` 등) 시그니처/로직 변경 금지.

  **Recommended Agent Profile**:
  - Category: `visual-engineering` — Reason: SwiftUI 레이아웃 구조화 작업의 일관성 확보
  - Skills: [`frontend-ui-ux`] — 레이아웃 밀도와 가독성 균형 조정
  - Omitted: [`playwright`] — 브라우저 UI 대상이 아님

  **Parallelization**: Can Parallel: NO | Wave 1 | Blocks: [2, 3, 4, 5] | Blocked By: []

  **References** (executor has NO interview context — be exhaustive):
  - Pattern: `wa/waApp.swift:644` — `SettingsView.body` 루트 구조 시작점
  - Pattern: `wa/waApp.swift:964` — 설정창 고정 frame 적용 위치
  - Pattern: `wa/waApp.swift:973` — SettingsView 내부 view helper 작성 패턴(`shortcutRow`)
  - API/Type: `wa/waApp.swift:634` — `SettingsTab` enum

  **Acceptance Criteria** (agent-executable only):
  - [ ] `wa/waApp.swift`에 `SettingsLayout`, `settingsCard(title:content:)`, `twoColumnContent(left:right:)`가 모두 존재한다 (`grep`으로 검증).
  - [ ] `TabView` frame이 `SettingsLayout` 상수를 통해 적용된다 (`python` AST/문자열 검증).

  **QA Scenarios** (MANDATORY — task incomplete without these):
  ```
  Scenario: Shared primitive 생성 확인
    Tool: Bash
    Steps: mkdir -p .sisyphus/evidence && grep -n "SettingsLayout\|settingsCard(title:content:)\|twoColumnContent(left:right:)" wa/waApp.swift > .sisyphus/evidence/task-1-layout-primitives.txt
    Expected: 3개 식별자가 모두 검색되며 evidence 파일에 기록됨
    Evidence: .sisyphus/evidence/task-1-layout-primitives.txt

  Scenario: 레거시 frame 상수 하드코딩 잔존 검출
    Tool: Bash
    Steps: mkdir -p .sisyphus/evidence && python3 - <<'PY'
from pathlib import Path
s=Path('wa/waApp.swift').read_text()
assert s.count('.frame(width: 1120, height: 700)') <= 1
print('ok')
PY
    Expected: 하드코딩 중복이 없고 검증 통과
    Evidence: .sisyphus/evidence/task-1-layout-primitives-error.txt
  ```

  **Commit**: NO | Message: `refactor(settings): introduce shared two-column layout primitives` | Files: [`wa/waApp.swift`]

- [ ] 2. `편집/색상` 탭 2열 카드형 재배치

  **What to do**: 첫 번째 탭(`editorAndTheme`)에서 `ScrollView`를 제거하고 2열 카드 배치로 재구성한다. 고정 배치 규칙: 좌열 `화면 설정 -> 편집기 설정`, 우열 `색상 테마 프리셋 -> 색상 설정 -> 색상 초기화`. 각 섹션 내 컨트롤 순서는 기존과 동일하게 유지한다.
  **Must NOT do**: 색상 preset 적용/초기화 로직(`applyColorThemePreset`, `resetColorsToDefaults`) 변경 금지.

  **Recommended Agent Profile**:
  - Category: `visual-engineering` — Reason: 정보구조 재배치와 밀도 튜닝 중심
  - Skills: [`frontend-ui-ux`] — 컨트롤 간 시각적 우선순위 정돈
  - Omitted: [`git-master`] — 본 task는 구현 자체에 집중

  **Parallelization**: Can Parallel: YES | Wave 1 | Blocks: [5] | Blocked By: [1]

  **References** (executor has NO interview context — be exhaustive):
  - Pattern: `wa/waApp.swift:645` — 탭 1 기존 `ScrollView` 시작
  - Pattern: `wa/waApp.swift:648` — `화면 설정`
  - Pattern: `wa/waApp.swift:657` — `편집기 설정`
  - Pattern: `wa/waApp.swift:696` — `색상 테마 프리셋`
  - Pattern: `wa/waApp.swift:715` — `색상 설정`
  - Pattern: `wa/waApp.swift:748` — `색상 초기화`
  - API/Type: `wa/waApp.swift:1052` — `applyColorThemePreset(_:)`
  - API/Type: `wa/waApp.swift:1041` — `resetColorsToDefaults()`

  **Acceptance Criteria** (agent-executable only):
  - [ ] 탭 1 블록에서 `ScrollView`가 제거된다 (SettingsView 블록 대상 문자열 검증).
  - [ ] 탭 1의 5개 GroupBox 제목 문자열이 모두 유지된다.
  - [ ] `applyColorThemePreset`/`resetColorsToDefaults` 호출 지점이 유지된다.

  **QA Scenarios** (MANDATORY — task incomplete without these):
  ```
  Scenario: 탭 1 구조/섹션 보존 확인
    Tool: Bash
    Steps: mkdir -p .sisyphus/evidence && python3 - <<'PY'
from pathlib import Path
s=Path('wa/waApp.swift').read_text()
start=s.index('case editorAndTheme') if 'case editorAndTheme' in s else s.index('.tag(SettingsTab.editorAndTheme)')
for label in ['GroupBox("화면 설정")','GroupBox("편집기 설정")','GroupBox("색상 테마 프리셋")','GroupBox("색상 설정")','GroupBox("색상 초기화")']:
    assert label in s
print('ok')
PY
    Expected: 5개 섹션 제목이 모두 유지되고 검증 통과
    Evidence: .sisyphus/evidence/task-2-editor-theme-structure.txt

  Scenario: 탭 1에 ScrollView 잔존 시 실패
    Tool: Bash
    Steps: mkdir -p .sisyphus/evidence && python3 - <<'PY'
from pathlib import Path
s=Path('wa/waApp.swift').read_text()
a=s.index('TabView(selection: $selectedSettingsTab)')
b=s.index('.tag(SettingsTab.editorAndTheme)')
chunk=s[a:b]
assert 'ScrollView' not in chunk
print('ok')
PY
    Expected: ScrollView가 남아있으면 assert 실패, 제거되면 통과
    Evidence: .sisyphus/evidence/task-2-editor-theme-error.txt
  ```

  **Commit**: NO | Message: `refactor(settings): relayout editor-theme tab into two-column cards` | Files: [`wa/waApp.swift`]

- [ ] 3. `출력/AI/저장` 탭 2열 카드형 재배치

  **What to do**: 두 번째 탭(`outputAIStorage`)을 2열로 재배치한다. 고정 배치 규칙: 좌열 `출력 설정 -> AI 설정`, 우열 `Whisper 받아쓰기 -> 데이터 저장소`. `AI 설정`의 모델 선택/직접입력/키 저장/키 삭제 흐름과 `Whisper`의 경로/상태/설치 액션은 기존 상태 바인딩 및 disable 조건을 그대로 유지한다.
  **Must NOT do**: Keychain 호출 경로(`saveGeminiAPIKey`, `deleteGeminiAPIKey`) 및 Whisper 설치 흐름(`installOrUpdateWhisper`) 로직 변경 금지.

  **Recommended Agent Profile**:
  - Category: `visual-engineering` — Reason: 긴 폼 섹션을 고밀도 2열 카드로 안정적으로 재구성
  - Skills: [`frontend-ui-ux`] — 폼 밀도 최적화/상태 메시지 가독성 정리
  - Omitted: [`playwright`] — 브라우저 자동화 불필요

  **Parallelization**: Can Parallel: YES | Wave 1 | Blocks: [5] | Blocked By: [1]

  **References** (executor has NO interview context — be exhaustive):
  - Pattern: `wa/waApp.swift:757` — 탭 2 기존 `ScrollView` 시작
  - Pattern: `wa/waApp.swift:759` — `출력 설정`
  - Pattern: `wa/waApp.swift:795` — `AI 설정`
  - Pattern: `wa/waApp.swift:852` — `Whisper 받아쓰기`
  - Pattern: `wa/waApp.swift:910` — `데이터 저장소`
  - API/Type: `wa/waApp.swift:1098` — `saveGeminiAPIKey()`
  - API/Type: `wa/waApp.swift:1114` — `deleteGeminiAPIKey()`
  - API/Type: `wa/waApp.swift:1189` — `installOrUpdateWhisper()`

  **Acceptance Criteria** (agent-executable only):
  - [ ] 탭 2의 4개 GroupBox 제목 문자열이 모두 유지된다.
  - [ ] `saveGeminiAPIKey`, `deleteGeminiAPIKey`, `installOrUpdateWhisper`, `openWorkspaceFile`, `createWorkspaceFile` 호출 버튼이 유지된다.
  - [ ] `whisperIsInstalling` 기반 버튼 disable/ProgressView 표시 조건이 유지된다.

  **QA Scenarios** (MANDATORY — task incomplete without these):
  ```
  Scenario: 탭 2 핵심 섹션/액션 보존 검증
    Tool: Bash
    Steps: mkdir -p .sisyphus/evidence && python3 - <<'PY'
from pathlib import Path
s=Path('wa/waApp.swift').read_text()
for token in [
 'GroupBox("출력 설정")','GroupBox("AI 설정")','GroupBox("Whisper 받아쓰기")','GroupBox("데이터 저장소")',
 'saveGeminiAPIKey()','deleteGeminiAPIKey()','installOrUpdateWhisper()','openWorkspaceFile()','createWorkspaceFile()'
]:
    assert token in s, token
print('ok')
PY
    Expected: 핵심 섹션/액션 토큰이 모두 존재
    Evidence: .sisyphus/evidence/task-3-output-ai-storage.txt

  Scenario: Whisper 설치 중 상태 처리 누락 검출
    Tool: Bash
    Steps: mkdir -p .sisyphus/evidence && python3 - <<'PY'
from pathlib import Path
s=Path('wa/waApp.swift').read_text()
assert 'if whisperIsInstalling' in s
assert '.disabled(whisperIsInstalling)' in s
print('ok')
PY
    Expected: 설치 중 보호 로직이 없으면 실패, 유지되면 통과
    Evidence: .sisyphus/evidence/task-3-output-ai-storage-error.txt
  ```

  **Commit**: NO | Message: `refactor(settings): relayout output-ai-storage tab into two-column cards` | Files: [`wa/waApp.swift`]

- [ ] 4. `단축키` 탭 고밀도 2열 가시화 재배치

  **What to do**: 세 번째 탭(`shortcuts`)을 별도 탭으로 유지하면서 2열 카드 배치로 재구성한다. 고정 배치 규칙: 좌열 `공통 -> 메인 작업 모드`, 우열 `포커스 모드 -> 히스토리 모드`. `shortcutSections` 데이터 소스와 `shortcutRow(_:)` 렌더링 함수는 유지하되, row spacing/폰트를 압축해 스크롤 없이 표시되게 한다.
  **Must NOT do**: 단축키 항목 문자열/의미 변경 금지.

  **Recommended Agent Profile**:
  - Category: `visual-engineering` — Reason: 정보 밀도 높은 목록의 카드화/가독성 개선
  - Skills: [`frontend-ui-ux`] — 리스트 압축 시 가독성 유지
  - Omitted: [`git-master`] — 구현 단계에서 불필요

  **Parallelization**: Can Parallel: YES | Wave 1 | Blocks: [5] | Blocked By: [1]

  **References** (executor has NO interview context — be exhaustive):
  - Pattern: `wa/waApp.swift:570` — `shortcutSections` 정의
  - Pattern: `wa/waApp.swift:940` — 탭 3 기존 `ScrollView`
  - Pattern: `wa/waApp.swift:942` — `GroupBox("단축키")`
  - API/Type: `wa/waApp.swift:973` — `shortcutRow(_:)`

  **Acceptance Criteria** (agent-executable only):
  - [ ] `shortcutSections` 및 `shortcutRow(_:)`가 유지된다.
  - [ ] 단축키 섹션 제목 4개(`공통`, `메인 작업 모드`, `포커스 모드`, `히스토리 모드`)가 모두 유지된다.
  - [ ] 단축키 탭이 스크롤 컨테이너 없이 렌더링되도록 구조가 변경된다.

  **QA Scenarios** (MANDATORY — task incomplete without these):
  ```
  Scenario: 단축키 데이터/타이틀 보존 검증
    Tool: Bash
    Steps: mkdir -p .sisyphus/evidence && python3 - <<'PY'
from pathlib import Path
s=Path('wa/waApp.swift').read_text()
for token in ['private var shortcutSections','func shortcutRow(_ item: ShortcutItem)','"공통"','"메인 작업 모드"','"포커스 모드"','"히스토리 모드"']:
    assert token in s, token
print('ok')
PY
    Expected: 데이터 소스/렌더러/섹션 타이틀이 모두 유지
    Evidence: .sisyphus/evidence/task-4-shortcuts-layout.txt

  Scenario: 단축키 항목 누락 검출
    Tool: Bash
    Steps: mkdir -p .sisyphus/evidence && python3 - <<'PY'
from pathlib import Path
s=Path('wa/waApp.swift').read_text()
for token in ['Cmd + Z','Cmd + Shift + Z','Cmd + F','Cmd + Shift + ]']:
    assert token in s, token
print('ok')
PY
    Expected: 핵심 공통 단축키 항목이 누락되면 실패
    Evidence: .sisyphus/evidence/task-4-shortcuts-layout-error.txt
  ```

  **Commit**: NO | Message: `refactor(settings): compact shortcuts tab into two-column cards` | Files: [`wa/waApp.swift`]

- [ ] 5. Scroll 제거 및 1120x700 무스크롤 피팅 보정

  **What to do**: `SettingsView` 3개 탭 콘텐츠에서 `ScrollView`를 완전히 제거하고, 카드 간격/내부 spacing/텍스트 lineLimit을 조정해 `1120x700`에서 스크롤 없이 보이도록 고정 배치한다. 장문 설명/상태 텍스트는 `lineLimit(2)` 이내로 제한하되 기능 정보는 유지한다.
  **Must NOT do**: `TabView` 구조, 탭 라벨/태그, frame(`1120x700`) 변경 금지.

  **Recommended Agent Profile**:
  - Category: `visual-engineering` — Reason: 최종 레이아웃 피팅/밀도 튜닝의 핵심 작업
  - Skills: [`frontend-ui-ux`] — 무스크롤 조건 충족을 위한 텍스트/간격 최적화
  - Omitted: [`playwright`] — 네이티브 macOS 창 검증은 Bash/정적검증 중심

  **Parallelization**: Can Parallel: NO | Wave 1 | Blocks: [6, 7, 8] | Blocked By: [2, 3, 4]

  **References** (executor has NO interview context — be exhaustive):
  - Pattern: `wa/waApp.swift:646` — 탭 1 `ScrollView`
  - Pattern: `wa/waApp.swift:757` — 탭 2 `ScrollView`
  - Pattern: `wa/waApp.swift:940` — 탭 3 `ScrollView`
  - Pattern: `wa/waApp.swift:964` — `.frame(width: 1120, height: 700)`
  - Pattern: `wa/waApp.swift:915` — 저장 경로 텍스트(`currentStoragePath`) lineLimit 적용 대상

  **Acceptance Criteria** (agent-executable only):
  - [ ] `SettingsView` 블록 문자열에서 `ScrollView` 토큰이 0회다.
  - [ ] `TabView` frame은 `1120x700`을 유지한다.
  - [ ] 장문 텍스트(저장 경로/상태 메시지) 영역이 lineLimit 규칙을 가진다.

  **QA Scenarios** (MANDATORY — task incomplete without these):
  ```
  Scenario: SettingsView 무스크롤 불변조건 검증
    Tool: Bash
    Steps: mkdir -p .sisyphus/evidence && python3 - <<'PY'
from pathlib import Path
s=Path('wa/waApp.swift').read_text()
a=s.index('struct SettingsView: View')
b=s.index('struct MainContainerView: View')
chunk=s[a:b]
assert 'ScrollView' not in chunk
assert '.frame(width: 1120, height: 700)' in chunk
print('ok')
PY
    Expected: SettingsView 내부 ScrollView 0, frame 유지
    Evidence: .sisyphus/evidence/task-5-no-scroll-fit.txt

  Scenario: 텍스트 overflow 방어 누락 검출
    Tool: Bash
    Steps: mkdir -p .sisyphus/evidence && python3 - <<'PY'
from pathlib import Path
s=Path('wa/waApp.swift').read_text()
assert 'currentStoragePath' in s
assert '.lineLimit(2)' in s or '.lineLimit(3)' in s
print('ok')
PY
    Expected: lineLimit 방어가 없으면 실패
    Evidence: .sisyphus/evidence/task-5-no-scroll-fit-error.txt
  ```

  **Commit**: NO | Message: `refactor(settings): remove per-tab scrolling and fit layout to fixed window` | Files: [`wa/waApp.swift`]

- [ ] 6. 상태/부수효과 무결성 회귀 방지 패스

  **What to do**: 레이아웃 변경 후 상태 바인딩/부수효과 연결을 회귀 점검하고 필요한 wiring 수정만 수행한다. 점검 범위: `@AppStorage` 키 선언, Gemini key save/delete, Whisper install/update/status, workspace open/create/reset, `onAppear` 초기화 시퀀스.
  **Must NOT do**: 저장 키 이름/기본값 변경, side-effect 함수 내부 로직 재설계 금지.

  **Recommended Agent Profile**:
  - Category: `unspecified-high` — Reason: UI/상태/부수효과 결합부 회귀 방지 작업
  - Skills: [`karpathy-guidelines`] — 최소 변경/검증 중심 패치 원칙 유지
  - Omitted: [`frontend-ui-ux`] — 이 task는 시각 개선보다 동작 보존이 핵심

  **Parallelization**: Can Parallel: YES | Wave 2 | Blocks: [8] | Blocked By: [5]

  **References** (executor has NO interview context — be exhaustive):
  - API/Type: `wa/waApp.swift:505` — Settings `@AppStorage` 선언 구간 시작
  - API/Type: `wa/waApp.swift:1098` — `saveGeminiAPIKey()`
  - API/Type: `wa/waApp.swift:1114` — `deleteGeminiAPIKey()`
  - API/Type: `wa/waApp.swift:1189` — `installOrUpdateWhisper()`
  - API/Type: `wa/waApp.swift:1229` — `openWorkspaceFile()`
  - API/Type: `wa/waApp.swift:1254` — `createWorkspaceFile()`
  - Pattern: `wa/waApp.swift:965` — `onAppear` 초기화 시퀀스
  - External: `wa/KeychainStore.swift:4` — Gemini key 저장소 계약
  - External: `wa/WhisperSupport.swift:1` — Whisper 환경/설치 계약

  **Acceptance Criteria** (agent-executable only):
  - [ ] 핵심 side-effect 함수 선언이 모두 유지된다.
  - [ ] `onAppear`의 4개 초기화 호출이 모두 유지된다.
  - [ ] 핵심 `@AppStorage` 키 토큰이 코드베이스에 유지된다.

  **QA Scenarios** (MANDATORY — task incomplete without these):
  ```
  Scenario: side-effect 엔트리포인트 보존 검증
    Tool: Bash
    Steps: mkdir -p .sisyphus/evidence && grep -n "func saveGeminiAPIKey\|func deleteGeminiAPIKey\|func installOrUpdateWhisper\|func openWorkspaceFile\|func createWorkspaceFile" wa/waApp.swift > .sisyphus/evidence/task-6-side-effect-integrity.txt
    Expected: 5개 함수 선언이 모두 검색됨
    Evidence: .sisyphus/evidence/task-6-side-effect-integrity.txt

  Scenario: 초기화 시퀀스 누락 검출
    Tool: Bash
    Steps: mkdir -p .sisyphus/evidence && python3 - <<'PY'
from pathlib import Path
s=Path('wa/waApp.swift').read_text()
for token in ['refreshGeminiAPIKeyStatus()','syncGeminiModelOptionSelection()','loadWhisperPathInputsFromResolvedConfig()','refreshWhisperStatusFromInputs()']:
    assert token in s, token
print('ok')
PY
    Expected: 초기화 호출 누락 시 실패
    Evidence: .sisyphus/evidence/task-6-side-effect-integrity-error.txt
  ```

  **Commit**: NO | Message: `chore(settings): preserve state and side-effect wiring after relayout` | Files: [`wa/waApp.swift`]

- [ ] 7. 정적 불변조건 자동검증 번들 구성

  **What to do**: 무스크롤/키보존/탭보존/핵심호출 보존을 자동 검증하는 명령 번들을 실행하고 결과를 `.sisyphus/evidence/`에 저장한다. 이 task는 코드 변경이 아니라 검증 실행/증거 수집이 목적이다.
  **Must NOT do**: 기능 코드를 추가 변경하지 말 것(검증 only).

  **Recommended Agent Profile**:
  - Category: `quick` — Reason: 검증 커맨드 실행/증거 수집 중심
  - Skills: [`karpathy-guidelines`] — pass/fail 기준 명확화
  - Omitted: [`frontend-ui-ux`] — 디자인 작업 아님

  **Parallelization**: Can Parallel: YES | Wave 2 | Blocks: [8] | Blocked By: [5]

  **References** (executor has NO interview context — be exhaustive):
  - Pattern: `wa/waApp.swift:634` — `SettingsTab` 케이스 기준
  - Pattern: `wa/waApp.swift:964` — frame 기준
  - API/Type: `wa/waApp.swift:505` — `@AppStorage` 구간

  **Acceptance Criteria** (agent-executable only):
  - [ ] 무스크롤/탭/키/함수 보존 검증 로그 4종 이상이 `.sisyphus/evidence/`에 생성된다.
  - [ ] 모든 검증 명령이 exit code 0으로 끝난다.

  **QA Scenarios** (MANDATORY — task incomplete without these):
  ```
  Scenario: 불변조건 검증 번들 실행
    Tool: Bash
    Steps: mkdir -p .sisyphus/evidence && python3 - <<'PY'
from pathlib import Path
s=Path('wa/waApp.swift').read_text()
a=s.index('struct SettingsView: View')
b=s.index('struct MainContainerView: View')
chunk=s[a:b]
assert 'ScrollView' not in chunk
for token in ['case editorAndTheme','case outputAIStorage','case shortcuts','.frame(width: 1120, height: 700)','@AppStorage("appearance")','@AppStorage("storageBookmark")','func saveGeminiAPIKey','func installOrUpdateWhisper']:
    assert token in s, token
Path('.sisyphus/evidence/task-7-invariants.txt').write_text('ok\n')
print('ok')
PY
    Expected: 불변조건 전체 통과 및 evidence 파일 생성
    Evidence: .sisyphus/evidence/task-7-invariants.txt

  Scenario: 금지된 ScrollView 회귀 검출
    Tool: Bash
    Steps: mkdir -p .sisyphus/evidence && python3 - <<'PY'
from pathlib import Path
s=Path('wa/waApp.swift').read_text()
a=s.index('struct SettingsView: View')
b=s.index('struct MainContainerView: View')
chunk=s[a:b]
assert chunk.count('ScrollView') == 0
Path('.sisyphus/evidence/task-7-invariants-error.txt').write_text('no-scroll-ok\n')
print('ok')
PY
    Expected: ScrollView가 재도입되면 실패
    Evidence: .sisyphus/evidence/task-7-invariants-error.txt
  ```

  **Commit**: NO | Message: `test(settings): add static invariants evidence for no-scroll relayout` | Files: [`.sisyphus/evidence/*`]

- [ ] 8. 최종 빌드/회귀 패스 및 커밋 준비

  **What to do**: 최종 빌드와 변경범위 검토를 수행하고 커밋 가능한 상태로 정리한다. 실행 순서 고정: (1) 불변조건 재실행, (2) `xcodebuild` Debug build, (3) 변경 파일 목록 검토, (4) 커밋 메시지 초안 확정.
  **Must NOT do**: 이 task에서 추가 UI 구조 변경 금지(검증/정리만 수행).

  **Recommended Agent Profile**:
  - Category: `unspecified-high` — Reason: 최종 통합 검증과 품질 게이트 통과
  - Skills: [`git-master`] — 변경 범위 점검/커밋 준비 정확성 확보
  - Omitted: [`playwright`] — 네이티브 앱 중심으로 빌드/정적검증 우선

  **Parallelization**: Can Parallel: NO | Wave 2 | Blocks: [Final Verification Wave] | Blocked By: [6, 7]

  **References** (executor has NO interview context — be exhaustive):
  - Pattern: `wa/waApp.swift:644` — SettingsView 본문
  - Pattern: `wa/waApp.swift:964` — frame 유지 확인점
  - Test: `.sisyphus/evidence/task-7-invariants.txt` — 사전 검증 결과

  **Acceptance Criteria** (agent-executable only):
  - [ ] `xcodebuild ... build`가 성공한다.
  - [ ] 변경 파일이 의도 범위(주로 `wa/waApp.swift` + evidence)에 한정된다.
  - [ ] 커밋 메시지 초안이 계획된 scope를 정확히 반영한다.

  **QA Scenarios** (MANDATORY — task incomplete without these):
  ```
  Scenario: 최종 통합 검증
    Tool: Bash
    Steps: mkdir -p .sisyphus/evidence && xcodebuild -project "wa.xcodeproj" -scheme "wa" -configuration Debug -destination 'platform=macOS' build | tee .sisyphus/evidence/task-8-build.log
    Expected: 로그에 "** BUILD SUCCEEDED **" 포함
    Evidence: .sisyphus/evidence/task-8-build.log

  Scenario: 변경 범위 오염 검출
    Tool: Bash
    Steps: mkdir -p .sisyphus/evidence && git status --short | tee .sisyphus/evidence/task-8-git-status.txt
    Expected: 설정 재배치와 무관한 소스 파일 변경이 없거나, 있으면 분리 필요로 fail 처리
    Evidence: .sisyphus/evidence/task-8-git-status.txt
  ```

  **Commit**: YES | Message: `refactor(settings): reorganize preferences into no-scroll two-column tabs` | Files: [`wa/waApp.swift`, `.sisyphus/evidence/*`]

## Final Verification Wave (4 parallel agents, ALL must APPROVE)
- [ ] F1. Plan Compliance Audit — oracle
- [ ] F2. Code Quality Review — unspecified-high
- [ ] F3. Real Manual QA — unspecified-high (+ playwright if UI)
- [ ] F4. Scope Fidelity Check — deep

## Commit Strategy
- Single commit after Task 8 verification bundle.
- Commit message: `refactor(settings): reorganize preferences into no-scroll two-column tabs`
- Include only settings-related diffs (`wa/waApp.swift` and optional local settings UI helper extraction file if explicitly introduced).

## Success Criteria
- 설정 탭을 열었을 때 3개 탭 모두에서 세로 스크롤 없이 모든 제어 요소가 보인다.
- 기존 사용자 설정값(`@AppStorage`)과 Keychain/Whisper/workspace 동작이 동일하게 유지된다.
- 전체 프로젝트 Debug 빌드가 통과하고, 불변조건 검사 스크립트가 모두 통과한다.
