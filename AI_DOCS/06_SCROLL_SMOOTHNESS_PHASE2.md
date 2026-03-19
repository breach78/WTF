# Scroll Smoothness Phase 2

작성일: 2026-03-18

## Phase 2 목표

메인 캔버스의 content render state와 navigation runtime state를 분리해서, 포커스/선택/편집 변화가 `MainCanvasHost`의 구조적 재구성 기준을 직접 흔들지 않게 만든다.

이번 단계에서는 scroll engine을 바꾸지 않는다. 핵심은 render invalidation 경계를 더 명확하게 만드는 것이다.

## 이번 단계에서 변경한 것

### 1. MainCanvasViewState에 navigation runtime state 추가

추가한 상태:

- `interactionFingerprint`
- `focusNavigationTargetID`
- `focusNavigationTick`

의미:

- 메인 캔버스 host는 이제 포커스 이동 트리거를 `renderState.activeCardID`에서 직접 받지 않고, `viewState`가 발행하는 navigation event를 통해 받는다.
- 포커스/선택/편집 변화는 content fingerprint가 아니라 lightweight runtime state로 흘러간다.

### 2. MainCanvasRenderState에서 active card 의존성 제거

`MainCanvasRenderState`에서 제거:

- `activeCardID`

변경 이유:

- active card 변화는 구조 변화가 아니라 navigation event이기 때문이다.
- horizontal scroll trigger를 render state 변화에 매달아 두면, main canvas host가 포커스 이동마다 구조적으로 다시 평가된다.

### 3. mainCanvasContentFingerprint 축소

content fingerprint에서 제거:

- `activeCardID`
- `editingCardID`
- `selectedCardIDs`
- `activeRelationFingerprint`

의미:

- 메인 캔버스의 구조적 재구성 기준이 카드 구조와 preview/AI/recording 같은 실제 content-driving state 쪽으로 더 좁혀졌다.
- 포커스, 선택, 편집, relation highlight는 `interactionFingerprint`와 row-local state가 담당한다.

### 4. active-card scroll trigger를 viewState event로 변경

기존:

- `MainCanvasHost`가 `renderState.activeCardID` 변경을 직접 감시

변경 후:

- `MainCanvasHost`가 `viewState.focusNavigationTick`을 감시
- target은 `viewState.focusNavigationTargetID`로 전달

의미:

- active card 변화와 main canvas content fingerprint가 분리됐다.
- horizontal auto-scroll은 이제 명시적인 navigation event에서만 실행된다.

## 변경 파일

- `/Users/three/app_build/wa/wa/WriterSharedTypes.swift`
- `/Users/three/app_build/wa/wa/WriterViews.swift`

## 기대 효과

이번 단계의 직접 기대 효과는 다음이다.

1. 포커스 이동 시 `MainCanvasHost`의 equatable render state churn 감소
2. horizontal auto-scroll trigger의 책임 분리
3. 이후 Phase 3에서 scroll coordinator를 붙일 때 render-state coupling이 더 적은 기반 확보

## 아직 남아 있는 것

이번 단계는 render-state 경계 정리까지만 한다. 다음은 아직 남아 있다.

- vertical column이 여전히 `activeCardID`와 `activeRelationFingerprint`를 직접 본다
- per-card `GeometryReader`와 synthetic layout snapshot 공존
- scroll verification retry 구조 자체는 아직 유지

즉, 이번 단계는 “무엇이 구조적 content 변화이고, 무엇이 navigation runtime 변화인가”를 메인 캔버스 수준에서 분리한 단계다.
