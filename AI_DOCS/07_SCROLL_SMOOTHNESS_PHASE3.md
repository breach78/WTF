# Scroll Smoothness Phase 3

작성일: 2026-03-18

## Phase 3 목표

메인 캔버스 세로 스크롤 orchestration을 여러 `.onChange`에서 걷어내고, `MainCanvasScrollCoordinator`를 통해 단일 intent 흐름으로 정리한다.

이번 단계에서는 geometry engine 자체를 바꾸지 않는다. 핵심은 "무슨 이유로 어떤 열이 스크롤되어야 하는가"를 typed intent로 정규화하는 것이다.

## 이번 단계에서 변경한 것

### 1. MainCanvasScrollCoordinator 도입

새 파일:

- `/Users/three/app_build/wa/wa/MainCanvasScrollCoordinator.swift`

역할:

- 열별 `NSScrollView` registry 관리
- navigation intent 발행
- global intent와 viewport-scoped intent를 분리 저장
- 열별 latest relevant intent 소비와 stale intent 판정 제공

도입한 intent 종류:

- `focusChange`
- `settleRecovery`
- `childListChange`
- `columnAppear`
- `bottomReveal`

### 2. vertical column trigger를 coordinator intent로 전환

기존에는 각 열이 아래를 직접 감시하고 즉시 스크롤을 실행했다.

- `activeCardID`
- `activeRelationFingerprint`
- `mainNavigationSettleTick`
- `childListSignature`
- `mainBottomRevealTick`

변경 후:

- 열은 `mainCanvasScrollCoordinator.navigationIntentTick`만 감시한다.
- 실제 정렬 실행은 `handleMainColumnNavigationIntent(...)`에서만 일어난다.
- `childListSignature`, `columnAppear`, `bottomReveal`은 직접 스크롤하지 않고 intent만 발행한다.

즉, 열별 orchestration entry point가 하나로 줄었다.

### 3. active focus 이동을 typed intent로 정규화

`handleActiveCardIDChange(_:)`는 relation sync 이후:

- `publishMainColumnFocusNavigationIntent(for:)`

를 호출해 global `focusChange` intent를 발행한다.

의미:

- 세로 열은 더 이상 `activeCardID`와 `activeRelationFingerprint`를 각각 따로 보고 스크롤을 재결정하지 않는다.
- focus 이동의 의미가 하나의 runtime intent로 묶였다.

### 4. settle recovery도 coordinator 경유로 전환

`scheduleMainArrowNavigationSettle()`는 기존처럼 main canvas horizontal settle tick을 유지하면서도, 세로 열에 대해서는 `settleRecovery` intent를 같이 발행한다.

의미:

- repeat navigation 복구 경로도 active focus 이동과 같은 orchestration 레이어로 들어왔다.

### 5. stale delayed focus work 차단

기존 `scheduleMainColumnActiveCardFocus(...)`는 `expectedActiveID`만 비교했다.

변경 후:

- delayed work item이 실행되기 전에
- `mainCanvasScrollCoordinator.isIntentCurrent(...)`

를 확인한다.

의미:

- 다른 viewport-scoped intent나 더 최신 global intent가 들어온 뒤에는 예전 delayed focus work가 실행되지 않는다.
- fast navigation에서 "나중에 도착한 오래된 scroll"이 덮어쓰는 위험을 줄였다.

### 6. scroll-view registry 책임 이동

기존 `MainColumnScrollRegistry.shared`를 제거하고, `MainColumnScrollViewAccessor`가 `MainCanvasScrollCoordinator`에 직접 register/unregister 하도록 바꿨다.

영향 범위:

- native vertical scroll path
- startup viewport restore path
- column accessor lifecycle

## 변경 파일

- `/Users/three/app_build/wa/wa/MainCanvasScrollCoordinator.swift`
- `/Users/three/app_build/wa/wa/WriterCardManagement.swift`
- `/Users/three/app_build/wa/wa/WriterSharedTypes.swift`
- `/Users/three/app_build/wa/wa/WriterViews.swift`

## 기대 효과

이번 단계의 직접 기대 효과는 다음과 같다.

1. 세로 열 스크롤 실행 entry point 단일화
2. active card / relation / settle / child-list / bottom-reveal 경로의 orchestration 일관성 향상
3. delayed focus work의 stale overwrite 감소
4. 이후 Phase 4에서 geometry authority를 단일화할 기반 확보

## 아직 남아 있는 것

이번 단계는 orchestration 정리까지만 수행한다. 다음은 아직 남아 있다.

- vertical geometry authority는 여전히 observed frame과 synthetic snapshot이 공존
- verification retry 구조 자체는 유지
- horizontal scroll engine은 아직 Phase 2의 runtime event 구조를 유지
- per-card `GeometryReader` churn은 아직 줄이지 않음

즉, 이번 단계는 "어떤 intent가 어떤 열을 스크롤시키는가"를 coordinator로 모은 단계다. 실제 정렬 좌표계의 단일화는 다음 Phase 4의 범위다.
