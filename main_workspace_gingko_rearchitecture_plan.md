# Main Workspace Gingko Rearchitecture Plan

상태:
- 이 문서는 `focus_mode_gingko_rearchitecture_plan.md`를 대체한다.
- 잘못된 범위였던 `포커스 모드` 계획은 폐기하고, 징코 카피 대상을 `메인 작업창 모드`로 다시 고정한다.

작업 범위 한 줄:
- 징코 라이터의 메인 작업창 카드 이동, 컬럼 정렬, 세로/가로 스크롤 질감을 우리 앱의 메인 작업창 모드에 그대로 복제한다.

배수의 진 선언:
- 이 작업은 메인 작업창에서 징코의 가벼운 질감을 재현하는 것이 목적이다.
- 숫자 튜닝, suppress flag 추가, retry 횟수 조정 같은 보정성 수정은 성공으로 간주하지 않는다.
- 메인 작업창의 주 경로가 징코처럼 단순해지지 않으면 이 계획은 실패다.

## 범위

이 문서의 대상:
- `showFocusMode == false` 인 메인 작업창
- 메인 작업창의 카드 활성 전환
- 메인 작업창의 세로 컬럼 스크롤
- 메인 작업창의 가로 캔버스 스크롤
- 메인 작업창의 활성 편집기 보호

이 문서의 비범위:
- 포커스 모드
- 인덱스카드 뷰
- 히스토리 뷰
- 히스토리 프리뷰 스크롤
- 인덱스 보드 전용 AppKit surface
- 포커스 모드 caret ensure 체계
- 포커스 모드 텍스트 에디터 geometry 조정
- 메인 작업창 밖의 뷰 구조 변경

비범위 파일:
- `wa/WriterFocusMode.swift`
- `wa/WriterHistoryView.swift`
- `wa/WriterIndexBoardPhaseTwo.swift`
- `wa/WriterIndexBoardPhaseThree.swift`
- `wa/WriterIndexBoardSurfaceAppKitPhaseTwo.swift`

주 작업 파일:
- `wa/WriterKeyboardHandlers.swift`
- `wa/WriterCardManagement.swift`
- `wa/WriterViews.swift`
- `wa/MainCanvasScrollCoordinator.swift`
- `wa/WriterCardViews.swift`
- `wa/WriterSharedTypes.swift`

## 이 문서가 근거로 삼는 코드

징코 메인 작업창에서 다시 읽은 코드:
- `/tmp/gingko-client/src/elm/Page/Doc.elm`
- `/tmp/gingko-client/src/elm/Doc/TreeUtils.elm`
- `/tmp/gingko-client/src/shared/doc-helpers.js`
- `/tmp/gingko-client/src/static/style.css`

우리 앱 메인 작업창에서 다시 읽은 코드:
- `wa/WriterKeyboardHandlers.swift`
- `wa/WriterCardManagement.swift`
- `wa/WriterViews.swift`
- `wa/MainCanvasScrollCoordinator.swift`
- `wa/WriterCardViews.swift`
- `wa/WriterSharedTypes.swift`

핵심 판단:
- 징코의 대응 대상은 `fullscreen`이 아니라 `normal document mode`다.
- 우리 앱에서 그 대응 대상은 `포커스 모드`가 아니라 `메인 작업창 모드`다.
- 따라서 징코에서 복제할 구조는 다중 컬럼 메인 작업창의 포커스 이동과 스크롤 파이프라인이다.

## 징코에서 실제로 복제할 것

징코의 메인 작업창은 다음 순서로 움직인다.

1. 입력이 들어오면 다음 활성 카드를 트리 모델에서 먼저 고른다.
2. 활성 카드가 바뀌면 조상, 자손, 최근 활성 히스토리를 한 번에 갱신한다.
3. `getScrollPositions`가 각 컬럼별 목표를 계산한다.
4. JS가 세로 컬럼 스크롤과 가로 캔버스 스크롤을 직접 적용한다.
5. 편집 중인 카드만 live textarea를 갖고, 활성 textarea에는 모델 텍스트를 덮어쓰지 않는다.

