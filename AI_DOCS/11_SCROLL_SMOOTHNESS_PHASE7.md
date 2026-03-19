# Scroll Smoothness Phase 7

작성일: 2026-03-18

## Phase 7 목표

text measurement를 animation path 밖으로 더 밀어내서, 긴 카드 구간의 fallback 계산 tail latency를 줄인다.

이번 단계에서는 기존 shared text measurement cache를 유지하되, 그 위에 main-canvas 전용 explicit card-height record를 추가한다. 메인 컬럼 layout snapshot은 이제 카드별 height record를 재사용하고, editing card만 live text view height override를 유지한다.

## 이번 단계에서 변경한 것

### 1. main-canvas card height record 추가

변경 위치:

- `/Users/three/app_build/wa/wa/WriterViews.swift`
- `/Users/three/app_build/wa/wa/WriterSharedTypes.swift`

변경 내용:

- `MainCardHeightMode`
- `MainCardHeightCacheKey`
- `MainCardHeightRecord`
- `WriterInteractionRuntime.mainCardHeightRecordByKey`

를 추가했다.

record key는 다음 축을 기준으로 만들어진다.

- `cardID`
- normalized text fingerprint
- text length
- width bucket
- font size bucket
- line spacing bucket
- display / editing fallback mode

의미:

- column snapshot이 다시 만들어질 때도, unchanged card의 높이는 다시 측정하지 않고 explicit record를 재사용할 수 있다.

### 2. shared text measurement fingerprint를 공용화

변경 위치:

- `/Users/three/app_build/wa/wa/WriterSharedTypes.swift`

변경 내용:

- `normalizedSharedMeasurementText(_:)`
- `sharedStableTextFingerprint(_:)`

를 top-level helper로 분리했다.

의미:

- low-level text measurement cache와 main-canvas card-height record가 동일한 normalization / fingerprint 기준을 공유한다.

### 3. editing card live override를 snapshot key에 반영

변경 위치:

- `/Users/three/app_build/wa/wa/WriterViews.swift`
- `/Users/three/app_build/wa/wa/WriterCardManagement.swift`

변경 내용:

- `MainColumnLayoutCacheKey`에 `editingCardID`, `editingHeightBucket` 추가
- `resolvedMainColumnLayoutSnapshot(...)`가 현재 열 안의 editing card live height를 한 번만 확인
- 그 override를 snapshot key와 snapshot build 둘 다에 사용

의미:

- 예전처럼 "editing card가 포함되면 snapshot cache 전체를 포기"하지 않아도 된다.
- editing 중이더라도 live height가 안정된 구간에서는 layout snapshot을 재사용할 수 있다.

### 4. resolvedMainCardHeight 경로를 explicit record 기반으로 전환

변경 위치:

- `/Users/three/app_build/wa/wa/WriterCardManagement.swift`

변경 내용:

- `resolvedMainCardLiveEditingHeightOverride(for:)`
- `resolvedMainCardHeightCacheKey(for:mode:)`
- `storeMainCardHeightRecord(_:)`
- `resolvedMainCardHeightRecord(for:liveEditingHeightOverride:)`

를 추가했다.

동작은 다음과 같다.

- editing card:
  - 가능한 경우 `NSTextView` live body height를 즉시 사용
  - live override가 없을 때만 editing fallback record 사용
- non-editing card:
  - explicit display record 사용

의미:

- scroll alignment, bottom reveal, layout snapshot build가 모두 같은 explicit record를 공유하게 된다.
- 긴 열에서 repeated synthetic height resolution 비용이 줄어든다.

## 변경 파일

- `/Users/three/app_build/wa/wa/WriterSharedTypes.swift`
- `/Users/three/app_build/wa/wa/WriterViews.swift`
- `/Users/three/app_build/wa/wa/WriterCardManagement.swift`

## 기대 효과

이번 단계의 직접 기대 효과는 다음과 같다.

1. 긴 카드가 많은 열에서 repeated text fingerprint / measurement 진입 감소
2. layout snapshot cache hit 시 카드별 높이 계산 경로 제거
3. editing 중이 아닌 네비게이션에서 synthetic fallback 비용 예측 가능성 향상
4. editing 중에도 stable live height 구간에서는 snapshot cache 재사용 가능

## 아직 남아 있는 것

이번 단계는 explicit height record와 snapshot key 정리까지만 수행한다. 다음은 아직 남아 있다.

- `NSLayoutManager` 측정 자체를 background/precompute 경로로 옮기지는 않음
- focus mode 쪽 measurement 경로는 별도 최적화 대상
- card view 실측 geometry와 text measurement cache를 완전히 통합하지는 않음

즉, 이번 단계는 "카드 높이를 어떻게 재사용할 것인가"를 정리한 단계다. geometry authority는 그대로 두고, text measurement가 포커스 스크롤 경로에 반복 진입하는 빈도를 줄였다.
