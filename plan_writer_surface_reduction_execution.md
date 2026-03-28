# Writer Surface Reduction And Giant File Decomposition Plan

참고:
- `LargeFileFeatureInventory.md`
- `/Users/three/app_build/reminder_/plan_projectwindow_reduction_execution.md`
- `AI_DOCS/01_ARCHITECTURE_DIAGNOSIS.md`
- `AI_DOCS/00_PROJECT_INDEX.md`
- `index_board_handoff.md`

## 작업 범위
`LargeFileFeatureInventory.md`에 기록된 `1500`줄 초과 Swift 파일 13개를 대상으로, 실사용 경로 기준으로 우선순위를 다시 세우고 각 파일을 `1500`줄 이하의 유지보수 가능한 단위로 분해하는 실행계획을 정의한다.

## Premise Challenge
이 계획의 핵심 전제는 단순한 "큰 파일 줄이기"가 아니다.

- 문제는 "`WriterCardManagement.swift`가 7058줄이다" 자체가 아니다.
- 실제 문제는 `ScenarioWriterView` 중심의 실사용 writer surface와 index board surface에서 상태 소유권, 편집 세션, 스크롤/모션, 보드 projection, persistence가 큰 파일 몇 개에 집중되어 있다는 점이다.
- 그래서 `MARK` 단위로 예쁘게 잘라서 줄 수만 낮추면 active path는 그대로 꼬여 있을 수 있다.
- 이번 계획의 목적은 "cosmetic split"이 아니라 "실제 수정이 자주 일어나는 경로를 안전하게 나눠서, 한 파일 수정이 다른 기능 붕괴로 번지지 않게 만드는 것"이다.

현재 코드와 문서 기준으로 load-bearing path는 아래다.

```text
waApp / MainContainer
  -> ScenarioWriterView (WriterViews.swift)
     -> main workspace / timeline / history / focus mode
     -> WriterCardManagement.swift
     -> WriterFocusMode.swift
     -> WriterHistoryView.swift
     -> WriterKeyboardHandlers.swift
     -> WriterCardViews.swift
     -> WriterSharedTypes.swift

ScenarioWriterView
  -> WriterIndexBoardScaffolding.swift
     -> WriterIndexBoardSurfaceAppKitPhaseTwo.swift
     -> WriterIndexBoardPhaseTwo.swift
     -> WriterIndexBoardSurfaceProjection / session state

Scenario / SceneCard / FileStore
  -> Models.swift
```

반면 아래와 같은 경로는 "앞으로 더 살을 붙일 중심 구조"로 취급하면 안 된다.

- `WriterIndexBoardSurfacePhaseTwo.swift`
  - handoff 문서 기준 fallback / compatibility 성격이 남아 있음
- `WriterViews.swift` 안의 거대한 stored state 묶음
  - extension 분해를 가로막는 현재 병목
- `WriterSharedTypes.swift` 안의 `ScenarioWriterView` nested type 의존
  - shared boundary를 흐리게 만드는 현재 병목

즉:
- `WriterViews.swift`와 `WriterCardManagement.swift`를 size-only로 자르는 것만으로는 충분하지 않다.
- `ScenarioWriterView` root state ownership, index board AppKit hot path, `FileStore` policy surface를 같이 줄여야 한다.
- 이번 계획의 목적은 giant file 수치 개선이 아니라, 수정 fear factor를 낮추는 것이다.

## 현재 시스템 상태

### Active writer path
- [wa/WriterViews.swift](/Users/three/app_build/wa/wa/WriterViews.swift)
  - `ScenarioWriterView` 선언부, stored state 허브, 주요 화면 조립
- [wa/WriterCardManagement.swift](/Users/three/app_build/wa/wa/WriterCardManagement.swift)
  - 메인 workspace motion, 편집 lifecycle, 카드 mutation, clipboard, export, selection
- [wa/WriterFocusMode.swift](/Users/three/app_build/wa/wa/WriterFocusMode.swift)
  - 포커스 모드 렌더/스크롤/편집/복원
- [wa/WriterHistoryView.swift](/Users/three/app_build/wa/wa/WriterHistoryView.swift)
  - history snapshot 엔진, preview, named snapshot
- [wa/WriterKeyboardHandlers.swift](/Users/three/app_build/wa/wa/WriterKeyboardHandlers.swift)
  - 키보드 라우팅과 편집 명령
- [wa/WriterCardViews.swift](/Users/three/app_build/wa/wa/WriterCardViews.swift)
  - 카드 셀 UI, AppKit editor wrapper, drop delegate
