# Index Board Drag Compositor Plan

## 목적

인덱스 보드에서 카드 드래그 `시작 순간`과 `드롭 순간`에 느껴지는 멈칫을 없앤다.

핵심 목표는 이것이다.

- 드래그 시작 시 바로 붙는다.
- 드롭 시 애니메이션 시작 전 정지가 없다.
- 그룹/카드가 깜빡이지 않는다.
- 기존 보드 기능, persistence, undo/redo, UI 동작은 유지한다.

이 문서는 `전체 보드 재작성`이 아니라, 현재 구조 안에서 `드래그 렌더 경로`를 별도 compositor 경로로 분리하는 실행 계획이다.

---

## 현재 문제의 본질

현재 보드는 “카드를 움직이는 엔진”이라기보다 “카드를 움직일 때마다 보드 전체 상태를 다시 세우는 엔진”에 가깝다.

### 드래그 시작 시 벌어지는 일

현재 시작 경로:

- `beginDrag(...)`
- `resolvedDropTarget(...)`
- `resolvedPresentationSurfaceProjection(...)`
- `applyCurrentLayout(animationDuration: 0)`

문제는 `applyCurrentLayout(...)`가 카드 한 장만 준비하는 것이 아니라 아래를 한 번에 다시 만진다는 점이다.

- document size 재계산
- card frame 전체 재계산
- `reconcileCardViews()`
- `reconcileLaneChipViews()`
- `updateLaneWrappers()`
- `updateIndicatorLayers()`
- `updateOverlayLayers()`
- `layoutInlineEditorIfNeeded()`

즉 드래그 시작부터 이미 full surface reconcile이 들어간다.

### 드래그 중 벌어지는 일

retarget가 발생하면 여전히:

- `resolvedPresentationSurfaceProjection(...)`
- `applyCurrentLayout(...)`

를 다시 탄다.

현재까지의 좌표계 리팩터 덕분에 타깃 정확도는 좋아졌지만, 렌더 경로는 여전히 무겁다.

### 드롭 시 벌어지는 일

드롭 순간에는 다음이 이어진다.

1. surface 쪽 drag state 종료
2. preview projection 종료/정리
3. `onCardMove(...)`
4. `scenario.performBatchedCardMutation { ... }`
5. `resolvedIndexBoardSurfaceProjection(...)`
6. `persistIndexBoardSurfacePresentation(...)`
7. `captureScenarioState()` 기반 undo 기록
8. SwiftUI `indexBoardCanvas(...)` 재조립
9. AppKit surface가 새 config를 받아 다시 layout/reconcile

즉 drop 전에 사용자가 느끼는 멈칫은 저장만의 문제가 아니라,

- 실제 모델 commit
- SwiftUI 파생값 재조립
- AppKit full reconcile

이 모두 메인 스레드에서 이어지는 구조 문제다.

---

## 왜 레퍼런스 앱은 부드러운가

레퍼런스 앱은 보통 다음 원칙을 따른다.

- 드래그 시작/드래그 중은 compositor(layers/transforms) 중심
- 실제 모델 commit은 drop 시점에만
- drop 직전 preview와 drop 직후 committed surface 사이의 전환을 사용자가 못 느끼게 숨김
- full view rebuild는 drag hot path에 올리지 않음

즉 부드러움의 차이는 `iPad 앱이라서`가 아니라 `드래그 렌더 경로가 live layout과 분리돼 있기 때문`이다.

---

## 목표 구조

## 1. Live Surface

현재 AppKit 보드 surface.

- 평소에는 이것이 실제 화면
- 실제 카드 뷰, 그룹 뷰, 요약 상태, 선택 상태를 책임짐
- 논리 state commit 결과를 렌더함

하지만 drag hot path에서는 이것을 직접 흔들지 않는다.

## 2. Drag Compositor Scene

드래그 중에만 잠깐 생기는 별도 렌더 경로.

