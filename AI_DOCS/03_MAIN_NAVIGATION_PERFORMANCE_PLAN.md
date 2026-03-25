# Main Navigation Performance Plan

작성일: 2026-03-25

## 작업 범위

메인 작업창(main workspace)의 카드 간 화살표 이동, 편집 중 boundary 이동, 포커스 카드 변경에 따른 부모/자식 체인 정렬, 관련 스크롤 hot path만 성능 개선 대상으로 다룬다.

## 절대 고정 조건

- 포커스 카드가 바뀔 때 부모/자식이 체인의 끝까지 재정렬되는 현재 동작은 유지한다.
- Focus View의 기능은 절대로 바꾸지 않는다.
- Index View의 기능은 절대로 바꾸지 않는다.
- 메인 작업창의 카드 의미, 정렬 규칙, undo/redo 의미, split/history/focus mode 의미는 유지한다.
- 성능 개선은 기능 삭제가 아니라 hot path 경량화로만 얻는다.
- 각 phase는 독립적으로 실행 가능해야 하고, phase 종료 시점마다 사용자가 앱을 직접 평가한 뒤 멈출 수 있어야 한다.

## 왜 이 순서로 가는가

현재 병목의 본질은 "포커스 이동 1회가 너무 많은 계산과 상태 전파를 한 번에 일으킨다"는 점이다.

즉, 성능 개선은 아래 순서가 가장 안전하다.

1. 입력 핫패스를 가볍게 만든다.
2. 포커스 변경에 따른 projection/layout 재사용 범위를 늘린다.
3. 렌더 invalidation 범위를 줄인다.
4. 그래도 부족할 때만 메인 캔버스 엔진 교체를 검토한다.

이 순서를 지키면 핵심 UX를 보존한 채 체감 성능을 단계적으로 끌어올릴 수 있다.

## 공통 운영 규칙

- 각 phase는 "빌드 가능 + 실행 가능 + 기존 기능 유지" 상태로 끝낸다.
- 각 phase가 끝나면 기존 앱을 종료하고 수정된 앱을 다시 실행한 뒤 사용자 평가를 받는다.
- 사용자가 만족하면 그 phase에서 중단한다.
- 사용자가 부족하다고 판단하면 다음 phase로 넘어간다.
- 다음 phase는 이전 phase의 결과를 전제로 하지만, Focus View와 Index View 기능 변화는 여전히 금지다.

## 공통 검증 체크리스트

모든 phase 종료 뒤 아래를 같은 순서로 확인한다.

1. 메인 작업창에서 `up/down/left/right` 반복 입력이 더 가벼워졌는지 확인
2. 포커스 카드 변경 시 부모/자식 체인 정렬 감각이 그대로인지 확인
3. 편집 중 경계 이동(`up/down/left/right` boundary)이 기존과 같은지 확인
4. Focus View 진입/이탈과 기본 조작이 기존과 같은지 확인
5. Index View 진입/이탈과 기본 조작이 기존과 같은지 확인

위 다섯 항목 중 기능 변화가 하나라도 보이면 그 phase는 실패로 간주한다.

## Phase 0. 기준선 고정

### 목적

이후 phase의 체감 개선 여부를 비교할 수 있도록 메인 작업창 네비게이션의 현재 기준선을 고정한다.

### 변경 범위

- 계측, 로그, signpost, lightweight counter
- 회귀 방지용 문서화

### 금지

- 실제 포커스 이동 규칙 변경
- 레이아웃 규칙 변경
- Focus View / Index View 동작 변경

### 실행 내용

- 메인 작업창 네비게이션 핫패스의 측정 지점을 정리한다.
- 최소한 아래 항목은 비교 가능하게 만든다.
  - 화살표 1회 처리 시간
  - key repeat 동안 처리 빈도
  - 포커스 변경 1회당 projection/layout 재계산 횟수
  - 포커스 변경 1회당 scroll target 재계산 횟수
- 측정은 파일 I/O가 아니라 필요 시 켜는 lightweight 방식으로 둔다.

### 완료 기준

- 이후 phase에서 "무엇이 빨라졌는지"를 같은 기준으로 비교할 수 있다.
- 계측 자체가 체감 성능을 해치지 않는다.

### 사용자 평가 포인트

- 아직 체감 개선이 없어도 괜찮다.
- 기준선과 비교 방식이 명확하면 통과다.

### stop / go

- 기준선만 확보한 뒤 바로 Phase 1로 진행한다.