징코의 실제 대응점:
- `Page/Doc.elm changeMode`
- `TreeUtils.elm getScrollPositions`
- `doc-helpers.js scrollColumns`
- `doc-helpers.js scrollHorizontal`
- `doc-helpers.js gw-textarea.attributeChangedCallback`

메인 작업창에서 꼭 복제할 구조:
- `Navigation Decision -> Scroll Plan -> Single Apply`
- 조상, 활성 카드, 자손 컬럼을 한 번에 계산하는 per-column policy
- 최근 활성 히스토리를 이용해 자손 컬럼의 우선 대상을 고르는 구조
- 세로 스크롤과 가로 스크롤을 각각 단일 실행기가 소유하는 구조
- 새 스크롤 명령이 이전 애니메이션을 덮어쓰는 overwrite semantics
- 활성 편집기만 live editor로 취급하고, 활성 편집기에는 모델 텍스트를 덮어쓰지 않는 원칙

## 현재 우리 메인 작업창이 징코와 다른 이유

현재 메인 작업창의 주 경로는 한 번의 입력에 대해 너무 많은 계층이 개입한다.

현재 hot path:
- `WriterKeyboardHandlers.performMainArrowNavigation`가 타깃 계산과 preemptive intent 발행을 동시에 한다.
- `WriterCardManagement.publishPreemptiveMainColumnFocusNavigationIntent`가 활성 변경 전 스크롤 예고를 발행한다.
- `WriterCardManagement.changeActiveCard`가 활성 카드와 관계 상태를 바꾼다.
- `WriterViews.syncMainCanvasInteractionState`가 `focusNavigationTick`를 올려 다시 스크롤 경로를 깨운다.
- `WriterViews.handleMainCanvasActiveCardChange`가 메인 캔버스 가로 스크롤을 다시 건드린다.
- `WriterCardManagement.handleMainColumnNavigationIntent`가 각 컬럼에서 intent를 소비한다.
- `WriterCardManagement.scheduleMainColumnActiveCardFocus`가 지연 실행을 건다.
- `WriterCardManagement.scrollToFocus`가 정렬과 keep-visible을 다시 분기한다.
- `WriterCardManagement.scheduleMainColumnFocusVerification`가 verification retry 사다리를 추가한다.
- `WriterViews.scheduleMainCanvasClickHorizontalFocusAlignment`가 가로 정렬 retry 사다리를 추가한다.

현재 구조의 결과:
- 활성 카드 결정과 스크롤 결정이 분리되어 있지 않다.
- 세로 스크롤과 가로 스크롤의 소유자가 여러 군데에 흩어져 있다.
- preemptive scroll, actual scroll, settle recovery, restore retry가 서로 겹친다.
- 한 번의 입력이 여러 work item과 여러 verify 경로를 만든다.
- 최신 입력보다 늦은 애니메이션 completion이나 verify가 뒤늦게 개입할 수 있다.

즉, 지금 메인 작업창은 징코처럼 가볍게 느껴지는 구조가 아니라, 여러 보정 계층이 서로 충돌하지 않게 붙잡고 있는 구조다.

## 새 목표 구조

메인 작업창의 새 주 경로는 아래 세 단계로 고정한다.

1. `MainWorkspaceNavigationModel`
2. `MainWorkspaceScrollPlan`
3. `MainWorkspaceScrollExecutor`

보조 원칙:
- 메인 작업창에서 활성 편집기 보호를 별도 규칙으로 둔다.
- 메인 작업창 hot path에서는 preview intent, retry ladder, settle recovery를 제거한다.
- 포커스 모드와 다른 뷰는 이 구조에 끌어들이지 않는다.

## 1. MainWorkspaceNavigationModel

목적:
- DOM, geometry, scroll state를 보기 전에 메인 작업창의 다음 활성 카드를 순수 모델에서 결정한다.

입력:
- 현재 활성 카드
- 현재 트리 구조
- 메인 작업창 전용 `activeHistory` 최근 40개
- `lastSelectedChildID` 기반의 branch-local fallback 기억
- 표시 중인 메인 컬럼 구조
- 사용자 입력 방향

출력:
- `newActiveID`
- `activeAncestorIDs`
- `activeDescendantIDs`
- `activeHistory`
- `preferredDescendantPath`
- `targetLevel`
- `trigger`

