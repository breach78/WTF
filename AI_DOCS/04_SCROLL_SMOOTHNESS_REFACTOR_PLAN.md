# Scroll Smoothness Refactor Plan

작성일: 2026-03-18

## 목적

메인 창의 좌우/상하 포커스 이동을 현재보다 훨씬 안정적이고 부드럽게 만든다. 목표는 단순히 easing 값을 바꾸는 것이 아니라, 스크롤 애니메이션이 레이아웃 계산과 뷰 invalidation에 끌려다니지 않는 구조로 전환하는 것이다.

이번 계획의 전제는 다음과 같다.

- visible user behavior는 유지
- 카드 구조, 정렬 규칙, 데이터 포맷, persistence는 유지
- 포커스 이동 규칙을 바꾸지 않고 실행 엔진만 정리
- 임시 보정, retry, 패치 누적보다 단일한 스크롤 엔진과 geometry source를 우선
- SwiftUI view 코드는 선언적 표현에 집중시키고, 포커스 스크롤은 coordinator/service로 내린다

## 범위

이번 문서는 다음 문제를 해결하기 위한 구조 전환 계획이다.

- 위아래 포커스 이동 시 긴 카드 구간에서 포커스가 화면 밖으로 사라지는 문제
- 부모/선조 열을 포함한 자동 정렬이 어떤 경우에는 애니메이션이 보이고 어떤 경우에는 거의 보이지 않는 문제
- 애니메이션이 켜져 있어도 iOS의 `UIScrollView`처럼 부드럽게 보이지 않는 문제
- 포커스 이동 한 번에 너무 많은 계산과 뷰 갱신이 같이 일어나는 문제

이번 문서의 직접 범위는 메인 캔버스 네비게이션이다.

- main canvas horizontal scroll
- main column vertical focus alignment
- active card change에 따라 발생하는 relation / layout / geometry / verification 경로

다음은 이번 범위에서 제외한다.

- 타임라인 패널 자체의 UX 재설계
- 카드 디자인 변경
- persistence 모델 변경
- AI, dictation, history 기능의 동작 변경

## 현재 구조 요약

현재 메인 캔버스 스크롤 파이프라인은 크게 다섯 층으로 섞여 있다.

1. 포커스 이벤트
2. 관계 상태 갱신
3. 표시 열 계산
4. 카드 프레임 관측과 추정 레이아웃 계산
5. 스크롤 실행과 verification retry

구체적으로는 아래 흐름이다.

1. 화살표 입력이 `activeCardID`를 바꾼다.
2. `activeRelationFingerprint`와 조상/형제/자손 상태가 갱신된다.
3. 메인 캔버스가 `displayedLevelsData()`와 `displayedMainLevelsData(...)`를 다시 구성한다.
4. 각 세로 열은 `activeCardID`, `activeRelationFingerprint`, `childListSignature`, `navigationSettleTick` 등의 변화를 보고 스크롤 정렬을 스케줄한다.
5. 실제 스크롤 시도는 두 경로로 갈라진다.
   - 관측 프레임이 있으면 `NSScrollView` 오프셋 애니메이션 사용
   - 관측 프레임이 없으면 `ScrollViewProxy.scrollTo` fallback 사용
6. 정렬 후에는 verification work item이 다시 target visibility / alignment를 검사하고 재시도할 수 있다.

이 구조는 동작은 하지만, 애니메이션 한 번에 너무 많은 SwiftUI 상태와 geometry 경로가 동시에 반응한다.

## 현재 병목과 근본 원인

### 1. geometry source가 둘이다

세로 정렬은 두 종류의 좌표를 섞어 쓴다.

- 실제 화면에서 수집한 observed card frame
- `resolvedMainColumnLayoutSnapshot(...)`가 만든 synthetic frame

문제는 synthetic frame이 실제 SwiftUI 카드 렌더러와 동일한 레이아웃 엔진에서 나오지 않는다는 점이다. synthetic path는 `sharedMeasuredTextBodyHeight(...)` 기반 `NSTextStorage / NSLayoutManager` 측정이고, 실제 화면은 SwiftUI `Text`와 편집기의 live text view가 만든다. 긴 카드, CJK 줄바꿈, line spacing, editing/live display 차이에서 오차가 생긴다.