- [wa/WriterSharedTypes.swift](/Users/three/app_build/wa/wa/WriterSharedTypes.swift)
  - shared render types, host bridge, geometry/clipboard support

### Active board path
- [wa/WriterIndexBoardScaffolding.swift](/Users/three/app_build/wa/wa/WriterIndexBoardScaffolding.swift)
  - board open/close, session/state bootstrapping, projection build entry
- [wa/WriterIndexBoardSurfaceAppKitPhaseTwo.swift](/Users/three/app_build/wa/wa/WriterIndexBoardSurfaceAppKitPhaseTwo.swift)
  - 현재 보드 주 경로인 AppKit surface, drag preview, inline edit, viewport, presentation
- [wa/WriterIndexBoardPhaseTwo.swift](/Users/three/app_build/wa/wa/WriterIndexBoardPhaseTwo.swift)
  - drop commit, model mutation, board session commit

### Compatibility / support path
- [wa/WriterIndexBoardSurfacePhaseTwo.swift](/Users/three/app_build/wa/wa/WriterIndexBoardSurfacePhaseTwo.swift)
  - SwiftUI surface/fallback 성격, 완전 삭제 전까지 계약 안정성 필요
- [wa/Models.swift](/Users/three/app_build/wa/wa/Models.swift)
  - `Scenario`, `SceneCard`, `HistorySnapshot`, `FileStore`
- [wa/SettingsView.swift](/Users/three/app_build/wa/wa/SettingsView.swift)
  - 설정 UI와 `@AppStorage`, Keychain, workspace 설정 플로우 직접 결합

### 현재 줄 수 기준선

| 파일 | 현재 줄 수 | 상태 |
|---|---:|---|
| `wa/WriterCardManagement.swift` | `7058` | active giant, main writer hot path |
| `wa/WriterIndexBoardSurfaceAppKitPhaseTwo.swift` | `6560` | active giant, current board hot path |
| `wa/WriterViews.swift` | `3634` | active root state hub |
| `wa/WriterFocusMode.swift` | `3537` | active giant, focus-mode hot path |
| `wa/WriterIndexBoardPhaseTwo.swift` | `2472` | active board commit giant |
| `wa/WriterSharedTypes.swift` | `2187` | shared boundary giant |
| `wa/WriterKeyboardHandlers.swift` | `2092` | active command-routing giant |
| `wa/WriterIndexBoardScaffolding.swift` | `2063` | active board bootstrap giant |
| `wa/WriterCardViews.swift` | `2060` | active UI shell giant |
| `wa/Models.swift` | `2013` | core model + persistence giant |
| `wa/WriterHistoryView.swift` | `1848` | active history giant |
| `wa/WriterIndexBoardSurfacePhaseTwo.swift` | `1805` | compatibility / fallback giant |
| `wa/SettingsView.swift` | `1541` | settings giant |

## Phase 0 기준선 잠금

- 기준선 캡처 시점은 `2026-03-28`이며, 대상 giant file 집합은 위 표의 `13`개 파일로 고정한다.
- `LargeFileFeatureInventory.md`를 기능/책임 인벤토리의 기준 문서로 사용한다.
- 이후 phase는 대상 파일 집합을 임의로 넓히거나 줄이지 않고, 필요 시 계획 문서와 인벤토리를 함께 갱신한다.
- 문서 하단 `Phase별 검증 체크리스트`를 모든 phase의 baseline checklist로 재사용하고, phase별 추가 확인만 덧붙인다.

## 진짜 목표

### 1차 목표
실사용 writer / board 경로에서 `1500`줄을 넘는 파일이 없도록 만든다.

### 2차 목표
`ScenarioWriterView`를 giant state dump가 아니라 composition root로 축소한다.

### 3차 목표
index board는 AppKit active path와 fallback / compatibility path를 명확히 분리한다.

### 4차 목표
`Models.swift`와 `SettingsView.swift`의 정책 surface를 줄여, 화면 수정이 저장/설정 경계 전체에 번지지 않게 만든다.

## 성공 기준

