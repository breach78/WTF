# Main Navigation Performance Plan

작성일: 2026-03-17

## 목표

현재 메인 작업창의 모양, 카드 정렬 방식, 부모 카드 자동 정렬, 포커스 UX, 포커스 모드 분리 구조를 유지한 채, 화살표 키 기반 포커스 이동의 버벅임을 구조적으로 줄인다.

이번 계획의 전제는 다음과 같다.

- 카드의 시각적 구성과 자동 정렬 감각은 유지
- 최근에 정리한 native scroll animation은 유지
- 기능 삭제로 성능을 얻지 않음
- 데이터 포맷과 undo/redo 의미는 유지

## 현재 판단

현재 버벅임의 주원인은 그래픽 렌더링보다 `포커스 이동 1회에 묶여 있는 계산/레이아웃/스크롤 파이프라인`이다.

포커스가 한 칸 이동할 때 현재 구조에서는 대략 아래 비용이 함께 발생한다.

1. 활성 카드 변경
2. 조상/형제/자손 관계 집합 재계산
3. 표시 열 데이터 재구성
4. 카드 높이 계산 및 레이아웃 추론
5. 관측 프레임 갱신
6. 부모 열 자동 정렬 판단 및 스크롤 애니메이션
7. 그 결과로 큰 범위의 SwiftUI invalidation

즉, 문제는 “카드가 텍스트라서 무겁다”가 아니라 “포커스 이동이 렌더/측정/스크롤을 한 트랜잭션으로 몰아친다”에 가깝다.

## 현재 병목이 걸린 코드 지점

### 1. 포커스 관계 상태 계산

- `WriterCardManagement.swift`
- `synchronizeActiveRelationState(for:)`

이 함수는 활성 카드가 바뀔 때마다 조상, 형제, 자손 집합을 다시 만든다. 현재는 결과 캐시가 있더라도 계산의 소유권이 UI 쪽에 가까워서, 포커스 이동과 뷰 invalidation이 강하게 결합돼 있다.

### 2. 표시 열 데이터 재구성

- `WriterViews.swift`
- `displayedLevelsData()`
- `WriterCardManagement.swift`
- `displayedMainLevelsData(from:)`

현재 열 데이터는 포커스 상태, split 상태, active category 등에 영향을 받는다. 이 계층이 `ScenarioWriterView`의 큰 상태 허브 안에 묶여 있어서, 작은 포커스 이동에도 상위 뷰가 넓게 다시 평가될 여지가 크다.

### 3. 카드 높이 계산과 열 레이아웃 추론

- `WriterCardManagement.swift`
- `resolvedMainCardHeight(for:)`
- `resolvedMainColumnTargetLayout(...)`

자동 정렬과 visible 추론은 카드 높이 계산에 의존한다. 텍스트 높이 측정 캐시는 이미 들어가 있지만, 현재는 포커스 이동 경로에서 “열 전체 레이아웃”이 별도 캐시 없이 반복 추론된다.

### 4. 관측 프레임과 자동 정렬

- `WriterCardManagement.swift`
- `scrollToFocus(...)`
- `performMainColumnNativeFocusScroll(...)`
- `WriterSharedTypes.swift`
- `MainColumnScrollRegistry`

최근 개선으로 애니메이션 품질은 좋아졌지만, 여전히 포커스 이동이 곧 스크롤 판단/실행으로 바로 이어진다. 즉, navigation state와 scroll state가 아직 느슨하게 분리되지 않았다.

## 근본 해결 방향

핵심 방향은 하나다.

`포커스 이동을 "데이터/레이아웃 갱신 사건"이 아니라 "런타임 네비게이션 이벤트"로 분리한다.`

이를 위해 다음 세 축으로 나눈다.

1. 포커스 상태를 별도 경량 런타임 모델로 분리
2. 카드 높이와 열 레이아웃을 캐시된 구조체로 분리
3. 자동 정렬을 그 캐시만 읽는 scroll coordinator로 분리

이 셋이 되면, 포커스 한 번 이동할 때 모든 카드 뷰를 다시 해석하지 않고도 필요한 정렬과 강조만 갱신할 수 있다.

## 제안하는 단계별 실행 계획

## Phase 1. Navigation Runtime 분리

### 목적

포커스 이동 시 가장 먼저 바뀌는 정보를 `activeCardID` 외의 대형 SwiftUI 상태와 분리한다.

### 구현 방향

- `WriterInteractionRuntime`에 navigation 전용 상태 묶음을 만든다.
- 포함 항목:
  - `activeCardID`
  - `ancestorIDs`
  - `siblingIDs`
  - `descendantIDs`
  - 현재 포커스 경로의 parent chain
  - 포커스 이동 source metadata
- `synchronizeActiveRelationState(for:)`는 UI 보조 함수가 아니라 navigation runtime 갱신 함수로 옮긴다.
- 가능한 한 `scenario.cardsVersion`이 바뀌지 않은 동안에는 precomputed parent/child index를 재사용한다.

### 기대 효과

- 포커스 이동의 첫 단계에서 SwiftUI 상위 상태 churn 감소
- 관계 계산과 화면 갱신의 결합 약화

### 리스크