결과적으로 현재 구조는 다음 둘 중 하나를 오간다.

- target frame이 실제로 관측된 경우: 비교적 정확
- target frame이 아직 없어서 synthetic path를 타는 경우: 한 칸 아래, 덜 정렬됨, 이후 보정 필요

이것이 긴 카드에서 긴 카드로 빠르게 이동할 때 취약해지는 핵심 이유다.

### 2. 애니메이션 엔진이 둘이다

현재 메인 캔버스는 동일한 포커스 이동에서도 서로 다른 스크롤 엔진을 쓸 수 있다.

- vertical native path: `NSScrollView` bounds origin animation
- vertical fallback path: `ScrollViewProxy.scrollTo`
- horizontal path: 여전히 `ScrollViewProxy.scrollTo` 중심

즉, 같은 “포커스 이동”이라는 UX가 내부적으로는 서로 다른 엔진으로 실행된다. 이 구조는 다음 문제를 만든다.

- 어떤 때는 스내피한 native scroll처럼 보임
- 어떤 때는 거의 순간이동처럼 보임
- 어떤 때는 verification retry와 섞이며 애니메이션이 지워짐

### 3. scroll animation loop 안에서 SwiftUI geometry churn이 계속 돈다

세로 열은 각 카드마다 `GeometryReader`를 달고 `PreferenceKey`로 frame을 올린다. 즉, 스크롤 중에도 열 전체가 지속적으로 frame collection을 수행한다.

현재 구조의 비용은 단순히 “카드 텍스트가 길어서”가 아니다. 실제 비용은 아래 조합에 가깝다.

- visible card마다 frame preference 발행
- column 단위 `onPreferenceChange`
- scroll offset feedback
- synthetic layout snapshot fallback
- verification retry scheduling
- active/relation 변화에 따른 상위 뷰 재평가

이 조합이 애니메이션의 마지막 감속 구간을 거칠게 보이게 만든다.

### 4. 메인 캔버스 invalidation 범위가 너무 넓다

`mainCanvasContentFingerprint()`는 구조 변화 외에도 아래를 포함한다.

- `activeCardID`
- `editingCardID`
- `selectedCardIDs`
- `activeRelationFingerprint`
- preview/history/AI/dictation 관련 상태

즉, 포커스 이동은 “콘텐츠 구조 변경”이 아님에도 메인 캔버스 host 재평가에 깊게 연결되어 있다. 포커스 스크롤은 원래 가벼운 runtime event여야 하는데, 현재는 render fingerprint에도 강하게 물려 있다.

### 5. 스크롤 orchestration이 분산되어 있다

현재 스크롤 트리거는 여러 군데에 흩어져 있다.

- active card change
- active relation change
- child list change
- column appear
- navigation settle
- bottom reveal
- history/focus exit restore
- zoom / horizontal mode change

이렇게 되면 “어떤 이벤트가 최종 target을 결정하고, 어떤 이벤트는 보조 복구만 해야 하는가”가 흐려진다. 그 결과 patch가 쌓일수록 경로가 더 무거워지고 설명 가능성이 떨어진다.

## 왜 iOS처럼 안 보이나

현재 애니메이션이 iOS의 `UIScrollView` 감속처럼 느껴지지 않는 이유는 easing curve가 아니라 실행 레이어 때문이다.

- iOS는 원래 스크롤 자체가 저수준 scroll physics 위에서 돈다.
- 현재 앱은 focus event에 반응하는 UI state 변화, geometry 관측, 텍스트 높이 계산, scroll target 계산이 같은 메인 스레드 흐름에 묶여 있다.

즉, 지금 문제는 “animation constant를 조금 더 좋은 값으로 바꾸면 된다”가 아니다. 스크롤 프레임마다 해야 할 일의 양과 종류를 줄이지 않으면 체감 프레임은 좋아지지 않는다.

## 목표 아키텍처

핵심 원칙은 하나다.

`포커스 이동을 SwiftUI 뷰 재구성 사건이 아니라, MainCanvasScrollCoordinator가 처리하는 runtime scroll event로 분리한다.`

목표 구조는 아래와 같다.

### 1. 단일 scroll coordinator

메인 캔버스 스크롤을 전담하는 `MainCanvasScrollCoordinator`를 둔다.

