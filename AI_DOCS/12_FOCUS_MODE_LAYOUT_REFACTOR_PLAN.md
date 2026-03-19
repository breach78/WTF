# Focus Mode Layout Refactor Plan

작성일: 2026-03-18

## 목적

포커스 모드에서 카드를 클릭하는 순간 카드 높이 또는 간격이 늘어나거나 줄어드는 현상을 근본적으로 제거한다.

이번 계획의 핵심은 보정 수치나 측정 patch를 더 얹는 것이 아니라, 포커스 모드의 editor 생명주기와 layout authority를 단일 구조로 재정의하는 것이다.

## 문제 요약

현재 포커스 모드에서는 카드를 클릭할 때 다음 증상이 남아 있다.

- 클릭 직후 카드 높이가 순간적으로 다시 계산되며 칸이 늘어나거나 줄어든다.
- 같은 카드 안에서 caret만 옮기고 싶어도 layout source가 바뀌며 reflow가 보인다.
- 여러 차례의 observed height / normalization patch 이후에도 재발한다.

영상과 코드 기준으로 보면, 이 문제는 단일 버그보다 구조 문제에 가깝다.

## 현재 구조 요약

현재 포커스 모드는 focused column의 카드들을 모두 `FocusModeCardEditor`로 렌더링한다.

관련 위치:

- `/Users/three/app_build/wa/wa/WriterFocusMode.swift`
- `/Users/three/app_build/wa/wa/WriterCardViews.swift`

핵심 흐름:

1. 포커스 모드의 각 카드가 `FocusModeCardEditor`를 가진다.
2. 각 카드의 높이는 세 가지 source 중 하나로 결정된다.
   - live `NSTextView` body height
   - `focusObservedBodyHeightByCardID`
   - deterministic text measurement
3. 카드 클릭 시 `activateFocusModeCardFromClick(_:)`가 active/editing 상태를 바꾼다.
4. 이어서 focus-mode offset normalization이 전체 text view 집합을 다시 스캔한다.
5. `focusObservedBodyHeightByCardID`가 갱신되고 각 카드가 다시 자기 높이를 선택한다.

즉, 클릭은 단순한 selection change가 아니라 layout authority 전환까지 동반한다.

## 근본 원인

### 1. 포커스 모드의 layout authority가 하나가 아니다

현재 `FocusModeCardEditor`는 다음 셋 중 하나를 골라 높이를 정한다.

- live responder height
- observed body height
- deterministic measured height

이 구조에서는 클릭 순간 active card가 바뀌면 높이 source도 바뀔 수 있다.

관련 위치:

- `/Users/three/app_build/wa/wa/WriterCardViews.swift`

### 2. inactive 카드도 모두 live editor 구조를 유지한다

현재 focused column의 카드들은 모두 `TextEditor` 기반 뷰를 유지한다.

이 구조는 다음 비용을 만든다.

- 여러 `NSTextView`가 동시에 존재
- offset normalization이 여러 editor를 스캔
- responder-card 매핑을 다시 추론
- inactive 카드의 observed body height도 지속 갱신

관련 위치:

- `/Users/three/app_build/wa/wa/WriterFocusMode.swift`
- `/Users/three/app_build/wa/wa/WriterCardViews.swift`

### 3. 클릭이 editor 전환과 layout recomputation을 한 번에 일으킨다

`activateFocusModeCardFromClick(_:)`는 클릭 시 아래를 한 번에 유발한다.

- active card 변경
- editing card 변경
- focus responder 변경
- caret relocation 준비
- offset normalization
- observed body height 갱신

이 경로는 “사용자 의도는 caret 이동 또는 card activation”인데, 내부적으로는 layout recomputation storm를 동반한다.

### 4. observed height cache가 runtime scan 결과에 의존한다

`focusObservedBodyHeightByCardID`는 앱의 현재 NSView tree를 스캔해서 얻는다.

이 구조는 본질적으로 unstable하다.

- 어떤 `NSTextView`가 현재 active인지
- 현재 window first responder가 누구인지
- remapping이 content match로 성공하는지

에 따라 같은 카드의 height source가 달라질 수 있다.