### 최종 성공 기준
- 대상 13개 파일 중 `1500`줄 초과 파일이 없다.
- `WriterViews.swift`는 `ScenarioWriterView` 선언, 핵심 stored property wiring, top-level composition까지만 남는다.
- `WriterCardManagement.swift`는 main canvas motion / edit lifecycle / mutation / clipboard-export / selection-delete로 분해된다.
- `WriterFocusMode.swift`는 surface / scroll / editing / transition 복원 경계로 분해된다.
- `WriterIndexBoardSurfaceAppKitPhaseTwo.swift`는 types-theme / NSView layer / document interaction / drag-drop / viewport-presentation으로 분해된다.
- `WriterIndexBoardSurfacePhaseTwo.swift`는 fallback 계약만 유지하는 compatibility layer가 되거나, 완전 제거 가능한 상태까지 축소된다.
- `WriterSharedTypes.swift`는 `ScenarioWriterView` nested-type 의존이 줄어든 shared boundary 파일이 된다.
- `Models.swift`는 core model과 `FileStore` policy / persistence helpers가 분리된다.
- `SettingsView.swift`는 섹션별 card builder와 storage adapter가 분리된다.

### 각 phase 완료 기준
- 해당 phase 대상 파일이 line budget에 근접하거나, 다음 phase로 이어지는 명확한 extraction seam이 만들어진다.
- `xcodebuild -project wa.xcodeproj -scheme wa -configuration Debug build` 통과
- 관련 테스트가 있으면 해당 테스트 통과
- 기존 앱 종료 후 수정된 앱 재실행
- 메인 writer 진입 확인
- focus mode 진입/종료 확인
- index board 열기/드래그/복원 확인
- 해당 phase 대표 상호작용 최소 1개 수동 확인

### 실패로 간주하는 경우
- `MARK` 기준 복사 분해만 하고, 상태 ownership은 그대로 남는다.
- `WriterViews.swift` 줄 수는 줄지만 stored state가 여전히 feature seam 없이 뭉쳐 있다.
- board AppKit surface를 잘라 놓고 drop commit / persisted session / reopen parity를 같이 안 맞춘다.
- fallback path를 active path와 같은 미래 구조처럼 계속 확장한다.
- `FileStore`와 settings logic을 건드리면서 화면 분해 가치보다 위험만 키운다.

## What Already Exists

이번 계획은 바닥부터 다시 만들지 않는다. 이미 좋은 seam이 있다.

- [wa/MainCanvasScrollCoordinator.swift](/Users/three/app_build/wa/wa/MainCanvasScrollCoordinator.swift)
  - main workspace motion ownership 후보
- [wa/WriterCaretAndScroll.swift](/Users/three/app_build/wa/wa/WriterCaretAndScroll.swift)
  - caret/scroll 보조 경계가 이미 일부 분리되어 있음
- [wa/WriterUndoRedo.swift](/Users/three/app_build/wa/wa/WriterUndoRedo.swift)
  - undo/redo가 이미 독립 extension 파일
- [wa/WriterAI+*.swift](/Users/three/app_build/wa/wa)
  - AI는 이미 확장 파일 분해 패턴을 한 번 성공적으로 적용함
- [wa/WriterIndexBoardTypes.swift](/Users/three/app_build/wa/wa/WriterIndexBoardTypes.swift)
  - board session 구조와 저장 위치 정의
- [wa/WriterIndexBoardSurfaceProjection.swift](/Users/three/app_build/wa/wa/WriterIndexBoardSurfaceProjection.swift)
  - projection 규칙과 surface rendering hot path를 분리할 기반
- [wa/WriterIndexBoardPhaseFour.swift](/Users/three/app_build/wa/wa/WriterIndexBoardPhaseFour.swift)
- [wa/WriterIndexBoardPhaseFive.swift](/Users/three/app_build/wa/wa/WriterIndexBoardPhaseFive.swift)
- [wa/WriterIndexBoardPhaseSix.swift](/Users/three/app_build/wa/wa/WriterIndexBoardPhaseSix.swift)
  - board가 phase 분리 패턴을 이미 일부 갖고 있음
- [AI_DOCS/01_ARCHITECTURE_DIAGNOSIS.md](/Users/three/app_build/wa/AI_DOCS/01_ARCHITECTURE_DIAGNOSIS.md)
  - root-view state concentration 완화, shared type extraction, `FileStore` policy split라는 우선순위를 이미 제시함

결론:
- 이 프로젝트는 이미 "작은 seam을 먼저 뽑고, 동작은 유지한 채 분해"하는 방향이 맞다고 문서화돼 있다.
- 이번 계획은 그 방향을 giant file budget 기준으로 실행 계획까지 내리는 것이다.

## Dream State Delta

```text
CURRENT
  ScenarioWriterView + giant extension files + giant board AppKit surface + giant FileStore
  구조로 동작한다.

THIS PLAN
  active writer path와 active board path를 먼저 1500줄 budget 아래로 정리하고,
  fallback path는 compatibility layer로 축소한다.

12-MONTH IDEAL
  ScenarioWriterView는 작은 composition root,
  main workspace / focus mode / history / board / settings / persistence가
  명확한 file boundary와 state owner를 가진 상태
```

