# Workspace Mode Parity Plan

작성일: 2026-03-25

## 작업 범위

작업창 모드의 `타이핑`, `활성 카드 전환`, `세로/가로 스크롤 정렬`만 레퍼런스 Gingko Writer 수준의 부드러움과 스내피함으로 끌어올린다.

## 최종 목표

- 작업창 모드가 레퍼런스 영상처럼 “한 번 반응하고, 한 번에 끝나는” motion을 보여야 한다.
- 입력 중에는 지연, 끊김, 뒤늦은 보정 움직임, 두 번 움직이는 느낌이 없어야 한다.
- 활성 카드 전환은 즉시 반응하고, 시각적 settle이 짧고 단조롭게 끝나야 한다.
- 세로/가로 스크롤 정렬은 늦게 따라붙는 2차 motion 없이 끝나야 한다.

## 실패 기준

- 작업창 모드에서 버벅임, 끊김, 늦은 보정 nudge, 2차 motion이 보이면 실패다.
- 타이핑, 활성 카드 전환, 세로/가로 스크롤 정렬 중 하나라도 레퍼런스 체감보다 확실히 떨어지면 실패다.
- “조금 나아졌다”는 기준은 불충분하다. 목표는 레퍼런스 수준의 체감이다.

## 사용자 확정 조건

- 우선순위: `최소 변경 우선, 필요하면 구조 변경 허용`
- 1차 핵심 지표: `타이핑`, `활성 카드 전환`, `세로/가로 스크롤 정렬`
- 단계별로 진행하고, 각 단계가 충분하면 거기서 중단한다.

## 시작 기준점

- 기준 브랜치: `origin/codex/workspace-perf-baseline-20260325`
- 시작 커밋: `0fc7b3b`
- 목적: 이후 모든 성능 개선은 이 기준점 대비 체감과 계측으로 평가한다.

## 레퍼런스 조사 요약

### Gingko Writer가 어떤 앱인가

- 트리형 카드 기반 장문 작성 도구다.
- 좌에서 우로 아이디어를 확장하는 horizontal outliner / corkboard 성격을 가진다.
- 긴 글, 논문, 소설, 보고서, 구조화된 메모 작성에 최적화된 제품이다.

공식 참고:

- https://gingkowriter.com/
- https://docs.gingkowriter.com/

### 현재 레퍼런스로 삼는 버전

- 현재 레퍼런스는 최신 웹 버전이다.
- 공식 README와 FAQ도 최신 버전은 웹 앱이고, 데스크톱 버전은 최신 웹 버전보다 뒤처져 있다고 명시한다.

공식 참고:

- https://github.com/gingko/client
- https://docs.gingkowriter.com/gingko-versions-v1-desktop

### 기술 스택 단서

- 클라이언트 핵심은 Elm이다.
- 현재 클라이언트 저장소는 Elm 0.19.1, Bun, Webpack, esbuild, Tailwind, Playwright 기반이다.
- Electron 패키징 경로도 존재하지만, 핵심 제품 경쟁력은 “웹 버전의 상호작용 품질”에서 이미 증명된다.
- 서버는 Node/Express/TypeScript와 `better-sqlite3`, Redis, WebSocket 계열을 사용한다.

기술 참고:

- https://raw.githubusercontent.com/gingko/client/master/package.json
- https://raw.githubusercontent.com/gingko/client/master/elm.json
- https://raw.githubusercontent.com/gingko/server/master/package.json
- https://raw.githubusercontent.com/gingko/client/desktop/app/package.json

### 조사에서 얻은 핵심 결론

- Gingko Writer의 부드러움은 “네이티브 앱이라서”가 아니라 “모션 경로가 compositor-friendly 하기 때문”으로 보인다.
- 즉, 우리 앱도 작업창 경로를 제대로 분리하면 레퍼런스 수준에 도달할 수 있다.

## 레퍼런스 영상 분석 요약

- 레퍼런스 영상은 큰 화면 변화가 생길 때도 한 프레임 점프로 끝나지 않는다.
- 변화가 5~7프레임에 걸쳐 단조롭게 감쇠하며, 늦은 보정 움직임이 적다.
- 정지 구간은 거의 완전히 멈춰 있고, 움직일 때만 짧고 일관된 ease-out처럼 보인다.
- 체감상 “애니메이션이 많다”가 아니라 “레이아웃을 적게 흔들고, 움직일 것만 부드럽게 움직인다”에 가깝다.

## 현재 앱에서 보이는 구조적 차이

### 작업창

