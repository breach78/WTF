# 보드 모션 엔진 재설계 플랜

## 1. 목적

이 문서의 목표는 현재 보드 뷰를 `기능은 유지하면서` 레퍼런스 앱 수준의 부드러운 드래그/재배치 감각으로 끌어올리기 위한
`모션 엔진 재설계 계획`을 고정하는 것이다.

핵심 기준:

- 문제를 `기능 추가`가 아니라 `보드 모션 엔진 자체`의 재설계 문제로 다룬다.
- 데이터 모델, 보드 세션, 카드 삭제/생성/편집 같은 상위 기능은 최대한 유지한다.
- 갈아엎는 범위는 `보드 surface의 드래그/재배치 핫패스`로 제한한다.
- 목표는 “평균적으로 빠르다”가 아니라 “드래그 중 손에 붙는다”는 체감이다.
- 임시 미세 튜닝으로 끝내지 않고, 측정 가능한 성능 기준과 검증 루프를 포함한다.

## 2. 현재 문제 정의

현재 보드는 기능적으로는 원하는 방향에 가깝지만, 모션 품질은 레퍼런스와 다르다.

체감 차이:

- 레퍼런스는 드래그 카드와 주변 카드가 같은 표면에서 연속적으로 미끄러진다.
- 현재 보드는 카드가 `즉시 반응`하기보다 `한 박자 늦게 따라오는` 느낌이 강하다.
- 사용자는 이를 `부드럽지 않다`, `버벅인다`, `더벅인다`로 인식한다.

이 문제는 단순 FPS 숫자 하나가 아니라 아래 세 가지가 합쳐진 결과로 봐야 한다.

- 포인터를 따라가는 주 카드의 latency
- 주변 카드가 재배치되기 시작하는 시점의 latency
- retarget가 자주 바뀔 때 발생하는 레이아웃/레이어 churn

## 3. 현재 구현에서 확인된 병목

핵심 병목은 `WriterIndexBoardSurfaceAppKitPhaseTwo.swift` 안의 드래그 루프다.

### 3-1. 드래그 프리뷰가 retarget마다 160ms layout animation을 탄다

현재 preview animation duration:

- `previewLayoutAnimationDuration = 0.16`
- `commitLayoutAnimationDuration = 0.18`

참조:

- `wa/WriterIndexBoardSurfaceAppKitPhaseTwo.swift`
  - `IndexBoardSurfaceAppKitConstants.previewLayoutAnimationDuration`
  - `IndexBoardSurfaceAppKitConstants.commitLayoutAnimationDuration`

이 값 자체가 절대 악은 아니지만, 현재 구조에서는 문제가 된다.

- retarget가 바뀔 때마다 새 layout animation이 다시 걸린다.
- 사용자는 카드가 포인터를 따라가는 것이 아니라 `뒤늦게 catch-up`하는 것처럼 느낀다.

### 3-2. retarget 시 전체 레이아웃 경로를 다시 탄다

현재 흐름:

- `resolvedDropTarget(for:)`
- `applyCardDragUpdate(...)`
- `applyCurrentLayout(animationDuration:)`

이 경로 안에서 아래 작업이 한 번에 일어난다.

- 카드 프레임 재계산
- 카드 뷰 reconcile
- lane chip reconcile
- lane wrapper 갱신
- placeholder/indicator layer 재생성
- overlay layer 갱신
- 모든 카드/칩 frame animation 적용

즉, 현재 구현은 `영향받는 카드 몇 장만 움직이는 엔진`이 아니라
`보드 표면 전체를 다시 맞춰보는 엔진`에 가깝다.

### 3-3. NSView/Layer churn이 핫패스에 남아 있다

현재 핫패스에서 반복적으로 부담이 생길 수 있는 경로:

- `reconcileCardViews()`
- `reconcileLaneChipViews()`
- `updateLaneWrappers()`
- `updateIndicatorLayers()`
- `updateOverlayLayers()`

특히 `updateIndicatorLayers()`는 기존 layer를 지우고 다시 만드는 방식이라
retarget가 자주 바뀌면 비용이 크게 뛸 수 있다.

### 3-4. 카드 렌더링이 draw 기반이다

현재 카드 렌더는 `IndexBoardSurfaceAppKitCardView.draw(_:)` 기반이다.

- 그림자
- 라운드 배경
- 텍스트 attributed draw