## 접근 방식 비교

### Approach A. 파일별 cosmetic split
- 요약: 각 giant file을 `MARK` 묶음 기준으로 잘라 줄 수만 낮춘다.
- 노력: `M`
- 리스크: `중간`
- 장점:
  - 빨리 시작할 수 있다.
  - 숫자상 giant file은 줄어든다.
- 단점:
  - active path ownership이 개선되지 않을 수 있다.
  - root state와 board hot path 결합을 그대로 보존할 가능성이 크다.
  - 다음 수정 때 다시 "어느 파일이 진짜 owner인지" 헷갈린다.

### Approach B. Active-Path-First + Compatibility Fence
- 요약: 실사용 writer / board 경로를 먼저 줄이고, fallback path와 shared boundary는 그 뒤에 fence를 친다.
- 노력: `L`
- 리스크: `중간`
- 장점:
  - 사용자 체감과 개발 생산성에 직접 닿는 경로가 먼저 좋아진다.
  - `ScenarioWriterView`와 board AppKit surface의 ownership이 분명해진다.
  - fallback file에 새 복잡도를 싣는 실수를 줄인다.
- 단점:
  - 순수 cosmetic split보다 설계 판단이 더 필요하다.
  - phase 설계와 검증 체크가 더 촘촘해야 한다.

### Approach C. 대규모 재설계 / controller-viewmodel 도입
- 요약: giant files를 줄이는 김에 state architecture까지 한 번에 갈아엎는다.
- 노력: `XL`
- 리스크: `높음`
- 장점:
  - 이상적인 구조에 가장 빨리 접근한다.
- 단점:
  - 지금 요구사항은 "작게 안전하게 나누기"인데, 이 방식은 ocean이다.
  - 회귀 리스크가 너무 크고 검증 범위가 넓다.

## Recommendation
`Approach B. Active-Path-First + Compatibility Fence`를 선택한다.

이유:
- 지금 문제는 giant file aesthetic이 아니라, 실사용 경로에서 수정 fear factor가 높다는 점이다.
- `WriterViews.swift`, `WriterCardManagement.swift`, `WriterFocusMode.swift`, `WriterIndexBoardSurfaceAppKitPhaseTwo.swift`를 먼저 줄여야 실제 가치가 생긴다.
- `WriterIndexBoardSurfacePhaseTwo.swift` 같은 fallback file은 forward architecture의 중심으로 더 키우면 안 된다.

## 기본 전략

### 1. `ScenarioWriterView` root state를 먼저 나눌 준비를 한다
`ScenarioWriterView`는 struct이므로 stored property를 extension으로 나눌 수 없다.

그래서 첫 extraction은 아래 순서여야 한다.

1. root file 안에 session state wrapper를 도입한다. 기본값은 `struct`다.
2. 각 wrapper를 stored property로 보관
3. view builder / helper / command routing을 extension 다파일로 이동

즉, `WriterViews.swift`를 바로 반으로 자르는 게 아니라 "stored state extraction -> extension split" 순서로 간다.

추가 원칙:
- Phase 1의 기본 wrapper 형태는 `struct`로 고정한다.
- `@Observable class` 또는 `ObservableObject` owner로의 승격은 Phase 1 안에서만 허용한다.
- 승격 조건은 아래 둘 중 하나가 명확할 때뿐이다.
  - binding 전달 churn이 커져 Phase 2 진입 전에 call site가 과도하게 비대해지는 경우
  - child surface가 wrapper 전체를 독립 observe해야 해서 value propagation보다 object ownership이 더 자연스러운 경우
- Phase 2 이후에는 wrapper 종류를 다시 바꾸지 않는다.

### 2. flat source tree는 유지한다
지금 `wa/`는 평면 구조이고 Xcode project도 flat file 추가에 더 유리하다.

따라서 이번 계획의 기본값은:
- 디렉터리 대이동보다
- `WriterXxx+Feature.swift` 또는 `WriterFeaturePart.swift` 식의 flat naming

이유:
- `project.pbxproj` churn 감소
- search 동선 유지
- rollback 단순화

예외:
- 같은 family 파일이 `7`개를 넘기면 그룹화 디렉터리를 허용한다.
- board AppKit 파일 군은 예외적으로 `wa/IndexBoard/` 아래로 묶을 수 있다.
- 즉, flat은 기본값이고 board AppKit family는 명시적 예외다.

