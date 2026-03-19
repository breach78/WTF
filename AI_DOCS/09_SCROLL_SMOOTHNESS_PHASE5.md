# Scroll Smoothness Phase 5

작성일: 2026-03-18

## Phase 5 목표

실제 포커스 이동 스크롤 엔진을 AppKit-first로 통일한다.

이번 단계에서는 geometry authority를 다시 건드리지 않는다. 핵심은 포커스 이동과 복구 스크롤의 주 경로를 `NSScrollView` bounds animation / immediate bounds origin 변경으로 옮기고, `ScrollViewProxy.scrollTo`는 fallback으로만 남기는 것이다.

## 이번 단계에서 변경한 것

### 1. horizontal native scroll helper 추가

추가 위치:

- `/Users/three/app_build/wa/wa/WriterSharedTypes.swift`

추가 내용:

- `resolvedHorizontalTargetX(...)`
- `resolvedHorizontalAnimationDuration(...)`
- `applyHorizontalScrollIfNeeded(...)`
- `applyAnimatedHorizontalScrollIfNeeded(...)`

의미:

- 가로 메인 캔버스도 세로와 같은 수준의 native offset animation 경로를 갖게 되었다.

### 2. main canvas horizontal scroll view accessor 추가

추가 위치:

- `/Users/three/app_build/wa/wa/WriterSharedTypes.swift`
- `/Users/three/app_build/wa/wa/MainCanvasScrollCoordinator.swift`
- `/Users/three/app_build/wa/wa/WriterViews.swift`

변경 내용:

- `MainCanvasHorizontalScrollViewAccessor` 추가
- `MainCanvasScrollCoordinator`가 main canvas horizontal `NSScrollView`를 직접 등록/보관
- `MainCanvasHost`의 horizontal `ScrollView`에 accessor 연결

의미:

- 메인 캔버스 가로 포커스 이동은 이제 실제 `NSScrollView`를 직접 제어할 수 있다.

### 3. horizontal focus scroll 주 경로를 native로 전환

변경 위치:

- `/Users/three/app_build/wa/wa/WriterCardManagement.swift`

변경 내용:

- `resolvedMainCanvasHorizontalAnchor(...)`
- `resolvedMainCanvasHorizontalTargetX(...)`
- `performMainCanvasHorizontalScroll(...)`
- `scrollToColumnIfNeeded(...)`는 native 경로를 먼저 시도하고, 실패 시에만 `ScrollViewProxy.scrollTo` fallback 사용

의미:

- 일반 좌우 포커스 이동, horizontal settle, restore가 가능한 경우 모두 native scroll path를 타게 됐다.
- `scrollTo`는 scroll view가 아직 준비되지 않은 초기 restore 같은 fallback으로 축소됐다.

### 4. vertical focus scroll도 native-first로 전환

변경 위치:

- `/Users/three/app_build/wa/wa/WriterCardManagement.swift`

변경 내용:

- `applyMainColumnFocusAlignment(...)`가 observed frame 존재 여부와 무관하게 native vertical scroll을 먼저 시도
- prediction frame이 있을 때도 native offset 계산 가능
- native path가 불가능할 때만 `ScrollViewProxy.scrollTo` fallback

의미:

- 세로 포커스 이동의 주 경로가 이제 truly native scroll engine이 되었다.

### 5. bottom reveal도 native path 우선 적용

변경 위치:

- `/Users/three/app_build/wa/wa/WriterCardManagement.swift`

변경 내용:

- `handleMainColumnBottomRevealIntent(...)`에서 bottom anchor용 native vertical scroll을 먼저 시도
- 실패 시에만 proxy fallback

의미:

- 긴 카드 끝 reveal도 세로 포커스 이동과 동일한 native engine 위에서 동작한다.

### 6. animation off 경로는 native immediate 우선

이번 단계에서 native path가 가능한 경우 animation off는 아래 방식으로 처리된다.

- vertical: `setBoundsOrigin` 기반 immediate scroll
- horizontal: `setBoundsOrigin` 기반 immediate scroll

proxy fallback이 필요한 경우에만 기존 `performWithoutAnimation` transaction path를 사용한다.

의미:

- "애니메이션 꺼짐"은 native scroll view가 준비된 상태에서는 실제로 즉시 이동에 더 가깝다.

## 변경 파일

- `/Users/three/app_build/wa/wa/WriterSharedTypes.swift`
- `/Users/three/app_build/wa/wa/MainCanvasScrollCoordinator.swift`
- `/Users/three/app_build/wa/wa/WriterViews.swift`
- `/Users/three/app_build/wa/wa/WriterCardManagement.swift`

## 기대 효과

이번 단계의 직접 기대 효과는 다음과 같다.

1. vertical/horizontal 포커스 이동의 엔진 일관성 향상
2. 부모/선조 열 포함 애니메이션 감각의 일관성 향상
3. animation on/off 체감 차이의 명확화
4. proxy scroll이 애니메이션 품질을 흔드는 빈도 감소

## 아직 남아 있는 것

이번 단계는 engine 통일까지만 수행한다. 다음은 아직 남아 있다.

- target view가 아직 현실화되지 않은 경우 proxy fallback은 여전히 필요
- per-card `GeometryReader` churn은 아직 남아 있음
- text measurement를 animation path 밖으로 완전히 밀어내지는 않음

즉, 이번 단계는 "어떤 엔진으로 스크롤할 것인가"를 정리한 단계다. geometry authority는 Phase 4에서 정리했고, 이제 main canvas navigation의 주 경로는 native `NSScrollView`에 가깝게 통일되었다.