정적 상태에서는 괜찮지만, 핫패스에서 뷰/레이어 갱신과 겹치면 부드러움을 해칠 수 있다.

### 3-5. 현재 구조는 “포인터 중심 연속 이동”보다 “드롭 타깃 변경 중심 재배치”에 가깝다

이 차이가 레퍼런스와의 가장 큰 질감 차이다.

- 레퍼런스: compositor-driven continuous motion
- 현재 구현: retarget-driven layout update

## 4. 재설계 원칙

이번 작업의 핵심은 `보드 전체 재작성`이 아니라 `모션 엔진 핫패스 재작성`이다.

유지 대상:

- `SceneCard` 트리 구조
- `BoardSurfaceProjection`
- 보드 세션 상태 저장 방식
- 카드 편집 sheet 진입
- 카드/그룹 삭제/생성/색상 변경 같은 상위 액션 API
- undo/redo 연동 포인트

교체 대상:

- 드래그 중 프리뷰 계산 방식
- 주변 카드 재배치 방식
- retarget hysteresis 방식
- drag hot path에서의 view/layer 갱신 방식
- drag commit 시점의 모델 반영 경로

즉:

- 데이터/기능 API는 유지
- 드래그/재배치 엔진은 다시 짠다

## 5. 목표 아키텍처

### 5-1. 정상 상태와 드래그 상태를 분리한다

보드는 두 상태를 가져야 한다.

- 정상 상태: 현재처럼 보드 surface를 렌더
- 드래그 상태: 별도 motion scene이 표면을 관리

드래그가 시작되면:

- 정상 뷰 계층은 정지된 기준 화면이 된다.
- motion scene이 카드 위치 업데이트를 전담한다.
- 포인터 이동 동안 상위 상태나 전체 reconcile을 다시 태우지 않는다.

### 5-2. 드래그 중엔 layout animation이 아니라 position/transform을 쓴다

드래그 상태에서 필요한 것은 `layout`이 아니라 `composition`이다.

권장 방식:

- 드래그 시작 시 각 카드의 resting frame을 캡처
- motion scene 안에서 카드별 `currentPosition`, `targetPosition`만 유지
- 매 프레임 또는 retarget 시 layer의 `position` 또는 `transform`만 갱신
- 드롭 순간에만 실제 모델과 projection을 commit

즉, `animator().frame` 중심에서 `CALayer position/transform` 중심으로 전환한다.

### 5-3. 정적 렌더는 캐시하고, 핫패스에서는 위치만 바꾼다

드래그 시작 시 캐시할 것:

- 카드 이미지 또는 카드 전용 layer subtree
- lane chip 이미지 또는 layer subtree
- 그룹 wrapper path
- 필요 시 placeholder geometry 캐시

드래그 중 바꿀 것:

- 주 카드 위치
- 영향받는 이웃 카드 위치
- 현재 placeholder 위치

드래그 중 바꾸지 말 것:

- 카드 텍스트 재측정
- 카드 draw 재실행
- chip model 재생성
- wrapper layer 재구성
- 상위 session 저장

### 5-4. retarget는 덜 민감해야 한다

현재 target 변경이 너무 자주 일어나면 다음 문제가 생긴다.

- preview animation 재시작
- placeholder 재생성
- 주변 카드 재배치 재계산
- 사용자가 느끼는 “덜컥덜컥” 증가

새 기준:

- 카드 중심이 슬롯 midpoint를 `충분히` 넘기 전에는 retarget를 유지
- row/column 이동에 별도 hysteresis 허용
- group 진입/이탈도 경계 밴드를 둔다

이 작업은 단순 상수 조정이 아니라 `retarget state machine` 정리다.

### 5-5. 모델 commit은 drop 시점으로 더 뒤로 민다

현재 구조에서 중요한 기준은 다음이다.

- drag preview는 로컬 scene state
- 실제 데이터 반영은 drop commit

드래그 중 상위 상태 변경이 줄어야 하는 이유:

- SwiftUI/AppKit 상위 업데이트를 피할 수 있다.
- 세션 저장 경로가 hot path에 끼어드는 것을 막을 수 있다.
- undo/redo 경로도 더 명확해진다.

## 6. 구현 작업 묶음

### A. Motion Path 교체

목표:

- drag 중 `animator().frame` 제거
- card/chip 이동을 layer position 기반으로 변경

