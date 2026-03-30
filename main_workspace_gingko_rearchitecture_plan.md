# Main Workspace Gingko Parity Reset Plan

상태:
- 이 문서는 기존 `main_workspace_gingko_rearchitecture_plan.md`를 전면 교체한다.
- 기존 계획은 메인 작업창을 징코처럼 "다시 만든다"는 목표를 충분히 강제하지 못했다.
- 현재 상태 평가는 10점 만점 기준 3점이다.
- 이번 문서의 목표는 메인 작업창 체감 품질을 9점 이상으로 끌어올리는 것이다.

작업 범위 한 줄:
- 메인 작업창 일반 모드를 징코의 `changeMode -> getScrollPositions -> direct scroll` 실행 경로와 undo 철학에 맞춰 다시 만든다.

## 목표

이 작업의 목표는 "더 빨라 보이게"가 아니다.

목표:
- 메인 작업창 활성 전환의 hot path를 징코처럼 짧고 결정적으로 만든다.
- 세로 정렬과 가로 정렬이 한 번에 맞게 만든다.
- undo 동작을 징코와 같은 사용자 모델로 바꾼다.
- 기존 WA의 복잡한 observer/retry/restore 구조를 메인 작업창 hot path에서 제거한다.

한 문장으로:
- 메인 작업창 일반 모드는 더 이상 WA식 범용 상태 트리의 일부가 아니라, 징코 문서 모드와 같은 구조를 가진 독립 실행 경로가 된다.

## 기준 구현

이번 작업의 기준은 WA 기존 구현이 아니라 징코 구현이다.

반드시 맞춰야 하는 기준 코드:
- 활성 전환: `/Users/three/app_build/wa/123/src/elm/Page/Doc.elm:1025`
- 세로 정렬 정책 계산: `/Users/three/app_build/wa/123/src/elm/Doc/TreeUtils.elm:358`
- 세로 스크롤 적용: `/Users/three/app_build/wa/123/src/shared/doc-helpers.js:197`
- 가로 스크롤 적용: `/Users/three/app_build/wa/123/src/shared/doc-helpers.js:247`
- 일반 모드 undo 메뉴 의미: `/Users/three/app_build/wa/123/src/electron/menu.js:157`
- 일반 모드 `Cmd+Z` 라우팅: `/Users/three/app_build/wa/123/src/electron/renderer.js:63`
- immutable commit 저장: `/Users/three/app_build/wa/123/src/electron/main.js:330`

이번 계획에서 "같다"의 의미:
- 같은 이름의 레이어를 쓰는 것이 아니라
- 같은 책임 분해와 같은 순서를 가진다는 뜻이다.

## 비타협 요구사항

### 1. 활성 전환 hot path

메인 작업창 일반 모드의 활성 전환은 반드시 아래 순서를 따른다.

1. `changeMode`에 해당하는 단일 함수가 활성 카드, 조상, 자손, recent history를 한 번 갱신한다.
2. `getScrollPositions`에 해당하는 단일 함수가 컬럼별 세로 정렬 정책을 한 번 계산한다.
3. 가로/세로 scroll view에 직접 `scrollTop`/`scrollLeft`에 해당하는 offset을 적용한다.

금지:
- `snapshot -> scroll plan -> scroll driver -> verify ladder` 같은 중간 레이어를 hot path에 두는 것
- 입력 1회에 대해 apply owner가 둘 이상 존재하는 것
- 정렬 성공 여부를 observer와 retry로 사후 보정하는 것

### 2. 세로/가로 정렬

반드시 만족해야 한다.

- 세로 정렬은 징코의 `Center / Before / After / Between / None` 규칙과 같은 의미를 가져야 한다.
- 가로 정렬은 활성 컬럼 중심 정렬 하나만 사용한다.
- 입력 1회에 대해 가로 1회, 필요한 컬럼 세로 1회만 적용한다.
- 적용 직후 추가 verify 보정이 들어오지 않아야 한다.

### 3. undo

undo는 징코의 사용자 모델을 그대로 따라간다.

