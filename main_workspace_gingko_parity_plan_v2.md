# Main Workspace Gingko Parity Plan v2

상태:
- 이 문서는 `main_workspace_gingko_rearchitecture_plan.md`를 교체한다.
- 이전 계획은 방향은 맞았으나, 데이터 모델 버그 3개를 Phase에 명시하지 않았고, 테스트 불가 구간이 있었고, 포팅 범위가 모호했다.
- 이번 문서는 그 세 가지를 보정한 실행 계획이다.

현재 점수: 10점 만점 기준 3점.
목표 점수: 9점 이상.

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
- 활성 전환: `123/src/elm/Page/Doc.elm:1025`
- 세로 정렬 정책 계산: `123/src/elm/Doc/TreeUtils.elm:358`
- 세로 스크롤 적용: `123/src/shared/doc-helpers.js:197`
- 가로 스크롤 적용: `123/src/shared/doc-helpers.js:247`
- 일반 모드 undo 메뉴 의미: `123/src/electron/menu.js:157`
- 일반 모드 `Cmd+Z` 라우팅: `123/src/electron/renderer.js:63`
- immutable commit 저장: `123/src/electron/main.js:330`

이번 계획에서 "같다"의 의미:
- 같은 이름의 레이어를 쓰는 것이 아니라
- 같은 책임 분해와 같은 순서를 가진다는 뜻이다.

## 이전 시도에서 반복된 실패 패턴

3번의 리팩터링이 모두 패치로 끝난 이유:
1. 기존 SwiftUI 구조 안에서 고치려 했다 — 구조가 수정을 거부한다.
2. 새 경로를 얹고 기존 경로를 남겨뒀다 — dual authority가 생겨서 새 경로가 legacy에 덮어씌워졌다.
3. 렌더 엔진과 독립적인 데이터 모델 버그를 다루지 않았다 — 렌더를 바꿔도 입력 데이터가 틀리면 정렬이 어긋난다.

이번에는:
- 기존 구조 안에서 고치지 않는다. AppKit canvas로 교체한다.
- 새 경로와 기존 경로를 동시에 유지하지 않는다.
- 데이터 모델 버그를 Phase에 명시하고 먼저 고친다.

## 비타협 요구사항

### 1. 활성 전환 hot path

메인 작업창 일반 모드의 활성 전환은 반드시 아래 순서를 따른다.

1. `changeMode`에 해당하는 단일 함수가 활성 카드, 조상, 자손, recent history를 한 번 갱신한다.
2. `getScrollPositions`에 해당하는 단일 함수가 컬럼별 세로 정렬 정책을 한 번 계산한다.
3. 가로/세로 scroll view에 직접 `scrollTop`/`scrollLeft`에 해당하는 offset을 적용한다.

금지:
- 입력 1회에 대해 apply owner가 둘 이상 존재하는 것
- 정렬 성공 여부를 observer와 retry로 사후 보정하는 것

### 2. 세로/가로 정렬

반드시 만족해야 한다.

- 세로 정렬은 징코의 `Center / Before / After / Between / None` 규칙과 같은 의미를 가져야 한다.
- 가로 정렬은 활성 컬럼 중심 정렬 하나만 사용한다.
- 입력 1회에 대해 가로 1회, 필요한 컬럼 세로 1회만 적용한다.
- 적용 직후 추가 verify 보정이 들어오지 않아야 한다.

### 3. column cards는 반드시 parent-child chain이어야 한다

현재 버그:
- `filteredCardsForMainCanvasColumn` (WriterViews.swift:2654)이 level > 1에서 `scenario.filteredCards(atLevel:category:)`를 쓴다.
- 즉 깊은 열은 "현재 부모의 자식 목록"이 아니라 "그 depth의 해당 category 전체"다.
- 징코의 `getScrollPositions`는 각 컬럼이 실제 parent-child chain이라는 것을 전제한다.
- 이 전제가 깨지면 알고리즘을 완벽하게 포팅해도 입력 데이터가 틀려서 결과가 어긋난다.

강제 규칙:
- `getScrollPositions`에 들어가는 column cards는 반드시 현재 active path의 parent-child chain이어야 한다.
- WA의 category 개념은 `TreeProjection` 레이어에서 column cards로 변환한 뒤, `getScrollPositions`에는 징코와 같은 형태로 들어간다.

### 4. undo

undo는 징코의 사용자 모델을 그대로 따라간다.