### 3. writer main path는 state owner 기준으로 나눈다
아래 기준을 파일 경계로 삼는다.

- composition root
- transient editor session
- motion / scroll ownership
- mutation commands
- clipboard / export
- selection / deletion
- focus-mode-only behavior
- history-only behavior

### 4. board path는 rendering hot path와 commit path를 분리한다
board는 아래 세 층을 절대 섞지 않는다.

- surface rendering / indicator / overlay
- interaction / drag / inline edit / viewport
- model commit / persisted session mutation

이 분리가 안 되면 preview는 맞는데 drop 뒤 state가 틀어지는 문제가 계속 난다.

### 5. fallback path에는 새 기능을 싣지 않는다
아래 파일은 forward path가 아니다.

- `WriterIndexBoardSurfacePhaseTwo.swift`

이 파일에 허용되는 작업은 아래 둘뿐이다.

- active AppKit path와의 계약 유지
- 삭제/축소를 위한 compatibility cleanup

### 6. `Models.swift`와 `SettingsView.swift`는 "보이는 giant"라서 뒤로 미룬다
둘 다 중요한 파일이지만, 지금 fear factor의 중심은 writer / board editing hot path다.

따라서 순서는:

1. writer root
2. writer hot path
3. board hot path
4. persistence / settings

## 목표 파일 구조

### Writer root / workspace 목표 구조

```text
wa/
  WriterViews.swift                      // ScenarioWriterView root + stored-property wiring only
  WriterWorkspaceSessionState.swift
  WriterWorkspaceHosts.swift
  WriterWorkspacePanels.swift
  WriterWorkspaceDialogs.swift
  WriterWorkspaceCommands.swift          // app/workspace-level command only, card mutation 제외
```

### Main workspace / card management 목표 구조

```text
wa/
  WriterCardManagement.swift             // thin coordinator / compatibility entry only
  WriterMainCanvasMotion.swift
  WriterMainCanvasEditorHost.swift
  WriterMainCanvasNavigation.swift
  WriterCardMutationCommands.swift
  WriterClipboardAndExport.swift
  WriterCardSelectionAndDeletion.swift
  WriterMainCanvasColumns.swift
```

### Focus mode 목표 구조

```text
wa/
  WriterFocusMode.swift                  // thin composition / bindings only
  WriterFocusModeSurface.swift
  WriterFocusModeScroll.swift
  WriterFocusModeEditing.swift
  WriterFocusModeTransitions.swift
```

### History / keyboard / card views 목표 구조

```text
wa/
  WriterHistoryView.swift                // section composition root
  WriterHistorySnapshots.swift
  WriterHistoryNamedSnapshots.swift
  WriterHistoryPreview.swift

  WriterKeyboardHandlers.swift           // command entry
  WriterKeyboardNavigation.swift
  WriterKeyboardEditingCommands.swift

  WriterCardViews.swift                  // section composition
  WriterCardChrome.swift
  WriterCardEditorBridges.swift
  WriterCardDropDelegates.swift
```

### Board 목표 구조

```text
wa/
  WriterIndexBoardScaffolding.swift
  WriterIndexBoardSessionStore.swift
  WriterIndexBoardOpenClose.swift

  WriterIndexBoardPhaseTwo.swift
  WriterIndexBoardCommitMoves.swift
  WriterIndexBoardCommitGroups.swift
  WriterIndexBoardCommitPersistence.swift

  IndexBoard/
    WriterIndexBoardSurfaceAppKitPhaseTwo.swift
    WriterIndexBoardAppKitTypes.swift
    WriterIndexBoardAppKitTheme.swift
    WriterIndexBoardAppKitViews.swift
    WriterIndexBoardAppKitDocumentInteractions.swift
    WriterIndexBoardAppKitInlineEditing.swift
    WriterIndexBoardAppKitDragDrop.swift
    WriterIndexBoardAppKitPresentation.swift
    WriterIndexBoardAppKitViewport.swift
    WriterIndexBoardAppKitDiagnostics.swift
    WriterIndexBoardSurfaceCompatFallback.swift  // frozen compatibility layer or removal candidate
```

### Shared types / model / settings 목표 구조

