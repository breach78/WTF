# Index Board View Handoff

기준 시점: 2026-03-24  
대상: 현재 보드 뷰를 다른 개발자에게 바로 넘겨서 이어서 개발하게 만들기 위한 인수인계 문서

## 1. 한 줄 요약

현재 보드 뷰는 별도 데이터 모델이 아니라 `SceneCard` 트리를 같은 데이터 소스로 쓰는 `보드 전용 projection + session + AppKit surface` 구조다.  
즉, 카드의 실제 저장/이동은 기존 카드 트리와 undo/redo 경로를 그대로 타고, 보드는 그 위에 배치 상태와 viewport 상태를 얹는 방식이다.

## 2. 먼저 알아야 할 핵심 모델

### 2-1. 소스 오브 트루스

- 실제 카드 데이터: `SceneCard`, `Scenario`, `FileStore`
- 실제 이동/저장: `parent`, `orderIndex`, `category`, `isArchived`, `isFloating` 변경 후 기존 `commitCardMutation(...)` / `captureScenarioState()` / 저장 경로 사용
- 보드 전용 상태: `IndexBoardSessionState`
- 보드 전용 렌더 모델: `BoardSurfaceProjection`
- 보드 전용 단순 projection: `IndexBoardProjection`

### 2-2. 상태는 4층으로 나뉜다

1. 카드 트리 상태  
`SceneCard` 자체. 부모/자식 관계와 순서가 진짜 데이터다.

2. 보드 세션 상태  
`IndexBoardSessionState`

- `source`: 어떤 컬럼을 보드로 열었는지
- `sourceCardIDs`: 보드에 포함될 원본 카드 ID 목록
- `entrySnapshot`: 보드 진입 전 메인 워크스페이스 복귀용 스냅샷
- `viewport`: 줌/스크롤
- `logical`: 그룹 위치, detached 카드 위치, temp strip
- `presentation`: 앞면/뒷면, collapsed lane, 마지막 편집 카드
- `navigation`: reveal 요청

3. surface projection  
`BoardSurfaceProjection`

- 현재 카드들을 어떤 lane/group/grid에 놓을지 계산된 결과
- AppKit surface가 실제로 그리는 기준

4. drag/motion 임시 상태  
`WriterIndexBoardSurfaceAppKitPhaseTwo.swift` 내부 drag state, motion scene, overlay layer

- drop 전까지는 모델이 아니라 surface 프리뷰 상태

## 3. 파일 맵

### 3-1. 진입점과 수명주기

- `wa/WriterViews.swift`
  - `ScenarioWriterView`가 전체 호스트다.
  - `workspaceCommandBoundRoot(...)`에서 notification을 받아 보드 토글을 처리한다.
- `wa/waApp.swift`
  - `Command+B`가 `.waOpenIndexBoardRequested`를 올린다.
- `wa/WriterIndexBoardScaffolding.swift`
  - 보드 열기/닫기/복원
  - surface projection 생성
  - canvas 조립

### 3-2. 상태와 저장

- `wa/WriterIndexBoardTypes.swift`
  - `IndexBoardSessionState`
  - `IndexBoardRuntime`
  - persisted session 구조

### 3-3. 렌더링

- `wa/WriterIndexBoardPhaseThree.swift`
  - 보드 호스트 뷰
  - editor overlay
- `wa/WriterIndexBoardSurfaceAppKitPhaseTwo.swift`
  - 현재 실사용 보드 surface
  - drag/drop, zoom, scroll, motion scene
- `wa/WriterIndexBoardPhaseTwo.swift`
  - legacy/fallback view도 남아 있지만, 핵심 이동 커밋 함수들도 여기 있다.
- `wa/WriterIndexBoardSurfaceProjection.swift`
  - surface용 레이아웃/정규화/helper

### 3-4. 보조 기능

- `wa/WriterIndexBoardPhaseFour.swift`
  - 카드 summary 저장/해석
- `wa/WriterIndexBoardPhaseFive.swift`
  - temp container / temp card 생성 규칙
- `wa/WriterIndexBoardPhaseSix.swift`
  - reveal, timeline 이동, split pane 연결