메인 작업창 일반 모드:
- 카드 편집 중이면 `NSTextView`의 native undo/redo를 사용한다.
- 카드 비편집 상태에서 `Cmd+Z`는 메모리 스냅샷 복원이 아니라 version history undo 의미로 동작한다.
- 지금 WA의 `ScenarioState` 전체 스냅샷 기반 undo를 메인 작업창 일반 모드의 기본 undo로 유지하지 않는다.

이유:
- 현재 전체 스냅샷 undo가 hot path에 무게를 더하고, 복원 경로가 정렬 경로와 엮여 있다.
- 이걸 분리해야 hot path가 가벼워진다.

### 5. 기준 점수

이 계획은 9점 미만이면 실패다.

## 현재 코드에서 확인된 데이터 모델 버그 3개

이 버그들은 렌더 엔진을 교체해도 따라오는 문제다. Phase에 명시적으로 배치한다.

### 버그 A: column cards가 parent-child chain이 아니라 category slice

위치: `WriterViews.swift:2879` `filteredCardsForMainCanvasColumn`
증상: level > 1에서 "현재 부모의 자식"이 아니라 "그 depth의 해당 category 전체"를 반환한다.
영향: 정렬 알고리즘의 입력 데이터가 근본적으로 틀리다. descendant 추적, surrounding policy 모두 영향 받는다.
고칠 곳: Phase 2 `MainWorkspaceTreeProjection`

### 버그 B: viewportKey의 branch identity가 명시적이지 않다

위치: `WriterCardManagement.swift:2160` `mainColumnViewportStorageKey(level:cards:)`
현재 코드: `"level:\(level)|category:\(category)|cards:\(fingerprint)"`
증상: branch identity가 parent ID가 아니라 rendered-card fingerprint에 의존한다. 같은 카드 집합이 다른 branch context에서 렌더될 때 구분이 안 되고, fingerprint가 바뀌면 기존 scroll state가 유실된다.
영향: branch 전환 시 scroll offset, observed frame cache가 불안정하다.
고칠 곳: Phase 1 `MainWorkspaceCanvasView` registry — branch identity를 명시적 parent ID 기반으로 전환

### 버그 C: activePast 갱신 owner가 분산되어 있다

위치: `WriterCardManagement.swift:3618` `recordMainWorkspaceActiveHistory`
증상: history 갱신이 `changeActiveCard`, `handleMainCanvasActiveCardChange`, legacy restore 등 여러 경로에서 각각 일어난다. 징코는 `changeMode` 한 곳에서만 `oldId :: activePast |> List.take 40`을 실행한다 (Doc.elm:1043).
영향: 갱신 자체는 징코와 비슷하게 "target이 바뀌면 갱신"이지만, 여러 경로에서 중복/누락/순서 역전이 생길 수 있다. `resolvedMainWorkspaceVisibleSubtreeChildSelection` (MainWorkspaceScrollPlan.swift:964)이 이 history에 의존하므로 descendant 선택이 불안정해진다.
고칠 곳: Phase 2 `MainWorkspaceDocRuntime.changeMode` — 갱신 owner를 하나로 모은다. 갱신 조건은 징코와 동일하게 유지한다.

## 새 목표 구조

### A. `MainWorkspaceDocRuntime`

역할:
- 징코의 `Page.Doc.changeMode`와 같은 역할

책임:
- active card
- active past (history 오염 문제 포함 — 버그 C 수정)
- ancestors
- descendants
- editing / normal mode 전환
- save-if-needed

강제 규칙:
- 메인 작업창 활성 전환은 이 runtime 하나에서만 결정한다.
- active/history/ancestor/descendant를 서로 다른 곳에서 따로 갱신하지 않는다.
- activePast 갱신은 징코와 동일한 규칙을 따른다: target이 현재 active와 다르면 무조건 `oldId :: activePast |> List.take 40` (Doc.elm:1043). 입력 종류(방향키, 클릭, 프로그래밍적 변경)를 구분하지 않는다.
- 현재 WA의 `recordMainWorkspaceActiveHistory`가 문제인 이유는 "너무 많이 갱신해서"가 아니라 "갱신 owner가 여러 곳에 분산되어 있어서"다. changeMode 하나에서만 갱신하되, 갱신 조건 자체는 징코와 같게 유지한다.

### B. `MainWorkspaceTreeProjection`

역할:
- 현재 시나리오를 징코가 기대하는 "column tree" 형태로 투영한다.

