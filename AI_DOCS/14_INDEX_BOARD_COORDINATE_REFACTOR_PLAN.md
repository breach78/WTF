# Index Board Coordinate Refactor Plan

## 핵심 진단

현재 인덱스 보드의 근본 문제는 `모델 좌표`와 `표현 좌표`가 섞여 있다는 점이다.

- 모델이 기억해야 하는 것은 `슬롯 좌표`다.
- 화면에서만 필요한 것은 `CGRect`, hover 확장 영역, preview frame, overlay frame`이다.
- 그런데 현재 구현은 이 둘이 여러 경로에서 같이 쓰이고 있다.

그 결과 다음 문제가 반복된다.

- 전혀 관계없는 슬롯이 반응함
- hover만으로 그룹 내부 순서가 흔들림
- drop 전후 감각이 달라짐
- 드롭 직후 불필요한 재계산이 커짐
- 좌표 버그를 threshold, 보정, 예외 처리로 때우게 됨

## 목표 원칙

보드의 진짜 상태는 픽셀 좌표가 아니라 `슬롯 좌표`여야 한다.

### 저장/undo/redo/persistence 대상

- 카드: `row, column`
- 그룹: `origin(row, column) + width + 내부 card order`
- temp strip: `row + member order`
- viewport: `scrollOffset + zoomScale`

### 저장 대상이 아닌 것

- `CGRect`
- hit test 확장 rect
- drag preview frame
- overlay 위치
- AppKit view/layer frame

이 값들은 전부 매 프레임 계산해서 버리는 파생값이어야 한다.

## 목표 구조

### 1. Logical Board State

보드 내용의 유일한 기준 상태.

- `cardID -> GridPosition(row, column)`
- `groupID -> origin(row, column), width, card order`
- `stripID -> row, member order`
- `viewport -> scrollOffset, zoomScale`

### 2. Derived Presentation

논리 상태에서 렌더용 구조를 만든다.

- `Logical Board State -> BoardSurfaceProjection`
- `BoardSurfaceProjection -> CGRect / wrapper / indicator / overlay`

즉 `BoardSurfaceProjection`은 저장 주체가 아니라 표현용 파생 구조다.

### 3. Drag Session

드래그 중 상태는 아래 4개만 가진다.

- drag 시작 시 logical snapshot 1개
- 현재 drag card body center 1개
- 현재 target slot 1개
- snapshot + pending move 로 만든 preview 1개

drop 시점에만 logical state를 commit한다.

## 드래그 규칙

### 공통 규칙

- 모든 타깃 판정은 `카드 몸통 중심` 기준으로 한다.
- 포인터 raw 좌표는 직접 target 계산에 쓰지 않는다.
- preview는 항상 `snapshot + pending move`에서만 만든다.
- 이전 preview를 다음 preview의 원본으로 재사용하지 않는다.

### 그룹 규칙

- 그룹 바깥 충돌/밀기에서는 `폭이 있는 블록`으로 본다.
- 실제 그룹 안으로 진입했을 때만 내부 slot을 연다.
- hover 중에는 그룹 내부 순서를 바꾸지 않는다.
- group order 변경은 drop 때만 commit한다.

### 충돌 규칙

- 인접함: 그룹 안 밀림
- 실제 column overlap 발생: 그룹 밀림
- 그룹이 충돌로 밀렸다면 그 origin은 session에 저장한다.
- 따라서 나중에 카드가 빠져도 그룹이 자동으로 다시 붙지 않는다.

## 절대 섞지 말 것

- pointer raw 좌표로 직접 commit target 계산
- preview projection을 다음 preview의 기준 상태로 사용
- hover 중 group order 재구성
- screen frame을 persisted state처럼 저장
- drop 중 여러 좌표계에서 각각 따로 판정

## 리팩터 순서

### 1단계

logical state와 presentation state를 타입으로 분리한다.

- logical state: 슬롯 기반
- presentation state: surface/projection/frame 기반

### 2단계

`resolvedDropTarget`을 `card body center -> logical slot` 하나로 통일한다.

### 3단계

preview를 `snapshot + pending move` 방식으로 통일한다.

### 4단계

그룹은 바깥에서 블록, 내부 진입 시에만 slot open 규칙으로 정리한다.

### 5단계

commit은 logical state만 갱신하고, render는 그 결과를 1회 반영한다.

### 6단계

persistence와 undo/redo는 logical state만 저장한다.

## 기대 효과

- 슬롯 반응 오차 감소
- hover만으로 순서가 바뀌는 버그 제거
- drop 전후 감각 일치
- 멈칫 원인 추적 단순화
- 유지보수 비용 감소
- threshold/보정 패치 의존 감소

## 최종 결론

인덱스 보드는 `슬롯 좌표 기반 엔진`으로 단순화해야 한다.

- 보드 내용은 logical slot state가 기준
- 화면 좌표는 전부 파생값
- 드래그와 commit은 logical slot 기준
- persistence/undo도 logical state 기준

즉 지금 필요한 것은 예외 보정보다 `모델 좌표`와 `표현 좌표`의 경계를 명확히 하는 것이다.