- `board_motion_engine_plan.md`
  - 현재 surface 구조의 배경과 성능 병목 문서

## 4. 진입 흐름

### 4-1. 커맨드에서 보드까지

1. `wa/waApp.swift`
   - `Command+B`가 `.waOpenIndexBoardRequested` notification 발행
2. `wa/WriterViews.swift`
   - `workspaceCommandBoundRoot(...)`가 이를 수신
3. `wa/WriterIndexBoardScaffolding.swift`
   - `handleOpenIndexBoardRequestNotification()` 실행

### 4-2. 열릴 때 무슨 일이 일어나는가

`handleOpenIndexBoardRequestNotification()` 순서:

1. 이미 보드가 열려 있으면 닫는다.
2. 아니면 `captureIndexBoardEntrySnapshot()`으로 메인 워크스페이스 상태를 저장한다.
3. `IndexBoardRuntime.persistedSession(...)`으로 이전 보드 세션이 있으면 복원 시도
4. 없으면 현재 메인 캔버스 문맥에서 fallback column을 계산
5. `openIndexBoard(...)` 호출

`openIndexBoard(...)`에서 하는 일:

1. `IndexBoardColumnSource(parentID, depth)` 생성
2. 동일 source의 persisted session이 있으면 viewport/logical/presentation 복원
3. 없으면 새 `IndexBoardSessionState` 생성
4. `finishEditing()`로 기존 편집 종료
5. `indexBoardRuntime.activate(...)`
6. 보드 안에서 참조할 카드 summary를 미리 reconcile
7. 메인 포커스를 보드 쪽으로 넘김

### 4-3. 닫힐 때 무슨 일이 일어나는가

`closeIndexBoard()` 흐름:

1. `deactivateIndexBoardSessionIfNeeded()`
2. 여기서 현재 viewport를 먼저 persist
3. editor draft 정리
4. `IndexBoardRuntime.deactivate(...)`
5. 마지막으로 `restoreIndexBoardEntrySnapshot(...)`으로 메인 워크스페이스 상태 복구

중요:

- `entrySnapshot`은 보드 세션 영속 상태가 아니라 "보드 들어가기 전 메인 화면 복귀용" 상태다.
- persisted session에는 `entrySnapshot`이 저장되지 않는다.

## 5. 저장은 어디에 되는가

### 5-1. 실제 카드 구조 저장

보드에서 카드를 옮겨도 별도 보드 파일에 저장되는 게 아니다.  
실제 저장 대상은 기존 `SceneCard` 트리다.

즉, 아래 변경은 기존 저장 경로를 탄다.

- 카드 부모 변경
- 카드 순서 변경
- 카드 내용 변경
- 그룹 부모 카드 생성
- Temp 컨테이너 생성

저장 매체:

- `FileStore`
- 시나리오 폴더 내부 `cards_index.json`
- 카드 본문 파일
- history / linked cards 등 기존 워크스페이스 저장 구조

### 5-2. 보드 session 저장

보드 전용 session은 `UserDefaults`에 저장된다.

- 키: `writer.indexboard.persisted-sessions.v1`
- 정의 위치: `wa/WriterIndexBoardTypes.swift`

저장되는 값:

- `source`
- `sourceCardIDs`
- `zoomScale`
- `scrollOffset`
- `detachedGridPositionByCardID`
- `groupGridPositionByParentID`
- `tempStrips`
- `collapsedLaneParentIDs`
- `showsBackByCardID`
- `lastPresentedCardID`

저장되지 않는 값:

- `entrySnapshot`
- editor draft
- drag state / motion scene
- pending reveal token

### 5-3. viewport 저장 방식

viewport는 두 단계다.

1. live viewport  
`IndexBoardRuntime.liveViewportByDescriptor`

- 스크롤/줌 중에 매 tick session publish를 피하려고 따로 들고 있는 임시 상태

2. persisted viewport  
`persistViewport(...)`

- 보드 종료 시점
- viewport finalize 시점
- 필요 시 explicit persist

### 5-4. summary 저장

보드 카드 summary는 `UserDefaults`가 아니라 `FileStore`에 저장된다.

