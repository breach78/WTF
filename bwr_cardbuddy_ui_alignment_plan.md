# BWR Card Buddy UI Alignment Plan

## Scope

현재 `Board Writer` 보드 표면을 `Card Buddy`의 카드/슬롯 문법에 최대한 가깝게 재정렬하되, `BWR`의 레이어, 그룹, 아카이브, 포커스, export 구조는 유지한다.

## Why This Exists

지금 `BWR`은 슬롯 기반 보드 엔진까지는 많이 따라왔지만, 카드 자체는 아직 `종이 인덱스 카드`보다 `앱 카드 컴포넌트`처럼 읽힌다.

현재 차이의 핵심:

1. 카드가 너무 많은 정보를 스스로 말한다.
   - 제목 행
   - 레이어 뱃지
   - 하단 kind / id 메타
   - 편집 버튼 텍스트
2. 상태 피드백이 카드 내부와 카드 외부에 섞여 있다.
3. 슬롯, 커서, hover, placeholder의 문법이 `Card Buddy`보다 더 앱스럽다.
4. 인라인 편집이 카드 고정 크기 문법을 깨는 순간이 있다.
5. 그룹 프레임과 카드 표면이 서로 경쟁해서 카드가 덜 두드러진다.

이번 계획의 목표는 리스킨이 아니다.

1. 카드 쉘을 `종이 카드`로 낮춘다.
2. 상태 피드백은 selection, cursor, placeholder, drag overlay가 말하게 한다.
3. 레이어 조작은 카드 내부의 편집 전용 affordance로 숨긴다.
4. 슬롯 기반 보드 문법과 카드 표면 문법을 하나로 맞춘다.

## Reference Baseline

이 계획은 아래 자료를 기준으로 잠근다.

1. 사용자 제공 영상
   - `/var/folders/xv/sl008w8x451b97mhtf_7rzc80000gn/T/TemporaryItems/NSIRD_screencaptureui_uCv2OD/화면 기록 2026-04-11 오후 2.55.46.mov`
   - `/var/folders/xv/sl008w8x451b97mhtf_7rzc80000gn/T/TemporaryItems/NSIRD_screencaptureui_VHhjFe/화면 기록 2026-04-11 오후 3.01.54.mov`
2. 사용자 제공 스크린샷
   - `/Users/three/Downloads/111.jpg`
   - `/Users/three/Downloads/112.jpg`
3. 로컬 번들 참고물
   - `/Users/three/app_build/wa/Contents_cardbuddy`
   - `/Users/three/app_build/wa/Contents_cardbuddy/Resources/Plot Outline.cards/thumbnail.jpg`
   - `/Users/three/app_build/wa/Contents_cardbuddy/Resources/Tutorial.cards/thumbnail.jpg`