## Phase 1. 입력 핫패스 경량화

### 목적

레이아웃 의미는 그대로 두고, 화살표 이동 목표 계산과 반복 입력 처리 비용부터 줄인다.

### 변경 범위

- `NavigationGraph` 또는 동등한 인접 이동 캐시
- repeat 입력 전용 루프 또는 coalescing
- `visualFocusedCardID`와 `committedActiveCardID` 분리
  - 단, 레이아웃은 `visualFocusedCardID`를 즉시 따라가야 한다.
  - 지연 가능한 것은 히스토리/부가 패널/부수효과뿐이다.

### 금지

- 포커스 카드 변경 타이밍 변경
- 부모/자식 체인 재정렬 지연
- Focus View / Index View 입력 규칙 변경

### 실행 내용

- `up/down/left/right` 목표 카드를 이동 시점마다 다시 찾지 않도록 인접 이동 캐시를 둔다.
- OS key repeat 이벤트를 그대로 다 처리하지 않고, 최신 방향만 반영하는 repeat loop 또는 coalescing 경로를 둔다.
- 반복 입력 중 지연 가능한 부수효과를 메인 포커스 변경과 분리한다.

### 기대 효과

- 반복 입력 중 target 계산 비용 감소
- key repeat burst 시 이벤트 폭주 감소
- 메인 작업창에서 "방향키를 길게 눌렀을 때" 첫 체감 개선 발생

### 완료 기준

- 동일 데이터에서 반복 화살표 이동이 이전보다 가볍다.
- 포커스 카드 변경 순간의 체인 재정렬 감각은 동일하다.
- Focus View / Index View 기능 차이는 없다.

### 사용자 평가 포인트

- 카드 수가 많은 구간에서 `up/down` 길게 누르기
- 깊은 체인에서 `left/right` 반복 이동
- 편집 상태 진입 전후 plain arrow 감각 비교

### stop / go

- 이 단계에서 충분히 만족하면 중단한다.
- 아직 버벅임이 남으면 Phase 2로 진행한다.

## Phase 2. Projection / Layout 재사용

### 목적

포커스 카드가 매번 바뀌더라도, 부모/자식 체인 재정렬에 필요한 projection과 column layout을 가능한 한 재사용한다.

### 변경 범위

- 메인 작업창 전용 projection cache
- column layout cache
- 편집 카드와 비편집 카드의 height/layout 처리 분리
- scroll 판단용 fast path

### 금지

- 카드 정렬 규칙 변경
- 부모 열 자동 정렬 의미 변경
- Focus View / Index View projection 공유 경로에 기능 회귀 유발

### 실행 내용

- `cardsVersion`과 viewport 조건이 같으면 projection의 큰 부분을 재사용한다.
- column 단위로 카드 frame, y-position, visible range를 캐시한다.
- 편집 중인 카드만 live override로 처리하고, 나머지는 cache를 우선 사용한다.
- 스크롤 판단은 먼저 cache만 읽고, 정보가 없을 때만 fallback 경로로 내려간다.

### 기대 효과

- 포커스 이동 1회당 projection/layout 재계산 횟수 감소
- 부모/자식 체인 재정렬을 유지하면서도 계산 경로가 짧아짐
- 긴 카드와 깊은 체인에서 차이가 커짐

### 완료 기준

- key repeat 시 projection/layout recompute가 눈에 띄게 줄어든다.
- 부모/자식 체인 정렬 모양과 타이밍은 기존과 같다.
- 편집 카드의 live height 동작이 유지된다.

### 사용자 평가 포인트

- 긴 카드가 포함된 열에서 `up/down` 반복 이동
- 부모 카드 자동 정렬이 필요한 깊은 체인 탐색
- 스크롤이 수반되는 빠른 좌우 이동

### stop / go

- 이 단계에서 만족하면 중단한다.
- 여전히 입력은 가볍지만 화면 쪽이 무겁다고 느껴지면 Phase 3으로 진행한다.

## Phase 3. SwiftUI invalidation 범위 축소

### 목적

포커스 이동 1회가 메인 작업창 전체 상태 변경처럼 퍼지지 않도록, 렌더 갱신 범위를 필요한 카드와 컬럼으로 좁힌다.

### 변경 범위

- 메인 작업창 전용 render snapshot 또는 column view model
- active/ancestor/descendant diff 기반 갱신
- scroll / highlight / selection 반영 범위 축소