세부 작업:

- 드래그 상태에서만 쓰는 `IndexBoardSurfaceMotionScene` 도입
- `applyCurrentLayout(animationDuration:)`를 drag hot path에서 제거
- drag 중 `cardView.frame` 직접 수정도 최소화하고 layer 이동 중심으로 전환
- commit 후 정상 surface로 복귀

완료 기준:

- 드래그 중 포인터와 주 카드 사이의 지연이 체감상 거의 없어야 한다.
- 주변 카드가 ease-out으로 늦게 따라오지 않아야 한다.

### B. Static Surface Cache 도입

목표:

- draw/reconcile 비용을 drag hot path에서 제거

세부 작업:

- drag start 시 resting scene snapshot 확장
- 카드 이미지를 미리 캡처하거나 layer subtree를 freezing
- lane chip도 같은 방식으로 정적 캐시
- 그룹 wrapper path도 frame cache 기반으로 유지

완료 기준:

- drag 중 `reconcileCardViews`, `reconcileLaneChipViews`, `updateLaneWrappers`, `updateIndicatorLayers`가 돌지 않거나,
  최소한 retarget마다 전체 실행되지 않아야 한다.

### C. Incremental Retarget Solver

목표:

- `보드 전체 재배치`가 아니라 `영향받는 범위 재배치`로 바꾸기

세부 작업:

- 슬롯 배열 또는 ordered card ids 기준의 local reorder 모델 도입
- old insertion index와 new insertion index 사이의 affected range만 계산
- group 이동도 같은 원칙으로 affected range만 재계산
- temp strip 진입/이탈도 full normalization 없이 preview state로 처리

완료 기준:

- 카드 한 장 이동 시 영향 없는 lane/group은 움직이지 않아야 한다.
- placeholder와 이웃 카드만 반응해야 한다.

### D. Retarget Hysteresis 재설계

목표:

- 드롭 타깃이 너무 자주 바뀌는 현상 줄이기

세부 작업:

- flow slot midpoint hysteresis
- row transition hysteresis
- group enter/exit hysteresis
- temp strip target retention band
- detached parking retain band

완료 기준:

- 포인터가 경계 근처를 오갈 때 target이 프레임마다 바뀌지 않아야 한다.
- 사용자가 느끼는 계단식 재배치가 줄어야 한다.

### E. Commit Path 정리

목표:

- drag preview와 실제 mutation 경로 분리

세부 작업:

- drag start: selection/active 변경 최소화
- drag update: 상위 session/state write 금지
- drag end: 단 한 번의 commit
- commit 후 필요한 session 저장, undo snapshot, viewport 보정 수행

완료 기준:

- drag 중 상위 state churn이 현저히 줄어야 한다.
- drop 시점만 mutation 경로로 취급된다.

### F. Instrumentation / Profiling

목표:

- 감이 아니라 측정으로 줄이기

측정 대상:

- `applyCurrentLayout`
- `resolvedDropTarget`
- `resolvedLocalCardDragPreviewFrames`
- `updateIndicatorLayers`
- `updateOverlayLayers`
- card draw count
- drag 중 layer count churn
- main-thread time per drag tick

도구:

- Instruments Time Profiler
- Core Animation FPS / frame pacing
- signpost 또는 단순 timing 로그

완료 기준:

- 어떤 경로가 병목인지 숫자로 설명 가능해야 한다.
- 최적화 전후 비교가 가능해야 한다.

## 7. 단계별 실행 순서

### 0단계. 베이스라인 측정

먼저 지금 상태를 측정한다.

- drag 1회당 retarget 빈도
- `applyCurrentLayout` 평균 시간
- drag 중 main thread 점유 시간
- card/layer 재생성 횟수

이 단계 없이 바로 고치면 개선 여부를 확정할 수 없다.

### 1단계. 드래그 중 layout animation 제거

가장 먼저 할 일:

- drag hot path에서 `animator().frame` 제거
- preview animation duration 기반 재배치 제거

이 단계만으로도 체감 개선이 가장 클 가능성이 높다.

### 2단계. static cache + local motion scene 도입

이 단계에서 `부드러움의 질감`이 크게 바뀐다.

- drag start 시 정적 표면 캐시
- drag 중엔 layer 위치만 변경
- 정상 뷰 계층은 frozen background 역할

