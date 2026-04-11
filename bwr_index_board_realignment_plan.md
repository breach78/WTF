# BWR Index Board Realignment Plan

## Scope

현재 `Board Writer`의 자유배치 보드를, 기존 `wa` 인덱스 뷰의 슬롯 기반 데스크탑 문법으로 다시 정렬한다. 목표는 `카드버디 같은 자유 캔버스`가 아니라, `일정한 슬롯 위에서 카드가 붙고 떨어지고 재흐름되는 인덱스 뷰 손맛`을 BWR 모델 위에 복원하는 것이다.

이 문서는 `/Users/three/app_build/wa/bwr_porting_plan_v2.md`의 보드 관련 가정을 보정하는 추가 계획이다. 레이어, 포커스 모드, export, archive, undo, link persistence는 유지하고, 보드 엔진과 정렬 규칙만 재설계한다.

## Phase 0 Status

`R0. Decision Lock`은 2026-04-09 기준으로 완료 처리한다.

잠긴 결정:

1. BWR 보드는 더 이상 자유배치 보드가 아니라 슬롯 기반 데스크탑이다.
2. live 카드는 동시에 여러 live group에 남지 않는다.
3. 여러 위치에서 같은 내용을 보이려면 clone만 사용한다.
4. `/Users/three/app_build/wa/bwr_porting_plan_v2.md`의 보드 관련 충돌 구간은 이 문서가 우선한다.
5. 다음 구현 시작점은 `R1. Persistence And Shadow Placement`다.

Source of truth:

1. 보드 배치, attach/detach, group/strip, slot order, reducer 의미 변경 범위는 이 문서를 따른다.
2. 포커스, export, archive, link persistence, 파일 앱 전략 중 이 문서와 충돌하지 않는 항목만 `/Users/three/app_build/wa/bwr_porting_plan_v2.md`를 계속 참조한다.

## Why This Exists

현재 결과물은 기존 인덱스 뷰와 핵심 문법이 다르다.

