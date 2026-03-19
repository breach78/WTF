# Scroll Smoothness Phase 1

작성일: 2026-03-18

## Phase 1 목표

구조 리팩터링에 들어가기 전에, 메인 캔버스 네비게이션의 현재 병목을 반복 가능하게 관찰하고 비교할 수 있는 계측 기반을 고정한다.

이번 단계에서는 스크롤 로직을 바꾸지 않는다. 포커스 이동 규칙, 정렬 방식, persistence, UI 동작은 유지한 채 diagnostics만 추가한다.

## 이번 단계에서 추가한 것

### 1. main-canvas navigation signpost

새 파일:

- `/Users/three/app_build/wa/wa/MainCanvasNavigationDiagnostics.swift`

추가된 signpost/event:

- `FocusIntent`
  - 화살표 네비게이션이 실제로 처리된 시점
- `RelationSync`
  - 조상/형제/자손 관계 상태 계산 완료 시점
- `ColumnLayoutResolve`
  - 세로 열 레이아웃 snapshot 계산 또는 cache hit 시점
- `ScrollAnimation`
  - 세로/가로 스크롤 애니메이션 시작과 종료
- `VerificationRetry`
  - verification retry가 실제로 발생한 시점

### 2. in-memory counter + summary

owner key 기준으로 다음 수치를 누적한다.

- focus intent count
- repeat focus intent count
- relation sync 평균 / 최대 시간
- column layout resolve 평균 / 최대 시간
- layout cache miss count
- vertical native scroll count
- vertical fallback scroll count
- horizontal fallback scroll count
- verification retry count

workspace가 사라질 때 summary를 `MainCanvasNavigation` 로그 카테고리로 출력한다.

### 3. baseline 재현 시나리오 고정

이제 아래 시나리오를 기준으로 모든 후속 개선을 비교한다.

1. 짧은 카드가 연속된 열에서 위/아래를 30회 이동
2. 긴 카드에서 긴 카드로 위/아래를 30회 이동
3. 형제 카드 사이를 위/아래로 왕복 이동
4. 부모/선조 열이 함께 바뀌는 위/아래 이동
5. 위/아래 키 repeat를 10초 이상 유지

## 계측이 들어간 코드 지점

- 화살표 입력 처리 후 focus intent 시작
  - `/Users/three/app_build/wa/wa/WriterKeyboardHandlers.swift`
- relation state 계산 완료
  - `/Users/three/app_build/wa/wa/WriterCardManagement.swift`
- column layout resolve / cache hit
  - `/Users/three/app_build/wa/wa/WriterCardManagement.swift`
- vertical native / fallback scroll start
  - `/Users/three/app_build/wa/wa/WriterCardManagement.swift`
- horizontal scroll start
  - `/Users/three/app_build/wa/wa/WriterCardManagement.swift`
- verification retry count
  - `/Users/three/app_build/wa/wa/WriterCardManagement.swift`
- diagnostics reset / summary emit
  - `/Users/three/app_build/wa/wa/WriterViews.swift`

## 관찰 방법

### Instruments

권장 도구:

- Instruments > Points of Interest
- subsystem: `com.riwoong.wa`
- category: `MainCanvasNavigation`

여기서 다음을 바로 볼 수 있다.

- focus intent 시작부터 relation sync 완료까지의 간격
- scroll animation 간격
- layout resolve event 빈도
- verification retry 발생 패턴

### Console / Unified Logging

category 필터:

- `MainCanvasNavigation`

workspace 종료 시 summary 로그가 남는다.

## Acceptance 기준

Phase 1 완료 기준은 성능 개선이 아니라 “측정 가능성 확보”다.

다음이 보이면 완료로 본다.

1. 화살표 입력 시 `FocusIntent` signpost가 남는다.
2. 같은 이동에 대해 `RelationSync` event가 남는다.
3. 세로 정렬 경로에서 `ColumnLayoutResolve`와 `VerificationRetry`를 관찰할 수 있다.
4. 세로/가로 스크롤 경로에서 `ScrollAnimation` 시작/종료가 관찰된다.
5. workspace 종료 시 baseline summary를 로그로 확인할 수 있다.

## 후속 Phase에서 이 수치로 확인할 것

- `FocusIntent -> RelationSync` 구간이 줄어드는가
- `ColumnLayoutResolve` 횟수와 cache miss가 줄어드는가
- `VerificationRetry`가 일반 입력에서 거의 사라지는가
- fallback scroll 대비 native scroll 비중이 늘어나는가

## 이번 단계의 결론

Phase 1은 “무엇이 느린지 보이는 상태”를 만드는 단계다. 이 단계가 끝나면 이후 리팩터링은 체감만으로 판단하지 않고, relation sync 시간, layout resolve 빈도, retry 발생량, scroll animation 경로 비율로 비교할 수 있다.