책임:
- visible columns
- level별 visible cards (반드시 parent-child chain — 버그 A 수정)
- active 위치
- category boundary 이동 정보

강제 규칙:
- 각 컬럼의 cards는 active path 상의 부모로부터 파생된 실제 자식 목록이어야 한다.
- WA의 category 필터링은 이 레이어에서 처리하되, 결과는 징코의 column 구조와 같은 의미를 가져야 한다.
- 이 레이어는 순수 데이터 계산만 한다.

### C. `MainWorkspaceScrollPositions`

역할:
- 징코의 `getScrollPositions`를 Swift로 옮긴 레이어

입력:
- `MainWorkspaceTreeProjection`이 만든 column cards (parent-child chain 보장됨)
- active card 위치
- ancestor/descendant 집합

출력:
- 컬럼별 `Center / Before / After / Between / None`
- 활성 컬럼 index
- instant 여부

포팅 범위:
- 포팅하는 것은 column policy 결정 알고리즘의 의미(center/before/after/between/none)다.
- WA의 category/linked card 개념은 TreeProjection 레이어에서 column cards로 변환한 뒤, ScrollPositions에는 징코와 같은 형태로 들어간다.
- 데이터 구조까지 징코와 같게 만드는 것이 아니다.

강제 규칙:
- 메인 작업창 세로 정렬 정책은 이 함수 하나에서만 계산한다.
- depth cutoff 없음 — 징코와 동일하게 모든 컬럼에 적용.

### D. `MainWorkspaceCanvasView`

역할:
- 징코의 `scrollColumns`, `scrollHorizTo`, `scrollTo`에 해당하는 AppKit canvas

책임:
- 컬럼 scroll view 직접 보유
- 가로 scroll view 직접 보유
- target card view lookup (branch context 포함 registry — 버그 B 수정)
- column index lookup
- direct scroll offset 적용

강제 규칙:
- 세로 정렬 적용은 `columnScrollView.contentView.bounds.origin.y = targetY` 한 번으로 끝난다.
- 가로 정렬 적용은 `horizontalScrollView.contentView.bounds.origin.x = targetX` 한 번으로 끝난다.
- scroll 직전에 **대상 column의 documentView에만** `layoutSubtreeIfNeeded` 허용. 전체 canvas에 광범위하게 돌리는 것은 금지.
- verify ladder 금지.
- target view가 아직 없으면 다음 run loop 1회만 defer. 그래도 없으면 포기하고 다음 상태 변경을 기다린다.

layout 타이밍 참고:
- 브라우저는 `getBoundingClientRect()` 호출 시 pending layout을 자동으로 flush한다. AppKit은 그렇지 않다.
- 따라서 새 카드를 추가한 직후 frame을 읽으려면 해당 view에 `layoutSubtreeIfNeeded`를 한 번 불러야 한다. 이건 제약이 아니라 API 사용법이다.
- 네이티브 AppKit은 브라우저보다 스크롤 제어가 더 직접적이다. `NSScrollView.contentView.bounds.origin` 직접 할당은 JavaScript `scrollTop` 할당보다 오버헤드가 적다.

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
- 모델은 반드시 "immutable object + head ref"여야 한다.
- 현재 WA의 in-memory scenario snapshot undo를 일반 모드 기본 undo로 계속 쓰지 않는다.

## 구현 단계

### Phase 0. Parity Harness

목적:
- 징코와 WA를 같은 문서 구조에서 비교 가능한 상태로 만든다.

작업:

**scroll parity golden**:
- deep tree fixture 3개 준비
- 활성 전환 시 기대 column policy golden 저장
- 징코 기준 active/history/ancestor/descendant 결과 golden 저장
- 징코 기준 세로/가로 target offset golden 저장

**undo parity golden**:
- 아래 시나리오 각각에 대해 징코 기준 trace golden 저장:
  - edit card → save (ESC) → Cmd+Z
  - create child → type → save → Cmd+Z
  - delete card → Cmd+Z
  - move card (방향키) → Cmd+Z
  - cut card → paste → Cmd+Z
  - edit card → Cmd+Z (편집 중 text undo)
  - Cmd+Z 연타 3회 → Cmd+Shift+Z 1회
- 각 trace에는 "commit이 만들어지는 시점", "Cmd+Z가 어디로 돌아가는지", "tree 상태"를 포함

**체감 체크리스트**:
- 메인 작업창 체감 점수 체크리스트 작성

