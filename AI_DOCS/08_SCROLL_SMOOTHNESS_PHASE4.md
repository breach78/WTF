# Scroll Smoothness Phase 4

작성일: 2026-03-18

## Phase 4 목표

세로 정렬의 geometry authority를 observed frame 중심으로 단일화한다.

이번 단계에서는 synthetic layout snapshot을 제거하지 않는다. 대신 그 역할을 "예측용 prediction"으로 제한하고, 정렬 성공 판정과 skip 판정은 authoritative observed geometry만 보게 만든다.

## 이번 단계에서 변경한 것

### 1. MainColumnGeometryModel 도입

추가 위치:

- `/Users/three/app_build/wa/wa/MainCanvasScrollCoordinator.swift`

추가 내용:

- `MainColumnGeometryModel`
- viewportKey별 observed frame 저장소
- `updateObservedFrames(...)`
- `observedFrame(...)`
- `geometryModel(...)`

의미:

- 세로 열의 실제 관측 frame은 이제 `MainCanvasScrollCoordinator`가 authoritative geometry로 소유한다.
- 기존 runtime dictionary는 debug/보조 용도로만 남고, 실제 정렬 로직은 coordinator geometry를 본다.

### 2. observed frame 업데이트를 coordinator로 연결

변경 위치:

- `/Users/three/app_build/wa/wa/WriterCardManagement.swift`

변경 내용:

- `MainColumnCardFramePreferenceKey` 수신 시
- `mainCanvasScrollCoordinator.updateObservedFrames(...)`

를 함께 호출하도록 변경

의미:

- SwiftUI `GeometryReader`가 올린 실제 frame이 바로 authoritative geometry model에 반영된다.

### 3. synthetic layout을 prediction 전용으로 분리

추가/변경 내용:

- `predictedMainColumnTargetFrame(...)`
- `resolvedMainColumnFocusTargetOffset(...)`는 observed frame이 있으면 그것을 쓰고, 없을 때만 predicted frame을 사용

의미:

- synthetic snapshot은 이제 "아직 target view가 현실화되지 않았을 때 어디쯤 가야 하는가"를 추정하는 데만 사용된다.
- observed frame이 있는 이후에는 synthetic path가 정렬 판정에 개입하지 않는다.

### 4. visible/aligned 성공 판정을 observed geometry로 제한

변경 내용:

- `isObservedMainColumnFocusTargetVisible(...)`
- `isObservedMainColumnFocusTargetAligned(...)`
- `resolvedMainColumnVisibleRect(...)`

정렬 성공 기준:

- target card observed frame 존재
- native `documentVisibleRect` 또는 동등한 visible rect 기준으로 visibility 확인
- 같은 authoritative 좌표계에서 alignment 확인

의미:

- 이제 observed frame이 없는데 synthetic estimate만으로 "정렬 성공" 처리되는 경로를 끊었다.

### 5. top-anchor skip 판정도 observed geometry 기준으로 변경

변경 내용:

- `shouldSkipMainColumnFocusScroll(...)`

기존:

- synthetic target minY와 current offset 비교

변경 후:

- observed frame이 있을 때만 skip 가능
- visible rect origin과 observed minY 비교

의미:

- 긴 카드 top reveal에서 synthetic 오차 때문에 잘못 skip되는 위험을 줄였다.

## 변경 파일

- `/Users/three/app_build/wa/wa/MainCanvasScrollCoordinator.swift`
- `/Users/three/app_build/wa/wa/WriterCardManagement.swift`

## 기대 효과

이번 단계의 직접 기대 효과는 다음과 같다.

1. 긴 카드에서 "한 칸 아래 걸리는" 현상 감소
2. observed frame이 생긴 뒤에는 정렬 성공 판정의 일관성 향상
3. verification retry가 synthetic false-positive에 의해 조기 종료되는 경로 제거
4. Phase 5에서 native scroll engine을 더 강하게 적용할 기반 확보

## 아직 남아 있는 것

이번 단계는 geometry authority만 정리한다. 다음은 아직 남아 있다.

- target이 아직 현실화되지 않았을 때는 proxy fallback이 여전히 필요
- verification retry 구조 자체는 유지
- horizontal scroll engine은 아직 별도 단계
- per-card `GeometryReader` churn 자체는 아직 줄이지 않음

즉, 이번 단계는 "어떤 좌표를 진실로 볼 것인가"를 정리한 단계다. synthetic layout은 아직 존재하지만, 더 이상 alignment success의 truth source가 아니다.
