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

### 8. Lazy row 안의 live AppKit editor churn

최신 로그로 확인된 가장 중요한 새 사실은, `ScrollView + LazyVStack` 안의 row에 live `NSViewRepresentable/NSTextView`를 직접 심는 방식이 edit entry 단계부터 subtree churn을 만든다는 점이다.

- `editingCardID`는 유지되는데도 `inline-editor-disappear`가 edit end 없이 단독으로 발생했다.
- 같은 `NSTextView` 인스턴스가 서로 다른 카드에 재사용되었다.
- `become-first-responder` 직후 `window/superview/scroll` attachment가 다시 흔들렸다.
- 이 churn은 key handling, caret restore, finish editing 보정보다 더 상위 원인이다.

결론:

- `row 내부 live AppKit editor`는 더 이상 안전한 중간 단계가 아니다.
- row는 geometry owner로 남기되, live editor ownership은 `lazy row subtree 밖의 안정된 host`로 옮겨야 한다.

## 수정된 설계 원칙

### 원칙 1. Row가 끝까지 geometry owner다

- 카드 높이
- 카드 frame
- 포커스 정렬 기준
- column layout의 editing override

위 네 가지는 모두 카드 row 기준이어야 한다.

### 원칙 1A. Live editor host는 lazy row subtree 밖에 둔다

- live editor는 `ScrollView + LazyVStack`가 virtualize하는 row subtree 안에 직접 들어가면 안 된다.
- host는 메인 컬럼 scroll hierarchy 안에는 있어야 하지만, lazy row 재활용의 대상이면 안 된다.
- row는 geometry와 slot frame만 제공하고, live editor instance ownership은 안정된 host가 가진다.

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

## Phase 2. Editor slot 분리

목적:

- row를 geometry owner로 유지한 채, live editor가 올라갈 `editor slot`과 shell/chrome을 분리한다.

범위:

- active row의 editor slot rect 추출
- row shell과 live editor slot 경계 고정
- slot rect를 메인 컬럼이 안정적으로 관찰 가능하게 연결

제약:

- 편집 엔진은 아직 baseline 유지
- live AppKit editor는 아직 row에도 host에도 올리지 않음

완료 기준:

- row subtree churn 없이 active row의 editor slot frame을 안정적으로 얻는다
- 포커스 정렬/스크롤 회귀가 없다

## Phase 2.5A. Stable host scaffold

목적:

- lazy row 밖, 같은 메인 컬럼 scroll hierarchy 안에 `stable editor host`를 만든다.

범위:

- 메인 컬럼 전용 host container
- active row slot rect를 따라가는 position/width 연결
- host lifecycle과 row lifecycle 분리

금지:

- host가 geometry owner가 되는 구조
- detached root overlay로 바로 가는 구조

완료 기준:

- active row 변경과 스크롤 중에도 host attachment churn이 없다
- host는 존재하지만 아직 편집 엔진 회귀를 만들지 않는다

## Phase 2.5B. Main editor session 명시화

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

## Phase 3. AppKit engine swap on stable host

목적:

- baseline `TextEditor`를 버리고, 메인 작업창 편집을 stable host 위의 AppKit editor로 교체한다.

범위:

- Enter/재클릭 편집 진입
- mounted editor identity
- first responder 획득 성공 기준
- 메인 작업창 전용 arrow/caret routing

금지:

- same `NSTextView`가 카드 사이를 암묵적으로 재사용하는 구조
- edit entry 중 host attach/detach churn

완료 기준:

- edit entry 직후 subtree/attachment churn이 없다
- caret이 즉시 보인다
- 포커스 정렬 회귀가 없다

## Phase 3.5. Height truth 단일화

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

## Phase 4. Scroll authority 정리

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

## Phase 4.5. Surface 경계 고정

목적:

- 메인 host가 timeline/index board를 침범하지 않게 한다.

범위:

- main workspace host kind
- timeline inline path
- index board path

완료 기준:

- 메인 host는 메인 작업창에서만 활성
- 타임라인/인덱스 보드는 기존 경로 유지

## Phase 5. Shell-editor typography 정렬

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

## Phase 6. Single reusable editor ownership

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

## Phase 7. Detached overlay 검토

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

### Gate A. Phase 2.5A 종료 후

아래를 통과하지 못하면 다음 단계로 가지 않는다.

- active row slot frame이 scroll 중에도 안정적으로 유지됨
- host attach/detach churn 없음
- 포커스 정렬 회귀 없음

### Gate B. Phase 3 종료 후

- Enter/재클릭 직후 caret 표시
- edit entry 중 subtree churn 없음
- 화살표 입력 시 main workspace navigation 계약 유지

### Gate C. Phase 4 종료 후

- 편집 진입 시 스크롤 덜컥 내려감 없음
- 편집 종료 후 active card 중앙 정렬 정상
- 하단 줄 소실/겹침/빈 공간 스크롤 없음

## 현재 판단

지금 기준으로 다음 단계는 `Phase 2`의 재시도가 아니라, 기존 `Phase 2` 가정을 폐기하고 `Phase 2 = slot 분리`, `Phase 2.5A = stable host scaffold`로 재시작하는 것이다.

이유:

- `row 내부 live AppKit editor`는 incremental step이 아니라, `LazyVStack`와 충돌하는 구조였다.
- 그래서 기존 `Phase 2`는 작은 lake가 아니라 잘못 잡은 intermediate state였다.
- 이제는 `geometry owner는 row`, `live editor ownership은 stable host`라는 경계를 먼저 세운 뒤에만 AppKit engine swap을 다시 시도해야 한다.

## 한 줄 결론

이번 계획의 핵심 수정은 `single editor` 목표는 유지하되, `row 내부 live AppKit editor` 단계를 버리고 `row-owned geometry + stable host ownership + single height truth + explicit editor session` 순서로 다시 밟는 것이다.