```text
wa/
  WriterSharedTypes.swift
  WriterWorkspaceSharedRenderTypes.swift
  WriterWorkspaceBridgeTypes.swift
  WriterWorkspaceClipboardTypes.swift

  Models.swift
  ScenarioModel.swift
  SceneCardModel.swift
  HistorySnapshotModel.swift
  FileStore.swift
  FileStorePersistence.swift
  FileStoreSharedCraft.swift
  FileStoreAIArtifacts.swift

  SettingsView.swift
  SettingsGeneralSection.swift
  SettingsAppearanceSection.swift
  SettingsAISection.swift
  SettingsBackupSection.swift
  SettingsStorageAdapters.swift
```

## 파일별 분해 우선순위

### Tier 1. writer root와 1차 hot path
1. `wa/WriterViews.swift`
2. `wa/WriterCardManagement.swift`
3. `wa/WriterFocusMode.swift`

이유:
- `ScenarioWriterView`와 main/focus editing 경계가 가장 먼저 안정돼야 이후 분해가 덜 흔들린다.

### Tier 2. writer support seam
1. `wa/WriterCardViews.swift`
2. `wa/WriterKeyboardHandlers.swift`
3. `wa/WriterHistoryView.swift`
4. `wa/WriterSharedTypes.swift`

이유:
- Tier 1이 만든 seam을 따라야 안전하게 쪼개진다.
- 특히 `WriterSharedTypes.swift`는 Phase 1에서 준비하고, Tier 2 시점 이후 실제 분해한다.

### Tier 3. board 선행 seam
1. `wa/WriterIndexBoardScaffolding.swift`
2. `wa/WriterIndexBoardPhaseTwo.swift`

이유:
- AppKit surface giant를 직접 자르기 전에 open/close/session/commit 경계를 먼저 분리해야 한다.

### Tier 4. board high-risk surface
1. `wa/WriterIndexBoardSurfaceAppKitPhaseTwo.swift`
2. `wa/WriterIndexBoardSurfacePhaseTwo.swift`

이유:
- 가장 큰 위험 파일이지만, 선행 seam 없이 들어가면 preview와 commit parity를 깨뜨리기 쉽다.

### Tier 5. policy surface
1. `wa/Models.swift`
2. `wa/SettingsView.swift`

이유:
- 최종 budget 목표에는 반드시 포함되지만, writer/board hot path를 먼저 줄인 뒤 들어가는 편이 안전하다.

## 실행 Phase

### Phase 0. 기준선 고정

- 작업
  - 대상 13개 파일 줄 수 기록
  - `LargeFileFeatureInventory.md`를 기준 인벤토리로 고정
  - 문서 하단의 "Phase별 검증 체크리스트"를 baseline checklist로 고정
  - phase별 추가 확인 항목만 그 checklist에 덧붙인다
- 산출물
  - 이 계획 문서
  - 하단 checklist를 baseline으로 쓰는 phase별 수동 검증 항목

### Phase 1. `ScenarioWriterView` stored state extraction

- 대상
  - `WriterViews.swift`
  - `WriterSharedTypes.swift`
- 작업
  - `ScenarioWriterView` stored property를 feature group wrapper로 묶기
    - `WriterWorkspaceSessionState`
    - `WriterFocusSessionState`
    - `WriterHistorySessionState`
    - `WriterBoardSessionState`
  - wrapper 기본값은 `struct`로 시작하고, owner object 승격 여부는 Phase 1 안에서만 확정
  - `WriterWorkspaceCommands.swift`는 `ScenarioWriterView` 레벨의 app/workspace command만 포함
  - card-level mutation command는 Phase 2의 `WriterCardMutationCommands.swift`로 보낸다
  - `WriterSharedTypes.swift`에서는 nested shared render/helper type의 root-type 의존 해제 준비만 수행
  - 즉, Phase 1의 `WriterSharedTypes.swift` 작업은 "실제 분해"가 아니라 "nested type 의존 해제 준비"로 제한한다
  - root file에서 "stored state + top-level composition"만 남기기
- 이유
  - 이후 extension file 분해의 선행조건
  - `WriterSharedTypes.swift` 실분해는 Phase 5에서 한다
- 완료 기준
  - `WriterViews.swift`가 1500줄에 근접
  - 다른 feature file이 root state wrapper를 통해 접근 가능
  - wrapper 종류가 Phase 1 종료 시점에 확정되어 이후 phase에서 다시 바뀌지 않는다

### Phase 2A. main workspace command/motion giant 분해

- 대상
  - `WriterCardManagement.swift`
- 작업
  - `WriterCardManagement.swift` 분리
    - motion / restore
    - editor host / live height
    - navigation / visibility
    - column layout / multi-column rendering
    - mutation commands
    - clipboard / export
    - selection / delete
- 이유
  - 가장 자주 건드리는 편집 경로의 blast radius를 줄임