원칙:
- 화살표 입력 단계에서는 더 이상 preemptive scroll을 실행하지 않는다.
- `performMainArrowNavigation`은 타깃 카드 결정까지만 담당한다.
- `changeActiveCard`는 활성 상태 적용만 담당한다.
- 메인 작업창에서 다음 카드 결정은 항상 모델 우선이다.
- 징코의 `activePast`에 대응하는 최근 활성 히스토리를 메인 작업창 전용 보조 상태로 유지한다.
- `lastSelectedChildID`는 완전 교체하지 않고, `activeHistory`가 해당 깊이에서 해답을 주지 못할 때 fallback으로만 쓴다.

징코 대응:
- `goUp/goDown/goLeft/goRight`
- `changeMode` 진입 직전의 active target 계산

우리 코드에서 교체 대상:
- `publishPreemptiveMainColumnFocusNavigationIntent`
- `pendingMainPreemptiveFocusNavigationTargetID`
- 활성 변경 전 가로 정렬 preview

## 2. MainWorkspaceScrollPlan

목적:
- 활성 카드가 바뀐 뒤 메인 작업창 전체 컬럼에 대해 한 번만 스크롤 계획을 만든다.

중요한 범위 결정:
- 이 계획은 `포커스 모드`용 단일 세로 컬럼 계획이 아니다.
- 메인 작업창은 징코와 동일하게 다중 컬럼이므로, scroll plan도 per-column policy를 계산해야 한다.

계획이 계산할 것:
- 가로 캔버스의 목표 level
- 가로 캔버스의 목표 `targetX`
- 각 세로 컬럼의 목표 카드와 목표 정렬 정책
- oversize 카드의 clamped center 처리
- 조상 컬럼, 활성 컬럼, 자손 컬럼, 그 밖의 컬럼 표시 정책
- 이번 scroll transaction의 `animated` 여부

제안 타입:
- `MainWorkspaceScrollPlan`
- `MainWorkspaceColumnPlan`
- `MainWorkspaceColumnPolicy`

`MainWorkspaceColumnPolicy`는 징코 `getScrollPositions`와 동형으로 설계한다.

정책 목록:
- `.centerActive(cardID)`
- `.centerAncestor(cardID)`
- `.centerPreferredDescendant(cardID)`
- `.centerOtherDescendant(cardID)`
- `.between(afterID, beforeID)`
- `.before(cardID)`
- `.after(cardID)`
- `.none`

추가 anchor 규칙:
- 카드 높이가 viewport보다 크면 top-anchor로 바꾸지 않는다.
- 대신 징코처럼 카드의 유효 높이를 clamp한 뒤 center 계산을 유지한다.
- 기본 규칙은 `clampedCenter(maxHeight: viewportHeight * 0.5 + chromeInset)`로 둔다.
- `chromeInset`은 징코의 `51px` 역할에 해당하는 메인 작업창 고정 여백으로 정의한다.
- 이 규칙은 column policy와 별도로 `anchorMode`로 둔다.

plan builder의 책임:
- 활성 컬럼은 활성 카드를 기준으로 계산한다.
- 조상 컬럼은 해당 컬럼 안의 active ancestor를 선택한다.
- 자손 컬럼은 `activeHistory`에서 해당 서브트리에 속하는 가장 최근 활성 카드를 먼저 찾는다.
- `activeHistory`가 해당 깊이에 답을 주지 못하면 `lastSelectedChildID` 사슬을 fallback으로 사용한다.
- 기타 컬럼은 현재 활성 카드의 preorder 기준 앞뒤 카드로 `before/after/between`을 계산한다.
- 가로 캔버스는 target level을 한 번만 계산한다.
- scroll policy 계산 대상은 실제 표시 컬럼만 포함한다.
- 징코의 synthetic root에 해당하는 가상 컨테이너가 있다면 제외한다.
- 우리 앱의 visible `level 0`은 실제 루트 카드 컬럼이므로 제외하지 않는다.

징코 대응:
- `TreeUtils.getScrollPositions`

우리 코드에서 교체 대상:
- `resolvedMainColumnFocusTargetID`
- `resolvedMainColumnPreferredDescendantTargetID`
- 컬럼별 `keepVisible`와 `forceAlignment` 분기 중심 판단
- `handleMainCanvasActiveCardChange` 안의 별도 가로 정렬 판단
- `oneStep / twoStep` 중심의 가로 이동 의미 체계

