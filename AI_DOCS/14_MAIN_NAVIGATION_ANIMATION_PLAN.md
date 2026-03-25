# Main Navigation Animation Plan

작성일: 2026-03-25

## 작업 범위

메인 작업창(main workspace)에서 포커스 카드 이동 시 발생하는 가로/세로 스크롤 애니메이션, retry/settle, geometry 의존 경로만 정리한다.

## 절대 고정 조건

- 포커스 카드가 바뀔 때 부모/자식이 체인의 끝까지 재정렬되는 현재 동작은 유지한다.
- Focus View의 기능은 절대로 바꾸지 않는다.
- Index View의 기능은 절대로 바꾸지 않는다.
- 메인 작업창의 카드 의미, 정렬 규칙, undo/redo 의미, split/history/focus mode 의미는 유지한다.
- 애니메이션 개선은 “느낌만 바꾸는 easing 튜닝”이 아니라 motion pipeline 정리로만 얻는다.
- 각 phase는 독립적으로 실행 가능해야 하고, phase 종료 시점마다 사용자가 앱을 직접 평가한 뒤 멈출 수 있어야 한다.
- 각 phase는 단독으로 배포 가능한 완성 상태여야 한다. 다음 phase 전용 임시 코드나 반쯤 연결된 경로를 남기지 않는다.

## 현재 진단

지금 메인 작업창 애니메이션이 거칠게 느껴지는 이유는 animation constant가 아니라 실행 경로가 여러 개로 갈라져 있기 때문이다.

핵심 문제는 아래 다섯 가지다.

1. 한 번의 포커스 이동에 가로와 세로 정렬이 서로 다른 코드 경로로 실행된다.
2. SwiftUI `proxy.scrollTo`와 AppKit `NSScrollView` 애니메이션이 섞여 있다.
3. observed geometry가 없으면 fallback / retry / settle이 뒤늦게 다시 움직인다.
4. 애니메이션 중에도 layout resolve와 geometry churn이 같이 돈다.
5. key repeat 중에는 animation suppression과 settle recovery가 들어가서 “흐르는 모션”보다 “가고 다시 맞추는 모션”처럼 보인다.

즉, 지금 문제의 본질은 “애니메이션 엔진 품질”보다 “모션 파이프라인 일관성 부족”이다.

## 이번 계획의 목표

최종 목표는 아래 세 가지다.

1. 포커스 이동 1회가 사용자 눈에는 하나의 연속된 motion처럼 보여야 한다.
2. 일반 입력 경로에서는 fallback, retry, settle이 눈에 띄는 2차 움직임을 만들지 않아야 한다.
3. 큰 구조를 유지한 채 단계적으로 개선하고, 각 단계마다 만족하면 중단할 수 있어야 한다.

## 공통 운영 규칙

- 각 phase는 “빌드 가능 + 실행 가능 + 기존 기능 유지” 상태로 끝낸다.
- 각 phase가 끝나면 기존 앱을 종료하고 수정된 앱을 다시 실행한 뒤 사용자 평가를 받는다.
- 사용자가 만족하면 그 phase에서 중단한다.
- 사용자가 부족하다고 판단하면 다음 phase로 넘어간다.
- 각 phase 종료 시점은 커밋 경계로 남긴다. 문제가 있으면 직전 phase 커밋으로 즉시 되돌릴 수 있어야 한다.

## 공통 검증 체크리스트

모든 phase 종료 뒤 아래를 같은 순서로 확인한다.

1. 메인 작업창에서 `left/right` 이동이 한 번의 연속된 가로 motion처럼 보이는지 확인
2. 메인 작업창에서 `up/down` 이동이 한 번의 연속된 세로 motion처럼 보이는지 확인
3. 긴 카드 -> 긴 카드 이동에서 마지막에 “한 번 더 맞추는” nudge가 줄었는지 확인
4. key repeat 중 움직임이 끊기거나 갑자기 snap되는 느낌이 줄었는지 확인
5. 부모/자식 체인 재정렬 의미가 기존과 같은지 확인
6. Focus View 진입/이탈과 기본 조작이 기존과 같은지 확인
7. Index View 진입/이탈과 기본 조작이 기존과 같은지 확인

위 항목 중 기능 변화가 하나라도 보이면 그 phase는 실패로 간주한다.

## 이미 확보된 기반