메인 작업창 일반 모드:
- 카드 편집 중이면 `NSTextView`의 native undo/redo를 사용한다.
- 카드 비편집 상태에서 `Cmd+Z`는 메모리 스냅샷 복원이 아니라 version history undo 의미로 동작한다.
- 지금 WA의 `ScenarioState` 전체 스냅샷 기반 undo를 메인 작업창 일반 모드의 기본 undo로 유지하지 않는다.

즉:
- 텍스트 편집 undo와 문서 히스토리 undo를 분리한다.
- 징코처럼 "편집 중 텍스트 undo"와 "일반 모드 history undo"가 다른 경로여야 한다.

### 4. 기준 점수

이 계획은 9점 미만이면 실패다.

판정 기준:
- 사용자가 징코와 비교해도 "하늘과 땅 차이"가 아니라 "거의 같다"라고 느껴야 한다.
- 정렬이 한 번에 맞지 않거나, 두 번째 보정이 보이면 실패다.
- undo가 지금처럼 "앱 상태 전체 snapshot 복원" 느낌이면 실패다.

## 현재 구조에 대한 판정

현재 WA 메인 작업창은 아래 이유로 징코와 거리가 멀다.

1. hot path가 여전히 길다.
- 현재는 `MainWorkspaceScrollPlan`, `MainWorkspaceScrollDriver`, surface controller, render state fingerprint가 함께 움직인다.
- 징코보다 책임 레이어가 많다.

2. 세로 정렬 owner가 너무 많다.
- surface, column observer, geometry cache, restore, verify의 흔적이 남아 있다.
- 그래서 정렬이 한 번에 맞지 않는 회귀가 반복된다.

3. undo 철학이 다르다.
- 현재 WA는 `ScenarioState` 전체 스냅샷을 메모리에 쌓아 복원한다.
- 징코는 일반 모드에서 immutable history/commit 관점으로 undo를 다룬다.

4. 메인 작업창이 아직도 "큰 SwiftUI 상태 트리"의 일부다.
- 징코는 문서 모드의 핵심 경로가 훨씬 더 얇다.

## 새 목표 구조

이번에는 구조를 아래처럼 다시 잡는다.

### A. `MainWorkspaceDocRuntime`

역할:
- 징코의 `Page.Doc.changeMode`와 같은 역할

책임:
- active card
- active past
- ancestors
- descendants
- editing / normal mode 전환
- save-if-needed

강제 규칙:
- 메인 작업창 활성 전환은 이 runtime 하나에서만 결정한다.
- active/history/ancestor/descendant를 서로 다른 곳에서 따로 갱신하지 않는다.

### B. `MainWorkspaceTreeProjection`

역할:
- 현재 시나리오를 징코가 기대하는 "column tree" 형태로 투영한다.

책임:
- visible columns
- level별 visible cards
- active 위치
- category boundary 이동 정보

중요:
- 이 레이어는 순수 데이터 계산만 한다.

### C. `MainWorkspaceScrollPositions`

역할:
- 징코의 `getScrollPositions`를 Swift로 그대로 옮긴 레이어

출력:
- 컬럼별 `Center / Before / After / Between / None`
- 활성 컬럼 index
- instant 여부

강제 규칙:
- 메인 작업창 세로 정렬 정책은 이 함수 하나에서만 계산한다.
- 지금의 범용 `MainWorkspaceScrollPlan`은 일반 모드 hot path에서 제거한다.

### D. `MainWorkspaceCanvasView`

역할:
- 징코의 `scrollColumns`, `scrollHorizTo`, `scrollTo`에 해당하는 AppKit canvas

책임:
- 컬럼 scroll view 직접 보유
- 가로 scroll view 직접 보유
- target card view lookup
- column index lookup
- direct scroll offset 적용

강제 규칙:
- 세로 정렬 적용은 `columnScrollView.contentView.bounds.origin.y = targetY` 한 번으로 끝난다.
- 가로 정렬 적용은 `horizontalScrollView.contentView.bounds.origin.x = targetX` 한 번으로 끝난다.
- broad `layoutSubtreeIfNeeded()` 호출 금지
- verify ladder 금지
- target view가 아직 없으면 다음 run loop 1회만 defer