- 메인 작업창은 큰 SwiftUI host와 content fingerprint 기반 invalidation 구조를 갖고 있다.
- 편집 카드가 live `TextEditor`를 직접 물고 있어 입력 중 비용이 높을 가능성이 크다.
- 작업창의 시각 반응과 부수 효과가 아직 강하게 결합되어 있다.

주요 코드 참고:

- `wa/WriterViews.swift`
- `wa/WriterCardViews.swift`

### 인덱스 보드

- 인덱스 보드는 이미 AppKit/CALayer 기반의 성능 경로를 일부 갖고 있다.
- drag tick budget, preview/commit animation duration, baseline logger가 존재한다.
- 즉, 이 앱 내부에도 “예산형 motion pipeline”의 선례가 이미 있다.

주요 코드 참고:

- `wa/WriterIndexBoardSurfaceAppKitPhaseTwo.swift`

### 현재 진단 결론

- 문제의 본질은 easing 부족이 아니라 motion pipeline 일관성 부족이다.
- 작업창은 아직 compositor-first 구조가 아니고, 인덱스 보드는 그 방향으로 일부 가 있다.
- 따라서 작업창 성능 개선은 “애니메이션 숫자 조정”이 아니라 “입력/전환/정렬 경로 분리”가 핵심이다.

## 이번 작업의 절대 원칙

- 작업 범위는 작업창 모드 성능에만 한정한다.
- Focus Mode 의미는 바꾸지 않는다.
- Index View 의미는 바꾸지 않는다.
- 카드 의미, 정렬 의미, undo/redo 의미, split/history 의미는 바꾸지 않는다.
- 먼저 최소 변경으로 시도하고, 레퍼런스 수준이 안 나오면 구조 변경을 허용한다.
- 각 단계는 독립적으로 실행 가능하고, 그 단계만으로 배포 가능한 완성 상태여야 한다.
- 각 단계가 끝날 때마다 사용자가 체감 평가를 하고, 충분하면 중단한다.

## 핵심 성능 지표

### 1. 타이핑

- 키 입력 후 글자가 즉시 반영되어야 한다.
- 입력 중 다른 열/카드가 불필요하게 다시 그려지면 안 된다.
- caret, 레이아웃, 스크롤 보정이 입력감을 해치면 실패다.

### 2. 활성 카드 전환

- active card가 바뀌는 즉시 시각 반응이 나와야 한다.
- 전환 후 카드/열/스크롤이 뒤늦게 다시 움직이면 실패다.
- click, keyboard, restore 경로가 같은 target을 중복으로 밀면 실패다.

### 3. 세로/가로 스크롤 정렬

- 정렬은 한 번에 끝나야 한다.
- fallback, retry, settle이 눈에 보이는 2차 motion을 만들면 실패다.
- 큰 카드나 긴 열에서도 target alignment가 늦게 바뀌면 실패다.

## 단계별 실행 계획

## Phase 0. 계측 고정

### 목적

체감 문제를 수치로 고정하고, 이후 단계가 실제로 좋아졌는지 판단할 기준을 만든다.

### 실행 내용

- 작업창에 `os_signpost` 또는 동등한 계측을 추가한다.
- 아래 세 경로의 시작/끝을 모두 잰다.
  - 키 입력 -> 화면 반영
  - active card 변경 -> caret ready
  - 세로/가로 scroll align 시작 -> settle
- 중복 motion request 수, retry 수, fallback 수, late nudge 수를 함께 기록한다.

### 완료 기준

- 세 지표의 baseline 숫자가 확보된다.
- “어디서 늦는가”를 코드 경로로 바로 연결할 수 있다.

### stop / go

- 계측만으로는 종료하지 않는다.
- 반드시 다음 단계로 진행한다.

## Phase 1. 타이핑 hot path 축소

### 목적

입력 중 active card 외의 영역이 다시 계산되거나 invalidate되지 않도록 줄인다.

### 실행 내용

- 메인 작업창 fingerprint를 다시 분리한다.
- 타이핑과 무관한 상태가 작업창 전체 invalidation을 일으키지 않게 정리한다.
- active editor 버스트 동안 비활성 카드와 열은 inert shell처럼 유지한다.
- 입력 중 scroll/restore/geometry side effect가 섞여 들어오지 않게 끊는다.

### 완료 기준

- 타이핑 중 프레임 드랍과 지연이 유의미하게 줄어든다.
- 입력하는 카드 이외의 열/카드가 흔들리지 않는다.
- 체감상 “타자칠 때 무거운 느낌”이 먼저 사라진다.