- 메모리 보관: `FileStore.indexBoardSummaryRecordsByScenarioID`
- 파일명: `card_summaries.json`
- 위치: 각 scenario 폴더 내부

summary record 내용:

- `cardID`
- `summaryText`
- `sourceContentHash`
- `updatedAt`
- `sourceType`
- `isStale`

## 6. 현재 보드가 어떤 데이터를 기준으로 열리는가

보드는 `IndexBoardColumnSource`로 열린다.

- `parentID`: 어떤 부모 카드의 children을 source로 잡을지
- `depth`: 메인 워크스페이스 상에서 그 컬럼의 depth

중요:

- 보드는 "현재 컬럼의 live children"을 바로 쓰기도 하고
- persisted session의 `sourceCardIDs`를 합쳐서 source 범위를 유지하기도 한다.

이유:

- 보드 안에서 그룹 이동, temp 이동, 부모 이동이 일어나면 단순 현재 컬럼 children만으로는 원래 보던 범위를 잃을 수 있기 때문

실제 live 카드 해석은 두 가지가 있다.

1. `resolvedLiveIndexBoardSourceCards(for source: IndexBoardColumnSource)`  
source parent의 현재 children을 읽는다.

2. `resolvedLiveIndexBoardSourceCards(for session: IndexBoardSessionState)`  
`sourceCardIDs`와 실제 카드 트리를 함께 써서 보드 범위를 안정적으로 재구성한다.

## 7. 메인 워크스페이스와 어떻게 연결되는가

### 7-1. 호스트

보드는 별도 윈도우나 별도 scene이 아니라 `ScenarioWriterView` 내부에 들어간다.

중요 연결:

- `ScenarioWriterView`가 보드 관련 대부분의 상태를 가지고 있다.
- `indexBoardRuntime`는 `shared` singleton이다.
- 한 시나리오에는 동시에 하나의 active session만 존재한다.
- `IndexBoardSessionDescriptor`에 `paneID`가 있지만, 실제 active map은 `scenarioID` 기준 하나다.

즉:

- split pane 환경에서도 같은 시나리오에서 보드를 동시에 두 pane에 독립적으로 띄우는 구조는 아니다.

### 7-2. split pane / timeline 연결

`WriterIndexBoardPhaseSix.swift`에서 처리한다.

- 현재 보드 범위 안 카드면:
  - selection 변경
  - active card 변경
  - reveal 요청
  - 필요 시 editor 열기
- 현재 범위 밖 카드면:
  - split mode면 다른 pane에 `.waRequestSplitPaneFocus` notification 발행
  - 아니면 보드를 접고 메인 워크스페이스로 이동

## 8. projection 생성 흐름

현재 보드의 핵심은 `resolvedIndexBoardSurfaceProjection(...)`이다.  
이 함수가 사실상 "live 카드 트리 -> 보드 레이아웃" 변환기다.

### 8-1. 입력

- active session
- live source cards
- temp container
- logical state
  - group positions
  - detached positions
  - temp strips
- optional override
  - drag preview용 group position override
  - detached position override
  - temp strip override

### 8-2. 처리 순서

1. source live cards 수집
2. temp container 아래 카드와 일반 카드를 분리
3. 일반 카드를 부모 기준으로 `BoardSurfaceParentGroupID`별 grouping
4. group origin을 session logical state 기준으로 복원
5. temp descendant 여부를 따라 temp group 식별
6. detached temp cards의 parking 위치 계산
7. persisted temp strip + live temp 멤버를 합쳐 `resolvedIndexBoardTempStrips(...)`
8. `resolvedIndexBoardTempStripSurfaceLayout(...)`으로 temp group / detached card 위치 계산
9. `normalizedIndexBoardSurfaceLayout(...)`으로 group 간 겹침 제거 및 row cluster anchor 보정
10. lane 배열 생성
11. surface item 배열 생성
12. 최종 `BoardSurfaceProjection` 반환

### 8-3. projection이 들고 있는 것

- `startAnchor`
- `lanes`
- `parentGroups`
- `tempStrips`
- `surfaceItems`
- `orderedCardIDs`

