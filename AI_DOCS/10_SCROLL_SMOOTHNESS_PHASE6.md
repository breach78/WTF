# Scroll Smoothness Phase 6

작성일: 2026-03-18

## Phase 6 목표

애니메이션 도중 매 프레임마다 발생하는 per-card `GeometryReader + PreferenceKey` fan-out을 줄인다.

이번 단계에서는 geometry authority를 다시 바꾸지 않는다. 핵심은 큰 세로 열에서 모든 카드의 frame을 계속 관측하지 않고, 현재 viewport와 포커스 주변에 필요한 subset만 관측하도록 범위를 줄이는 것이다.

## 이번 단계에서 변경한 것

### 1. geometry observation window 계산 추가

변경 위치:

- `/Users/three/app_build/wa/wa/WriterCardManagement.swift`

변경 내용:

- `mainColumnGeometryObservationCardIDs(in:viewportKey:viewportHeight:)` 추가
- 카드 수가 `24`개 이하인 작은 열은 기존처럼 전체 관측 유지
- 큰 열은 `resolvedMainColumnLayoutSnapshot(...)`과 `resolvedMainColumnVisibleRect(...)`를 이용해 현재 viewport 주변의 predicted frame만 선별
- viewport 기준 preload 범위는 `max(viewportHeight * 0.75, 240)`로 확장

의미:

- 큰 열에서도 현재 보이는 구간과 바로 인접한 구간만 geometry preference를 발생시킨다.

### 2. 포커스 주변 카드 우선 관측

변경 위치:

- `/Users/three/app_build/wa/wa/WriterCardManagement.swift`

변경 내용:

- `resolvedMainColumnFocusTargetID(in:)`가 있으면 해당 카드 기준으로 앞뒤 `6`개 카드까지 observation set에 강제 포함
- `activeCardID`, `editingCardID`도 현재 열에 있으면 항상 observation set에 포함
- 예외적으로 set이 비면 앞 `12`개 카드를 fallback으로 포함

의미:

- 빠른 포커스 이동이나 편집 중인 카드가 viewport 경계에 있더라도, geometry authority에 필요한 최소 카드들은 계속 관측된다.

### 3. per-card GeometryReader 부착 범위 축소

변경 위치:

- `/Users/three/app_build/wa/wa/WriterCardManagement.swift`

변경 내용:

- `column(for:level:parent:screenHeight:)`에서 `observedCardIDs`를 먼저 계산
- 각 `cardRow`의 background `GeometryReader`는 `observedCardIDs.contains(card.id)`일 때만 부착
- 그 외 카드는 더 이상 매 프레임 `MainColumnCardFramePreferenceKey`를 밀어 올리지 않음

의미:

- 긴 열에서 스크롤/포커스 애니메이션 중 발생하던 geometry preference churn이 줄어든다.

## 변경 파일

- `/Users/three/app_build/wa/wa/WriterCardManagement.swift`

## 기대 효과

이번 단계의 직접 기대 효과는 다음과 같다.

1. 긴 열에서 `GeometryReader`/preference fan-out 감소
2. 빠른 위아래 포커스 이동 중 메인 스레드 geometry churn 감소
3. native scroll animation이 preference flood에 덜 방해받는 기반 확보

## 아직 남아 있는 것

이번 단계는 geometry observation 범위만 줄인다. 다음은 아직 남아 있다.

- text measurement 자체는 여전히 animation path 근처에 남아 있음
- prediction layout snapshot은 계속 사용되므로 긴 텍스트 비용이 완전히 사라진 것은 아님
- column-local anchor collection 같은 더 큰 구조 전환은 아직 하지 않음

즉, 이번 단계는 geometry authority를 유지한 채, "얼마나 많은 카드가 동시에 관측되는가"를 줄이는 단계다.