역할:

- 각 열의 실제 `NSScrollView` 등록과 생명주기 관리
- 현재 viewport offset / content size / visible rect 관리
- active focus change를 받아 최종 target offset 계산
- vertical / horizontal scroll animation 실행
- repeat input 중 target coalescing
- verification은 coordinator 내부의 rare recovery path로만 유지

이 coordinator는 `WriterInteractionRuntime`의 일부가 되거나 별도 service로 분리될 수 있다. 중요한 것은 SwiftUI view body 밖에서 scroll state를 소유하는 것이다.

### 2. geometry authority 단일화

열 정렬용 좌표는 하나의 authoritative source를 사용해야 한다.

이상적인 방향:

- 실제 rendered card frame이 존재하면 그것만 사용
- 아직 frame이 없는 카드는 “view realization용 fallback”까지만 허용
- synthetic text-layout snapshot은 primary geometry source가 아니라 prefetch / estimate 용도로만 축소

즉, synthetic snapshot으로 alignment success를 판정하지 않는다. 최종 정렬 성공 기준은 observed geometry 또는 native scroll view geometry여야 한다.

### 3. AppKit-first scroll engine

포커스 이동 애니메이션의 주 경로는 `ScrollViewProxy.scrollTo`가 아니라 실제 `NSScrollView` 오프셋 제어가 되어야 한다.

적용 방향:

- vertical main column focus alignment: native path가 primary
- horizontal main canvas centering / step scroll: native path로 통일
- `scrollTo`는 view realization 또는 fallback에만 사용

이렇게 해야 animation curve보다 더 중요한 “프레임 간 연속성”을 확보할 수 있다.

### 4. content render state와 navigation runtime state 분리

메인 캔버스가 구조적으로 다시 그려져야 하는 상태와, 포커스가 어디인지에 따라 스크롤만 달라져야 하는 상태를 분리한다.

분리 원칙:

- content structure state
  - `scenario.cardsVersion`
  - 실제 열 구성 변경
  - history preview structure
- navigation runtime state
  - `activeCardID`
  - ancestor/sibling/descendant path
  - pending focus target
  - scrolling mode
  - animation mode

`mainCanvasContentFingerprint()`는 구조 상태 중심으로 좁혀야 한다. 포커스 변화는 가능한 한 row highlight와 coordinator만 반응해야 한다.

### 5. column-local layout model

세로 열마다 card order / cached height / group separator / cumulative y-offset를 갖는 경량 layout model을 둔다.

이 모델의 목적:

- 포커스 이동 때 열 전체를 다시 측정하지 않음
- 같은 width / font / line spacing / cardsVersion 조합에서 stable snapshot 재사용
- editing card만 live override 허용

이 layout model은 animation loop 밖에서 갱신되어야 한다.

## 제안하는 실행 단계

## Phase 1. 계측과 acceptance 기준 고정

### 목적

구조를 갈아엎기 전에 “무엇이 좋아져야 완료인지”를 수치와 시나리오로 고정한다.

### 작업

- main-canvas navigation signpost 추가
- 아래 구간을 구분 계측
  - focus intent 발생 시점
  - relation state 완료 시점
  - column layout resolve 완료 시점
  - scroll animation 시작/끝
  - verification retry 발생 횟수
- 아래 재현 시나리오를 고정
  - 짧은 카드 연속 이동
  - 긴 카드 -> 긴 카드 연속 이동
  - 형제 이동
  - 부모/선조 열이 바뀌는 이동
  - 키 repeat 10초 이상 유지

### 완료 기준

- 문제 재현 시나리오를 누구나 같은 방법으로 확인 가능
- 현재 baseline에서 retry 빈도와 layout miss 빈도를 볼 수 있음

## Phase 2. navigation runtime과 content render state 분리

### 목적

포커스 이동이 메인 캔버스 전체 render fingerprint를 계속 흔들지 않게 만든다.

### 작업

- `MainCanvasRenderState`에서 구조 상태와 navigation 상태를 분리
- `mainCanvasContentFingerprint()`를 구조 변화 중심으로 축소
- `activeCardID`, `activeRelationFingerprint`, selection 등은 row-level highlight와 scroll coordinator가 담당
- main canvas host는 “구조가 바뀐 경우”에만 재구성되게 조정