이 중 실제 드래그/렌더링에 가장 중요한 것은:

- `parentGroups`
- `surfaceItems`
- `tempStrips`

## 9. surface 모델과 simple projection의 차이

### 9-1. `BoardSurfaceProjection`

AppKit surface가 쓰는 진짜 레이아웃 결과다.

- grid 좌표가 명시적이다.
- detached 카드와 temp strip 개념이 있다.
- parent group 배치가 명시적이다.

### 9-2. `IndexBoardProjection`

surface projection에서 다시 내려 만든 단순 모델이다.

- group 중심 구조
- legacy/fallback view 호환용
- 일부 커밋 함수도 이 단순 projection을 참고한다.

즉, 현재 구조는:

- surface는 `BoardSurfaceProjection`
- 커밋 함수 일부는 `IndexBoardProjection`

둘 다 살아 있다.

## 10. 렌더링 파이프라인

### 10-1. canvas 조립

`indexBoardCanvas(size:)`에서 한다.

여기서:

1. `resolvedIndexBoardSurfaceProjection()` 계산
2. 보드에 필요한 카드/summary/digest만 추려서 cache payload 생성
3. `IndexBoardPhaseThreeView` 생성

### 10-2. `IndexBoardPhaseThreeView`

역할:

- AppKit surface와 editor overlay를 한데 묶는 호스트
- callback wiring 담당

선택 로직:

- `surfaceProjection`이 있으면 `IndexBoardSurfaceAppKitPhaseTwoView`
- 없으면 legacy `IndexBoardPhaseTwoView`

### 10-3. 현재 실사용 renderer

`WriterIndexBoardSurfaceAppKitPhaseTwo.swift`

핵심 클래스:

- `IndexBoardSurfaceAppKitConfiguration`
- `IndexBoardSurfaceAppKitContainerView`
- `IndexBoardSurfaceAppKitDocumentView`

역할 분리:

- configuration: 바깥 SwiftUI -> AppKit 브리지 입력
- container view: scroll/magnify/viewport 적용
- document view: 카드 뷰, chip 뷰, selection, drag overlay, motion scene 담당

### 10-4. 드래그 중 surface가 어떻게 동작하는가

현재 구조는 drag 중 모델을 건드리지 않고 motion scene으로 프리뷰한다.

대략 흐름:

1. `beginDrag(cardID:pointer:)`
2. moving card 집합 계산
3. `resolvedDropTarget(for:)`
4. 프리뷰용 projection/temp strip/layout 계산
5. `beginMotionScene(...)`
6. `applyCardDragUpdate(...)`마다 target 갱신
7. `updateMotionSceneLayout()`
8. drop 시에만 callback으로 실제 commit

현재 알려진 핫패스:

- `updateIndicatorLayers()`
- `updateOverlayLayers()`

둘 다 드래그 중 layer churn이 남아 있는 구간이다.

## 11. 편집, 앞면/뒷면, summary

### 11-1. editor

`IndexBoardPhaseThreeView` 위에 editor overlay가 뜬다.

관련 상태:

- `indexBoardEditorDraft`
- `IndexBoardEditorDraft`

관련 함수:

- `presentIndexBoardEditor(for:)`
- `presentIndexBoardEditorForSelection()`
- `updateIndexBoardEditorDraft(_:)`
- `saveIndexBoardEditor()`
- `commitIndexBoardInlineEdit(cardID:contentText:)`

### 11-2. 저장 규칙

editor 저장 시 바뀔 수 있는 것:

- 카드 content
- manual summary
- `showsBackByCardID`

주의:

- Temp 카드 생성 직후 내용과 summary가 모두 비어 있으면 생성 취소로 간주하고 이전 상태를 복원한다.

### 11-3. summary 해석 우선순위

`resolvedIndexBoardSummary(for:)` 기준:

1. 저장된 manual/digest summary record
2. 없으면 digest cache fallback
3. 둘 다 없으면 nil

## 12. Temp 구조

### 12-1. Temp는 별도 테이블이 아니다

Temp는 카드 트리 안에 숨은 구조 카드로 표현된다.