- 메인 작업창 네비게이션 diagnostics는 이미 들어가 있다.
- 입력 hot path, projection/layout reuse, invalidation narrowing은 일부 진행되었다.
- 이번 문서는 그 위에서 “모션 파이프라인”만 따로 다룬다.

즉, 이번 계획은 성능 계획의 대체가 아니라 그 다음 층이다.

## Phase 1. Motion Arbiter 단일화

### 목적

포커스 이동 1회가 여러 trigger에서 중복 실행되지 않도록, 메인 작업창 motion 실행 권한을 한 곳으로 모은다.

### 변경 범위

- 메인 작업창 전용 motion arbiter 또는 동등한 coordinator
- active card change / click focus / settle / restore의 우선순위 정리
- “어떤 이벤트가 실제 motion을 실행하는가”의 단일화

### 금지

- 실제 포커스 이동 규칙 변경
- 부모/자식 체인 재정렬 지연
- Focus View / Index View 동작 변경

### 실행 내용

- `activeCardID` 변경 후 가로/세로 스크롤 실행이 여러 군데서 동시에 발화하지 않게 정리한다.
- click focus, arrow navigation, restore, settle을 모두 “motion request”로 변환하고 우선순위를 정한다.
- 같은 target에 대해 중복된 motion request가 들어오면 하나로 coalesce한다.
- phase 종료 시점에는 “한 포커스 이동에 누가 최종 motion owner인지”가 코드에서 명확해야 한다.

### 완료 기준

- 일반 입력 경로에서 동일 target에 대한 중복 스크롤 시도가 눈에 띄게 줄어든다.
- click / keyboard / restore 경로가 서로 다른 타이밍으로 같은 이동을 다시 덮어쓰지 않는다.
- 기능 의미는 그대로다.

### 사용자 평가 포인트

- 같은 카드 경로를 마우스 클릭과 화살표 키로 각각 이동
- 좌우 이동 직후 세로 정렬까지 같이 흔들리는지 확인
- 포커스 카드만 바뀌고 스크롤이 늦게 따라오는 경우가 줄었는지 확인

### stop / go

- 이 단계에서 “이중으로 한 번 더 움직이는 느낌”이 충분히 줄면 중단할 수 있다.
- 여전히 좌우 motion이 거칠면 Phase 2로 진행한다.

## Phase 2. Horizontal Engine 통일

### 목적

메인 작업창 가로 이동은 한 종류의 engine으로만 실행되게 만들어, 좌우 motion을 먼저 안정화한다.

### 변경 범위

- 메인 캔버스 horizontal scroll primary engine
- horizontal fallback / restore 정책
- horizontal animation duration / interrupt 정책

### 금지

- 세로 정렬 의미 변경
- 가로 visible range 의미 변경
- Focus View / Index View scroll 경로 변경

### 실행 내용

- 메인 작업창 가로 이동의 primary path를 AppKit native scroll로 통일한다.
- `proxy.scrollTo`는 view realization 또는 non-animated emergency fallback으로만 축소한다.
- pending horizontal restore는 “나중에 한 번 더 보이는 motion”이 아니라 primary engine의 내부 복구 경로가 되게 정리한다.
- 일반 입력에서 animated horizontal fallback이 보이면 실패로 본다.

### 완료 기준

- `left/right` 이동 시 가로 motion이 한 번의 연속된 motion처럼 보인다.
- column scroll이 중간에 끊기거나 다시 한 번 따라잡는 느낌이 줄어든다.
- 기존 스크롤 target 의미는 그대로다.

### 사용자 평가 포인트

- 깊은 체인에서 `left/right`를 천천히 한 칸씩 이동
- 긴 문서에서 `left/right` 길게 반복 입력
- 클릭 focus로 먼 열을 이동했을 때 좌우 motion이 한 번에 끝나는지 확인

### stop / go

- 좌우 motion이 충분히 자연스러우면 여기서 멈출 수 있다.
- 세로 motion이 여전히 거칠면 Phase 3으로 진행한다.

## Phase 3. Vertical Engine 통일

### 목적

세로 열 정렬도 한 종류의 engine 중심으로 정리해서, `up/down`과 boundary 이동을 안정화한다.

### 변경 범위

- column vertical focus alignment primary engine
- visibility reveal / focus alignment / bottom reveal 경로 정리
- verification retry의 역할 축소

### 금지