### 3단계. incremental solver + hysteresis

이 단계는 “부드러움”을 “안정감”으로 바꾸는 단계다.

- target이 자주 흔들리지 않게 만들고
- 영향받는 이웃만 반응하게 만든다

### 4단계. commit path와 session write 정리

이 단계에서 상위 상태 churn을 정리한다.

- drag update 로컬화
- drop commit 1회화
- undo/redo와의 결합 지점 정리

### 5단계. polish + 기준 검증

마지막 단계에서 아래를 다듬는다.

- auto-scroll 감각
- temp strip 진입/이탈
- group 이동 질감
- zoom 상태에서의 motion 품질
- split pane과의 안정성

## 8. 수용 기준

이번 재설계는 아래 기준을 만족해야 한다.

- 드래그 중 주 카드가 포인터를 즉시 따라와야 한다.
- 주변 카드가 `따라오듯` 움직이지 않고 `같은 표면에서 밀리듯` 움직여야 한다.
- 경계 근처에서 target이 프레임마다 출렁이지 않아야 한다.
- 카드 수가 늘어나도 드래그 감각이 급격히 무너지지 않아야 한다.
- drop 직후 commit 애니메이션만 남고, drag 중에는 지연감이 거의 없어야 한다.

권장 수치 기준:

- drag hot path 평균 main-thread 비용: 4ms 이하 목표
- retarget 빈도: 현재 대비 의미 있게 감소
- 체감 frame pacing: 60Hz 디스플레이 기준 끊김이 명확히 줄어야 함

## 9. 비목표

이번 작업에서 하지 않을 것:

- 새 카드 데이터 모델 도입
- 보드 기능 의미 변경
- 보드 UX를 완전히 다른 앱처럼 바꾸는 것
- undo/redo 전체 통합을 이번 작업에 같이 묶는 것
- temp/group 정책 변경

즉, 이 작업은 `보드 모션 엔진`에만 집중한다.

## 10. 리스크

### 10-1. 반쯤 고친 상태에서 더 복잡해질 위험

`animator().frame`만 조금 손보고 나머지를 그대로 두면
코드는 더 복잡해지고 체감은 애매하게 남을 수 있다.

그래서 이번 작업은 `핫패스 교체` 단위로 묶어야 한다.

### 10-2. 정상 상태와 드래그 상태의 이중 구조가 꼬일 위험

motion scene을 도입하면 상태가 둘이 된다.

- 정상 surface
- drag preview surface

이 둘의 책임이 섞이면 버그가 늘어난다.

따라서 원칙은 분명해야 한다.

- drag 중: motion scene authoritative
- drop 후: normal surface authoritative

### 10-3. temp/group 예외 케이스가 다시 full layout을 부를 위험

temp strip, detached parking, group 이동은 예외가 많다.
이 예외를 핑계로 full layout 경로를 다시 부르면 성능 이득이 사라진다.

따라서 예외도 preview state 안에서 처리해야 한다.

## 11. 권장 구현 단위

이번 작업은 아래 세 묶음으로 나누는 것이 가장 안전하다.

### Batch 1. Hot Path 분리

- instrumentation 추가
- drag hot path에서 layout animation 제거
- motion scene 뼈대 도입

### Batch 2. Cache + Incremental Solver

- static card/lane cache
- affected range만 이동
- placeholder/local scene 정리

### Batch 3. Hysteresis + Commit Path

- retarget state machine 정리
- drop commit 정리
- profiling 기반 polish

## 12. 결론

이 작업은 `기존 보드가 조금 느리다` 수준의 문제가 아니다.
현재 보드와 레퍼런스의 차이는 `플랫폼`보다 `모션 엔진 구조` 차이에 가깝다.

따라서 맞는 방향은 다음이다.

- 전체 보드를 다시 만들지 않는다.
- 데이터/세션/기능 API는 유지한다.
- 대신 `보드 드래그/재배치 핫패스`는 rewrite급으로 바꾼다.
- drag 중엔 compositor 중심 position/transform 엔진으로 간다.
- drop 시점에만 모델과 session을 commit한다.
- 그리고 Instruments로 실제 병목을 측정하면서 줄인다.

즉, 이번 플랜의 핵심은
`보드 전체 갈아엎기`가 아니라
`보드 모션 엔진만 정확히 갈아엎기`다.