경로:

- root card
- note container
- temp container

생성 함수:

- `ensureIndexBoardTempContainer()`

판별 규칙:

- note container: `category == note` 또는 첫 줄이 `"note"`
- temp container: 첫 줄이 `"temp"`

### 12-2. Temp에 들어갈 수 있는 것

1. temp child card  
루트 그룹 바깥에 parking된 카드

2. temp group  
부모 카드 자체가 temp container 아래로 이동한 그룹

### 12-3. temp strip이 하는 일

`IndexBoardTempStripState`는 temp 영역에서 카드와 그룹의 row/column block 순서를 잡는다.

구성:

- `row`
- `anchorColumn`
- `members`
  - `.card(UUID)`
  - `.group(UUID)`

temp strip이 필요한 이유:

- detached 카드와 temp group을 같은 평면에서 섞어서 배치해야 하기 때문
- 실제 temp container children 순서만으로는 보드의 2D 배치를 표현할 수 없기 때문

## 13. 이동 로직 전체 지도

### 13-1. 이동 로직의 큰 원칙

보드 이동은 항상 두 층으로 나뉜다.

1. surface에서 drop target 계산
2. drop 시 실제 카드 트리와 logical state를 커밋

즉:

- drag 중에는 preview
- drop 시에만 실제 model mutation

### 13-2. drop target 구조

`IndexBoardCardDropTarget`

주요 필드:

- `groupID`
- `insertionIndex`
- `laneParentID`
- `previousCardID`
- `nextCardID`
- `previousTempMember`
- `nextTempMember`
- `detachedGridPosition`
- `preferredColumnCount`
- `groupBlockParentID`

의미:

- 일반 그룹 삽입인지
- temp strip 사이 삽입인지
- detached parking인지
- 다중 선택의 시각적 열 수를 유지할지

### 13-3. 단일 카드 이동

`commitIndexBoardCardMove(...)`

순서:

1. live projection 재해석
2. target이 temp strip이면 detached 경로로 보냄
3. 아니면 destination group 계산
4. `resolvedIndexBoardCardDestination(...)`로 실제 parent/index 계산
5. `applyIndexBoardParentPlacement(...)`로 모델 반영
6. detached 위치 제거
7. surface presentation 재정규화 후 logical state persist
8. selection/active card 갱신
9. `commitCardMutation(...)`

### 13-4. 다중 선택 이동

`commitIndexBoardCardMoveSelection(...)`

특징:

- `resolvedIndexBoardMovingCards(...)`가 surface 상의 시각적 grid 순서대로 moving cards를 정렬한다.
- 그래서 다중 선택 이동은 selection set 순서가 아니라 "현재 보드에서 보이는 순서"를 기준으로 들어간다.

나머지 원리는 단일 카드 이동과 같다.

### 13-5. detached 이동

`commitDetachedIndexBoardCardMove(...)`  
`commitDetachedIndexBoardCardMoveSelection(...)`

공통 원리:

1. target 기준으로 새 temp strip 배열 계산
2. 실제 카드 parent를 temp container로 옮김
3. `applyIndexBoardTempStripOrdering(...)`로 temp children 순서 정리
4. 새 surface projection을 다시 persist

즉, detached는 "화면상 떠 있는 카드"가 아니라 실제로 temp container 아래 자식이 된다.

### 13-6. 그룹 이동

`commitIndexBoardGroupMove(...)`

여기서 group은 "부모 카드가 있는 그룹"이다.

순서:

1. moving group의 parent card를 찾음
2. visible mainline groups 기준 target index 계산
3. `IndexBoardResolvedGroupMoveContext`로 이전/다음 group 문맥 계산
4. `resolvedIndexBoardGroupDestination(...)`으로 실제 parent/index 계산
5. `applyIndexBoardParentPlacement(...)`

실제로는 그룹 박스 자체를 옮기는 것이 아니라, 그 그룹을 대표하는 부모 카드를 트리에서 재배치한다.

### 13-7. 부모 그룹 위치 이동

`commitIndexBoardParentGroupMove(...)`