- 편집 카드 caret visibility 의미 변경
- tall card top/bottom reveal 의미 변경
- Focus View vertical scroll 변경

### 실행 내용

- vertical focus alignment의 primary path를 AppKit native scroll로 통일한다.
- `proxy.scrollTo`는 target view가 아직 realize되지 않았을 때의 non-primary fallback으로만 유지한다.
- verification retry는 일반 motion path가 아니라 예외 복구용으로만 남긴다.
- bottom reveal, keep-visible, focus alignment가 서로 다른 motion을 중복 발행하지 않게 정리한다.

### 완료 기준

- `up/down` 이동 시 세로 motion이 한 번의 연속된 motion처럼 보인다.
- boundary 이동 후 세로 정렬이 늦게 다시 한 번 바뀌는 빈도가 줄어든다.
- 긴 카드 top/bottom reveal 의미는 유지된다.

### 사용자 평가 포인트

- 긴 카드가 섞인 열에서 `up/down` 반복 이동
- 편집 중 boundary 이동
- 마지막 카드/첫 카드 주변에서 reveal 동작 확인

### stop / go

- 이 단계에서 일반 입력이 충분히 자연스러우면 중단할 수 있다.
- 긴 카드 구간에서 late nudge가 남으면 Phase 4로 진행한다.

## Phase 4. Geometry Authority 정리

### 목적

애니메이션 시작 전에 target geometry의 신뢰도를 높여, “대충 움직였다가 다시 맞추는” 현상을 줄인다.

### 변경 범위

- observed frame과 predicted layout의 역할 분리
- motion success criteria 재정의
- geometry prewarm 또는 realization 정책

### 금지

- 카드 레이아웃 규칙 변경
- 카드 높이 계산 의미 변경
- 편집 카드 live height 의미 변경

### 실행 내용

- observed geometry를 최종 정렬 판단의 authoritative source로 격상한다.
- predicted layout은 prefetch / provisional target 용도로만 사용하고, 정렬 성공 판정에는 직접 쓰지 않는다.
- geometry가 아직 없는 카드에 대해서는 즉시 animated fallback보다 prewarm 또는 delayed commit 정책을 쓴다.
- 목표는 “틀린 target으로 먼저 움직이고 나중에 고치는 것”보다 “조금 늦더라도 한 번에 맞게 움직이는 것”이다.

### 완료 기준

- 긴 카드 -> 긴 카드 이동에서 마지막 nudge 빈도가 확실히 줄어든다.
- 일반적인 포커스 이동이 geometry miss 때문에 두 번 움직이지 않는다.
- 카드 height / line spacing / 편집 중 높이 의미는 그대로다.

### 사용자 평가 포인트

- 긴 카드에서 긴 카드로 빠르게 왕복 이동
- CJK 줄바꿈이 많은 카드 구간
- 편집 카드와 비편집 카드가 섞인 구간

### stop / go

- late nudge가 충분히 줄면 여기서 멈춘다.
- key repeat에서만 여전히 모션이 나쁘면 Phase 5로 진행한다.

## Phase 5. Repeat Motion Model 재설계

### 목적

key repeat를 “이벤트 연타”가 아니라 “지속 입력”으로 취급해서, 반복 입력 중 motion이 더 일관되게 보이게 만든다.

### 변경 범위

- repeat input coalescing / ticker
- repeat 중 animation suppression과 settle 정책
- keyup 시 최종 정렬 정책

### 금지

- 카드 이동 규칙 변경
- key repeat에서 target 순서 변경
- Focus View / Index View repeat 입력 변경

### 실행 내용

- key repeat 동안 각 반복 이벤트를 독립 애니메이션으로 실행하지 않도록 정리한다.
- repeat 중에는 최신 target만 유지하고 motion request를 coalesce한다.
- settle recovery는 “일반 입력에서도 늘 보이는 2차 motion”이 아니라 예외 복구용으로 더 축소한다.
- keyup 이후 최종 정렬이 필요해도 snap처럼 느껴지지 않게 정책을 정리한다.

### 완료 기준

- `left/right/up/down`를 길게 눌렀을 때 motion이 더 연속적으로 느껴진다.
- 키를 뗀 직후 마지막에 눈에 띄는 snap이 줄어든다.
- target 순서와 포커스 의미는 그대로다.

### 사용자 평가 포인트