### Phase 2B. focus mode giant 분해

- 대상
  - `WriterFocusMode.swift`
- 작업
  - `WriterFocusMode.swift`
    - surface
    - scroll/caret stability
    - editing lifecycle
    - transition snapshot/restore
- 이유
  - Tier 1 파일을 Tier 2 support file보다 먼저 줄여 writer hot path의 fear factor를 바로 낮춘다.
- 실행 순서
  - `2A -> 2B` 순차 진행
  - 이유: focus mode가 main scroll/caret, editing lifecycle, active-card transition 경계와 맞물려 있어 `WriterCardManagement.swift` 분해 뒤에 들어가는 편이 안전하다.

### Phase 3A. writer support surface 분해

- 대상
  - `WriterCardViews.swift`
  - `WriterKeyboardHandlers.swift`
- 작업
  - `WriterCardViews.swift` 분리
    - card chrome
    - AppKit editor bridge
    - drop delegates
  - `WriterKeyboardHandlers.swift` 분리
    - navigation
    - editing commands
    - selection / hierarchy commands
- 이유
  - main/focus hot path를 가른 뒤 support surface를 따라가면 file 경계가 더 선명해진다.
- 완료 기준
  - `WriterCardViews.swift`와 `WriterKeyboardHandlers.swift` 둘 다 `1500`줄 budget 아래로 내려가야 Phase 3A 완료로 본다.

### Phase 3B. history giant 분해

- 대상
  - `WriterHistoryView.swift`
- 작업
  - `WriterHistoryView.swift`
    - snapshot engine
    - preview UI
    - named snapshot UI / note sync
- 이유
  - history는 독립 책임이 분명해 별도 phase로 두는 편이 완료 기준을 잡기 쉽다.

### Phase 4A. board bootstrap / commit seam 분해

- 대상
  - `WriterIndexBoardScaffolding.swift`
  - `WriterIndexBoardPhaseTwo.swift`
- 작업
  - `WriterIndexBoardScaffolding.swift`
    - session bootstrap
    - open/close/reveal wiring
    - persistence publish
  - `WriterIndexBoardPhaseTwo.swift`
    - move commit
    - group/temp commit
    - persistence/save hooks
- 이유
  - AppKit surface giant 분해 전에 commit/persistence seam을 먼저 세워야 한다.

### Phase 4B. board AppKit surface giant 분해

- 대상
  - `WriterIndexBoardSurfaceAppKitPhaseTwo.swift`
- 작업
  - `WriterIndexBoardSurfaceAppKitPhaseTwo.swift`
    - type/theme/helpers
    - NSView components
    - document interaction
    - inline editing
    - drag/drop + preview
    - presentation/layout
    - viewport/diagnostics
- 이유
  - 가장 위험한 giant file이므로 board 전용 phase로 분리해 검증 깊이를 높인다.

### Phase 4C. board compatibility fence

- 대상
  - `WriterIndexBoardSurfacePhaseTwo.swift`
- 작업
  - `WriterIndexBoardSurfacePhaseTwo.swift`
    - fallback / compatibility만 남기고 신규 책임 금지
    - frozen 상태가 확인되면 `IndexBoard/WriterIndexBoardSurfaceCompatFallback.swift`로 이동 또는 rename
  - Phase 4B 완료 후 `2주` 이내에 `WriterIndexBoardSurfacePhaseTwo.swift` 삭제 가능 여부를 판단한다
  - 삭제가 어렵다면 남겨야 하는 compatibility contract를 별도 섹션이나 문서로 고정한다
- 이유
  - compatibility file을 active AppKit family와 같은 책임으로 취급하지 않기 위함이다.

### Phase 5. shared boundary 정리

- 대상
  - `WriterSharedTypes.swift`
- 작업
  - render-state types, bridge hosts, clipboard payload, geometry/helper를 분리
  - `ScenarioWriterView` nested type 직접 참조 제거
- 이유
  - giant extension 파일들이 shared boundary giant에 다시 매달리는 것을 방지

### Phase 6. model / persistence 분해

- 대상
  - `Models.swift`
- 작업
  - `Scenario`, `SceneCard`, `HistorySnapshot`, `FileStore` 분리
  - Phase 6 시작 전에 기존 `FileStore` 호출 site 유지 전략을 결정한다
    - 기본값은 `FileStore` public API를 유지하고 내부 helper/file split만 수행
    - 필요 시 facade 또는 typealias 전략을 먼저 고정한 뒤 분해에 들어간다
  - `FileStore`는 아래 seam으로 분해
    - pure persistence
    - shared craft sync
    - AI artifact persistence
    - scenario sorting / folder helpers
  - AI artifact persistence 분리 시 `ai_threads.json`, `ai_embedding_index.json`, vector index read/write smoke를 별도 수동 검증 항목으로 추가
