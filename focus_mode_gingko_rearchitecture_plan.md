# Superseded

이 문서는 범위를 잘못 잡았다.
- 징코 카피의 실제 대상은 `포커스 모드`가 아니라 `메인 작업창 모드`다.
- 구현 기준은 `main_workspace_gingko_rearchitecture_plan.md`를 사용한다.
- 이 문서는 구현 입력으로 사용하지 않는다.

# Focus Mode Gingko Rearchitecture Plan

목표 한 줄:
- `wa`의 포커스 모드를 징코 라이터처럼 즉시 반응하는 단일 포커스/스크롤 파이프라인으로 재구축한다.

문서 목적:
- 기존 포커스 모드의 미세 조정이 아니라 구조 교체가 필요하다는 점을 고정한다.
- 구현 중에 다시 "기존 보정 로직을 조금 살려서 봉합"하는 방향으로 후퇴하지 않게 한다.

비타협 기준:
- 징코 라이터의 가벼운 카드 전환 감각이 재현되지 않으면 이 작업은 실패다.
- retry 횟수 조절, dead-zone 숫자 튜닝, suppress flag 추가 같은 미세 수선은 본 계획의 성공으로 간주하지 않는다.

---

## 문제 정의

현재 포커스 모드는 사용자 입력 1회에 대해 다음 계층들이 순차 혹은 중첩으로 개입한다.

- 카드 활성 전환
- 편집 상태 전환
- caret 복원
- live editor layout 대기
- outer scroll keep-visible
- typewriter 위치 보정
- boundary reveal
- retry / ensure burst / fallback reveal

이 구조는 증상별 응급처치에는 유효했지만, 체감 질감은 무거워졌다.

현재 코드에서 그 징후가 강하게 보이는 곳:

- `/Users/three/app_build/wa/wa/WriterFocusMode.swift`
- `/Users/three/app_build/wa/wa/MainCanvasScrollCoordinator.swift`
- `/Users/three/app_build/wa/wa/WriterCaretAndScroll.swift`
- `/Users/three/app_build/wa/wa/WriterKeyboardHandlers.swift`

특히 현재 포커스 모드는:

- 전환 후 사후 보정이 많고
- "누가 마지막으로 viewport를 움직이는지"가 단순하지 않고
- active/editing/caret/scroll이 하나의 결정 경로에서 같이 나오지 않는다.

이 구조로는 징코식의 가벼움을 만들기 어렵다.

---

## 징코에서 가져올 핵심 원칙

징코 라이터의 질감은 애니메이션 커브보다 구조에서 나온다.

1. 포커스 대상은 모델에서 먼저 결정한다.
2. 스크롤 목표도 모델에서 먼저 결정한다.
3. DOM/뷰 계층은 이미 결정된 목표를 한 번 수행한다.
4. 살아 있는 편집기는 최소화한다.
5. 늦게 도착한 보정 콜백이 현재 결정을 뒤집지 못하게 한다.

우리 앱에 맞게 번역하면:

1. 카드 이동 결과는 `active/editing/caret/scroll target`을 한 번에 계산해야 한다.
2. 스크롤은 단일 소유자가 단일 계획을 적용해야 한다.
3. 포커스 모드에서는 실질적으로 한 카드만 live editor여야 한다.
4. 나머지 카드는 정적 렌더 + 레이아웃 캐시여야 한다.

---

## 하지 않을 것

다음은 이번 계획의 해법이 아니다.

- 기존 `ensure burst` 유지
- `applyFocusModeCaretWithRetry`의 retry 숫자 조정
- `suppressFocusModeScrollOnce` 류 플래그 추가
- caret ensure authority 세분화만 추가
- 기존 구조 위에 intent 레이어만 한 장 덧씌우기
- "우선 최소 변경으로 해보고" 접근하기

이런 접근은 증상을 조금 줄여도 징코 질감으로 가지 못한다.

---

## 목표 구조

포커스 모드 핵심 경로를 아래 네 단계로 단순화한다.

### 1. Navigation Decision

입력:

- 현재 active card
- 현재 editing card
- 카드 트리
- 최근 이동 히스토리
- 현재 명령

출력:

- 다음 active card
- 다음 editing card
- caret placement policy
- scroll target policy

이 단계는 순수 모델 계산이어야 한다.

새 타입:

- `FocusNavigationCommand`
- `FocusNavigationContext`
- `FocusNavigationResult`

후보 파일:

- `/Users/three/app_build/wa/wa/WriterFocusNavigationModel.swift`

### 2. Single Live Editor

포커스 모드의 활성 카드만 실제 AppKit editor를 가진다.

나머지 카드는:

- read-only text rendering
- 측정 캐시 사용
- editor responder chain에서 제외

이 단계가 없으면 카드 전환 때마다 responder, caret, layout, scroll이 서로 얽힌다.

활성 편집기 보호 원칙:

- 활성 `NSTextView`에는 모델에서 내려오는 텍스트 업데이트를 직접 적용하지 않는다.
- 활성 카드의 텍스트 source of truth는 편집 중에는 editor다.
- editor가 포커스를 잃거나 편집 세션이 종료될 때만 모델과 동기화한다.
- 이 원칙이 깨지면 Single Live Editor 구조에서도 caret jump가 다시 생긴다.

### 3. Scroll Plan

`FocusNavigationResult`를 받아 실제 viewport 목표를 계산한다.

이 단계는 "스크롤할지 말지"가 아니라 "어디로 보여줄지"를 계산한다.

범위 결정:

- 포커스 모드는 징코의 다중 컬럼 뷰와 달리 단일 세로 컬럼이다.
- 따라서 징코의 `centerAncestor / centerLastActiveDescendant / centerOtherDescendants / Before / After / Between` 같은 컬럼별 주변 카드 정책을 그대로 복제하지 않는다.
- 이 계획의 ScrollPlan은 활성 카드 기준 단일 세로 viewport 정책만 계산한다.
- 위아래 문맥은 필요하면 활성 카드 주변의 가시 범위로 해결하고, 별도의 조상/자손/히스토리 다중 정책 계층으로 확장하지 않는다.
- 구현 중 "주변 카드도 따로 정책화해야 하지 않나?"가 다시 나오면, 그것은 본 계획의 범위 확장으로 간주한다.

정책 예시:

- `.centerCard`
- `.preserveViewport`
- `.revealEdgeMinimal`
- `.placeCaretLineAtTypewriterBand`

새 타입:

- `FocusScrollPlan`
- `FocusScrollPolicy`
- `FocusViewportSnapshot`

후보 파일:

- `/Users/three/app_build/wa/wa/FocusScrollPlan.swift`

### 4. Single Scroll Apply

스크롤 뷰는 `FocusScrollPlan`만 수행한다.

원칙:

- 새 plan이 들어오면 진행 중인 in-flight 애니메이션부터 취소하거나 overwrite한다.
- 취소된 이전 plan의 completion과 verify는 현재 plan을 덮어쓰지 못해야 한다.
- AppKit `layoutSubtreeIfNeeded()`와 TextKit layout ensure 이후에만 rect를 측정한다.
- rect 확보와 목표 Y 계산은 반드시 같은 레이아웃 확정 구간 안에서 수행한다.
- 포커스 모드는 세로 단일 스크롤만 다루며, 가로 scroll-snap 대응 계층은 만들지 않는다.
- programmatic vertical scroll transaction 시작 전에는 다른 scroll owner, wheel/momentum carry-over, 자동 위치 재조정의 개입만 억제한다.
- 1회 애니메이션 또는 즉시 적용
- transaction 종료 후 억제 상태를 복원한다.
- target card view가 아직 존재하지 않으면 다음 runLoop 1회만 대기 후 다시 측정한다.
- 다음 runLoop에도 target card view가 없으면 포기하고 추가 retry 계층을 만들지 않는다.
- 필요 시 1회 검증
- 실패 시에도 늦은 구세주성 fallback 연쇄 실행 금지

이 단계가 현재 `retry / ensure / fallback` 다층 구조를 대체한다.

후보 파일:

- `/Users/three/app_build/wa/wa/FocusScrollExecutor.swift`

---

## 삭제/축소 대상

다음은 이번 재설계에서 "살릴 자산"이 아니라 우선 검토 후 줄이거나 제거할 대상이다.

1. `WriterFocusMode.swift`의 post-switch caret retry 체인
2. `requestFocusModeCaretEnsure(...)` burst 계열
3. boundary reveal 이후 늦게 들어오는 fallback scroll
4. 여러 suppress flag에 의존하는 viewport 보정
5. scroll authority가 현재 intent를 사후적으로 쫓는 경로

