# Main Workspace Card Three-Layer Plan

작성일: 2026-03-26

## 목표

메인 작업창 카드를 아래 구조로 옮긴다.

- 모든 카드는 기본적으로 immutable shell
- 포커스 이동은 선택 상태와 스크롤만 바꿈
- 편집 중인 카드만 live editor를 가짐
- 가능하면 live editor는 하나만 유지

다만 지금까지의 회귀를 기준으로, `column-root detached overlay`를 바로 목표로 두지 않는다.
우선은 `row가 geometry owner인 상태`를 유지하면서 `single editor ownership`에 접근한다.

## 지금까지 확인된 문제

### 1. Geometry owner 분리

가장 치명적인 회귀는 `편집기`와 `포커스 정렬 기준 카드`가 다른 객체가 된 순간 발생했다.

- 메인 컬럼 정렬은 카드 row frame을 기준으로 동작한다.
- external editor host를 카드 바깥으로 빼면, 편집 lifecycle과 정렬 lifecycle이 서로 다른 geometry를 본다.
- 그 결과 편집 진입 순간 정렬이 깨지거나, 이후 active card 이동이 더 이상 중앙 정렬을 복구하지 못했다.

결론:

- 편집기가 하나여도 `row가 geometry owner`인 계약은 깨면 안 된다.

### 2. Height truth가 둘 이상 존재

반복해서 나온 텍스트 소실/겹침/빈 공간 스크롤의 공통 원인은 `높이의 진실`이 여러 개였다는 점이다.

- editor 실제 AppKit layout 높이
- row placeholder 높이
- overlay/shell frame 높이
- column layout snapshot이 믿는 높이

이 값들이 동시에 존재하면 다음이 재발한다.

- Enter로 줄을 늘릴 때 하단 줄이 편집 중 사라짐
- 텍스트가 카드 아래로 흘러내려 다음 카드 위에 겹침
- 빈 공간까지 스크롤되거나 스크롤이 다시 아래로 끌려감
- 편집 종료 후에만 숨겨진 줄이 나타남

결론:

- mounted editor가 존재하는 동안에는 `observed body height` 하나만 진실이어야 한다.

### 3. 관찰되지 않는 runtime state

한 시점에는 live height를 계산하고도 SwiftUI가 그 값을 보지 못했다.

- runtime 필드만 바뀌고 view invalidation은 발생하지 않았다.
- 로그상 `report-live-body-height`는 계속 변하지만 row/overlay는 계속 stale 값을 봤다.

결론:

- session state는 SwiftUI가 실제로 관찰하는 경로로 흘러야 한다.
- plain runtime 필드에만 저장된 값은 layout truth가 될 수 없다.

### 4. Scroll authority가 여러 군데 흩어짐

편집 진입/종료 시 스크롤이 무너진 원인은 여러 scroll actor가 동시에 같은 컬럼을 움직였기 때문이다.

- active card 정렬
- caret ensure
- bottom reveal
- focus verification
- viewport restore

이들이 edit entry/exit와 겹치면 포커스 정렬이 깨졌다.

결론:

- 편집 전환 중에는 scroll authority를 하나로 줄여야 한다.
- mounted editor가 준비되기 전에는 caret 기반 reveal을 시작하면 안 된다.

### 5. First responder / caret ownership 불안정

Enter로 편집에 들어가도 caret이 안 보이거나, 방향키가 편집이 아니라 카드 이동으로 처리되는 문제가 있었다.

결론:

- `editingCardID`와 `실제 first responder editor`는 별도 상태로 봐야 한다.
- 편집 시작 성공 기준은 `editingCardID`가 아니라 `mounted editor + responder 획득`이다.

### 6. Shell과 editor의 layout engine 차이

비편집 shell은 `Text`, 편집은 `TextEditor` 또는 `NSTextView`를 쓰면 줄바꿈/행간/패딩이 달라진다.

이 차이는 다음 회귀를 만든다.

- shell과 editor가 동시에 보일 때 잔상
- 편집 전환 시 줄바꿈 튐
- shell 높이와 editor 높이 차이

결론:

- 최소한 `live height`는 editor layout engine만 기준으로 삼아야 한다.
- shell-editor typography 통합은 later phase로 두되, live height truth와 경쟁하게 두면 안 된다.

### 7. Surface 경계가 불명확할 때 메인 host가 다른 화면을 침범

메인 작업창용 host가 타임라인이나 linked cards 경로를 침범하면, 편집 경계가 꼬인다.

결론:

- main workspace, timeline, index board는 host ownership을 분리해야 한다.
- 메인 host는 메인 작업창에서만 동작해야 한다.

## 수정된 설계 원칙

### 원칙 1. Row가 끝까지 geometry owner다

- 카드 높이
- 카드 frame
- 포커스 정렬 기준
- column layout의 editing override

위 네 가지는 모두 카드 row 기준이어야 한다.

### 원칙 2. Mounted editor가 있을 때 높이 truth는 하나다

- source: mounted AppKit editor의 observed body height
- consumer:
  - row height
  - layout snapshot
  - visible editor frame

mounted 이후에는 다른 fallback이 경쟁하면 안 된다.

### 원칙 3. Edit session은 명시 상태다

세션은 최소한 아래를 가져야 한다.

- `requestedCardID`
- `mountedCardID`
- `textView identity`
- `caret seed`
- `observed body height`
- `isFirstResponderReady`

### 원칙 4. Scroll authority를 분리한다

- ordinary focus scroll
- edit entry
- caret reveal

이 세 경로는 순차적으로만 실행되게 한다.

### 원칙 5. Detached overlay는 마지막 옵션이다

지금까지의 회귀를 기준으로, detached overlay는 `최종 목표 후보`이지 `다음 단계`가 아니다.

우선순위는:

1. row-owned single editor
2. mounted session 안정화
3. single height truth
4. scroll authority 정리
5. 필요하면 detached overlay 검토

## 수정된 단계 계획

## Phase 0. Baseline + 계측

목적:

- 회귀를 추측으로 고치지 않기 위한 최소 계측 확보

범위:

- active/editing/mounted editor 상태
- observed editor body height
- editing card row height
- focus intent와 실제 native scroll 실행

완료 기준:

- 같은 재현에 대해 entry, typing, exit 시점 로그를 시간순으로 대조할 수 있다.

## Phase 1. Card 본문과 chrome 분리

목적:

- card body와 선택/관계 강조를 분리해, 이후 편집 경로를 건드려도 chrome churn을 줄인다.

범위:

- `content shell`
- `chrome overlay`

제약:

- 편집기는 아직 카드 row 내부 inline 경로 유지
- geometry, scroll, editor ownership은 건드리지 않음

완료 기준:

- 사용자 동작 변화 없음
- 본문과 chrome이 별도 컴포넌트로 나뉨

## Phase 2. Row-owned AppKit editor 전환

목적:

- SwiftUI `TextEditor`를 바로 버리고, 메인 카드 편집기를 `row 내부 AppKit editor`로 바꾼다.

이 단계가 중요한 이유:

- geometry owner를 유지한 채 editing engine을 AppKit으로 통일할 수 있다.
- detached overlay 없이도 caret, measured height, responder를 더 정확히 다룰 수 있다.

제약:

- editor는 여전히 row 안에 있어야 한다.
- column root overlay로 빼지 않는다.

완료 기준:

- Enter/재클릭 편집 진입 정상
- caret이 즉시 보임
- 포커스 정렬 회귀 없음

## Phase 2.5A. Main editor session 명시화

목적:

- `editingCardID`와 실제 mounted editor를 분리한다.

범위:

- `requestedCardID`
- `mountedCardID`
- `textView identity`
- `caret seed`
- `isFirstResponderReady`

완료 기준:

- main workspace 편집 관련 코드가 `firstResponder + string 비교` 없이 mounted session을 우선 사용한다.

## Phase 2.5B. Height truth 단일화

목적:

- mounted editor가 있는 동안 높이 source를 하나로 만든다.

범위:

- row height
- layout snapshot editing override
- visible editor frame

금지:

- mounted 이후 `card.content` 재측정과 `editor observed height`가 경쟁하는 구조

완료 기준:

- 하단 줄 소실, 아래 카드 위 겹침, 편집 종료 후 숨은 줄 등장 현상이 없어야 한다.

## Phase 2.5C. Scroll authority 정리

목적:

- edit entry/exit에서 정렬이 깨지지 않게 한다.

범위:

- ordinary focus scroll
- edit entry reveal
- caret ensure
- viewport restore

규칙:

- mounted editor 준비 전 caret reveal 금지
- edit entry 중 ordinary verification 금지
- edit exit 후 stale transition state 즉시 정리

완료 기준:

- 편집 진입 순간 덜컥 내려가지 않음
- 편집 종료 후 포커스 이동이 다시 정상 중앙 정렬

## Phase 2.5D. Surface 경계 고정

목적:

- 메인 host가 timeline/index board를 침범하지 않게 한다.

범위:

- main workspace host kind
- timeline inline path
- index board path

완료 기준:

- 메인 host는 메인 작업창에서만 활성
- 타임라인/인덱스 보드는 기존 경로 유지

## Phase 2.5E. Shell-editor typography 정렬

목적:

- 편집 전환 시 shell과 editor의 시각 차이를 줄인다.

범위:

- font
- line spacing
- padding
- measure width

주의:

- 이 단계는 live height truth를 다시 둘로 만들면 안 된다.
- shell 통합은 visual parity 목적이지 height source 변경 목적이 아니다.

완료 기준:

- 편집 진입/종료 시 줄바꿈 차이와 잔상이 줄어든다.

## Phase 3. Single reusable editor ownership

목적:

- live editor를 하나로 줄이되, geometry owner는 여전히 row로 유지한다.

권장 방식:

- 같은 `NSTextView` 인스턴스를 카드 사이에서 재사용
- 하지만 mount 위치는 항상 active row의 editor slot
- 즉 `single editor`, `row-owned geometry`

이 단계에서 얻는 것:

- invalidation fanout 감소
- edit engine 단일화
- detached overlay보다 낮은 리스크

완료 기준:

- live editor 인스턴스는 하나
- 포커스 정렬과 카드 높이 회귀 없음

## Phase 4. Detached overlay 검토

전제:

- Phase 3가 성능 목표를 만족하면 이 단계는 생략 가능

진입 조건:

- geometry owner를 row에 남기는 우회가 없는지 명확히 설명 가능
- height truth가 계속 하나로 유지됨
- scroll authority 충돌이 재현되지 않음

원칙:

- overlay는 position/width만 가져간다
- height truth와 scroll authority를 가져가면 안 된다

## 중간 게이트

### Gate A. Phase 2 종료 후

아래를 통과하지 못하면 다음 단계로 가지 않는다.

- Enter 편집 진입 즉시 caret 표시
- 편집 중 포커스 정렬 회귀 없음
- 타이핑 중 하단 줄 소실 없음

### Gate B. Phase 2.5C 종료 후

- 편집 진입 시 스크롤 덜컥 내려감 없음
- 편집 종료 후 active card 중앙 정렬 정상
- 화살표 이동 연속 입력에서도 정렬 유지

### Gate C. Phase 3 종료 후

- live editor는 하나
- 메인 작업창 카드 수가 많아도 포커스 이동 체감 개선
- 이전 회귀 재발 없음

## 현재 판단

지금 기준으로 바로 가야 하는 다음 단계는 `Phase 1`이 아니라, 먼저 `Phase 0 계측 정리 + Phase 1 범위 재고정`이다.

이유:

- 이미 한 번 `detached overlay`를 너무 빨리 시도해서 회귀를 크게 만들었다.
- 이후의 부분 원복 과정에서 코드가 혼합 상태가 되기 쉬웠다.
- 따라서 이번에는 단계 경계를 엄격하게 지키고, 한 단계가 안정화되기 전에는 다음 단계 요소를 절대 섞지 않는다.

## 한 줄 결론

이번 계획의 핵심 수정은 `single editor` 목표는 유지하되, `detached overlay`를 다음 단계에서 제외하고 `row-owned geometry + single height truth + explicit editor session`을 먼저 완성하는 것이다.