1. 현재 BWR 보드는 카드가 raw 좌표를 직접 들고 [BWRPhase0Support.swift](/Users/three/app_build/wa/wa/BWRPhase0Support.swift#L57), 드래그 시 그 좌표를 바로 갱신하며 [BWRCoreReducer.swift](/Users/three/app_build/wa/wa/BWRCoreReducer.swift#L224), 화면도 `ZStack + .position` 기반 자유 배치다 [BWRBoardCanvasView](/Users/three/app_build/wa/wa/BWRBoardCanvasView.swift#L23).
2. 기존 인덱스 뷰는 카드가 `slotIndex`, `detachedGridPosition`, `gridPosition`을 가진 슬롯 표면이고 [WriterIndexBoardSurfaceProjection.swift](/Users/three/app_build/wa/wa/WriterIndexBoardSurfaceProjection.swift#L67), 그룹과 detached 카드가 temp strip/slot descriptor를 통해 붙고 떨어지는 규칙을 갖는다 [WriterIndexBoardSurfaceProjection.swift](/Users/three/app_build/wa/wa/WriterIndexBoardSurfaceProjection.swift#L147) [WriterIndexBoardSurfaceAppKitPhaseTwo.swift](/Users/three/app_build/wa/wa/WriterIndexBoardSurfaceAppKitPhaseTwo.swift#L3964).
3. 그래서 현재 보드는 "카드를 어디든 놓는 캔버스"이고, 기존 인덱스 뷰는 "슬롯 위에서 카드 흐름을 조립하는 데스크탑"이다.

결론은 단순 폴리시 조정이 아니라, 보드 레이아웃 엔진을 교체해야 한다는 것이다.

## Hard Product Decisions

이 계획은 아래 결정을 전제로 한다.

1. 보드는 자유배치가 아니라 `slot-based desktop`이다.
2. 카드의 위치 canonical source of truth는 더 이상 raw `x/y`가 아니다.
3. 그룹 내부 순서는 `슬롯 순서`가 canonical이며, export와 focus mode도 이 순서를 사용한다.
4. 그룹 밖 카드도 보드에 존재할 수 있다. 이 카드는 `parking strip`에 놓인다.
5. `parking strip`은 옛 트리 앱의 temp container가 아니다. BWR 보드 전용 작업면이다.
6. 그룹에 묶인 카드만 focus/export 대상이다. parking strip 카드는 작업용이다.
7. `한 장의 라이브 카드`는 보드 표면에서 `하나의 host group` 또는 `하나의 parking strip 위치`만 가진다.
8. 같은 내용을 여러 그룹에 동시에 보이게 하려면 `clone`을 사용한다.
9. 따라서 현재 v2 문서의 `카드는 여러 그룹에 동시에 속할 수 있다`는 보드 표면 규칙으로는 더 이상 유지하지 않는다. 논리 공유보다 표면 일관성을 우선한다.
10. 이건 placement만 바꾸는 일이 아니라 reducer 전체 의미를 바꾸는 일이다. 현재 `splitCard`의 다중 그룹 복제, `archiveGroup`의 "다른 그룹에 남아 있으면 보존" 규칙도 함께 교체해야 한다.
11. live membership은 독립 many-to-many 관계가 아니라 `group.memberCardIDs` 또는 `strip.cardIDs` 중 하나에서만 성립한다.
12. undo/redo나 load 이후에 이 규칙을 어기는 secondary membership은 invalid state로 보고 normalize하거나 실패시킨다.
13. 이 결정은 기존 인덱스 뷰의 붙기/떼기 감각을 되찾기 위한 핵심 잠금이다.

## What Stays

아래는 그대로 유지한다.

1. `.bwr` 패키지 포맷 자체
2. 카드별 레이어 구조 `본문 n > 트리트먼트 > 시나리오`
3. 포커스 모드 3축 `현재 레이어 / 트리트먼트 / 시나리오`
4. PDF/TXT export bridge와 기존 렌더러
5. archive/search
6. clone 동기화
7. structural undo + text undo 경계
8. link 모델과 persistence
9. Apple Silicon Mac 검증 호스트 전략

## What Changes

아래는 갈아엎는다.

1. `BWRCard.layout`를 canonical placement로 쓰는 방식
2. `setCardLayouts` 기반 raw 이동 모델
3. `BWRBoardCanvasView`의 자유배치 드래그 해석
4. 화살표 이동의 유클리드 거리 기반 선택
5. 그룹을 단순 membership 집합으로만 보는 시각적 모델
6. 카드가 여러 라이브 그룹에 동시에 남아 있을 수 있다는 reducer 가정
7. `layout` row-major를 직접 읽어 순서를 계산하는 모든 consumer

## Canonical Board Model

### Card Placement

카드의 표면 위치는 아래 둘 중 하나다.

1. `attached`
   - `hostGroupID`
   - `slotIndex`

2. `parked`
   - `stripID`
   - `slotIndex`

카드는 둘 중 하나의 placement만 가진다.

### Group Layout

그룹은 아래를 가진다.

1. `id`
2. `name`
3. `originSlot`
   - `column`
   - `row`
4. `memberCardIDs`
   - slot order와 동일한 순서 배열
5. `isArchived`
6. `archivedAt`

규칙:

1. `memberCardIDs` 순서가 곧 그룹의 시퀀스 순서다.
2. 표면 렌더링은 `originSlot + slotCount`를 기준으로 그룹 frame을 계산한다.
3. 그룹 내부 row wrap이 필요하면 `slotIndex -> local row/column` 매핑으로 계산하되 canonical order는 그대로 1차원 배열로 유지한다.
4. live 카드 ID는 동시에 둘 이상의 live group `memberCardIDs`에 나타나면 안 된다.
5. group membership은 placement의 canonical owner이므로, stale reference는 load/undo 시 repair 대상이다.

### Parking Strip

기존 temp strip 개념은 이름만 바꿔 BWR 전용 surface construct로 가져온다.

1. `id`
2. `row`
3. `anchorColumn`
4. `cardIDs`

규칙:

1. parking strip은 그룹 밖 카드들의 작업 공간이다.
2. strip은 detached card를 정리하는 표면 구조일 뿐, 출력/포커스 단위가 아니다.
3. strip은 여러 개 존재할 수 있다.
4. strip 안 카드도 슬롯 순서를 가진다.

### Projection Scope Against Legacy Index View

기존 인덱스 뷰는 `laneParentID`, `laneIndex`, `slotIndex`, `detachedGridPosition`, temp strip descriptor처럼 더 풍부한 projection 상태를 가졌다. 이번 재정렬은 그 모든 축을 곧바로 persistence로 옮기지 않는다.

원칙:

1. 문서에는 `placement + group origin + strip anchor/order`만 canonical로 저장한다.
2. lane/block/placeholder/temp-like hover state는 projection 단계에서 계산한다.
3. 기존 surface parity를 맞추는 데 projection-only 정보가 더 필요해지면, raw `x/y`를 되살리기보다 projection model을 확장한다.
4. 즉, `legacy surface richness`는 무시하지 않되, persistence를 다시 자유배치로 후퇴시키지도 않는다.

### Clone Rule Under Slot Model

1. clone은 별도 카드다.
2. clone은 별도 placement를 가진다.
3. clone은 다른 그룹이나 다른 strip에 놓일 수 있다.
4. clone family에는 영구적인 master card를 두지 않는다. UI상으로는 모든 sibling을 대칭으로 취급한다.
5. reducer 내부에서는 `가장 이른 생성 시각, 동률이면 smallest ID`를 family leader로 삼아 shared payload write 순서를 결정한다.
6. 어떤 clone이 삭제되면 남은 sibling이 그대로 살아 있고, live sibling이 1장만 남으면 그 survivor의 `cloneGroupID`를 nil로 만들어 collapse한다.
7. selection, link anchor, undo target은 항상 concrete card instance 기준이다. 본문/색상/레이어 sync만 clone family 기준이다.

## Persistence Changes

현재 v2의 raw layout 중심 포맷을 아래로 보정한다.

### Schema

1. `schemaVersion`을 올린다.
2. `BWRCard.layout`는 R1에서 바로 지우지 않는다. R1-R4 동안은 `slot placement에서 파생되는 shadow cache`로만 두고, 직접 mutate하는 command를 금지한다.
3. 새 persisted fields:
   - `placementKind`
   - `hostGroupID?`
   - `stripID?`
   - `slotIndex`
4. `BWRGroup`에 `originSlot`을 추가한다.
5. `parkingStrips.json`을 추가한다.
6. `layout` 제거는 surface, focus, export, selection consumer가 모두 slot helpers로 옮겨간 뒤 마지막에 한다.

### Migration Policy

레거시 호환은 하지 않는다.

1. `wtf` 마이그레이션 없음
2. 현재 unreleased BWR dev format도 hard reset 허용
3. branch 안에서만 쓰인 기존 `.bwr` fixture는 새 schema로 재생성

즉, 구현을 단순하게 유지하기 위해 dev-only breaking change를 허용한다.

### Transition Strategy

`layout`을 먼저 지우면 현재 board/document/focus ordering과 drag preview가 한 번에 다 깨진다. 따라서 전환은 아래 순서를 따른다.

1. T0. `placement`를 canonical로 도입하고, `layout`은 placement에서 파생되는 shadow cache로만 유지한다.
2. T1. reducer command와 persistence, normalization, ordering helper를 모두 placement 기준으로 먼저 전환한다.
3. T2. projection과 surface가 slot placement만 읽도록 바꾼다.
4. T3. focus/export/search/archive 인접 선택까지 slot order helper로 옮긴 뒤 `layout` reader를 제거한다.
5. T4. 마지막에 `layout` persisted field 자체를 삭제한다.

### Load / Repair Rules

load와 undo/redo 복원 시 아래 invalid state를 명시적으로 다룬다.

1. `attached` 카드인데 `hostGroupID`가 없거나 group이 존재하지 않으면, deterministic rule로 strip으로 강등하거나 복구 불가 시 실패한다.
2. `parked` 카드인데 `stripID`가 없거나 strip이 없으면, nearest recovery strip을 만들거나 복구 불가 시 실패한다.
3. 같은 group/strip 안에서 `slotIndex`가 중복되면 stable sort 후 재번호 매긴다.
4. archived 카드가 live group/strip에 남아 있으면 참조를 제거한다.
5. live 카드가 둘 이상의 live group/strip에 동시에 참조되면, 자동 clone 승격이나 임의 winner 선택을 하지 않고 `placement corruption`으로 명시 실패시킨다.
6. 빈 group/strip 정리 규칙을 deterministic하게 적용한다.
7. unrecoverable corruption은 `ReferenceFileDocument` load failure로 surface에 명시적으로 올린다. silent fallback은 허용하지 않는다.

## Interaction Spec

### Desktop

1. 보드 배경에는 일정 간격의 slot lattice가 있다.
2. 그룹은 이 lattice 위에 블록처럼 놓인다.
3. parking strip도 이 lattice 위에 놓인다.

### New Card

1. 그룹이 선택된 상태에서 새 카드를 만들면:
   - 선택 카드 다음 slot에 삽입
   - 선택 카드가 없으면 그룹 마지막 slot 뒤에 삽입
2. 그룹 선택이 없으면:
   - 현재 viewport 근처의 parking strip 빈 slot에 생성
   - 적절한 strip이 없으면 새 strip 생성

### Selection Precedence

새 카드 생성, split, attach target 계산 전에 selection을 아래 우선순위로 정규화한다.

1. live group 안의 `selectedCardID`
2. live strip 안의 `selectedCardID`
3. `selectedGroupID`
4. 현재 viewport band의 primary parking strip
5. stale selection은 command 진입 시 제거한다.

### Drag

드래그는 자유 이동이 아니라 slot target 해석이다.

1. `attached -> attached`
   - 같은 그룹 내 reorder
   - 다른 그룹 slot gap에 attach
2. `attached -> parked`
   - 그룹 capture 영역을 벗어나고 parking strip target이 성립하면 detach
3. `parked -> attached`
   - 그룹 gap hover가 성립하면 attach
4. `parked -> parked`
   - strip 내부 reorder 또는 다른 strip으로 이동
5. `group block drag`
   - group originSlot 이동
   - 내부 카드 slot order는 유지

### Parking Strip Determinism

1. strip 선택은 `viewport 중심과의 거리 -> 같은 row band 우선 -> anchorColumn 우선 -> strip id` 순으로 deterministic하게 결정한다.
2. 새 strip 생성 위치는 "보이는 곳 어딘가"가 아니라 `현재 viewport band의 마지막 occupied row 다음`으로 고정한다.
3. strip anchor가 group block과 충돌하면 `아래 방향 row-major scan`으로 첫 free row를 찾는다.
4. 빈 strip은 drag in-flight 상태가 아니면 commit 시 제거한다.
5. strip merge/split 규칙도 ID 생성이 아니라 slot occupancy 기준으로 deterministic하게 수행한다.

### Group Block Drag Collision

1. group body hover와 slot gap hover는 서로 다른 activation frame과 hysteresis를 가진다.
2. group drag candidate는 lattice에 snap된 `originSlot`으로 계산한다.
3. target origin이 다른 group/strip occupancy와 충돌하면 `candidate에서 시작하는 row-major free-origin scan`으로 첫 valid 위치를 찾는다.
4. drop 후 group 내부 `memberCardIDs` 순서는 절대 변하지 않는다.
5. attach placeholder와 block placeholder의 우선순위 충돌은 중앙 geometry helper 한 곳에서만 계산한다.

### Attach / Detach Feel

기존 인덱스 뷰의 손맛은 아래에서 나온다.

1. slot gap이 미리 보인다.
2. attach 후보로 들어가면 insertion placeholder가 뜬다.
3. detach 후보로 빠지면 parking placeholder가 뜬다.
4. drop 후 즉시 reflow된다.
5. 카드가 임의 픽셀 위치에 남지 않는다.

이 5개가 이번 재정렬의 핵심 acceptance다.

### Split

1. 그룹 안 카드 split:
   - 현재 카드 다음 slot에 새 카드 삽입
   - 같은 group membership 유지
   - current visible layer만 분할
2. parked 카드 split:
   - 같은 strip의 다음 slot에 삽입

### Arrow Navigation

기존 거리 기반 선택을 제거한다.

1. 그룹 안에서는 논리 slot 기준 이동
2. strip 안에서도 논리 slot 기준 이동
3. 좌우는 같은 row 안 인접 slot
4. 상하는 같은 visual column의 인접 row
5. 경계를 넘으면 다음/이전 strip 또는 그룹 block으로 이동
6. global traversal order는 `visible group blocks row-major -> visible parking strips row-major -> block 내부 slot order`로 deterministic하게 고정한다.

## Focus And Export Changes

포커스와 export는 유지하되, 입력 순서만 바뀐다.

1. focus mode entry order는 더 이상 raw 좌표 row-major가 아니라 `group.memberCardIDs` 순서다.
2. export bridge도 동일하게 `group.memberCardIDs` 순서를 사용한다.
3. parking strip 카드는 focus/export에서 제외한다.
4. 그룹 frame의 시각 row wrap은 표시용이며, canonical sequence는 1차원 slot order다.
5. `liveCards`, `orderedLiveCards`, focus projection, export input, archive 인접 선택, 검색 결과 다음/이전 이동은 모두 같은 slot-order helper를 공유한다.
6. 어떤 consumer도 `layout` row-major를 독자적으로 다시 계산하지 않는다.

이 변경 덕분에 시퀀스 순서가 드래그 후에도 결정적으로 유지된다.

## File-Level Cut Plan

### Keep

1. [BWRDocumentInfrastructure.swift](/Users/three/app_build/wa/wa/BWRDocumentInfrastructure.swift)
2. [BWRExportBridge.swift](/Users/three/app_build/wa/wa/BWRExportBridge.swift)
3. [BWRFocusModeView.swift](/Users/three/app_build/wa/wa/BWRFocusModeView.swift)
4. archive/search/link persistence 관련 reducer와 harness

### Rewrite Or Replace

1. [BWRBoardCanvasView.swift](/Users/three/app_build/wa/wa/BWRBoardCanvasView.swift)
2. `BWRCard.layout`와 `setCardLayouts` 중심 reducer 경로
3. focus/export ordering source

### New Seams

1. `BWRSlotBoardGeometry.swift`
   - slot metrics, occupancy map, placeholder math, hysteresis constants, collision scan
2. `BWRSlotBoardModels.swift`
   - placement, strip, projected block descriptors
3. `BWRSlotBoardProjection.swift`
   - group frame, slot rect, parking strip projection
4. `BWRSlotBoardSurface.swift`
   - AppKit/SwiftUI host, drawing, hit testing
5. `BWRSlotBoardDragController.swift`
   - attach/detach/reflow target resolution
6. `BWRSlotBoardCommands.swift`
   - insert, reorder, detach, attach, split placement, archive normalization

파일은 모두 1500줄 이하 seam으로 분리한다.

## Milestones

### R0. Decision Lock

1. free board 가정을 폐기한다.
2. `single host placement per live card`를 잠근다.
3. multi-group visible reuse는 clone으로만 허용한다.
4. v2 문서의 충돌 구간을 이 문서 기준으로 supersede 표시한다.
5. reducer 의미 변경 범위를 명시한다.

### R1. Persistence And Shadow Placement

1. placement persisted fields 추가
2. group originSlot persisted field 추가
3. parking strips 저장 추가
4. `layout`를 shadow cache로만 유지
5. fixture와 harness schema 갱신
6. decode failure path를 명시 에러로 연결

완료 기준:

1. `.bwr` round-trip이 새 placement 모델로 통과
2. group/strip/card 순서가 저장 후 유지

### R2. Commands, Normalization, Undo Alignment

1. attach/detach/reorder command 추가
2. split placement 규칙 변경
3. archive/delete가 `single host placement`와 일관되게 작동하도록 reducer semantics 교체
4. clone collapse와 leader selection 규칙 구현
5. load/undo normalization 추가
6. selection precedence 고정
7. slot-order helper API를 도입해 ordering consumer를 한곳으로 모은다.

완료 기준:

1. 구조 변경이 모두 undo/redo된다.
2. text undo와 structural undo 경계가 유지된다.
3. `layout`는 shadow cache일 뿐, command source of truth가 아니다.

### R3. Projection Engine

1. slot lattice metrics 정의
2. group frame projection 구현
3. strip projection 구현
4. card rect derivation 구현
5. placeholder rect derivation 구현
6. parking strip deterministic placement 규칙 구현
7. group collision scan 구현

완료 기준:

1. slot rect 계산이 결정적
2. 같은 입력에서 항상 같은 frame 출력

### R4. Surface Rewrite

1. 자유배치 drag 제거
2. slot hover, attach hover, detach hover placeholder 추가
3. group block drag 추가
4. strip rendering 추가
5. 기존 인라인 편집/큰 카드 편집 진입 연결
6. AppKit surface가 필요하면 `NSViewRepresentable`를 쓰되, text focus와 IME/undo 경계를 별도 설계 문서 없이 흐리지 않는다.

완료 기준:

1. 카드가 임의 픽셀 위치에 남지 않음
2. drop 후 즉시 슬롯 재흐름

### R5. Order Consumers Switch

1. focus projection을 slot order 기반으로 전환
2. export bridge를 slot order 기반으로 전환
3. parked 카드 제외 규칙 고정
4. archive/search 인접 선택을 slot order 기반으로 전환
5. keyboard traversal을 slot order 기반으로 전환
6. 남아 있는 `layout` reader 제거

완료 기준:

1. 그룹 slot 순서와 포커스/출력이 항상 일치
2. ordering logic이 한 helper로 수렴

### R6. Acceptance Harness

1. slot ordering suite
2. attach/detach suite
3. split placement suite
4. clone + detach/delete suite
5. load/repair corruption suite
6. Mac acceptance smoke
7. portrait/landscape/split layout smoke
8. deterministic placeholder suite
9. keyboard traversal snapshot suite

완료 기준:

1. 기존 인덱스 뷰 손맛의 핵심 규칙이 자동화된 하네스로 고정

## Acceptance Bar

이 계획이 성공했다고 보려면 아래가 모두 맞아야 한다.

1. 새 카드가 빈 픽셀 공간이 아니라 slot에 생성된다.
2. 그룹 안 카드가 slot 사이에서 reorder된다.
3. 카드가 그룹에서 떨어지면 parking strip으로 간다.
4. 카드가 다른 그룹 gap에 들어가면 attach된다.
5. split 후 새 카드가 다음 slot에 들어간다.
6. focus mode 순서와 export 순서가 보드 slot 순서와 같다.
7. Mac host에서 키보드, 트랙패드, 저장, export, undo가 막히지 않는다.
8. 같은 드래그 hover 입력을 10번 반복해도 placeholder target이 매번 동일하다.
9. keyboard traversal snapshot이 wrapped group/strip fixture에서 결정적으로 유지된다.
10. 200-card fixture 기준 projection + target resolution median이 M1 Mac host 디버그 하네스에서 16ms 이하를 유지한다.
11. viewport나 hover state만 바뀌었을 때 문서 canonical data는 dirty되지 않는다.

## Non Goals

1. 링크 화살표 렌더링
2. Pencil 전용 상호작용
3. AppKit다운 Mac 네이티브 룩
4. 기존 `wtf` 또는 현재 unreleased BWR 문서 호환
5. 복수 보드/복수 시나리오

## Main Risks

1. `single host placement` 결정이 현재 group membership 모델과 충돌할 수 있다.
   - 대응: logical multi-membership을 끊고, 중복 시각 배치는 clone으로만 허용한다. reducer semantics를 placement 기준으로 먼저 갈아엎는다.
2. SwiftUI만으로 기존 인덱스 뷰의 attach/detach 손맛을 못 낼 수 있다.
   - 대응: surface 계층은 `NSViewRepresentable` 허용. 단, text focus/IME/text undo 경계를 별도 acceptance로 둔다.
3. free-layout 기반 하네스가 대거 깨질 수 있다.
   - 대응: schema reset + slot harness 우선.
4. focus/export뿐 아니라 search/archive adjacent selection까지 ordering consumer가 넓어 변경면이 커질 수 있다.
   - 대응: slot-order helper를 단일 소스로 만들고 모든 consumer를 그 helper에 종속시킨다.
5. parking strip과 group block collision 규칙이 느슨하면 기존 손맛 대신 랜덤한 재배치로 느껴질 수 있다.
   - 대응: geometry helper에 deterministic scan과 hysteresis constants를 중앙화한다.

## First Implementation Move

첫 작업은 UI가 아니라 모델 잠금이다.

1. `BWRCard.layout`를 즉시 지우지 않고 shadow cache로 격하한다고 확정
2. `placement + group origin + parking strip + normalization`을 먼저 도입
3. reducer command를 slot placement source of truth로 바꾼다.
4. 그 뒤에 projection과 surface를 교체한다.

이 순서를 지켜야 보드 표면이 다시 흔들리지 않는다.