## 3. MainWorkspaceScrollExecutor

목적:
- 메인 작업창에서 세로와 가로 스크롤을 실행하는 유일한 소유자가 된다.

입력:
- `MainWorkspaceScrollPlan`
- 최신 generation id

`MainWorkspaceScrollPlan` 필수 필드:
- `animated: Bool`
- `horizontalTargetX: CGFloat`
- `columnPlans: [MainWorkspaceColumnPlan]`

실행 순서:
1. 새 plan이 오면 진행 중인 메인 작업창 스크롤 애니메이션을 취소한다.
2. 메인 작업창 레이아웃을 동기적으로 확정한다.
3. 확정된 레이아웃에서 rect를 측정한다.
4. 세로 컬럼 스크롤과 가로 캔버스 스크롤을 같은 generation으로 적용한다.
5. 끝나면 generation 일치 조건에서만 1회 verify 한다.

애니메이션 overwrite 원칙:
- 새 plan은 이전 plan의 vertical animation, horizontal animation, completion, verify를 모두 무효화한다.
- 오래된 completion callback이 최신 위치를 덮어쓰면 실패다.

레이아웃 타이밍 계약:
- rect 측정 전에는 메인 작업창 관련 NSView 트리에 `layoutSubtreeIfNeeded()`를 강제한다.
- 활성 NSTextView가 있다면 TextKit layout도 확정한 뒤 측정한다.
- 측정 전 layout, 측정 후 apply 순서를 문서상 계약으로 고정한다.

target view 부재 처리:
- target view가 아직 없으면 다음 run loop 1회만 대기 후 다시 측정한다.
- 그래도 target view가 없으면 이번 plan은 포기하고 다음 상태 변경을 기다린다.
- 메인 작업창 hot path에 다단 retry ladder를 다시 만들지 않는다.

애니메이션 계약:
- `animated == false`인 plan은 복원, 첫 진입, semantic restore 같은 비즉각 이동에서 사용한다.
- `animated == true`인 plan만 animation context를 사용한다.
- 메인 작업창 executor는 자체 판단으로 애니메이션을 추가하지 않는다.

스크롤 충돌 억제:
- 세로 컬럼 스크롤은 메인 작업창 vertical executor만 소유한다.
- 가로 캔버스 스크롤은 메인 작업창 horizontal executor만 소유한다.
- 실행 중에는 아래 개입을 억제한다.
- `scheduleMainCanvasClickHorizontalFocusAlignment`
- `navigationSettleTick` 기반 가로 재정렬
- restore retry가 hot path를 덮는 경로
- proxy fallback과 native scroll이 동시에 경쟁하는 경로

메인 작업창에서의 억제 대상 구체화:
- 징코의 `scroll-snap none`과 정확히 같은 CSS 동작은 없다.
- 대신 AppKit에서 억제해야 하는 것은 `다른 scroll owner`, `늦은 restore`, `늦은 settle`, `중복 apply`다.
- 세로 스크롤 자체에 과한 suppression layer를 추가하는 것이 목표가 아니다.
- 목표는 메인 작업창에서 스크롤 소유자를 하나로 만드는 것이다.

가로 스크롤 목표 공식:
- 가로 스크롤은 "활성 컬럼을 뷰포트 가로 중앙에 놓는 것"으로 고정한다.
- 목표식은 징코와 동일하게 `columnMinX + 0.5 * (columnWidth - viewportWidth)` 계열의 중앙 정렬 공식을 사용한다.
- 구현자가 컬럼 왼쪽 끝 snap이나 2단계 예고 정렬로 해석하면 실패다.

verify 원칙:
- verify는 generation이 맞을 때만 1회 실행한다.
- verify는 target이 없을 때 구조적 재시도를 만들지 않는다.
- verify는 hot path가 아니라 안전장치여야 한다.

징코 대응:
- `doc-helpers.js scrollColumns`
- `doc-helpers.js scrollHorizontal`
- GSAP overwrite에 해당하는 cancellation semantics