- `left/right` 5초 이상 길게 누르기
- `up/down` 5초 이상 길게 누르기
- 키를 떼는 순간 최종 위치가 자연스러운지 확인

### stop / go

- repeat 감각까지 충분히 좋아지면 중단한다.
- 구조는 안정적이지만 curve와 감속 감각이 여전히 아쉬우면 Phase 6으로 진행한다.

## Phase 6. Motion Curve / Duration 통일

### 목적

구조 문제를 정리한 뒤 마지막으로 curve, duration, dead-zone, interrupt 규칙을 통일해 체감 polish를 올린다.

### 변경 범위

- horizontal / vertical 공용 motion token
- duration scaling 규칙
- interrupt / cancel / dead-zone / snap-to-pixel 정책

### 금지

- 구조 문제를 curve로 덮기
- Focus View / Index View animation token까지 같이 변경

### 실행 내용

- 가로/세로 motion curve를 공용 token으로 묶는다.
- distance 기반 duration scaling을 통일한다.
- dead-zone과 interrupt 정책을 재정리해 “어느 경로는 끊기고 어느 경로는 미끄러지는” 차이를 줄인다.
- 이 단계는 구조적 회귀를 만들지 않는 polish 단계여야 한다.

### 완료 기준

- 같은 종류의 이동은 비슷한 감속과 응답성을 가진다.
- 일반 입력과 click focus의 motion 성격이 지나치게 다르지 않다.
- 이전 phase의 구조 개선 효과를 해치지 않는다.

### 사용자 평가 포인트

- 좌우/상하 모두 같은 스타일로 자연스럽게 느껴지는지 확인
- 짧은 이동과 긴 이동의 감속 시간이 과하지 않은지 확인

### stop / go

- 이 단계에서 만족하면 종료한다.
- 그래도 “메인 작업창 자체를 더 낮은 레벨 엔진으로 바꿔야 한다”는 느낌이 남으면 선택적으로 Phase 7로 진행한다.

## Phase 7. 선택 사항: 메인 캔버스 Motion Layer 분리

### 목적

그래도 남는 모션 품질 한계를 넘기 위해, 메인 작업창에서 motion layer만 더 낮은 레벨로 내리는 선택지다.

### 전제

- 이 단계는 선택 사항이다.
- Phase 1~6으로 충분하면 들어가지 않는다.
- Focus View와 Index View 기능은 여전히 건드리지 않는다.

### 변경 범위

- 메인 작업창 motion layer의 AppKit 중심 분리
- SwiftUI는 shell과 content declaration 위주로 유지
- scroll / geometry / motion orchestration만 더 낮은 레벨로 이동

### 금지

- 메인 작업창 기능 의미 변경
- Focus View / Index View 엔진까지 함께 교체
- 편집 기능 손상

### 완료 기준

- 남아 있던 미세한 motion jerk가 더 줄어든다.
- 엔진 복잡도 증가가 실제 체감 개선으로 정당화된다.

## 추천 진행 순서

현재 상태에서는 아래 순서가 가장 안전하다.

1. Phase 1
2. 사용자 평가
3. 필요 시 Phase 2
4. 필요 시 Phase 3
5. 긴 카드 late nudge가 남을 때만 Phase 4
6. repeat 품질이 마지막 문제일 때만 Phase 5
7. 구조가 안정된 뒤 polishing이 필요할 때만 Phase 6
8. 정말 상한선을 더 올려야 할 때만 Phase 7

## 사용자용 실행 문구

아래처럼 말하면 된다.

- `Animation Phase 1 실행해. 문서 기준으로 진행하고 끝나면 앱 재실행 후 내가 평가할게.`
- `좋아. Animation Phase 2 진행해.`
- `아직 부족해. Animation Phase 3 진행해.`
- `긴 카드에서 마지막 nudge가 남아. Animation Phase 4 진행해.`
- `repeat 입력이 아직 거칠어. Animation Phase 5 진행해.`
- `마지막 polish만 하자. Animation Phase 6 진행해.`
- `정말 필요하면 Animation Phase 7 진행해.`

## 최종 메모

이번 계획의 핵심은 “애니메이션 수치 튜닝”이 아니라 “모션 파이프라인 정리”다.

즉, 먼저 구조를 단일화하고, 그 다음에 feel을 다듬는다. 이 순서를 지켜야 각 phase가 온전한 형태로 끝나고, 중간 어느 지점에서도 만족하면 멈출 수 있다.