중요:
- 코드가 남아 있더라도 핵심 경로에서 빠져야 한다.
- "혹시 몰라서 보조로 남김"이 주 경로를 다시 오염시키면 실패다.

---

## 구현 페이즈

## Phase 0. 기준선 확보

목표:
- 지금 체감이 왜 무거운지 측정 가능한 기준을 남긴다.

활용:
- `/Users/three/app_build/wa/wa/MainCanvasNavigationDiagnostics.swift`

기록할 값:

- key down -> active card 확정 시간
- active card 확정 -> scroll start 시간
- scroll start -> scroll settle 시간
- card switch 1회당 late correction 횟수
- caret retry 발동 횟수

성공 기준:
- 이후 페이즈에서 late correction count가 구조적으로 줄어야 한다.

## Phase 1. Navigation Model 분리

목표:
- 카드 이동 판단을 `WriterFocusMode.swift`에서 떼어내어 순수 모델로 만든다.

범위:
- 위/아래 이동
- 부모/자식 이동
- sibling boundary 이동
- 삭제 후 다음 포커스 후보 계산 통합

결과:
- 이동 결과가 `FocusNavigationResult` 하나로 귀결된다.

성공 기준:
- `changeActiveCard`, `editingCardID`, `focusModeEditorCardID`를 여러 함수에서 따로 만지지 않는다.

## Phase 2. Single Live Editor 적용

목표:
- 포커스 모드에서 active/editing 카드만 AppKit live editor로 유지한다.

범위:
- focused column card view 계층
- live editor 장착/해제 타이밍
- 정적 카드 측정 캐시와 연결
- 활성 `NSTextView` 보호 원칙 적용

핵심 원칙:

- 활성 편집 중인 카드에는 모델 텍스트를 덮어쓰지 않는다.
- 비활성 카드만 모델 스냅샷을 반영한다.
- 포커스 상실 또는 편집 종료 시점에만 editor -> model 동기화를 수행한다.

성공 기준:
- 카드 전환 후 이전 카드 editor cleanup과 다음 카드 editor attach가 단순해진다.
- non-active 카드가 scroll/caret 경합에 개입하지 않는다.
- 활성 편집 카드에 모델 업데이트가 내려와도 caret 위치가 변하지 않는다.

## Phase 3. Scroll Plan 도입

목표:
- 카드 전환 직후 실행할 viewport 결정을 plan 객체 하나로 만든다.

범위:
- entry centering
- ordinary card switch
- boundary preserve viewport
- typewriter caret band

중요:
- 여기서부터 `cardScrollAnchor`, `preserveViewportOnSwitch`, `suppressFocusModeScrollOnce`의 역할을 축소한다.
- 이 단계는 Single Live Editor로 레이아웃 간섭을 줄인 뒤에만 신뢰할 수 있다.
- 이 단계의 scope는 단일 세로 컬럼의 활성 카드 기준 단일 정책 계산으로 한정한다.

성공 기준:
- "스크롤 결정을 어디서 했는지"가 plan 생성 지점 하나로 좁혀진다.

## Phase 4. Single Scroll Executor 교체

목표:
- 기존 focus-mode 스크롤 실행 경로를 새 executor로 바꾼다.

대체 대상:

- `applyFocusModeCaretWithRetry(...)`
- `requestFocusModeCaretEnsure(...)`
- `scheduleFocusModeCaretEnsureBurst()`
- 늦은 fallback reveal 경로 일부

실행 원칙:

- 새 plan이 들어오면 이전 in-flight 애니메이션을 먼저 cancel 또는 overwrite
- AppKit `layoutSubtreeIfNeeded()`와 TextKit layout ensure로 레이아웃 동기 확정
- 그 다음에만 새 카드의 rect 확보
- target card view가 아직 없으면 다음 runLoop 1회만 대기 후 재시도
- 다음 runLoop에도 없으면 포기하고 더 늦은 retry 계층을 만들지 않음
- 목표 Y 계산
- 애니메이션 시작 전 세로 스크롤에 대해서만 다른 스크롤 소유자, wheel/momentum carry-over, 자동 재정렬 개입 억제
- outer scroll view 1회 적용
- 애니메이션 종료 후 억제 상태 복원
- 필요한 경우 1회 verify