우리 코드에서 교체 대상:
- `handleMainColumnNavigationIntent`
- `scheduleMainColumnActiveCardFocus`
- `scrollToFocus`
- `scheduleMainColumnFocusVerification`
- `scheduleMainCanvasClickHorizontalFocusAlignment`
- `handleMainCanvasNavigationSettle`

## 4. MainWorkspaceActiveEditorGuard

목적:
- 메인 작업창의 활성 편집기만 live editor로 다루고, 활성 편집기에는 모델 텍스트를 덮어쓰지 않는다.

현재 상태 판단:
- 메인 작업창은 이미 `editingCardID` 기준으로 실질적인 단일 live editor 구조에 가깝다.
- 하지만 `MainWorkspaceEditableTextRenderer.updateNSView`는 `textView.string != text`이면 활성 상태와 무관하게 editor 내용을 다시 넣는다.
- 이 구조는 모델 업데이트가 내려올 때 caret jump를 만들 여지가 있다.

새 원칙:
- 활성 NSTextView가 first responder이고 동일 card session이면 모델에서 오는 text replacement를 적용하지 않는다.
- editor에서 model로 가는 업데이트는 계속 허용한다.
- model에서 editor로 가는 업데이트는 editor가 비활성일 때만 적용한다.
- 외부 강제 세션 전환이 있을 때만 explicit reset을 허용한다.

징코 대응:
- `gw-textarea.attributeChangedCallback`
- `!this._isActive()` 가드

우리 코드에서 교체 대상:
- `WriterCardViews.MainWorkspaceEditableTextRenderer.updateTextView`

유지할 것:
- 메인 작업창에서 비활성 카드는 정적 렌더링
- 활성 카드 높이는 live editor 측정값 우선
- 비활성 카드 높이는 캐시 기반 계산

## 5. 메인 작업창에서 삭제하거나 hot path 밖으로 밀어낼 것

삭제 대상은 "프로젝트 전체 삭제"가 아니라 "메인 작업창 주 경로에서 제거"를 뜻한다.

우선 제거 대상:
- `publishPreemptiveMainColumnFocusNavigationIntent`
- `pendingMainPreemptiveFocusNavigationTargetID`
- `focusNavigationTick` 기반 메인 작업창 세로 정렬 전달
- `scheduleMainColumnActiveCardFocus`
- `scheduleMainColumnFocusVerification`의 다단 retry
- `scheduleMainCanvasClickHorizontalFocusAlignment`의 다단 retry
- `navigationSettleTick` 기반 강제 재정렬
- hot path에서의 `suppressHorizontalAutoScroll` 봉합 경로
- preview scroll과 actual scroll이 둘 다 존재하는 구조
- 메인 작업창 hot path의 `oneStep / twoStep` 분기

조건부 유지:
- restore 기능이 메인 작업창 외 시나리오에 필요하면 남길 수 있다.
- 단, 메인 작업창 입력 hot path에는 다시 들어오면 안 된다.

실패 조건:
- 새 구조를 넣은 뒤에도 메인 작업창 화살표 입력이 multiple work item, multiple verify, multiple scroll owner를 만든다면 실패다.

## 구현 Phase

### Phase 0. 기준선 측정

측정 항목:
- 화살표 입력부터 첫 스크롤 apply 시작까지 시간
- 화살표 연타 시 animation overlap count
- vertical verify retry count
- horizontal retry count
- active editor caret jump 재현 횟수

목적:
- 메인 작업창이 실제로 가벼워졌는지 체감이 아니라 데이터로 확인한다.

### Phase 1. MainWorkspaceNavigationModel 분리

작업:
- 메인 작업창의 카드 이동 결정을 순수 모델 계층으로 뺀다.
- 화살표 처리에서 preemptive scroll 발행을 제거한다.
- 활성 카드 변경은 `newActiveID` 적용과 relation state 동기화까지만 담당하게 한다.

완료 기준:
- 메인 작업창에서 입력 1회당 활성 카드 결정은 정확히 1회만 일어난다.

### Phase 2. MainWorkspaceScrollPlan 도입

작업:
- 활성 카드 변경 뒤 메인 작업창 전체 컬럼에 대한 scroll plan을 한 번 생성한다.
- plan은 징코처럼 조상, 활성, 자손, 주변 컬럼 정책을 모두 포함한다.
- plan은 가로 `targetLevel`, 가로 `targetX`, `animated` 여부를 함께 포함한다.