완료 기준:
- 이후 scroll 단계는 "징코와 같은 column policy인가"로 판정 가능해야 한다.
- 이후 undo 단계는 "징코와 같은 commit boundary와 restore 결과인가"로 판정 가능해야 한다.

### Phase 1. AppKit Canvas 최소 골격

목적:
- 테스트 가능한 canvas를 먼저 세운다.
- 이후 Phase에서 로직을 연결할 때 즉시 화면에서 체감 확인이 가능하게 한다.

이전 실패 패턴:
- 로직을 먼저 만들고 나중에 canvas에 연결하면, "로직은 맞는데 연결하면 안 맞는다"가 반복된다.
- canvas 골격이 먼저 있어야 changeMode와 getScrollPositions를 연결하면서 즉시 체감 테스트가 가능하다.

작업:
- `MainWorkspaceCanvasView` (NSViewRepresentable wrapping AppKit)
- 가로 NSScrollView + 컬럼별 세로 NSScrollView 구조
- 카드 렌더는 최소한 text + active tint 수준 (경량 chrome)
- column/card view lookup registry (branch context 포함 — 버그 B 해결 기반)
- direct scroll offset 적용 (`bounds.origin` 직접 할당)
- 기존 SwiftUI main canvas와 스위치 가능한 상태 (feature flag). **이 flag는 Phase 4 완료 시 반드시 제거한다.** Phase 4 종료 후에는 일반 모드에서 새 canvas만 사용하며, old/new 공존 상태를 남기지 않는다.

완료 기준:
- canvas에 카드가 보이고, `bounds.origin`을 직접 쓰면 스크롤이 움직인다.
- registry에서 특정 card의 frame을 조회할 수 있다.

### Phase 2. TreeProjection + changeMode 포팅

목적:
- 데이터 모델을 징코 전제에 맞게 고치고, 활성 전환을 단일 함수로 옮긴다.

작업:

**TreeProjection (버그 A 수정)**:
- `MainWorkspaceTreeProjection` 도입
- 각 컬럼의 cards를 active path의 parent-child chain으로 생성
- WA category 필터링을 이 레이어에서 처리하되, 출력은 징코의 column 구조와 같은 의미
- `filteredCardsForMainCanvasColumn`의 category slice 방식을 대체

**changeMode (버그 C 수정)**:
- `MainWorkspaceDocRuntime.changeMode(...)` 도입
- active card, active past, ancestors, descendants를 한 함수에서 갱신
- activePast 갱신은 징코와 동일: target이 현재 active와 다르면 `oldId :: activePast |> List.take 40` (Doc.elm:1043). 입력 종류를 구분하지 않음.
- 핵심은 "언제 갱신하느냐"가 아니라 "어디서 갱신하느냐" — changeMode 하나에서만 갱신. 기존의 `recordMainWorkspaceActiveHistory` 등 분산된 갱신 경로를 대체.

**canvas 연결**:
- Phase 1의 canvas에 TreeProjection 결과를 연결
- 체감 테스트: active 전환 시 올바른 parent-child chain이 컬럼에 표시되는지 확인

완료 기준:
- golden fixture 기준, 모든 level의 column cards가 parent-child chain이다.
- 활성/history/relation 갱신 owner가 하나다.
- activePast 갱신이 징코와 같은 조건으로 같은 결과를 만든다.
- canvas에 렌더된 카드의 높이/inset/text layout이 production과 동일하다 (production card metrics identical). Phase 1의 minimal chrome이 실제와 다른 metrics를 가지면 이 시점에서 보정한다. 카드 metrics가 틀리면 getScrollPositions가 맞아도 target offset이 틀린다.

### Phase 3. getScrollPositions + Direct Scroll 포팅

목적:
- 세로/가로 정렬을 징코와 같은 계산으로 만들고, canvas에서 직접 적용한다.

작업:

**getScrollPositions**:
- 징코 `TreeUtils.getScrollPositions`의 column policy 결정 알고리즘을 Swift로 포팅
- 포팅 범위: 알고리즘 의미 (center/before/after/between/none). 데이터 구조가 아님.
- TreeProjection이 만든 parent-child chain을 입력으로 받음
- depth cutoff 없음 — 모든 컬럼에 적용
- golden fixture와 1:1 비교

**세로 스크롤 적용**:
- 징코 `scrollTo` 수식 포팅: clamped center (`adjustedHeight = min(rect.height, viewportHeight - 51)`)
- `columnScrollView.contentView.bounds.origin.y = targetY` 한 번으로 끝냄
- scroll 직전에 대상 column documentView에만 `layoutSubtreeIfNeeded` (필요 시)