### E. `MainWorkspaceEditSession`

역할:
- 일반 모드 카드 편집 세션 관리

책임:
- 현재 편집기 responder 소유
- edit enter / save / exit
- native text undo 연결
- model overwrite 차단

강제 규칙:
- 편집 중 typing undo는 `NSTextView`가 담당한다.
- 일반 모드 문서 undo와 섞지 않는다.

### F. `MainWorkspaceHistoryStore`

역할:
- 징코식 immutable commit/history 모델

책임:
- commit object append
- head ref
- checkout / restore source
- 일반 모드 undo의 backing store

구현 원칙:
- 저장 엔진은 `.wtf` 내부 key-value store 또는 sqlite table일 수 있다.
- 하지만 모델은 반드시 "immutable object + head ref"여야 한다.
- 현재 WA의 in-memory scenario snapshot undo를 일반 모드 기본 undo로 계속 쓰지 않는다.

## 저장 구조 결정

현재 `.wtf` 패키지는 유지한다.

대신 메인 작업창 일반 모드 undo/history는 아래처럼 재편한다.

- 기존 시나리오 카드 저장:
  - 계속 `.wtf` 내부 JSON + card text 파일 유지 가능
- 새 history store:
  - `.wtf/history_store/` 하위에 immutable commit object 저장
  - commit graph + head ref + metadata 유지

즉:
- 카드 본문 저장 구조와
- undo/history 구조를 분리한다.

목적:
- 사용자는 여전히 `.wtf`를 쓴다.
- 그러나 일반 모드 undo는 징코처럼 commit 기반이 된다.

## 기존 구조에서 폐기할 것

메인 작업창 일반 모드 hot path에서 제거 대상:
- `MainWorkspaceScrollPlan` 기반 범용 계획/검증 구조
- `MainWorkspaceScrollDriver`의 verify/retry ownership
- `navigationFingerprint` 기반 hot path 재실행
- `PreferenceKey` 기반 상시 프레임 관찰
- `boundsDidChange -> state write -> re-evaluate` 루프
- `ScenarioState` 전체 스냅샷 기반 일반 undo
- 일반 모드에서의 `mainTypingUndoStack`
- 일반 모드에서의 `undoStack`, `redoStack` 기본 경로

남겨도 되는 것:
- 포커스 모드 전용 undo
- 인덱스보드 전용 undo
- `.wtf` 파일 저장 인프라

## 구현 원칙

### 1. 더 이상 "현 구조를 다듬지 않는다"

금지:
- suppress flag 추가
- retry 횟수 조정
- delay 숫자 조정
- observer를 남긴 채 owner만 교체

이번에는 포팅한다.

### 2. 알고리즘 parity를 먼저 맞춘다

순서:
- 징코의 `changeMode`
- 징코의 `getScrollPositions`
- 징코의 `scrollColumns / scrollHorizTo`
- 징코의 undo 의미

이 순서가 바뀌면 안 된다.

### 3. 한 단계씩 삭제까지 완료한다

각 단계 완료 기준:
- 새 경로 추가
- 기존 hot path 호출 제거
- dead code 삭제

새 경로를 얹고 기존 경로를 남겨두는 방식은 실패다.

## 구현 단계

### Phase 0. Parity Harness

목적:
- 징코와 WA를 같은 문서 구조에서 비교 가능한 상태로 만든다.

작업:
- deep tree fixture 3개 준비
- 활성 전환 시 기대 column policy golden 저장
- 징코 기준 active/history/ancestor/descendant 결과 golden 저장
- 징코 기준 세로/가로 target offset golden 저장
- 메인 작업창 체감 점수 체크리스트 작성

완료 기준:
- 이후 단계는 모두 "징코와 같은 결과인가"로 판정 가능해야 한다.

### Phase 1. `changeMode` 포팅

목적:
- 활성 전환의 중심을 징코와 같은 단일 함수로 옮긴다.

작업:
- `MainWorkspaceDocRuntime.changeMode(...)` 도입
- active card, active past, ancestors, descendants를 한 함수에서 갱신
- 일반 모드 편집 enter/exit도 이 경로에서 관리