### 금지

- 상위 기능 의미 변경
- split/history/focus mode 동기화 의미 변경
- Focus View / Index View 렌더 규칙 변경

### 실행 내용

- `displayedLevelsData()` 같은 대형 계산을 포커스 이동과 느슨하게 분리한다.
- 이전 active와 새 active의 diff만 반영하도록 highlight 갱신을 좁힌다.
- 메인 작업창에서 포커스와 무관한 상태가 body 재평가를 넓게 일으키지 않게 구조를 정리한다.

### 기대 효과

- 카드 수가 많을수록 체감 개선이 커진다.
- 이동 계산뿐 아니라 "화면 전체가 다시 흔들리는 느낌"이 줄어든다.

### 완료 기준

- 대형 문서/깊은 트리에서 방향키 반복 입력이 확실히 가벼워진다.
- 카드 강조, selection, 편집 상태 전환 의미는 기존과 같다.
- Focus View / Index View 동작 차이는 없다.

### 사용자 평가 포인트

- 카드 수가 많은 실제 작업 시나리오에서 연속 이동
- active 강조와 주변 카드 강조 전환 감각 확인
- 선택 범위, 편집 진입/이탈 회귀 확인

### stop / go

- 이 단계에서 만족하면 중단한다.
- 그래도 "계산은 빨라졌는데 캔버스 자체가 무겁다"는 느낌이 남으면 Phase 4로 진행한다.

## Phase 4. 메인 캔버스 엔진 교체(AppKit / CALayer)

### 목적

메인 작업창만 별도 엔진으로 분리해, 비편집 카드는 레이어 기반으로 유지하고 활성 카드만 편집 뷰를 올리는 구조로 성능 상한선을 올린다.

### 전제

- 이 phase는 선택 사항이다.
- Phase 1~3으로 충분하면 들어가지 않는다.
- 이 phase에 들어가도 Focus View와 Index View 기능은 바꾸지 않는다.

### 변경 범위

- 메인 작업창 캔버스만 `NSView + CALayer` 중심으로 교체
- SwiftUI는 바깥 shell과 상태 연결만 유지
- 비편집 카드는 cached layer/text rendering 사용
- 활성 카드만 `NSTextView` 또는 동등한 편집 경로 유지

### 금지

- 메인 작업창 의미 변경
- Focus View / Index View 엔진까지 함께 교체
- 텍스트 편집 기능, 선택 기능, 접근성 의미 손상

### 실행 내용

- 드로잉 기술만 바꾸는 것이 아니라, 메인 작업창을 scene engine처럼 분리한다.
- 포커스 이동 시 이전 active, 새 active, 관련 체인만 diff로 갱신한다.
- 스크롤, 하이라이트, 텍스트 표시를 layer 중심으로 관리한다.
- 편집 시작 시에만 실제 텍스트 편집 뷰를 활성화한다.

### 기대 효과

- 반복 이동과 key repeat에서 가장 높은 성능 상한선 확보
- 카드 수가 매우 많을 때도 입력당 비용을 더 안정적으로 유지

### 완료 기준

- 메인 작업창에서 연속 방향키 이동이 확실히 더 가볍다.
- 부모/자식 체인 정렬 감각과 편집 전환 의미가 그대로다.
- Focus View / Index View는 기능상 완전히 동일하다.

### 사용자 평가 포인트

- 대형 데이터에서 장시간 탐색
- 편집 진입/이탈이 잦은 실제 작업 루프
- Focus View / Index View smoke test

### stop / go

- 이 단계는 마지막 단계다.
- 여기까지 와도 만족하지 못하면 추가 미세 튜닝이 아니라 별도 재진단이 필요하다.

## 권장 실행 순서

1. Phase 0
2. Phase 1
3. 사용자 평가
4. 필요 시 Phase 2
5. 사용자 평가
6. 필요 시 Phase 3
7. 사용자 평가
8. 정말 필요할 때만 Phase 4

## 최종 성공 기준

이번 계획이 성공이라고 보려면 아래를 모두 만족해야 한다.

- 메인 작업창의 반복 화살표 이동과 key repeat가 체감상 훨씬 가볍다.
- 포커스 카드 변경 시 부모/자식 체인이 끝까지 재정렬되는 핵심 UX는 유지된다.
- Focus View 기능 변화가 없다.
- Index View 기능 변화가 없다.
- 사용자가 원하는 시점에서 phase 단위로 중단 가능하다.