이건 일반 group reorder보다 한 단계 surface 중심이다.

경우가 두 가지다.

1. moving group이 temp group일 때

- temp strip만 갱신
- model은 temp ordering만 반영

2. moving group이 mainline group일 때

- target origin으로 override한 새 `surfaceProjection` 생성
- 그 projection을 logical state로 persist
- `applyIndexBoardSurfaceParentOrdering(...)`로 실제 카드 트리 순서를 surface와 맞춘다

즉, 부모 그룹 이동은 "먼저 surface를 정답으로 만든 뒤, 모델이 그 배치를 따라가게 만드는" 방식이다.

### 13-8. 핵심 helper

`applyIndexBoardParentPlacement(...)`

- parent cycle 방지
- 동일 parent 내 재정렬 처리
- 다른 parent로 이동 시 sibling index 정리
- `isFloating = false`
- subtree category 동기화
- 기존/신규 parent index normalize

`resolvedIndexBoardCardDestination(...)`

- drop target의 exact previous/next card 힌트를 우선 사용
- 안 되면 주변 card의 parent 문맥 사용
- 안 되면 ancestor parent fallback
- 끝까지 안 되면 source parent fallback

`isValidIndexBoardParent(...)`

- 자기 자신 밑으로 넣는 것 방지
- descendant 밑으로 넣는 것 방지

## 14. logical state 정규화 규칙

보드에서는 surface를 그대로 저장하지 않는다.  
surface에서 "다시 계산 가능한 것"을 걷어내고 logical state만 저장한다.

`resolvedIndexBoardLogicalState(from:)`

- group origin 저장
- detached position 저장
- temp strip을 canonical form으로 다시 생성

`persistIndexBoardSurfacePresentation(...)`

- 위 logical state를 runtime session에 반영
- 필요 시 deferred persist

중요:

- 실제 저장 단위는 `BoardSurfaceProjection` 전체가 아니라 `IndexBoardLogicalState`
- 다음 open 시 projection은 live 카드 트리 + logical state로 재계산된다

## 15. temp strip / detached 보정 함수들

`WriterIndexBoardSurfaceProjection.swift`의 핵심 helper:

- `resolvedIndexBoardTempStrips(...)`
  - persisted strip에서 죽은 멤버 제거
  - 누락된 live temp 멤버를 다시 붙임
- `resolvedIndexBoardTempStripSurfaceLayout(...)`
  - strip을 2D 위치로 바꿈
- `resolvedIndexBoardTempStripsByApplyingMove(...)`
  - drag target 기준 strip 배열 업데이트
- `resolvedIndexBoardDetachedPositionsByApplyingDrop(...)`
  - detached 카드 parking / block insertion 계산
- `normalizedIndexBoardSurfaceLayout(...)`
  - group 겹침 제거
  - reference layout anchor와 최대한 비슷하게 유지

이 레이어는 "보드가 왜 저 위치에 그려지나"를 설명하는 핵심 파일이다.

## 16. undo/redo와 커밋 경로

보드는 별도 undo stack을 가지지 않는다.

대부분의 보드 액션은:

1. `captureScenarioState()`
2. live 모델 mutation
3. `commitCardMutation(...)` 또는 `scheduleIndexBoardCommitCardMutation(...)`

으로 기존 undo/redo 체계에 들어간다.

즉:

- 보드 이동
- 보드 편집
- Temp 카드 생성
- 부모 카드 생성

모두 기존 시나리오 상태 snapshot 기반으로 되돌릴 수 있다.

## 17. 지금 구조에서 중요한 불변식

1. 보드는 별도 카드 저장소를 만들지 않는다.  
카드 이동은 항상 실제 `SceneCard.parent` / `orderIndex`를 바꾼다.

2. 보드 layout은 영구 저장 대상이 아니라 재구성 대상이다.  
저장되는 것은 logical state뿐이다.

3. temp는 "그냥 화면에 떠 있는 카드"가 아니다.  
실제 temp container 아래 카드/부모 그룹으로 존재한다.

4. 다중 선택 이동 순서는 selection set 순서가 아니라 현재 surface 상의 시각 순서다.