### 5. 현재 patch들은 증상을 완화하지만 source of truth를 줄이지 못한다

지금까지의 patch는 주로 아래에 속한다.

- observed range 허용
- deterministic fallback
- normalization burst
- click caret 보존

이들은 각각 부분 증상을 줄일 수는 있지만, “카드 높이의 최종 권한이 누구에게 있는가”를 하나로 만들지는 못한다.

## 목표 아키텍처

핵심 원칙은 하나다.

`포커스 모드에서는 active 카드만 실제 editor이고, 나머지 카드는 read-only 렌더링이어야 한다.`

### 1. Single Active Editor Model

포커스 모드에서 실제 `NSTextView`를 가진 카드는 한 장만 둔다.

- active/editing card만 editor host 사용
- inactive 카드들은 read-only `Text` 또는 동일 스타일의 display renderer 사용
- 클릭 시 inactive card는 editor를 “가지고 있던 뷰”가 아니라 “editor host의 다음 target”이 된다

기대 효과:

- 클릭 순간 다수 editor의 responder/offset 상태를 다시 맞출 필요가 없다
- layout change는 active card 전환 또는 content change 때만 발생한다

### 2. Single Layout Authority

포커스 모드 카드 높이는 전용 layout model이 소유한다.

height source 규칙:

- inactive 카드: explicit layout cache record
- active 카드: explicit layout cache record + optional live override
- observed body height dictionary는 primary authority가 아니다

즉, `focusObservedBodyHeightByCardID`는 제거 대상 또는 보조 telemetry로만 축소한다.

### 3. Editor Session과 Layout Model 분리

포커스 모드에는 아래 두 runtime 객체가 필요하다.

- `FocusModeEditorSession`
  - active/editing card id
  - caret hint
  - current responder
  - click activation / boundary navigation / programmatic caret entry 관리
- `FocusModeLayoutCoordinator`
  - card width
  - typography bucket
  - card height records
  - cumulative y-offset / visible rect
  - active card live height override

이 둘은 서로 연결되되, editor session이 직접 전체 카드 높이를 다시 계산하지는 않는다.

### 4. Focus Mode Card Shell 고정

각 카드의 외곽 shell은 view identity와 layout identity가 stable해야 한다.

- 클릭 전후에도 같은 card shell 유지
- 내부 content만 display renderer ↔ editor renderer로 교체
- shell height는 coordinator가 제공

즉, 클릭은 shell replacement가 아니라 content role switch여야 한다.

### 5. NSView Tree Scan 제거

현재 구조의 불안정성은 NSView tree 전체 scan에 크게 의존한다.

장기적으로는 다음을 제거하거나 축소해야 한다.

- `collectEditableFocusModeTextViews`
- responder-card remap 추론
- inactive text editor offset normalization

active editor가 하나뿐이라면, normalization 자체가 대부분 불필요해진다.

## 제안하는 실행 단계

## Phase 1. 현재 focus-mode layout event 계측

### 목적

클릭 순간 어떤 이벤트가 얼마나 연쇄되는지 측정 가능하게 만든다.

### 작업

- `FocusModeClickActivate`
- `FocusModeEditorSwap`
- `FocusModeLayoutResolve`
- `FocusModeObservedHeightUpdate`
- `FocusModeNormalization`

signpost 추가

### 완료 기준

- 클릭 한 번에 몇 번의 normalization과 height update가 발생하는지 볼 수 있다.

## Phase 2. FocusModeLayoutCoordinator 도입

### 목적

포커스 모드 카드 높이 계산을 editor runtime에서 분리한다.

### 작업

- `FocusModeLayoutCoordinator` 추가
- key:
  - cardID
  - content fingerprint
  - width bucket
  - font size bucket
  - line spacing bucket
  - display / active-editor mode
- cumulative y-offset snapshot 제공

### 완료 기준

- 카드 높이는 coordinator의 explicit record에서 읽는다.
- `FocusModeCardEditor`가 자체적으로 최종 height source를 선택하지 않는다.

## Phase 3. Single Active Editor 전환

### 목적

inactive 카드의 `TextEditor`를 제거한다.

### 작업