성공 기준:
- 카드 전환마다 여러 delayed scroll callback이 연속 발화하지 않는다.
- 빠른 연타 시 이전 scroll 애니메이션이 새 plan에 의해 취소되고 새 목적지로 즉시 출발한다.
- rect 측정이 레이아웃 확정 이전에 일어나지 않는다.
- 애니메이션 도중 시스템이 위치를 재조정하지 않는다.
- target card view 부재에 대한 재시도는 최대 1회 runLoop 대기에서 끝난다.

## Phase 5. 삭제 단계

목표:
- 이전 보정 코드가 주 경로로 복귀하지 못하게 정리한다.

삭제 또는 강등 후보:

- legacy retry helper
- unused suppress flags
- late reveal fallback
- 중복 authority check

성공 기준:
- 포커스 카드 전환 핵심 흐름을 1개의 문서 블록으로 설명할 수 있다.

---

## 파일별 작업 가이드

### `/Users/three/app_build/wa/wa/WriterFocusMode.swift`

역할 변경:

- 거대한 조정자에서 orchestration 레이어로 축소
- navigation result와 scroll plan을 받아 상태 반영만 담당

남겨둘 것:

- 포커스 모드 lifecycle
- UI 이벤트 진입점

줄일 것:

- 직접적인 caret retry 스케줄링
- 스크롤 보정 세부 로직

### `/Users/three/app_build/wa/wa/MainCanvasScrollCoordinator.swift`

역할 변경:

- 범용 intent 저장소에서 focus-mode scroll executor의 하부 도구로 축소
- focus-mode 전용 plan 타입을 이해하도록 확장 가능

### `/Users/three/app_build/wa/wa/FocusModeLayoutCoordinator.swift`

역할 유지:

- 정적 카드 높이 캐시
- live editor 높이 반영

역할 추가:

- single live editor 구조에서 필요한 "현재 활성 카드의 레이아웃 준비 여부"를 더 직접 제공

### 새 파일 후보

- `/Users/three/app_build/wa/wa/WriterFocusNavigationModel.swift`
- `/Users/three/app_build/wa/wa/FocusScrollPlan.swift`
- `/Users/three/app_build/wa/wa/FocusScrollExecutor.swift`

---

## 수용 기준

아래가 안 되면 징코 방향으로 간 것으로 보지 않는다.

1. 위/아래 화살표로 카드 이동할 때 카드 전환과 viewport 이동이 한 동작처럼 느껴질 것
2. boundary 이동 시 화면이 덜컥거리지 않고, 늦은 두 번째 보정이 보이지 않을 것
3. 새 카드 진입 시 caret이 즉시 기대 위치에 붙을 것
4. 카드 삭제 후 다음 카드 전환이 "임시 보정 후 안정화"처럼 보이지 않을 것
5. typewriter 모드가 일반 카드 전환을 지배하지 않을 것
6. 빠른 연타 시 이전 scroll 애니메이션이 새 plan에 의해 취소되고 새 목적지로 즉시 출발할 것
7. rect 측정은 항상 AppKit layout 확정과 TextKit layout ensure 이후에 일어날 것
8. 활성 편집 카드에 모델 업데이트가 내려와도 커서 위치가 변하지 않을 것

---

## 중간 점검 질문

구현 중 아래 질문에 하나라도 "아니오"면 방향이 틀어진 것이다.

1. 이번 단계가 실제로 late correction 경로를 제거했는가?
2. 이번 단계가 active/editing/caret/scroll 결정을 한 곳으로 모았는가?
3. 이번 단계가 non-active 카드의 live 편집 개입을 줄였는가?
4. 이번 단계가 코드를 더 단순하게 설명 가능하게 만들었는가?

하나라도 아니면:
- 그 단계는 징코 질감 재구축이 아니라 응급처치일 가능성이 높다.

---

## 최종 선언

이 작업의 방향은 "기존 구조를 살려 조금 덜 흔들리게 만들기"가 아니다.

이 작업의 방향은:

- 포커스 결정 재구성
- 스크롤 계획 단일화
- 실행 경로 단순화
- live editor 단일화

즉, 징코 라이터의 가벼운 느낌을 위해 포커스 모드 핵심 경로를 구조적으로 교체하는 것이다.