### 기대 효과

- 포커스 이동 시 상위 host 재평가 폭 감소
- scroll animation 중 body churn 감소

### 리스크

- highlight, selection, editing state 반영 범위를 잘못 자르면 UI가 stale해질 수 있음

## Phase 3. MainCanvasScrollCoordinator 도입

### 목적

스크롤 orchestration을 여러 `.onChange`에서 걷어내고 단일 객체로 모은다.

### 작업

- 열별 `NSScrollView` registry를 coordinator가 직접 관리
- focus event를 `NavigationIntent`로 정규화
- intent 종류 예시
  - sibling move
  - parent/child move
  - restore request
  - bottom reveal
  - settle recovery
- coordinator가 현재 상태를 바탕으로 최종 scroll target만 결정
- repeat input 중간 target은 coalesce하고 마지막 target만 보장

### 기대 효과

- “어느 change handler가 마지막으로 scroll을 덮어썼는가” 문제 제거
- fast path / fallback path / recovery path 분리 가능

### 리스크

- 기존 patch behavior를 coordinator에 정확히 이관해야 함

## Phase 4. vertical geometry authority 단일화

### 목적

세로 정렬이 synthetic layout과 observed frame을 오락가락하지 않게 만든다.

### 작업

- `MainColumnGeometryModel` 도입
- 실제 관측된 카드 frame을 authoritative geometry로 저장
- synthetic layout snapshot은 “대상 카드 현실화가 아직 안 된 경우의 prediction”으로 한정
- alignment success 판정은 observed frame 또는 native visible rect 기준만 허용
- verification retry는 “frame 없음” 또는 “실제 alignment failure”일 때만 동작

### 기대 효과

- 긴 카드에서 한 칸 아래 걸리는 현상 감소
- retry의 빈도와 비용 감소

### 리스크

- LazyVStack realization 시점과 geometry refresh 시점을 정확히 다뤄야 함

## Phase 5. AppKit-first scroll engine로 통일

### 목적

실제 포커스 이동 애니메이션이 동일한 엔진에서 실행되게 만든다.

### 작업

- vertical focus scroll 주 경로를 `NSScrollView` bounds animation으로 고정
- horizontal main canvas focus scroll도 native offset animation으로 이전
- `ScrollViewProxy.scrollTo`는 아래에만 사용
  - 아직 view가 realized되지 않은 경우
  - 복구용 fallback
  - deep restore 초기 1회
- animation off 경로는 `Transaction(animation: nil)`과 native immediate scroll을 사용해 truly immediate로 맞춤

### 기대 효과

- 애니메이션 품질의 일관성 확보
- 부모/선조 열 포함 스내피한 동작 재현 가능

### 리스크

- native scroll과 SwiftUI content lifecycle의 경계에서 sync 문제가 날 수 있음

## Phase 6. per-card GeometryReader churn 제거

### 목적

애니메이션 도중 매 프레임마다 발생하는 frame preference 비용을 줄인다.

### 작업

- 각 카드의 `GeometryReader + PreferenceKey` fan-out을 단계적으로 축소
- 가능한 경우 column-local measurement/anchor collection으로 전환
- 완전 제거가 어렵다면 최소한 visible card subset만 관측하도록 범위를 줄임
- 스크롤 엔진이 이미 아는 `NSScrollView` visible rect 정보와 중복되는 관측은 제거

### 기대 효과

- animation 중 geometry churn 감소
- 긴 열에서 체감 부드러움 개선

### 리스크

- 이 단계는 구현 난이도가 가장 높고, 시기상조 최적화가 되지 않게 앞 단계 성과를 먼저 확인해야 함

## Phase 7. text measurement를 animation path 밖으로 밀어내기

### 목적

긴 카드 이동 시 fallback이 여전히 무거워지는 원인을 줄인다.

### 작업

- card height cache를 explicit record로 승격
- key 예시
  - cardID
  - content save version
  - width bucket
  - font size bucket
  - line spacing bucket
  - editing/display mode
- editing card만 live text view height override 유지
- layout snapshot 재계산은 content / width / typography 변경 때만 수행

### 기대 효과

- 긴 카드 구간에서 focus movement의 tail latency 감소
- synthetic fallback path도 예측 가능해짐