### stop / go

- 타이핑이 레퍼런스 수준에 도달하면 Phase 2로 넘어간다.
- 타이핑이 아직 무겁다면 이 단계 안에서 더 판다.

## Phase 2. 활성 카드 전환 단일화

### 목적

한 번의 카드 전환이 여러 경로에서 중복 실행되지 않게 만들고, 전환을 compositor-first 경로로 단순화한다.

### 실행 내용

- click focus, arrow navigation, restore, settle을 하나의 motion owner 아래로 모은다.
- 같은 target에 대한 중복 request를 coalesce한다.
- active card 시각 반응과 무거운 부수 효과를 분리한다.
- 필요하면 incoming/outgoing 카드만 snapshot 또는 shell 기반으로 바꾼다.

### 완료 기준

- active card 전환이 “즉시 반응 + 짧은 settle 1회”로 보인다.
- 카드가 바뀐 뒤 스크롤이 늦게 따라오는 느낌이 줄어든다.
- click과 keyboard 경로의 체감이 비슷해진다.

### stop / go

- 활성 카드 전환이 충분히 스내피하면 Phase 3으로 이동한다.
- late align이나 double motion이 남으면 여기서 더 정리한다.

## Phase 3. 세로/가로 스크롤 정렬 정리

### 목적

정렬을 layout animation이 아니라 scroll engine의 단일 경로로 끝내게 만든다.

### 실행 내용

- horizontal align과 vertical align의 primary engine을 정리한다.
- 일반 경로에서 `proxy.scrollTo`는 fallback 축으로만 축소한다.
- `NSScrollView` / coordinator 기반 정렬이 1차 경로가 되도록 조정한다.
- retry와 settle은 예외 복구용으로만 남긴다.

### 완료 기준

- 좌우 이동 시 한 번의 연속된 가로 motion처럼 보인다.
- 상하 이동 시 한 번의 연속된 세로 motion처럼 보인다.
- 큰 카드와 긴 열에서도 2차 보정 움직임이 줄어든다.

### stop / go

- 세로/가로 정렬이 레퍼런스 수준에 가까우면 사용자 평가 후 중단할 수 있다.
- 부족하면 Phase 4로 진행한다.

## Phase 4. 구조 변경 여부 판정

### 목적

최소 변경으로는 레퍼런스 수준이 나오지 않을 때, 어디까지 구조를 바꿔야 하는지 판정한다.

### 구조 변경 허용 범위

- 작업창의 일부를 AppKit/CALayer 기반 retained surface로 이동
- active card만 live editor 유지
- 비활성 카드/열을 snapshot/shell 기반으로 유지
- layout resolve와 motion compose를 분리

### 원칙

- 대수술은 마지막 단계에서만 한다.
- 단, 레퍼런스 수준에 필요한 변경이면 주저하지 않는다.
- 구조 변경이 들어가더라도 작업 의미는 절대 바꾸지 않는다.

### 완료 기준

- 레퍼런스 수준에 도달하기 위한 최소 구조 변경 범위가 명확해진다.
- 그 범위 안에서만 구현을 시작한다.

## 각 단계 공통 검증 체크리스트

1. 타이핑 중 지연, 끊김, 버벅임이 없는지 확인
2. active card 전환이 즉시 반응하는지 확인
3. 카드 전환 후 스크롤이 늦게 다시 움직이지 않는지 확인
4. 좌우 이동이 한 번의 연속된 motion처럼 보이는지 확인
5. 상하 이동이 한 번의 연속된 motion처럼 보이는지 확인
6. 긴 카드/긴 열에서 late nudge가 줄었는지 확인
7. Focus Mode 기능 의미가 그대로인지 확인
8. Index View 기능 의미가 그대로인지 확인

위 항목 중 기능 변화가 보이면 그 단계는 실패다.

## 중단 규칙

- 각 단계가 끝날 때마다 사용자가 직접 체감 평가한다.
- 사용자가 “이 정도면 충분하다”고 판단하면 즉시 중단한다.
- 만족하지 못하면 다음 단계로 넘어간다.

## 결론

이번 작업은 “작업창을 조금 덜 느리게 만드는 것”이 아니라 “레퍼런스와 같은 반응성 체감까지 도달하는 것”이다.

따라서 이번 계획의 핵심은 아래 한 줄로 요약된다.

`작업창을 SwiftUI 전체 레이아웃 반응 경로에서 분리하고, 입력/전환/정렬을 compositor-first motion pipeline으로 재구성한다.`