**가로 스크롤 적용**:
- 징코 `scrollHorizTo` 수식 포팅: `col.offsetLeft + 0.5 * (col.offsetWidth - appEl.offsetWidth)`
- `horizontalScrollView.contentView.bounds.origin.x = targetX` 한 번으로 끝냄

**dual authority 제거**:
- `handleMainColumnObservedTargetFrameChange` → `scrollToFocus` 경로 차단
- legacy intent 경로가 새 canvas 활성 시 vertical authority를 못 잡게 막음
- 이 시점에서 세로 정렬 owner는 정확히 하나

완료 기준:
- golden fixture 기준 징코와 동일한 scroll policy가 나온다.
- 입력 1회당 가로 1회, 세로 1회만 적용된다.
- verify ladder가 없다.
- 적용 직후 두 번째 보정이 없다.

### Phase 4. 편집 세션 이관

목적:
- 인라인 편집을 새 canvas에서 동작하게 한다.

작업:
- `MainWorkspaceEditSession` 도입
- NSTextView 편집기를 canvas 내부에서 호스팅
- edit enter/save/exit 경로
- model overwrite 차단 (활성 편집기 first responder 보호)
- 편집 중 typing undo는 NSTextView가 담당

완료 기준:
- 새 canvas에서 카드 편집이 동작한다.
- 편집 중 caret jump가 없다.
- 편집 중 주변 컬럼 정렬이 편집기를 흔들지 않는다.

### Phase 5. Undo 교체

목적:
- undo를 징코와 같은 사용자 모델로 바꾼다.

**commit boundary 정의 (징코 기준)**:

아래 각 사용자 동작이 하나의 commit을 만든다.

| 동작 | commit 생성 시점 | 근거 |
|------|-----------------|------|
| 카드 편집 저장 (ESC, Enter, 클릭으로 exit) | edit mode 종료 시 | Doc.elm:529 |
| 카드 삭제 (Ctrl+Backspace) | 즉시 | Doc.elm:1326 |
| 카드 잘라내기 (Ctrl+X) | 즉시 (copy + delete) | Doc.elm:1410 |
| 카드 붙여넣기 (Ctrl+V) | 즉시 | Doc.elm:1431 |
| 카드 이동 (Ctrl+방향키 또는 드래그) | 즉시 | Doc.elm:1528 |
| 카드 위로 합치기 (Ctrl+Shift+K) | 즉시 | Doc.elm:1771 |
| 카드 아래로 합치기 (Ctrl+Shift+J) | 즉시 | Doc.elm:1829 |
| 체크박스 토글 (클릭) | 즉시 | Doc.elm:637 |
| 외부 텍스트 드래그-드롭 | 즉시 | Doc.elm:1995 |
| 편집 중 자동 저장 (241초 타이머) | 타이머 만료 시 | Doc.elm:529 |

commit을 만들지 **않는** 동작:

| 동작 | 이유 |
|------|------|
| 새 카드 생성 (Ctrl+K/J 등) | edit mode로 진입만 함 — 저장은 exit 시 |
| 편집 중 타이핑 | dirty flag만 설정 — commit은 exit 또는 auto-save 시 |
| 카드 복사 (Ctrl+C) | clipboard만 — commit은 paste 시 |
| 카드 선택/이동 (방향키) | 네비게이션만 — 구조 변경 아님 |

**Cmd+Z 동작 (일반 모드)**:
- History Slider UI를 열고, git commit graph에서 이전 commit으로 checkout한다.
- 개별 동작 단위 undo가 아니라, commit 단위 tree 상태 복원이다.
- 근거: `renderer.js:63` → `Keyboard "mod+z"` → Elm에서 history slider 표시

작업:
- `MainWorkspaceHistoryStore` 도입
- immutable commit object 저장 (`.wtf/history_store/`)
- 위 표의 commit boundary를 그대로 구현
- 일반 모드 비편집 `Cmd+Z` → version history undo (commit 단위 checkout)
- 일반 모드 편집 중 `Cmd+Z` → NSTextView native undo
- 기존 `ScenarioState` 전체 스냅샷 undo를 일반 모드 경로에서 제거