### 리스크

- editing/live display 차이를 캐시 무효화 규칙으로 잘 처리해야 함

## 파일별 책임 재정의

### `/Users/three/app_build/wa/wa/WriterViews.swift`

- 메인 캔버스의 선언적 조립만 담당
- 구조적 열 구성과 background tap 같은 UI 표현만 남김
- scroll target 계산, verification, retry 로직 제거

### `/Users/three/app_build/wa/wa/WriterCardManagement.swift`

- 현재는 scroll orchestration이 너무 많이 몰려 있음
- 최종적으로는 card interaction과 navigation intent 생성만 남기는 방향이 맞음
- 세로 정렬 수식, verification 루프, mixed fallback path는 coordinator/service로 이동

### `/Users/three/app_build/wa/wa/WriterSharedTypes.swift`

- 현재 runtime cache와 native scroll helper가 있음
- 여기 또는 인접 파일에 `MainCanvasScrollCoordinator`, geometry cache, layout cache를 두는 것이 자연스러움
- 단, giant shared file가 더 비대해지지 않게 전용 파일 분리도 고려

### `/Users/three/app_build/wa/wa/WriterCardViews.swift`

- 카드 표현은 그대로 유지
- frame observation은 최소한으로 축소
- highlight와 editing 표현은 row-local state 중심으로 유지

### `/Users/three/app_build/wa/wa/Models.swift`

- 현재 index/cache는 비교적 양호
- model layer는 구조 변경 우선순위가 낮음
- 단, navigation runtime이 model index를 효율적으로 읽을 수 있도록 read API는 보강 가능

## 성공 기준

다음이 만족되면 구조 전환이 성공한 것이다.

1. 긴 카드에서 위아래 repeat 입력을 10초 이상 유지해도 포커스가 화면 밖으로 사라진 채 복구되지 않는 상태가 재현되지 않는다.
2. 형제 이동과 부모/선조 열 이동에서 애니메이션 켬/끔 차이가 명확하다.
3. 애니메이션 켬 상태에서 부모 열과 현재 열이 같은 품질의 scroll engine으로 움직인다.
4. animation off 상태는 정말 즉시 반응한다.
5. verification retry는 예외 상황에서만 발생하고, 일반 경로에서는 거의 0에 가깝다.
6. main canvas host는 포커스 이동만으로 광범위하게 재구성되지 않는다.
7. 긴 카드가 많은 시나리오에서도 멈춤 구간의 체감 프레임이 현저히 개선된다.

## 구현 원칙

이번 리팩터링은 다음 원칙을 지켜야 한다.

- 동작 동일성 우선
- patch를 더 얹기 전에 source of truth를 줄인다
- scroll engine은 하나의 주 경로를 갖는다
- verification은 복구용이지 정상 경로의 일부가 아니다
- fallback은 primary path를 대체하지 못한다
- focus event와 content render를 분리한다

## 권장 실행 순서

실행 순서는 아래가 맞다.

1. Phase 1
2. Phase 2
3. Phase 3
4. Phase 4
5. Phase 5
6. Phase 7
7. Phase 6

이 순서가 맞는 이유는 다음과 같다.

- 먼저 render invalidation과 scroll orchestration을 분리해야 한다.
- 그다음 geometry authority를 정리해야 한다.
- 그 후에 native scroll engine 통일과 measurement cache 고도화를 넣어야 한다.
- `GeometryReader` fan-out 제거는 가장 큰 변경이라, 앞단 구조가 안정화된 뒤 들어가는 것이 안전하다.

## 이번 문서의 결론

현재 문제의 핵심은 “스크롤 보정이 조금 부족하다”가 아니라 다음 세 가지다.

1. geometry source가 둘로 나뉘어 있다
2. scroll engine이 둘로 나뉘어 있다
3. focus 이동이 content render invalidation과 너무 강하게 결합돼 있다

따라서 다음 구현 단계는 보정 패치를 더 추가하는 것이 아니라, `MainCanvasScrollCoordinator` 중심으로 스크롤 책임을 재배치하고, geometry source와 animation engine을 단일화하는 쪽으로 가야 한다.

이 문서는 구현 전환을 위한 기준 문서이며, 이번 단계에서는 코드 동작을 변경하지 않는다.