5. parent move는 surface 좌표만 바꾸는 것이 아니다.  
결국 실제 카드 트리 order까지 맞춰야 끝난다.

6. session persistence와 content persistence는 저장 매체가 다르다.

- 보드 세션: `UserDefaults`
- 카드/summary: `FileStore`

7. 현재 실사용 surface는 AppKit path다.  
legacy path가 남아 있어도 주 수정 대상은 보통 `WriterIndexBoardSurfaceAppKitPhaseTwo.swift`다.

## 18. 새 개발자가 먼저 읽어야 할 순서

추천 읽기 순서:

1. `wa/WriterIndexBoardScaffolding.swift`
   - 열기/닫기/복원
   - surface projection 생성
2. `wa/WriterIndexBoardTypes.swift`
   - session 구조와 저장 위치
3. `wa/WriterIndexBoardSurfaceProjection.swift`
   - group/temp/detached 레이아웃 규칙
4. `wa/WriterIndexBoardSurfaceAppKitPhaseTwo.swift`
   - 실제 surface 렌더링과 drag 프리뷰
5. `wa/WriterIndexBoardPhaseTwo.swift`
   - drop commit과 model mutation
6. `wa/WriterIndexBoardPhaseFive.swift`
   - temp 구조
7. `wa/WriterIndexBoardPhaseFour.swift`
   - summary 저장
8. `wa/WriterIndexBoardPhaseSix.swift`
   - timeline/split pane 연결

## 19. 현재 작업 시 가장 조심해야 할 부분

### 19-1. surface만 바꾸고 model commit을 안 맞추는 실수

프리뷰는 예뻐졌는데 drop 뒤 실제 트리와 session logical state가 어긋나는 문제가 생기기 쉽다.  
수정 후에는 반드시 아래 셋이 동시에 맞는지 봐야 한다.

- 실제 `SceneCard` parent/order
- persisted logical state
- 다음 reopen 시 재구성된 surface

### 19-2. temp strip과 detached position을 따로 놀게 만드는 실수

temp 쪽은 다음 세 가지가 같이 맞아야 한다.

- temp container children order
- `tempStrips`
- detached grid positions

### 19-3. viewport를 session publish로 과도하게 태우는 실수

줌/스크롤 중에 매번 full session publish를 태우면 surface 전체 갱신 비용이 커진다.  
현재는 `liveViewportByDescriptor`를 둔 이유가 있다.

### 19-4. AppKit surface만 고치고 legacy/fallback path를 잊는 실수

현재 주 경로는 AppKit이 맞지만, `IndexBoardProjection`과 legacy view가 아직 남아 있다.  
완전히 제거하지 않는 한, 타입/콜백 계약이 깨지지 않는지 같이 봐야 한다.

## 20. 성능 관점에서 이미 알려진 병목

`board_motion_engine_plan.md` 참고.

현재 문맥에서 특히 봐야 할 곳:

- `updateIndicatorLayers()`
- `updateOverlayLayers()`
- drag retarget 시 전체 surface 갱신 범위
- viewport apply / magnify sync 경로

즉, 지금 구조는 기능적으로는 보드가 성립되어 있지만, 모션 품질과 핫패스 최적화는 아직 별도 관심사로 남아 있다.

## 21. 실무적으로 바로 써먹을 체크리스트

새 개발자가 어떤 수정이든 시작하기 전에 확인할 것:

1. 이 수정이 card tree를 바꾸는가, session logical state만 바꾸는가, surface preview만 바꾸는가
2. 저장 매체가 `UserDefaults`인지 `FileStore`인지
3. reopen 후에도 같은 배치가 재구성되는가
4. split pane / timeline / editor overlay에 영향이 없는가
5. Temp 그룹과 detached 카드 케이스를 같이 검증했는가

---

이 문서의 핵심 문장 하나만 남기면 이렇다.

현재 보드 뷰는 `SceneCard 트리 위에 얹힌 보드 projection 편집기`이고,  
실제 수정 포인트는 보통 `Scaffolding -> SurfaceProjection -> AppKitSurface -> PhaseTwo commit` 순서로 따라가면 된다.