완료 기준:
- 메인 작업창 일반 모드에서 active/history/relation 갱신 owner가 하나다.

### Phase 2. `getScrollPositions` 포팅

목적:
- 세로 정렬 정책을 징코와 같은 계산으로 만든다.

작업:
- 징코 `TreeUtils.getScrollPositions`를 Swift로 그대로 포팅
- output enum도 `Center / Before / After / Between / None` 의미를 유지
- golden fixture와 1:1 비교

완료 기준:
- fixture 기준 징코와 동일한 scroll policy가 나온다.

### Phase 3. Direct Scroll Canvas

목적:
- `scrollTop/scrollLeft` 직접 적용 경로를 만든다.

작업:
- `MainWorkspaceCanvasView.scrollColumns(...)`
- `MainWorkspaceCanvasView.scrollHorizTo(...)`
- 컬럼/카드 view lookup registry 구현
- direct offset apply 구현

완료 기준:
- 입력 1회당 direct apply 1회만 발생한다.
- verify ladder가 없다.

### Phase 4. 일반 모드 렌더 교체

목적:
- 메인 작업창 일반 모드를 징코식 imperative canvas에 완전히 연결한다.

작업:
- 기존 surface/controller/render fingerprint 경로 제거
- 일반 모드 column/card mount를 canvas registry 방식으로 교체
- geometry 상시 publish 제거

완료 기준:
- 일반 모드 hot path에서 SwiftUI observer 기반 재정렬이 사라진다.

### Phase 5. Undo / History 교체

목적:
- undo를 징코와 같은 사용자 모델로 바꾼다.

작업:
- 일반 모드 편집 중: `NSTextView` native undo
- 일반 모드 비편집: version history undo
- immutable commit store 도입
- 기존 scenario snapshot undo를 일반 모드 경로에서 제거

완료 기준:
- `Cmd+Z` 의미가 징코와 같아진다.
- 일반 모드에서 whole-scenario snapshot restore가 기본 undo가 아니다.

### Phase 6. Old Path 삭제

목적:
- 기존 WA식 hot path를 실제로 지운다.

작업:
- 일반 모드에서 old scroll plan/driver 삭제
- 일반 모드 undo snapshot stack 삭제
- 남은 adapter 정리

완료 기준:
- 메인 작업창 일반 모드 코드만 읽어도 징코식 경로가 보인다.

## 수용 기준

아래를 모두 만족해야 완료다.

1. 활성 전환 hot path가 `changeMode -> getScrollPositions -> direct scroll`로 읽힌다.
2. 메인 작업창 일반 모드에서 `MainWorkspaceScrollPlan`과 `MainWorkspaceScrollDriver`가 hot path가 아니다.
3. 상하 이동 시 세로 정렬은 한 번에 끝난다.
4. 좌우 이동 시 가로 정렬은 한 번에 끝난다.
5. 입력 1회에 대해 "잠깐 뒤 두 번째 보정"이 없다.
6. 일반 모드 편집 중 undo는 native text undo다.
7. 일반 모드 비편집 `Cmd+Z`는 version history undo다.
8. 일반 모드 기본 undo가 `ScenarioState` 전체 snapshot 복원이 아니다.
9. deep fixture 기준 사용자가 9점 이상을 준다.

## 금지

- 현 구조 위에 또 다른 patch layer를 얹는 것
- 일반 모드에서 old/new hot path를 동시에 유지하는 것
- 일반 모드 undo에 snapshot restore를 남겨두는 것
- 세로 정렬 실패를 retry와 verify로 감추는 것
- "체감상 조금 나아졌다"를 완료로 선언하는 것

## 최종 선언

이번 계획은 기존 WA 메인 작업창을 "최적화"하는 계획이 아니다.

이번 계획은:
- 징코 문서 모드의 핵심 실행 경로를
- WA 메인 작업창 일반 모드에
- 알고리즘과 사용자 모델 수준에서 다시 이식하는 계획이다.

성공 조건은 명확하다.

- 사용자가 더 이상 "하늘과 땅 차이"라고 느끼지 않아야 한다.
- 점수로는 9점 이상이어야 한다.