완료 기준:
- `Cmd+Z` 의미가 징코와 같다.
- 위 표의 10가지 동작이 각각 commit을 만든다.
- commit을 만들지 않는 동작이 commit을 만들지 않는다.
- Phase 0의 undo trace golden과 1:1 비교해서 같은 결과가 나온다.
- 일반 모드에서 whole-scenario snapshot restore가 기본 undo가 아니다.

### Phase 6. Old Path 삭제

목적:
- 기존 WA식 hot path를 실제로 지운다.

삭제 대상:
- `MainCanvasScrollCoordinator.NavigationIntent`
- `navigationIntentTick`
- `publishMainColumnNavigationIntent`
- `handleMainColumnNavigationIntent`
- `rerouteLegacyMainColumnAlignmentToScrollPlanIfNeeded`
- `rerouteLegacyMainColumnIntentToScrollPlanIfNeeded`
- `scheduleMainColumnFocusVerification`
- `handleMainColumnNavigationSettle`
- `handleMainColumnObservedTargetFrameChange` → `scrollToFocus` 경로
- click-focus 전용 horizontal retry 경로
- restore retry를 hot path로 재진입시키는 경로
- `PreferenceKey` 기반 상시 카드 프레임 관찰
- `boundsDidChange` → state write → re-evaluate 루프
- 일반 모드에서의 `mainTypingUndoStack`
- 일반 모드에서의 `undoStack`, `redoStack` 기본 경로
- 기존 `MainWorkspaceScrollPlan` 기반 범용 계획/검증 구조
- 기존 `MainWorkspaceScrollDriver`의 verify/retry ownership

완료 기준:
- 메인 작업창 일반 모드 코드만 읽어도 징코식 경로가 보인다.
- 메인 작업창에서 old path symbol이 dead code가 아니라 실제로 제거된다.

## 각 Phase 완료 원칙

각 단계 완료 기준:
1. 새 경로 추가
2. 기존 hot path 호출 제거
3. dead code 삭제
4. 화면에서 체감 테스트

새 경로를 얹고 기존 경로를 남겨두는 방식은 실패다.

## 수용 기준

아래를 모두 만족해야 완료다.

1. 활성 전환 hot path가 `changeMode -> getScrollPositions -> direct scroll`로 읽힌다.
2. 메인 작업창 일반 모드에서 기존 `MainWorkspaceScrollPlan`과 legacy intent가 hot path가 아니다.
3. 상하 이동 시 세로 정렬은 한 번에 끝난다.
4. 좌우 이동 시 가로 정렬은 한 번에 끝난다.
5. 입력 1회에 대해 "잠깐 뒤 두 번째 보정"이 없다.
6. 모든 컬럼의 cards가 parent-child chain이다 (category slice가 아니다).
7. branch 전환 시 viewport state가 오염되지 않는다.
8. activePast 갱신이 징코와 같은 조건으로 같은 결과를 만든다.
9. 일반 모드 편집 중 undo는 native text undo다.
10. 일반 모드 비편집 `Cmd+Z`는 version history undo다.
11. 일반 모드 기본 undo가 `ScenarioState` 전체 snapshot 복원이 아니다.
12. deep fixture 기준 사용자가 9점 이상을 준다.

## 금지

- 현 구조 위에 또 다른 patch layer를 얹는 것
- 일반 모드에서 old/new hot path를 동시에 유지하는 것
- 일반 모드 undo에 snapshot restore를 남겨두는 것
- 세로 정렬 실패를 retry와 verify로 감추는 것
- 전체 canvas에 광범위한 `layoutSubtreeIfNeeded`를 돌리는 것
- 로직을 먼저 만들고 canvas를 나중에 붙이는 것 (테스트 불가 구간 금지)
- "체감상 조금 나아졌다"를 완료로 선언하는 것

## 최종 선언

이번 계획은 기존 WA 메인 작업창을 "최적화"하는 계획이 아니다.

이번 계획은:
- 징코 문서 모드의 핵심 실행 경로를
- WA 메인 작업창 일반 모드에
- 알고리즘과 사용자 모델 수준에서 다시 이식하는 계획이다.

이전 3번의 실패에서 배운 것:
- 기존 구조 안에서는 안 된다.
- 새 경로를 얹고 기존을 남기면 안 된다.
- 데이터 모델 버그를 안 고치면 렌더를 바꿔도 안 된다.

성공 조건은 명확하다.
- 사용자가 더 이상 "하늘과 땅 차이"라고 느끼지 않아야 한다.
- 점수로는 9점 이상이어야 한다.