- 이유
  - editor surface 분해 이후에도 core model giant가 남으면 다음 병목이 바로 여기로 이동한다

### Phase 7. settings 분해

- 대상
  - `SettingsView.swift`
- 작업
  - category card builder를 섹션별 파일로 분리
  - `@AppStorage` / Keychain / workspace file action adapter를 별도 helper로 이동
- 이유
  - 설정 수정이 UI builder giant와 storage logic을 동시에 건드리지 않게 함

## Phase별 검증 체크리스트

이 섹션은 Phase 0에서 고정한 baseline checklist이며, 이후 phase는 필요한 추가 검증 항목만 여기에 덧붙인다.

### Writer path 공통
- 앱 실행
- 시나리오 열기
- 카드 선택 / 편집 / 추가 / 삭제
- 메인 캔버스 스크롤 / active card 이동
- 검색 열기 / 닫기
- export / clipboard 기본 동작

### Focus mode
- focus mode 진입
- 편집 중 caret 유지
- focus mode 종료 후 메인 workspace 복원

### History
- snapshot 생성
- preview 진입 / 복원
- named snapshot note 편집

### Board
- board 열기 / 닫기
- 카드 드래그
- 그룹/임시 strip 관련 대표 시나리오 1개
- 줌 / 스크롤 복원
- reopen 후 배치 재구성
- drag preview 종료 후 NSView / overlay / indicator 레이어 순서 정상 복원
- inline edit 커밋 직후 scroll offset 보정과 caret 가시성 유지
- viewport 좌표와 presentation 좌표가 분리된 상태에서도 drop target 계산 일치

### Model / settings
- workspace reopen
- auto backup / workspace 파일 열기
- 설정 변경 후 재실행 복원
- AI artifact read/write smoke

## 구현 중 강제 규칙

1. 한 phase에서 하나의 giant file family만 건드린다.
2. 동작 변경과 file split을 한 커밋에 섞지 않는다.
3. active path에서 쓰지 않는 fallback file에 새 기능을 넣지 않는다.
4. 새 파일은 prefix naming과 flat source tree를 기본으로 한다. 단, 단일 family가 `7`개를 넘으면 그룹화 디렉터리를 허용하고, board AppKit family는 `wa/IndexBoard/` 예외를 허용한다.
5. root state extraction 없이 `WriterViews.swift`를 억지로 반으로 자르지 않는다.
6. board는 preview, commit, persisted session parity를 같이 검증한다.

## 추천 실행 순서

추천 실행 순서는 Phase 정의를 그대로 따른다.

1. Phase 0. 기준선 고정
2. Phase 1. `WriterViews.swift` + `WriterSharedTypes.swift` 준비 작업
3. Phase 2A. `WriterCardManagement.swift`
4. Phase 2B. `WriterFocusMode.swift`
5. Phase 3A. `WriterCardViews.swift` + `WriterKeyboardHandlers.swift`
6. Phase 3B. `WriterHistoryView.swift`
7. Phase 4A. `WriterIndexBoardScaffolding.swift` + `WriterIndexBoardPhaseTwo.swift`
8. Phase 4B. `WriterIndexBoardSurfaceAppKitPhaseTwo.swift`
9. Phase 4C. `WriterIndexBoardSurfacePhaseTwo.swift` compatibility fence
10. Phase 5. `WriterSharedTypes.swift` 실분해
11. Phase 6. `Models.swift`
12. Phase 7. `SettingsView.swift`

## Open Questions

- `WriterIndexBoardSurfacePhaseTwo.swift`는 Phase 4B 완료 후 `2주` 안에 삭제 가능 여부를 판단해야 한다. 그 시점까지도 유지가 필요하면 compatibility contract를 문서화한 뒤 frozen file로 취급한다.

## Recommended Approach

이번 리팩터링의 정답은 "모든 giant file을 같은 템플릿으로 자르기"가 아니다.

정답은 아래 두 줄이다.

- `ScenarioWriterView`와 index board AppKit surface라는 실사용 경로를 먼저 줄인다.
- fallback / shared / persistence는 그 seam이 생긴 뒤 따라온다.

이 순서로 가면 giant file budget도 맞추고, 실제 수정 fear factor도 같이 줄일 수 있다.