구성 요소:

- moving card layer
- stationary card preview offsets
- group block preview
- placeholder / indicator layer

이 scene은 `snapshot + pending move`만 보고 움직인다.

여기서는:

- full card view reconcile 없음
- wrapper 재생성 최소화
- AppKit view tree 변경 최소화
- layer frame/transform만 변경

## 3. Commit Bridge

드롭 순간에는 아래 순서만 허용한다.

1. compositor는 마지막 preview를 그대로 유지
2. 실제 logical state commit
3. live surface가 committed state 준비
4. 준비가 끝난 뒤 compositor 제거

즉 사용자가 보는 화면은 `preview -> blank -> final`이 아니라 `preview -> final`로 이어져야 한다.

---

## 절대 하지 말아야 할 것

- 드래그 시작 시 `applyCurrentLayout()` full pass 실행
- retarget마다 `reconcileCardViews()` 전체 실행
- drop 직전 preview를 먼저 걷고 나서 실제 commit 기다리기
- drag 중 live card view frame을 전부 다시 세팅하기
- preview projection을 full render state처럼 SwiftUI/AppKit 전체로 다시 흘려보내기

---

## 실행 계획

## 0단계. 기준선 유지

현재 drop/start 계측은 유지한다.

최소한 아래 지표는 계속 본다.

- drag start enter
- drag retarget time
- drop callback time
- deferred commit queue wait
- `applyCurrentLayout`
- `reconcileCardViews`

목적:

- 체감 개선을 계측값으로 확인

---

## 1단계. Drag Start 경량화

목표:

- 드래그 시작 시 full layout을 없앤다.

수정 원칙:

- `beginDrag(...)`에서는 live surface를 full reconcile하지 않는다.
- moving card snapshot/layer만 만들고,
- 초기 target 계산과 compositor scene 초기화만 한다.

구체적으로:

- `applyCurrentLayout(animationDuration: 0)`를 drag start hot path에서 제거
- 필요한 경우 overlay/indicator 전용 layer만 즉시 갱신
- live card view는 숨김/고정만 하고 다시 layout하지 않음

수용 기준:

- 마우스를 누르고 끌기 시작할 때 첫 프레임 hitch가 눈에 띄게 줄어야 한다.

---

## 2단계. Drag Update를 Compositor 전용 경로로 제한

목표:

- retarget 때 full surface update를 없앤다.

수정 원칙:

- `resolvedDropTarget(...)`는 logical snapshot 기준 유지
- preview frame 계산은 계속 `snapshot + pending move`
- 실제 화면 반영은 layer frame/transform만 업데이트

구체적으로:

- `resolvedPresentationSurfaceProjection(...)` 결과를 live AppKit 뷰 전체에 다시 먹이지 않는다.
- moving card, affected row, placeholder만 갱신한다.
- `reconcileCardViews/reconcileLaneChipViews/updateLaneWrappers`는 drag update에서 금지한다.

수용 기준:

- 드래그 중 retarget가 생겨도 surface 전체가 다시 그려지는 느낌이 없어야 한다.

---

## 3단계. Group도 Card와 같은 Compositor 규칙 적용

목표:

- 그룹 drag도 같은 경량 경로를 탄다.

수정 원칙:

- 그룹 바깥에서는 block preview만
- 그룹 내부 진입 때만 slot preview
- live group wrapper는 움직이지 않고 compositor layer만 움직임

구체적으로:

- group drag의 local preview도 full projection/layout을 태우지 않는다.
- group frame, child preview frame, target indicator만 compositor에서 갱신한다.

수용 기준:

- 그룹 drag 시도 카드 drag와 같은 감각으로 시작/업데이트되어야 한다.

---

## 4단계. Drop Bridge 구축

목표:

- drop 직전 preview가 사라지며 생기는 정지를 감춘다.

수정 원칙:

- drop 순간 compositor는 그대로 유지
- 실제 commit은 뒤에서 수행
- live surface가 committed state를 받으면 그때만 compositor 제거

구체적으로:

- `endDrag(...)`에서 preview를 먼저 걷지 않는다.
- `onCardMove` 호출 후 live surface가 새 projection/layout을 적용할 때까지
  drag compositor snapshot을 잠깐 유지한다.
- 단, 이전처럼 그룹이 깜빡이지 않도록
  `그룹 wrapper를 다시 snapshot layer로 덮는 방식`이 아니라
  `현재 moving/affected row만 유지`하는 방향으로 구현한다.

수용 기준:

- 마우스를 놓은 뒤 애니메이션 시작 전 빈 정지가 없어야 한다.
- 그룹/카드가 한 프레임 사라졌다가 나타나면 실패다.

---

## 5단계. Commit 후 Partial Reconcile

목표:

- committed surface 반영도 full reconcile이 아니라 partial reconcile로 제한한다.

수정 원칙:

- card content/summary/theme가 바뀌지 않았다면 card view 재생성 금지
- 실제 이동된 카드와 영향 row만 frame 갱신
- wrapper/lane/indicator도 영향 범위만 갱신

구체적으로:

- 현재 있는 `shouldSkipCardViewReconcileForNextLayout` 최적화를 확대
- moved card IDs / affected group IDs / affected rows를 기반으로
  update 범위를 좁힌다.

수용 기준:

- drop 후에도 메인 스레드 full reconcile이 상시 발생하지 않아야 한다.

---

## 6단계. SwiftUI 파생값 경량화

목표:

- 드롭 후 SwiftUI 쪽 재조립 비용을 더 줄인다.

수정 원칙:

- `indexBoardCanvas(size:)`에서 projection/cardsByID/summary 파생값을 더 잘게 캐시
- drag/drop으로 카드 위치만 바뀌었을 때 content digest, summary dictionary까지 다시 만들지 않음

수용 기준:

- drop 후 `deferred_commit_start queue_ms`가 확실히 줄어야 한다.

---

## 구현 범위 밖

이번 계획에서 하지 않는 것:

- 전체 보드 엔진 재작성
- SwiftUI 제거
- persistence 포맷 변경
- 사용자 동작 변경
- 보드 레이아웃 규칙 재설계

즉 목표는 `현재 기능 유지 + drag renderer 경량화`다.

---

## 리스크

### 1. preview와 final state mismatch

compositor preview와 committed surface가 다르면 사용자가 jump를 느낄 수 있다.

대응:

- preview는 반드시 same logical snapshot + pending move 결과만 쓴다.

### 2. 그룹 깜빡임

preview bridge를 잘못 구현하면 그룹 wrapper가 한 프레임 사라질 수 있다.

대응:

- group 전체를 새 snapshot으로 덮지 말고,
- moving/affected row만 유지한다.

### 3. inline editor 충돌

drag 중 편집기 배치가 다시 끼어들면 full layout이 돌아간다.

대응:

- drag active 동안 inline editor layout 업데이트는 금지하거나 defer한다.

---

## 완료 판단 기준

아래를 모두 만족해야 완료다.

- 드래그 시작 시 눈에 띄는 hitch 없음
- 드롭 시 애니메이션 시작 전 정지 없음
- 그룹/카드 깜빡임 없음
- drop 전후 좌표/슬롯 감각 동일
- persistence/undo 동작 유지
- 기존 보드 기능 회귀 없음

---

## 최종 결론

지금 필요한 것은 더 많은 보정 패치가 아니다.

필요한 것은:

- drag hot path를 live layout에서 분리하고
- compositor가 드래그 시작/업데이트/드롭 직전까지 화면을 책임지게 만들고
- 실제 모델 commit과 live surface rebuild를 그 뒤로 숨기는 것

즉 다음 단계의 본질은 `보드 전체 최적화`가 아니라 `드래그 렌더 경로 분리`다.