- undo/redo, split pane, focus mode가 모두 active card state를 쓰므로 동기화 소유권을 잘 정해야 한다.

## Phase 2. Main Column Layout Cache 도입

### 목적

포커스 이동 때마다 카드 높이와 열 내 y-position을 다시 추론하지 않도록 한다.

### 구현 방향

- 열 단위 레이아웃 캐시 구조를 도입한다.
- key 예시:
  - `viewportKey`
  - `cardsVersion`
  - `fontSize`
  - `lineSpacing`
  - `columnWidth`
  - `zoomScale`
- value 예시:
  - 카드별 `height`
  - 카드별 `minY/maxY`
  - 마지막 카드 bottom
  - group separator 위치
- 카드 내용이 실제로 바뀐 카드만 부분 무효화한다.
- 포커스 이동만 일어났을 때는 레이아웃 캐시를 재계산하지 않는다.

### 기대 효과

- `resolvedMainCardHeight(for:)`와 `resolvedMainColumnTargetLayout(...)` 호출량 감소
- 부모 열 자동 정렬 계산의 fast path 확보

### 리스크

- 편집 중 live height와 cached height가 다를 수 있으므로, 편집 카드에 한해 live override 경로는 유지해야 한다.

## Phase 3. Scroll Coordinator 완전 분리

### 목적

자동 정렬이 SwiftUI body 재평가 타이밍에 덜 의존하게 만든다.

### 구현 방향

- `performMainColumnNativeFocusScroll(...)`가 뷰 계층을 다시 해석하지 않고, navigation runtime + layout cache + observed scroll view만 읽도록 단순화한다.
- 스크롤 판단을 다음 두 경로로 분리한다.
  - fast path: cached frame/offset만으로 바로 target 계산
  - fallback path: 관측 프레임이 아직 없을 때만 기존 추론 경로 사용
- 연속 화살표 이동 중에는 이전 animation completion을 기다리지 않고 target만 최신 값으로 갱신할 수 있게 만든다.
- 동일 target에 대한 dead-zone 정책을 명시적으로 분리한다.

### 기대 효과

- 포커스 이동 도중 “상태 재계산 -> 스크롤 -> 다시 상태 재계산” 루프 약화
- 이번에 얻은 부드러운 애니메이션 품질 유지

### 리스크

- top reveal, long card 예외, 부모 정렬 유지 규칙을 coordinator 내부에서 정확히 재현해야 한다.

## Phase 4. Main Canvas Invalidation 범위 축소

### 목적

포커스 이동이 상위 뷰 전체를 흔들지 않게 한다.

### 구현 방향

- 열 단위 view model 또는 render snapshot을 도입한다.
- `displayedLevelsData()` 결과를 포커스 이동과 분리 가능한 부분에서 memoize한다.
- `ScenarioWriterView`의 대형 state 허브에서 포커스와 무관한 state를 하위 객체로 내린다.
- 카드 row는 가능한 한 `active/ancestor/descendant/selected/editing` 변화만 반영하도록 좁힌다.

### 기대 효과

- 카드가 많아질수록 체감 차이가 커짐
- split pane / history / AI 상태가 메인 네비게이션 렌더에 덜 전파됨

### 리스크

- 이 단계는 구조 변경 폭이 커서, 앞 단계가 안정화된 뒤 들어가는 것이 안전하다.

## Phase 5. 검증용 경량 측정 도구 교체

### 목적

지금처럼 파일 로그를 남기지 않고도 병목을 계측할 수 있게 한다.

### 구현 방향

- `bounceDebugLog` 같은 파일 기록형 계측 대신, 필요 시 켜는 lightweight signpost 또는 in-memory counters로 전환
- 측정 대상:
  - active card change 당 relation 계산 시간
  - layout cache miss율
  - scroll target recalculation 횟수
  - column body recompute 추정 횟수

### 기대 효과

- 성능 리팩터링 과정에서 다시 “계측이 성능에 끼는” 문제를 줄임

## 우선순위

실행 순서는 아래가 맞다.

1. Phase 1
2. Phase 2
3. Phase 3
4. Phase 5
5. Phase 4

이 순서가 좋은 이유는, 먼저 포커스 이동의 계산 경로를 가볍게 만들고, 그 다음에 렌더 invalidation을 줄이는 쪽이 리스크가 낮기 때문이다.

## 완료 기준

이번 계획이 성공했다고 보려면 다음 조건을 만족해야 한다.

- 빠른 좌우/상하 화살표 이동 시 체감 끊김이 현저히 줄어듦
- 부모 카드 자동 정렬 감각은 유지
- 긴 카드 top reveal 규칙 유지
- 포커스 모드와 메인 작업창의 의미 차이는 유지
- split pane / history preview / undo redo 회귀 없음

## 권장 1차 작업 범위

지금 바로 들어간다면 1차 범위는 아래로 제한하는 것이 안전하다.

- Navigation runtime 분리
- Main column layout cache 도입
- scroll coordinator fast path 연결

즉, 이번 라운드의 핵심 산출물은 “포커스 이동 1회가 전체 열 레이아웃 추론을 다시 부르지 않게 만드는 것”이다.

이 세 단계만 제대로 들어가도, 현재 UX를 유지한 채 체감 성능이 가장 크게 개선될 가능성이 높다.