완료 기준:
- 메인 작업창에서 세로 컬럼과 가로 캔버스가 같은 plan generation으로 묶인다.

### Phase 3. MainWorkspaceScrollExecutor 교체

작업:
- 메인 작업창 스크롤 실행기를 단일 소유자로 교체한다.
- animation cancel, layout contract, single apply, single verify를 구현한다.
- 다단 retry와 settle recovery를 hot path에서 제거한다.

완료 기준:
- 빠른 연타 시 이전 animation은 최신 plan에 의해 즉시 무효화된다.
- rect 측정은 항상 layout 확정 뒤에 일어난다.
- 메인 작업창 입력 hot path에 다단 verification 사다리가 남아 있지 않다.

### Phase 4. MainWorkspaceActiveEditorGuard 적용

작업:
- 활성 editor 보호 가드를 넣는다.
- 활성 text view에는 model text replacement를 막는다.
- blur 또는 명시적 session reset 시에만 model->editor sync를 허용한다.

완료 기준:
- 메인 작업창 편집 중 외부 state change가 와도 caret가 튀지 않는다.

### Phase 5. 레거시 main workspace 경로 삭제

작업:
- 더 이상 필요 없는 preview intent, click alignment retry, settle recovery, verify retry를 정리한다.
- 메인 작업창 전용 hot path와 비범위 뷰 경로를 분리한다.

완료 기준:
- 메인 작업창 관련 코드가 "결정 -> plan -> apply" 구조로 읽힌다.

## 수용 기준

1. 메인 작업창만 바뀌고 포커스 모드, 인덱스카드 뷰, 히스토리 뷰는 동작이 유지된다.
2. 화살표 입력 1회는 활성 카드 결정 1회와 scroll plan 생성 1회만 유발한다.
3. 메인 작업창의 scroll plan은 조상, 활성, 자손, 주변 컬럼 정책을 징코처럼 per-column으로 계산한다.
4. 메인 작업창은 최근 활성 `activeHistory`를 유지하고, 자손 컬럼 정책 계산에 이를 사용한다.
5. oversize 카드는 top-anchor가 아니라 clamped center 규칙으로 정렬된다.
6. 세로 컬럼 스크롤과 가로 캔버스 스크롤은 같은 generation의 executor가 한 번만 적용한다.
7. 빠른 연타 시 이전 animation과 completion은 최신 plan에 의해 무효화된다.
8. rect 측정은 항상 layout 확정 뒤에만 일어난다.
9. target view가 없을 때 재시도는 다음 run loop 1회까지만 허용된다.
10. 활성 main editor에 model 업데이트가 내려와도 caret 위치가 바뀌지 않는다.
11. 가로 스크롤 목표는 항상 활성 컬럼 중앙 정렬 공식으로 계산된다.
12. 우리 앱의 visible `level 0` 루트 컬럼은 scroll plan 계산 대상에 포함된다.
13. 메인 작업창 hot path에는 preview scroll, click-focus retry ladder, multi-pass verify ladder가 남아 있지 않다.
14. 체감상 메인 작업창의 카드 이동과 스크롤이 징코처럼 즉각적이고 가볍게 느껴진다.

## 구현 중 금지

- 포커스 모드 코드를 끌어와 메인 작업창 계획을 채우는 것
- 메인 작업창 문제를 suppress flag 추가로 봉합하는 것
- retry 계층을 다시 만드는 것
- restore 로직을 hot path의 일부로 되돌리는 것
- "일단 보조 경로로 남겨두자"며 주 경로를 다시 오염시키는 것

## 최종 선언

이 문서는 징코의 메인 작업창 구조를 우리 메인 작업창에 복제하기 위한 기준 문서다.

성공 조건은 "조금 덜 불편함"이 아니다.
- 메인 작업창에서 징코처럼 한 번 결정하고 한 번 움직이는 구조가 되어야 한다.
- 그 구조가 코드에서 바로 읽혀야 한다.
- 그 질감이 실제 인터랙션에서 느껴져야 한다.

그 수준에 못 미치면 이 계획은 완료가 아니다.