- active 카드만 editor renderer 사용
- inactive 카드는 display renderer 사용
- 클릭 시 editor host를 새 카드로 옮김
- inactive 카드의 `NSTextView` 생성을 중단

### 완료 기준

- focused column 내에서 실제 editable `NSTextView`는 한 장만 존재한다.

## Phase 4. Click Activation Path 단순화

### 목적

클릭이 layout recomputation storm를 일으키지 않게 만든다.

### 작업

- `activateFocusModeCardFromClick(_:)`를 selection + editor target change 중심으로 축소
- click에서 즉시 발생하던 observed height 갱신 제거
- caret handoff는 active editor session 내부에서만 수행

### 완료 기준

- 클릭 시 card shell height가 즉시 바뀌지 않는다.

## Phase 5. Observed Height / Normalization 제거 또는 축소

### 목적

기존 patch 경로를 정리한다.

### 작업

- `focusObservedBodyHeightByCardID`를 primary source에서 제거
- `normalizeInactiveFocusModeTextEditorOffsets` 제거 또는 active editor 전용으로 축소
- burst normalization 제거

### 완료 기준

- 클릭/포커스 이동 경로에서 inactive text editor normalization이 사라진다.

## Phase 6. 최종 polish와 validation

### 목적

포커스 모드 UX를 기존과 동일하게 유지하면서 구조 전환을 마무리한다.

### 작업

- caret preservation 검증
- boundary navigation 검증
- search popup / selection highlight / clone-linked marker 검증
- 긴 카드 시나리오 stress test

### 완료 기준

- visible behavior는 유지되고, 클릭 시 카드 높이 점프가 재현되지 않는다.

## 파일별 책임 재정의

### `/Users/three/app_build/wa/wa/WriterFocusMode.swift`

- focus-mode interaction orchestration만 담당
- click, boundary nav, search, caret session 관리
- card height 선택 책임 제거

### `/Users/three/app_build/wa/wa/WriterCardViews.swift`

- `FocusModeCardDisplay`
- `FocusModeActiveCardEditor`
- `FocusModeCardShell`

로 역할 분리

- shell은 stable width/height만 적용
- active editor만 `TextEditor` 사용
- inactive card는 pure display renderer 사용

### `/Users/three/app_build/wa/wa/WriterViews.swift`

- 포커스 모드 state binding과 coordinator 주입만 담당
- `focusObservedBodyHeightByCardID` 제거 후보

### 신규 파일 권장

- `/Users/three/app_build/wa/wa/FocusModeLayoutCoordinator.swift`
- `/Users/three/app_build/wa/wa/FocusModeEditorSession.swift`

## 성공 기준

다음이 만족되면 구조 전환이 성공한 것이다.

1. 포커스 모드에서 카드를 클릭해도 카드 shell 높이와 간격이 순간적으로 늘어나거나 줄어들지 않는다.
2. active 카드 전환 시에도 scroll position은 유지되고, 카드 외곽 크기는 stable하다.
3. 포커스 모드에서 실제 editable `NSTextView`는 한 장만 존재한다.
4. inactive card normalization scan이 일반 경로에서 사라진다.
5. click activation, boundary navigation, caret restore가 기존 동작을 유지한다.
6. 긴 카드가 많은 시나리오에서도 클릭 직후 reflow flash가 재현되지 않는다.

## 구현 원칙

- display와 editor를 같은 뷰로 억지 통합하지 않는다
- click 시 source of truth를 바꾸지 않는다
- active editor는 하나만 둔다
- inactive card는 측정 대상이 아니라 stable display 대상이다
- layout authority는 coordinator가 가진다
- observed height는 primary source가 될 수 없다

## 결론

현재 포커스 모드의 클릭 흔들림은 “측정값이 조금 틀린 문제”가 아니라, 모든 카드가 editor 구조를 유지하고 클릭 순간에 layout authority가 바뀌는 구조 문제다.

따라서 다음 구현은 보정치를 더 추가하는 것이 아니라:

1. active editor를 하나로 줄이고,
2. 포커스 모드 높이 권한을 coordinator로 모으고,
3. inactive card를 stable display renderer로 전환하는 방향이어야 한다.