4. 제품 사이트
   - [Card Buddy](https://www.ussherpress.com/cardbuddy/)

사이트에서 이번 계획에 직접 영향을 주는 문구:

1. `auto-arranging cards`
2. `Powerful Keyboard Control`
3. `It's like operating a beautiful spreadsheet of index cards`
4. `Create Beautiful Cards With Little Effort`
5. `Grid ... all cards are the same size`

## Decision Lock

### Visual Fidelity

1. 카드 크기, 내부 여백, 그림자, 선택 outline, 빈 슬롯 느낌은 `Card Buddy`에 거의 동일한 수준으로 맞춘다.
2. `Kanban`은 참조하지 않는다.
3. 포커스 모드는 별도 문법으로 유지하고, 이번 계획의 주대상은 보드 카드 UI다.

### Card Surface

1. 카드 크기는 고정이다.
2. 인라인 편집 중에도 카드 외곽 크기는 고정이다.
3. 큰 편집은 별도 창으로 연다.
4. 카드 상단 헤더는 없다.
5. 카드 내부 본문만 보인다.
6. 카드 본문은 Markdown 렌더링 결과를 보여준다.
7. 대략 5줄 정도만 보이고, 초과 내용은 카드 아래로 이어 보여주지 않는다.
8. 기본 카드는 흰색이다.
9. 카드 색상은 카드별로 다를 수 있다.
10. 배경 보드 색도 변경 가능해야 한다.

### Layer Affordance

1. 레이어 개념은 유지한다.
2. 카드 자체에는 항상 보이는 레이어 헤더나 뱃지를 두지 않는다.
3. 레이어 순환 affordance는 편집 중에만 작게 보인다.
4. 위치는 `Card Buddy` 하단 아이콘 문법을 따른다.
5. 의미는 `BWR`에 맞게 바꾼다.
6. 키보드 레이어 순환 단축키는 유지한다.

### State Grammar

1. 슬롯은 평소에 보이지 않는다.
2. 슬롯은 간격과 카드 정렬로만 느껴져야 한다.
3. 키보드 커서는 회색 영역 하나만 존재한다.
4. 마우스 hover는 점선 placeholder로 표현한다.
5. 카드 선택은 파란 outline로 표현한다.
6. 드래그 중에는 카드가 살짝 뜬다.
7. 드래그 시작 원위치는 파란 강조 상태를 가진다.
8. 드랍 후보 슬롯은 커서 이동형 placeholder처럼 보여야 한다.
9. 내려놓는 순간 자석처럼 슬롯에 탁 붙어야 한다.

### Input Contract

1. 방향키는 선택 카드를 움직이는 것이 아니라 `slot cursor`를 움직인다.
2. slot cursor는 보드 위에 하나만 존재한다.
3. single click은 카드 선택이다.
4. Enter는 현재 카드 인라인 편집 또는 현재 slot cursor 위치의 카드 생성/편집 진입이다.
5. double click은 큰 편집기다.
6. multi-select는 마우스 기반이다.

### Zoom Semantics

1. 카드와 슬롯의 `논리 크기`는 고정이다.
2. 보드 zoom은 현재처럼 전체 슬롯 표면을 확대/축소한다.
3. 즉 `화면상 크기`는 zoom에 따라 바뀌고, `document-space slot size`는 고정이다.
4. 이번 계획은 zoom 모델 자체를 갈아엎지 않는다.

### Group

1. 그룹은 `Card Buddy`에는 없는 개념이다.
2. 하지만 `BWR`에서는 반드시 계속 보인다.
3. 그룹 시각은 카드 앞이 아니라 카드 뒤에 깔리는 판넬/프레임이다.
4. 그룹은 보드 위에서 충분히 분명하게 보여야 한다.
5. 단, 카드 표면보다 더 강하게 시선을 가져가면 안 된다.

### Project Theme State

1. 카드 색상은 카드별 document state로 저장한다.
2. 보드 배경색도 project-level document state로 저장한다.
3. placeholder, selection, cursor의 대비는 배경색이 바뀌어도 유지되어야 한다.

## Existing Code Gaps

현재 보드 구현에서 이번 계획과 충돌하는 지점:

1. `/Users/three/app_build/wa/wa/BWRBoardCanvasView.swift`
   - 카드에 제목 행이 있다.
   - 레이어 뱃지가 있다.
   - 하단 kind / id 메타가 있다.
   - 카드 코너와 그림자가 `Card Buddy`보다 더 앱 카드 같다.
   - 인라인 편집 시 카드 높이와 폭이 바뀐다.
   - 카드 내부에 텍스트 버튼이 직접 노출된다.
2. `/Users/three/app_build/wa/wa/BWRDocumentShellView.swift`
   - 전체 쉘이 아직 앱 패널 구조를 강하게 드러낸다.
   - 카드 내부 affordance보다 사이드바/인스펙터가 더 강하게 읽힌다.
   - 방향키는 빈 슬롯이 아니라 현재 선택 카드 기준으로 동작한다.
3. `/Users/three/app_build/wa/wa/BWRSlotBoardProjection.swift`
   - projection은 슬롯 기반이지만 `slot cursor`, `hover placeholder`, `source marker`, `destination marker`를 담을 독립 상태가 없다.
4. `/Users/three/app_build/wa/wa/BWRSlotBoardInteraction.swift`
   - hover 상태 추적이 없고, placeholder는 드래그 중일 때만 계산된다.
5. `/Users/three/app_build/wa/wa/BWRSlotBoardGeometry.swift`
   - 인라인 편집 시 별도 `inlineCardSize`를 써서 고정 카드 크기 목표와 충돌한다.
6. `/Users/three/app_build/wa/wa/BWRCardTextEditing.swift`
   - 편집기는 기능적으로 충분하지만 카드형 인라인 문법과 결합하는 방식이 아직 거칠다.
7. Markdown preview는 현재 실제 렌더링이 아니라 plain text snippet이다.

## Required State Additions

이번 계획은 아래 상태 추가 없이는 구현할 수 없다.

### 1. Slot Cursor State

새 상태:

1. `slotCursorHost`
2. `slotCursorIndex`
3. `slotCursorVisibility`
4. `lastInputModality`

규칙:

1. 빈 슬롯도 커서 대상이 된다.
2. 방향키는 card selection보다 slot cursor를 우선 갱신한다.
3. card selection은 slot cursor와 공존할 수 있지만, keyboard 입력 기준점은 slot cursor다.

### 2. Hover Placeholder State

새 상태:

1. `hoveredHost`
2. `hoveredInsertionIndex`
3. `hoverLocation`

규칙:

1. hover는 drag state와 별개다.
2. pointer exit 시 즉시 제거된다.
3. keyboard cursor보다 시각 우선순위가 낮다.

### 3. Drag Overlay State

새 상태:

1. `dragSourceSlot`
2. `dragDestinationSlot`
3. `dragLiftStyle`

규칙:

1. source marker와 destination marker는 동시 표시 가능해야 한다.
2. 현재 단일 placeholder 타입으로는 충분하지 않다.

### 4. Appearance Theme State

새 상태:

1. `boardBackgroundHex`
2. `boardAccentMode` 또는 동등한 theme token

규칙:

1. `.bwr` 문서에 저장한다.
2. 카드 색상과 분리한다.

### 5. Markdown Preview Renderer

새 의존성:

1. plain text snippet 대신 lightweight markdown preview renderer가 필요하다.
2. bold, list, soft line break를 카드 안에 맞게 잘라내는 규칙이 필요하다.
3. card preview와 large editor가 서로 다른 markdown 문법을 보여주면 안 된다.

## Target UI Grammar

### 1. Card Shell

카드는 `종이 한 장`처럼 보여야 한다.

필수 규칙:

1. 표면 정보는 본문만.
2. 카드 상단에 별도 텍스트 헤더 없음.
3. 카드 하단에 kind / id / 디버그성 메타 없음.
4. 코너 라운드는 현재보다 줄여 `Card Buddy`에 더 가까운 값으로 고정.
5. 그림자는 더 낮고 넓고 부드러운 종이 떠오름 느낌으로 조정.
6. 본문 시작점은 더 위, 더 왼쪽에 고정.
7. 카드 외곽 rect는 상태와 무관하게 동일하다.
8. 인라인 편집 진입 전후 외곽 프레임은 변하지 않는다.

### 2. Card Content

카드 안의 내용은 `rendered markdown preview`다.

규칙:

1. 글머리표, 굵게, 줄바꿈은 보인다.
2. 텍스트는 너무 조밀하지 않게 유지한다.
3. 5줄 정도의 시각 밀도를 기준으로 한다.
4. overflow는 자연스럽게 잘린다.
5. 본문 첫 줄이 사실상 제목처럼 읽히는 것은 허용한다.

### 3. Selection

선택 상태는 카드 내부가 아니라 카드 외곽이 말한다.

규칙:

1. 파란 outline은 `111.jpg` 기준의 비율과 감각을 따른다.
2. 선택 시 내부 레이아웃은 바뀌지 않는다.
3. 선택 outline은 카드보다 약간 바깥으로 부풀어 오르는 형태가 우선이다.
4. 그룹 선택과 카드 선택은 시각적으로 분리한다.
5. 카드 선택이 그룹 판넬보다 항상 우선 읽혀야 한다.

### 4. Cursor And Hover

보드에는 `단 하나의 keyboard cursor slot`이 있다.

규칙:

1. 방향키는 카드를 움직이는 것이 아니라 커서를 움직인다.
2. keyboard cursor는 카드가 없어도 존재할 수 있다.
3. Enter는 현재 커서 슬롯에서 카드 편집/생성을 연다.
4. 마우스 hover는 keyboard cursor와 별도다.
5. hover는 점선 placeholder로 보인다.
6. keyboard cursor는 회색 solid selection region으로 보인다.
7. 둘은 동시에 존재할 수 있지만, active 입력 장치에 따라 강조 우선순위를 둔다.

### 5. Drag And Drop

드래그는 `floating card`보다 `slot negotiation`처럼 느껴져야 한다.

규칙:

1. 드래그 중 카드가 살짝 뜬다.
2. 드래그 원위치는 파란 source marker를 유지한다.
3. 드랍 후보는 빈 슬롯 placeholder로 드러난다.
4. source marker와 destination marker는 서로 다른 overlay 타입이다.
5. 이웃 카드는 auto-arrange 문법으로 비켜 준다.
6. drop animation은 짧고 자석처럼 끝나야 한다.
7. group block drag도 같은 문법을 따른다.

### 5A. Card Movement Logic Lock

이 섹션은 `카드 이동`만 다룬다.

1. 아직 그룹 자체를 어떻게 드래그하는지는 여기서 잠그지 않는다.
2. 아래 규칙은 카드가 어느 host sequence 안에서 빠지고, 끼워지고, 줄이 닫히는지의 source of truth다.

용어:

1. `host sequence`
   - 카드가 순서 배열로 들어 있는 한 줄의 슬롯 집합
   - 현재 문서 구조에서는 그룹 내부 카드 배열 또는 parking strip 카드 배열이 여기에 해당한다
2. `moving block`
   - 지금 이동 중인 카드들의 순서 보존 블록
3. `stationary cards`
   - 현재 target host에서 moving block을 제외한 카드들
4. `insertion gap`
   - stationary cards 사이, 맨 앞, 맨 뒤를 포함한 드롭 가능한 틈
5. `neighbor anchors`
   - 드롭 순간의 gap 양옆 stationary card identity
   - `previousCardID`, `nextCardID`에 해당하는 앵커 정보
6. `parking anchors`
   - parking strip 내부 gap 양옆 member identity
   - 기존 strip 내부 삽입의 의미를 유지하기 위한 앵커 정보

순서 결정 규칙:

1. 여러 카드를 선택해 이동할 때는 `선택 순서`가 아니라 `현재 보드의 시각 순서`로 moving block을 만든다.
2. moving block 내부 순서는 드래그 전 시각 순서를 그대로 유지한다.
3. 드래그한 대표 카드가 무엇이든, 실제 삽입되는 순서는 moving block의 시각 순서가 기준이다.
4. 시각 순서 tie-break는 아래 순서로 고정한다.
5. 1차 키: 현재 보드의 row
6. 2차 키: 현재 보드의 column
7. 3차 키: 현재 host 내부 순서
8. 4차 키: stable ID
9. 이 tie-break는 flow / parked / 혼합 selection 모두 동일하게 쓴다.

드롭 계산 규칙:

1. target은 항상 `stationary cards 기준 insertion gap`으로 계산한다.
2. 즉 target host 안에 moving card가 이미 있더라도, 드롭 계산에서 그 카드들은 먼저 빠진 것으로 본다.
3. insertion gap은 `0...stationaryCount` 범위를 가진다.
4. `0`은 맨 앞 삽입이다.
5. `stationaryCount`는 맨 뒤 삽입이다.
6. insertion gap만 저장해서는 안 된다.
7. flow host 드롭 타깃은 `host + insertionIndex + previousCardID + nextCardID`를 함께 가진다.
8. parking host 드롭 타깃은 `strip + insertionIndex + previousMemberID + nextMemberID`를 함께 가진다.
9. 커밋 시에는 index보다 anchor를 우선 신뢰하고, index는 fallback으로만 쓴다.

커밋 규칙:

1. 커밋은 항상 두 단계다.
2. 먼저 moving block을 기존 source host들에서 제거한다.
3. source host는 제거 즉시 빈칸 없이 닫힌다.
4. 그 다음 target host의 insertion gap에 moving block을 통째로 삽입한다.
5. target host의 뒤쪽 stationary cards는 moving block 크기만큼 뒤로 밀린다.
6. moving block은 삽입 후 한 덩어리로 연속 배치된다.
7. 이동 후 host 안에는 중간 빈 슬롯이 남지 않는다.
8. 여러 source host에서 왔더라도 removal은 각 source host에서 independently 닫힌다.
9. insertion correction은 오직 `target host` 기준으로만 한다.

같은 host 안 재배치 규칙:

1. 같은 host 안에서 카드를 옮길 때도 먼저 moving block을 제거한 뒤 다시 끼운 것으로 처리한다.
2. 그래서 target gap이 moving block의 원래 뒤쪽에 있을 경우, removal 이전 index를 그대로 쓰면 한 칸 이상 밀린다.
3. 이 경우 `moving block 중 target gap보다 앞에 있던 카드 수`만큼 insertion index를 줄여 보정한다.
4. 여기서 세는 카드는 `destination host 안에 원래 들어 있던 moving cards`만이다.
5. 다른 source host에서 같이 선택된 카드는 same-host 보정 계산에 포함하면 안 된다.
4. 최종 위치가 원래 위치와 완전히 같으면 no-op다.

단일 카드 예시:

1. 맨 앞 카드 하나를 빼서 중간에 넣으면:
   - 원래 host에서는 두 번째 카드가 새 맨 앞이 된다
   - 그 뒤 카드들도 한 칸씩 당겨진다
   - target gap 뒤의 카드들은 한 칸씩 밀린다
2. 맨 뒤 카드 하나를 빼면:
   - 원래 host는 끝이 한 칸 줄어든다
   - 뒤에서 당겨질 카드는 없다
3. 맨 뒤 카드를 다른 host의 중간에 넣으면:
   - source host는 끝이 줄어든다
   - target host는 insertion gap 뒤가 한 칸씩 밀린다

여러 카드 예시:

1. 여러 장을 선택해 이동하면 각각 따로 흩어져 들어가는 게 아니다.
2. 선택된 카드들은 시각 순서 기준의 `한 블록`으로 이동한다.
3. 원래 source host에서는 선택된 카드 수만큼 구멍이 한 번에 닫힌다.
4. target host에서는 그 블록 길이만큼 한 번에 자리를 비운다.
5. 비연속 선택이어도 드롭 후에는 연속 블록으로 붙는다.

parking 이동 규칙:

1. host 밖으로 떼어내는 이동도 같은 removal-first 규칙을 쓴다.
2. source host에서는 moving block이 빠진 뒤 즉시 닫힌다.
3. 기존 parking strip에 놓으면 그 strip의 insertion gap에 moving block을 끼운다.
4. 이때 gap 의미는 `parking anchors`로 유지한다.
5. 어느 strip에 놓을지는 pointer hit와 strip activation rect로 결정한다.
6. 어떤 strip에도 속하지 않으면 `parking drop`으로 본다.
7. parking drop은 start slot에서 연속 빈 슬롯을 찾아 moving block footprint를 배치한다.
8. 기존 strip이 없으면 새 parking strip을 만들고 거기에 moving block을 0번 gap부터 넣는다.
9. parking strip 안에서도 카드들은 빈칸 없이 연속 순서를 가진다.
10. parking에서도 최종 target이 원래 strip, 원래 anchor, 원래 연속 위치와 같으면 no-op다.

시각 피드백 규칙:

1. source marker는 moving block이 빠져나간 원래 슬롯들을 보여줘야 한다.
2. target placeholder는 moving block이 들어갈 연속 footprint를 보여줘야 한다.
3. 여러 카드 이동이면 source marker도 여러 칸, target marker도 여러 칸 블록이어야 한다.
4. 즉 “원래 자리의 닫힘”과 “새 자리의 열림”이 동시에 읽혀야 한다.
5. same-host 재배치에서 source footprint와 target footprint가 겹칠 수 있다.
6. 이 경우 프리뷰는 `최종 커밋 후 배치`를 기준으로 그린다.
7. 즉 source marker는 removal 이후 사라질 칸, target marker는 insertion 이후 생길 칸을 의미해야 한다.
8. 겹치는 칸을 source와 target이 동시에 다른 뜻으로 칠하면 안 된다.

금지:

1. selection 순서대로 카드가 뒤섞여 들어가는 동작 금지.
2. source host에 빈 슬롯을 남기는 동작 금지.
3. moving cards를 target host에서 하나씩 따로 삽입하는 동작 금지.
4. 같은 host 재배치에서 index 보정 없이 한 칸 어긋나는 동작 금지.
5. 다중 선택 이동 후 상대 순서가 뒤바뀌는 동작 금지.
6. anchor 없이 index만 믿고 드롭 의미가 흔들리는 동작 금지.
7. parking에서 같은 자리에 내려놨는데 strip churn이나 slot churn이 생기는 동작 금지.

### 6. Layer Controls

레이어는 보이지 않다가 편집 순간에만 드러난다.

규칙:

1. 카드 normal state에는 레이어 이름/뱃지 없음.
2. 카드 inline editing state에서만 작은 하단 아이콘 affordance를 보인다.
3. 왼쪽 하단:
   - 레이어 순환 버튼
   - 현재 레이어 index / total
4. 오른쪽 하단:
   - 큰 편집기 열기
5. hover만으로는 보이지 않는다.
6. keyboard shortcut은 언제나 사용 가능하다.

### 7. Group Panel

그룹은 카드 밑에 깔리는 `작업 구획`처럼 보여야 한다.

규칙:

1. 항상 보인다.
2. 카드보다 뒤에 있고, 카드와 경쟁하지 않는다.
3. 선택 시 더 분명해진다.
4. 그룹 제목은 프레임 일부로 남길 수 있다.
5. 프레임은 슬롯 흐름을 읽게 도와야지, 카드 표면을 대체하면 안 된다.

### 8. Large Editor

큰 편집기는 `112.jpg` 문법을 따른다.

규칙:

1. dark scrim 위의 큰 흰 종이.
2. 카드와 같은 본문 중심 편집.
3. 하단의 작은 보조 아이콘 문법 유지.
4. `Cancel`, `Save` 류의 명확한 액션 유지.
5. 레이어 이동도 이 창에서 가능해야 한다.

## Implementation Strategy

## Phase A. Preflight Dependencies

목표:

카드 외형보다 먼저, 현재 코드에 없는 상태와 의존성을 문서화하고 seam을 잠근다.

할 일:

1. slot cursor state 추가 지점 확정.
2. hover tracking 추가 지점 확정.
3. drag source / destination overlay 분리 지점 확정.
4. board background theme state 저장 위치 확정.
5. markdown preview renderer 전략 확정.
6. visual snapshot harness 방식 확정.

게이트:

1. `cursor / hover / drag / preview / theme` 각각이 어느 상태와 파일에 들어갈지 명시돼야 한다.
2. 이 게이트 없이 카드 쉘 수정 금지.

## Phase B. Surface Audit Lock

목표:

1. 현재 카드, placeholder, group, cursor의 실제 시각 상태를 스크린샷 기준으로 목록화한다.
2. `Card Buddy` 레퍼런스에서 복사해야 할 값을 수치화한다.

할 일:

1. 카드 외곽 radius, shadow, inner padding, text inset, visible line density를 snapshot으로 잡는다.
2. selection outline thickness, outer spread, color를 snapshot으로 잡는다.
3. overlay 상태 diff 표를 만든다.
   - keyboard cursor
   - mouse hover placeholder
   - drag source marker
   - drag destination placeholder
4. 현 상태와 목표 상태 diff 표를 만든다.

게이트:

1. 카드와 상태 피드백을 같은 테스트 캔버스에서 나란히 비교할 수 있어야 한다.

## Phase C. Slot State Model Rewrite

목표:

현재 `selected-card navigation`을 `slot cursor navigation`으로 바꾸고 hover, source, destination overlay를 독립 상태로 분리한다.

주 수정 파일:

1. `/Users/three/app_build/wa/wa/BWRDocumentShellView.swift`
2. `/Users/three/app_build/wa/wa/BWRBoardOrderResolver.swift`
3. `/Users/three/app_build/wa/wa/BWRBoardCanvasView.swift`
4. `/Users/three/app_build/wa/wa/BWRSlotBoardInteraction.swift`
5. `/Users/three/app_build/wa/wa/BWRSlotBoardProjection.swift`

할 일:

1. 방향키 기준점을 slot cursor로 전환.
2. 빈 슬롯 포커스 허용.
3. hover tracking 도입.
4. drag source / destination overlay 상태 분리.
5. 기존 placeholder kind를 overlay-family 구조로 재정의.
6. source gap / target gap을 moving block 길이에 맞게 동시에 계산.

게이트:

1. 카드가 없는 슬롯에도 회색 cursor가 존재한다.
2. hover와 keyboard cursor가 서로 다른 시각 문법으로 동시에 살아 있다.
3. drag source marker와 destination marker가 동시에 보인다.
4. 다중 선택 드래그 시 source와 destination이 모두 block footprint로 보인다.

## Phase D. Card Shell Rewrite

목표:

카드를 `body-only paper card`로 바꾼다.

주 수정 파일:

1. `/Users/three/app_build/wa/wa/BWRBoardCanvasView.swift`
2. 필요 시 카드 표면 subview 신규 분리

할 일:

1. 제목 행 제거.
2. 레이어 뱃지 제거.
3. 하단 kind / id 메타 제거.
4. 카드 색상 렌더링을 `기본 흰색 + 선택 색상 옵션` 문법으로 정리.
5. card radius, stroke, shadow, padding 재조정.
6. plain text snippet을 markdown preview renderer로 교체.
7. Markdown preview를 5줄 밀도 기준으로 재설계.

게이트:

1. normal card와 selected card가 `111.jpg`와 같은 인상으로 읽혀야 한다.
2. 카드 하나만 캡처해서 봤을 때 앱 위젯처럼 보이면 실패다.

## Phase E. Geometry And Editing Rewrite

목표:

고정 카드 크기와 인라인 편집 문법을 geometry, projection, input 차원에서 맞춘다.

주 수정 파일:

1. `/Users/three/app_build/wa/wa/BWRBoardCanvasView.swift`
2. `/Users/three/app_build/wa/wa/BWRSlotBoardProjection.swift`
3. `/Users/three/app_build/wa/wa/BWRSlotBoardGeometry.swift`
4. `/Users/three/app_build/wa/wa/BWRCardTextEditing.swift`
5. `/Users/three/app_build/wa/wa/BWRDocumentShellView.swift`

할 일:

1. inline expanded rect를 제거하거나 shadow mode로 후퇴.
2. card rect와 editing rect를 분리해도 외곽 card size는 고정 유지.
3. double click large editor 규칙 적용.
4. Enter 인라인 편집 규칙 적용.
5. 편집 중 하단 소형 아이콘 affordance 추가.
6. layer cycle affordance를 편집 중에만 노출.

게이트:

1. 인라인 편집 진입 전후 card frame이 고정이다.
2. split, undo, selection hit-test가 고정 frame 기준으로 계속 맞다.
3. 더블 클릭은 large editor, Enter는 inline edit로 안정적으로 분리된다.

## Phase F. State Grammar Rendering Rewrite

목표:

slot 상태 피드백을 `Card Buddy` 문법으로 렌더링한다.

주 수정 파일:

1. `/Users/three/app_build/wa/wa/BWRBoardCanvasView.swift`
2. `/Users/three/app_build/wa/wa/BWRSlotBoardProjection.swift`
3. `/Users/three/app_build/wa/wa/BWRSlotBoardInteraction.swift`
4. `/Users/three/app_build/wa/wa/BWRSlotBoardGeometry.swift`

할 일:

1. slot grid baseline을 평소엔 숨긴다.
2. keyboard cursor를 회색 영역으로 렌더링.
3. hover placeholder를 점선 문법으로 렌더링.
4. drag source marker를 파란 문법으로 렌더링.
5. drag destination marker를 drop placeholder 문법으로 렌더링.
6. 세 상태의 우선순위를 정한다.
7. multi-card drag일 때 source와 destination 모두 contiguous block frame으로 렌더링.

게이트:

1. 평상시 슬롯선이 안 보인다.
2. cursor, hover, source, destination 네 상태가 전부 구분된다.

## Phase G. Group And Board Theme Integration

목표:

`BWR` 고유 개념인 그룹과 배경색 변경 기능을 `Card Buddy` 문법을 깨지 않는 선에서 얹는다.

주 수정 파일:

1. `/Users/three/app_build/wa/wa/BWRBoardCanvasView.swift`
2. `/Users/three/app_build/wa/wa/BWRDocumentShellView.swift`

할 일:

1. 그룹 판넬을 카드 뒤에 깔리는 프레임/판으로 재설계.
2. 그룹 프레임 색과 두께를 선택, 비선택 두 상태로 고정.
3. 보드 배경색을 document theme state로 저장.
4. 카드 색상과 배경색 조합이 읽히는 palette guardrail 마련.

게이트:

1. 그룹이 보여도 카드가 주인공이어야 한다.
2. 보드 배경색이 달라져도 placeholder, selection, cursor가 항상 읽혀야 한다.

## Phase H. Shell Softening

목표:

카드 주변의 앱 크롬을 약화시켜 카드가 먼저 읽히게 만든다.

주 수정 파일:

1. `/Users/three/app_build/wa/wa/BWRDocumentShellView.swift`

할 일:

1. 보드 배경과 문서 shell의 패널 대비를 낮춘다.
2. 사이드바와 인스펙터의 시각 무게를 줄인다.
3. 보드 중앙 집중도를 높인다.
4. 레이어 조작 UI가 카드 표면보다 먼저 읽히지 않게 줄인다.

게이트:

1. 첫 인상이 `앱 패널`보다 `카드 데스크탑`이어야 한다.

## Phase I. Acceptance Harness

목표:

취향 평가가 아니라, 비교 가능한 시각/동작 검증으로 잠근다.

필수 하네스:

1. visual snapshot harness 기반 준비
2. markdown preview snapshot
3. card state snapshot
   - normal
   - selected
   - inline editing
   - colored
4. slot state snapshot
   - keyboard cursor
   - mouse hover
   - drag source
   - drag destination
   - empty slot placeholder
5. 그룹, 비그룹 혼합 snapshot
6. large editor snapshot
7. 키보드 이동 smoke
8. drag reorder smoke
9. single-card move edge-case smoke
10. multi-card block move smoke

필수 구현 의존성:

1. hover와 drag를 강제로 주입할 수 있는 preview host
2. cursor state를 직접 넣을 수 있는 harness entrypoint
3. board theme color variation harness
4. `source host closing`과 `target host opening`을 검증할 수 있는 deterministic move fixtures

필수 acceptance:

1. 카드 간 간격이 항상 일정하다.
2. 카드 크기는 상태와 무관하게 고정이다.
3. normal card에 메타성 텍스트가 남아 있지 않다.
4. 레이어 affordance는 편집 중에만 보인다.
5. hover, cursor, drag placeholder 상태가 서로 구분된다.
6. drop 후 카드가 정확히 slot rect로 정렬된다.
7. 보드 배경색이 바뀌어도 selection과 placeholder 대비가 깨지지 않는다.
8. 맨 앞 카드 이동, 맨 뒤 카드 이동, 중간 삽입, 다중 선택 이동에서 source host가 빈칸 없이 닫힌다.
9. 다중 선택 이동 후 moving block 내부 순서가 유지된다.

## File Impact Map

### Primary

1. `/Users/three/app_build/wa/wa/BWRBoardCanvasView.swift`
2. `/Users/three/app_build/wa/wa/BWRDocumentShellView.swift`
3. `/Users/three/app_build/wa/wa/BWRSlotBoardProjection.swift`
4. `/Users/three/app_build/wa/wa/BWRSlotBoardInteraction.swift`
5. `/Users/three/app_build/wa/wa/BWRSlotBoardGeometry.swift`
6. `/Users/three/app_build/wa/wa/BWRCardTextEditing.swift`
7. `/Users/three/app_build/wa/wa/BWRBoardOrderResolver.swift`

### Likely New Files

1. `BWRCardSurfaceStyle.swift`
   - 카드 쉘 style token과 state style 계산
2. `BWRBoardStateOverlay.swift`
   - cursor, hover, drag overlay 렌더링 분리
3. `BWRCardEditingChrome.swift`
   - 편집 중 하단 아이콘 affordance 분리
4. `BWRMarkdownCardPreview.swift`
   - 5줄 밀도의 lightweight markdown preview
5. `BWRBoardThemeState.swift`
   - 보드 배경색과 대비 token

새 파일은 모두 1500줄 이하로 쪼갠다.

## Non Goals

1. Kanban 복제
2. 포커스 모드 재설계
3. export 로직 재설계
4. clone, archive, persistence 의미 변경
5. 레이어 모델 변경

## Sequencing Rules

1. slot cursor model 없이 카드 외형만 먼저 바꾸는 작업 금지.
2. hover tracking 없이 점선 placeholder 작업 금지.
3. plain text snippet 상태로 카드 스타일만 바꾸는 작업 금지.
4. card shell과 state grammar는 분리 구현하되, acceptance는 항상 함께 본다.
5. 그룹은 마지막에 얹는다.
6. large editor는 card shell 문법이 잠긴 뒤 맞춘다.
7. shell softening은 카드와 상태가 맞아진 뒤 한다.
8. 카드 이동 구현은 예전 인덱스 뷰의 `remove first, then insert block` 논리를 따른다.

## Review Adjustments

이 문서는 저장 후 적대적 리뷰를 반영해 아래를 추가로 잠갔다.

1. `slot cursor`는 현재 코드에 없으므로 별도 상태 모델 도입이 선행돼야 한다.
2. hover placeholder는 현재 코드에 없으므로 pointer tracking이 필요하다.
3. 고정 카드 크기는 스타일 작업이 아니라 geometry와 projection 작업이다.
4. markdown preview는 snippet 치환만으로 끝나지 않고 별도 renderer가 필요하다.
5. drag source marker와 destination marker는 현재 단일 placeholder 타입으로는 표현할 수 없다.
6. 보드 배경색 커스터마이즈는 document state와 persistence가 필요하다.
7. visual acceptance를 위해 별도 snapshot harness 준비가 선행돼야 한다.
8. 카드 이동 규칙은 `selection order`가 아니라 `current visual order` 기준으로 잠가야 한다.

## Done Definition

완료 기준:

1. `Board Writer` 보드를 처음 봤을 때, 현재보다 훨씬 더 `Card Buddy`의 카드, 슬롯 문법으로 읽힌다.
2. 카드가 `앱 정보 패널`이 아니라 `종이 카드`처럼 보인다.
3. 커서, hover, drag, drop의 상태가 카드 내부가 아니라 슬롯 상태로 읽힌다.
4. 레이어와 그룹이라는 `BWR` 고유 기능이 남아 있어도, Card Buddy의 첫인상을 해치지 않는다.
5. 사용자가 첨부한 `111.jpg`, `112.jpg`, 두 개의 영상과 나란히 놓고 봐도 방향이 명확히 맞다고 말할 수 있다.
