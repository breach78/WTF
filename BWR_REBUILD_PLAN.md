# BWR Rebuild Plan

## 목적

BWR를 Card Buddy의 스토리보드 계열 핵심만 남긴 형태로 다시 만든다.

이번 리빌드의 목표는 다음 네 가지다.

- `.cards`와 같은 패키지 문서형 컨테이너를 가진다.
- 카드 배치는 자유 좌표가 아니라 희소한 논리 슬롯 `x, y` 기반으로 동작한다.
- 카드 내용은 단일 노트가 아니라 다층 `layer` 구조로 저장된다.
- 키보드 커서, 포인터 호버, 카드 선택, 다중 선택, 드래그 드롭이 서로 독립된 상태로 동작한다.

## 확정된 제품 결정

- 기존 데이터 마이그레이션은 하지 않는다.
- 저장 포맷은 새 포맷으로 깨끗하게 시작한다.
- 문서는 패키지 컨테이너다.
- 패키지 안에는 최소 `database.sqlite`, `assets/`, `thumbnail.jpg`를 둔다.
- PDFKit은 사용하지 않는다.
- 텍스트 스타일은 markdown 하나만 지원한다.
- kanban 보드는 만들지 않는다.
- 문서 단위 설정 테이블은 유지한다.
- soft delete와 `lastModified`를 처음부터 저장한다.
- 썸네일은 문서 안에 미리 렌더링해 저장한다.

## 원본 분석에서 가져갈 것

- 카드 배치 인스턴스와 실제 내용 저장소를 분리한다.
- 카드 내용은 `content` 아래의 여러 `layer`로 나눈다.
- 각 layer는 독립적으로 markdown, palette, asset link를 가질 수 있다.
- 보드 좌표는 픽셀이 아니라 논리 슬롯이다.
- 문서 수준 `settings`가 보드 해석 방식을 결정한다.
- 이미지와 기타 자료는 카드 타입이 아니라 layer에 연결된 asset로 본다.

## 버릴 것

- 기존 JSON 기반 저장 포맷
- 고정 `rows x columns`만 전제하는 현재 보드 모델
- 카드 한 장에 note 하나만 있는 현재 모델
- `plain`, `flashcard` 같은 텍스트 스타일 분기
- PDF export/import 계열
- kanban 전용 레이아웃과 동작
- 기존 데이터 호환성

## 영상 기반 상호작용 해석

업로드된 [화면 기록 2026-04-11 오후 7.59.44.mov](/var/folders/xv/sl008w8x451b97mhtf_7rzc80000gn/T/TemporaryItems/NSIRD_screencaptureui_CDLV6A/화면%20기록%202026-04-11%20오후%207.59.44.mov)을 5초 단위 시퀀스 시트와 샘플 프레임으로 확인했다.

핵심 상태는 최소 네 개다.

- `keyboardCursorSlot`
  짙은 회색의 다른 카드보다 큰 슬롯 음영이다. 화살표 키 이동에 반응한다. 카드 선택 여부와 별개로 존재한다.
- `hoverSlot`
  옅은 점선 슬롯이다. 포인터 위치에만 반응한다. 키보드 커서와 동시에 다른 위치에 존재할 수 있다.
- `selection`
  카드 선택 상태다. 원본 영상은 파란 외곽선처럼 보이지만, 우리 앱에서는 이전 결정대로 카드 아래 깔리는 반전 underlay로 표현한다.
- `dragPreview`
  다중 선택 후 이동할 때 반투명한 파란 프리뷰 블록이 함께 움직인다. 단일 카드 드래그와 다중 카드 드래그가 시각적으로 다르다.

영상에서 읽힌 동작은 다음과 같다.

- 키보드 커서는 빈 슬롯과 카드 슬롯을 모두 통과하며 이동한다.
- 포인터 호버 슬롯은 키보드 커서와 독립적으로 남는다.
- 선택된 카드는 커서 이동과 별도로 유지된다.
- 키보드 이동 중 선택 카드가 바뀌는 구간이 있고, 선택은 카드 단위다.
- 다중 선택 후 드래그할 때 개별 카드 테두리와 별도 반투명 블록 프리뷰가 겹쳐 보인다.
- 드롭 대상 슬롯 주변에 별도 강조가 나타난다.
- 빈 슬롯은 생성 대상이 될 수 있고, 선택과 호버의 기준이 된다.

이 해석에 따라 보드 렌더링 상태는 최소 아래 구조로 잡는다.

```swift
enum BoardSelection {
    case none
    case cards(Set<UUID>)
    case slots(Set<BoardSlot>)
}

struct BoardInteractionState {
    var keyboardCursorSlot: BoardSlot?
    var hoverSlot: BoardSlot?
    var selection: BoardSelection
    var marqueeRect: CGRect?
    var dragSession: BoardDragSession?
    var editingCardID: UUID?
}
```

상태 불변식:

- `selection`은 `cards` 또는 `slots` 중 하나만 가진다.
- `editingCardID != nil`이면 `marqueeRect == nil` 이어야 한다.
- `dragSession != nil`이면 새 marquee 시작은 금지한다.
- `selection = .slots`일 때 해당 슬롯에는 active card가 없어야 한다.
- `keyboardCursorSlot`과 `hoverSlot`은 selection과 독립이지만 둘 다 유효 slot이어야 한다.

## 목표 문서 구조

`.bwr` 패키지 예시:

```text
My Board.bwr/
  database.sqlite
  assets/
    <asset-id>.<ext>
  thumbnail.jpg
```

문서 저장의 기준은 SQLite다.

- 보드 모델 상태는 SQLite에 저장한다.
- 썸네일은 별도 파일로 저장한다.
- 실제 바이너리 자산은 `assets/` 폴더에 둔다.
- 데이터베이스에는 자산 메타데이터와 상대 경로만 둔다.
- v1 패키지 문서는 `database.sqlite-wal`, `database.sqlite-shm`를 문서 구성에 포함하지 않는다.
- 이를 위해 문서 DB는 `journal_mode = DELETE`로 고정하고, 저장은 checkpoint 없는 단일 파일 기준으로 처리한다.
- 문서 저장은 `임시 패키지 작성 -> SQLite 닫기 -> 필수 파일 검증 -> atomic replace` 순서로 처리한다.

## 저장소 불변식

- v1에서 active card 1장은 active content 1개를 소유한다.
- active card는 한 번에 하나의 active slot만 가진다.
- active slot 하나에는 active card 하나만 존재한다.
- presented layer는 `layerIndex`가 아니라 `layerId`로 참조한다.
- `layerIndex`는 content 내부에서 `0` 기반 연속 정수다.

## SQLite 스키마 초안

현재 목표는 원본의 단순 복제가 아니라, layer 수를 열어 둔 확장형 저장소다.

### 1. 문서와 설정

`DocumentMeta`

- `documentId TEXT PRIMARY KEY`
- `createdAt TEXT NOT NULL`
- `updatedAt TEXT NOT NULL`
- `schemaVersion INTEGER NOT NULL`

`DocumentSettings`

- `documentId TEXT PRIMARY KEY`
- `canvasTemplate TEXT NOT NULL`
- `layoutAlgorithm TEXT NOT NULL`
- `layoutMode TEXT NOT NULL`
- `insertMode TEXT NOT NULL`
- `cardWidth REAL NOT NULL`
- `cardHeight REAL NOT NULL`
- `spacingX REAL NOT NULL`
- `spacingY REAL NOT NULL`
- `cardCornerRadius REAL NOT NULL`
- `backgroundTone TEXT NOT NULL`
- `defaultCardPalette TEXT`
- `tabKeySaves INTEGER NOT NULL`
- `enterKeySaves INTEGER NOT NULL`
- `lastModified TEXT NOT NULL`

초기 settings 후보:

- `canvasTemplate = "chronological"`
- `layoutAlgorithm = "chronological"`
- `layoutMode = "grid"`
- `insertMode = "horizontal"`
- `cardSize = [w,h]`
- `cardSpacing = [x,y]`
- `cardCornerRadius`
- `backgroundTone`
- `defaultCardPalette`
- `defaultLayerMarkdownMode = "markdown"`
- `tabKeySaves`
- `enterKeySaves`

### 2. 카드 인스턴스와 배치

`Cards`

- `cardId TEXT PRIMARY KEY`
- `contentId TEXT NOT NULL UNIQUE`
- `x INTEGER NOT NULL`
- `y INTEGER NOT NULL`
- `deleted INTEGER NOT NULL DEFAULT 0`
- `createdAt TEXT NOT NULL`
- `lastModified TEXT NOT NULL`

`CardPresentedLayers`

- `cardId TEXT PRIMARY KEY`
- `presentedLayerId TEXT NOT NULL`
- `lastModified TEXT NOT NULL`

`CardPalettes`

- `cardId TEXT PRIMARY KEY`
- `paletteName TEXT`
- `lastModified TEXT NOT NULL`

### 3. 콘텐츠와 레이어

`CardContents`

- `contentId TEXT PRIMARY KEY`
- `createdAt TEXT NOT NULL`
- `lastModified TEXT NOT NULL`

`Layers`

- `layerId TEXT PRIMARY KEY`
- `contentId TEXT NOT NULL`
- `layerIndex INTEGER NOT NULL`
- `createdAt TEXT NOT NULL`
- `deleted INTEGER NOT NULL DEFAULT 0`
- `lastModified TEXT NOT NULL`

`LayerMarkdown`

- `layerId TEXT PRIMARY KEY`
- `markdown TEXT`
- `lastModified TEXT NOT NULL`

`LayerPalette`

- `layerId TEXT PRIMARY KEY`
- `paletteName TEXT`
- `lastModified TEXT NOT NULL`

`LayerAsset`

- `layerId TEXT PRIMARY KEY`
- `assetId TEXT`
- `lastModified TEXT NOT NULL`

### 4. 자산

`Assets`

- `assetId TEXT PRIMARY KEY`
- `storedFilename TEXT NOT NULL`
- `originalFilename TEXT`
- `contentType TEXT`
- `createdAt TEXT NOT NULL`
- `updatedAt TEXT NOT NULL`

추가 제약:

- `UNIQUE(contentId, layerIndex)` on `Layers`
- `UNIQUE(x, y) WHERE deleted = 0` on `Cards`
- `FOREIGN KEY(Cards.contentId) -> CardContents.contentId`
- `FOREIGN KEY(CardPresentedLayers.cardId) -> Cards.cardId`
- `FOREIGN KEY(Layers.contentId) -> CardContents.contentId`
- `FOREIGN KEY(LayerMarkdown.layerId) -> Layers.layerId`
- `FOREIGN KEY(LayerPalette.layerId) -> Layers.layerId`
- `FOREIGN KEY(LayerAsset.layerId) -> Layers.layerId`
- `FOREIGN KEY(LayerAsset.assetId) -> Assets.assetId`
- `CardPresentedLayers.presentedLayerId`가 해당 카드의 `contentId` 소속 layer인지 검증하는 trigger를 둔다.
- `CardPresentedLayers.presentedLayerId`는 `deleted = 0`인 layer만 가리킬 수 있다.
- v1 드롭 충돌 정책은 다음과 같이 고정한다.
  - 단일 카드가 occupied slot에 드롭되면 `swap`
  - 연속 sequence/cluster가 occupied slot 범위에 들어가면 `insertMode` 축 기준으로 shift
  - invalid collision은 reject
- 좌표가 여러 장 동시에 바뀌는 모든 연산은 transaction 안에서 `parking slot -> target slot`의 2단계 remap으로 처리한다.
- row/column insert, delete, reorder, sequence shift는 순진한 단일 `UPDATE`를 금지한다.

## 앱 메모리 모델 방향

UI는 DB row를 직접 다루지 않고, 아래 읽기 모델로 조립한다.

```swift
struct BoardDocumentModel {
    var metadata: BoardDocumentMetadata
    var settings: BoardSettings
    var cards: [BoardCardInstance]
    var contents: [UUID: BoardCardContent]
    var assets: [UUID: BoardAsset]
}

struct BoardCardInstance {
    var id: UUID
    var contentID: UUID
    var slot: BoardSlot
    var presentedLayerID: UUID
    var palette: CardPalette?
    var deleted: Bool
    var createdAt: Date
    var updatedAt: Date
}

struct BoardCardContent {
    var id: UUID
    var layers: [BoardLayer]
    var updatedAt: Date
}

struct BoardLayer {
    var id: UUID
    var index: Int
    var markdown: String
    var palette: CardPalette?
    var assetID: UUID?
    var updatedAt: Date
}
```

## 렌더링 모델

보드는 희소한 슬롯 기반으로 렌더링한다.

- 저장은 `x, y`만 믿는다.
- 화면에 보이는 범위는 카드 분포, 커서 슬롯, hover 슬롯, 드래그 프리뷰를 모두 포함하는 bounds를 계산해서 정한다.
- 따라서 실제 렌더링 그리드는 "고정 보드 크기"가 아니라 "현재 필요한 가시 영역"이다.

필요 계산:

- visible min/max slot bounds
- content bounds padding
- drop target preview slots
- sequence/cluster drag ghost bounds

논리 순서 규칙:

- 기본 logical order는 `y ASC, x ASC`다.
- `insertMode = horizontal`이면 같은 row 안에서는 `x` 우선, 다음 row로 넘어간다.
- empty slot도 logical order에 포함한다.
- 편집 중 `Tab`으로 다음 logical slot이 비어 있으면 새 카드 생성 후 편집으로 이어질 수 있다.

## 입력 및 상태 머신

### 키보드

- 화살표 키: `keyboardCursorSlot` 이동
- `Enter`
  - 빈 슬롯이면 새 카드 생성
  - 카드 슬롯이면 현재 presented layer를 인라인 편집
- `Tab`
  - logical order 다음 슬롯으로 이동
  - 편집 중이면 저장 후 다음 슬롯 편집
- `Shift+Tab`
  - 이전 슬롯 이동
- `Esc`
  - 편집 취소
- `Delete`
  - soft delete

명령 타깃 우선순위:

- `editing text`
- `drag session`
- `explicit selection`
- `keyboardCursorSlot`

키 규칙:

- `Delete`는 편집 중이면 텍스트 삭제만 하고 카드 삭제로 승격되지 않는다.
- `Delete`는 편집 중이 아닐 때 explicit selection을 우선 삭제한다.
- explicit selection이 없으면 `keyboardCursorSlot` 아래 active card를 삭제한다.
- `Esc`는 편집 종료 후 drag, marquee, selection 순으로 한 단계씩 닫는다.
- `Enter`는 편집 중이면 저장, 편집 중이 아니면 타깃 우선순위에 따라 생성 또는 편집 진입이다.

### 포인터

- hover: `hoverSlot` 업데이트
- single click
  - 카드면 카드 선택
  - 빈 슬롯이면 슬롯 선택
- double click
  - 카드면 인라인 편집
  - 빈 슬롯이면 카드 생성 후 편집
- drag
  - 단일 카드 드래그
  - 다중 카드면 cluster 또는 sequence drag

### 선택 모델

- 단일 카드 선택
- 다중 카드 선택
- marquee box 선택
- sequence 선택
- head 기준 sequence 선택

## 선택/드래그 규칙

### 단일 선택

- 카드 선택은 카드 단위다.
- 빈 슬롯 선택은 카드가 없을 때만 별도 상태로 둔다.
- 선택된 카드가 있어도 `keyboardCursorSlot`은 다른 슬롯에 있을 수 있다.

### 다중 선택

- `selection = .cards`를 기준으로 유지한다.
- 선택 카드가 한 행 또는 한 열로만 이어지면 sequence 후보로 본다.
- 2차원으로 퍼져 있으면 cluster로 본다.
- 비연속 선택은 항상 cluster다.
- sequence는 `동일 축 + 연속 좌표`일 때만 성립한다.
- head는 v1에서 `최초 선택 카드`로 고정한다.

### 드래그 프리뷰

- 단일 카드 드래그는 카드 한 장 ghost를 보여준다.
- sequence 드래그는 드롭 방향의 행 또는 열 프리뷰를 그린다.
- cluster 드래그는 원래 상대 배치를 유지한 프리뷰를 그린다.
- 드롭 대상은 별도 slot emphasis를 준다.

## 생성과 편집 UX

- 카드 수정은 카드 인라인에서 직접 한다.
- 오른쪽 패널은 이번 범위에 넣지 않는다.
- 현재 presented layer의 markdown을 카드 안에서 편집한다.
- layer 전환 UI는 첫 단계에서는 단순하게 두고, 저장소는 다층 구조를 먼저 연다.
- 초기 버전에서는 새 카드 생성 시 layer 1개를 만든다.
- 이후 layer 추가, 순서 변경, 활성 layer 전환을 붙인다.
- v1에서는 layer 삭제를 UI에 노출하지 않는다.
- layer reorder는 단일 transaction에서 전체 `layerIndex`를 재번호한다.

## 행과 열 관련 기능

kanban은 없지만 row/column 조작은 유지한다.

후속 구현 후보:

- row insert
- column insert
- row delete
- column delete
- row/column reorder handle

이 기능은 실제 저장을 대량 좌표 변환으로 처리한다.

행/열 변환 규칙:

- active card만 이동 대상이다.
- soft-deleted card는 이동하지 않는다.
- 변환 완료 후 `keyboardCursorSlot`, `hoverSlot`, `selection`은 동일 delta로 재매핑한다.
- 충돌 가능 연산은 `parking slot`에 잠시 비운 뒤 최종 좌표로 재배치한다.

## 검색과 이동

- 검색은 현재 presented layer markdown과 다른 layer markdown 전체를 모두 검색한다.
- 검색 읽기 모델은 `SearchResult(cardId, layerId, range)`다.
- `Go To`는 검색 결과 첫 카드로 커서를 이동하고 선택을 맞춘다.
- 매치가 비표시 layer에 있으면 `presentedLayerID`를 그 layer로 임시 전환하거나 hit badge를 표시한다.
- 검색 결과 이동은 logical order를 따른다.

## soft delete와 변경 추적

모든 핵심 row는 `lastModified`를 둔다.

삭제 규칙:

- 카드는 바로 물리 삭제하지 않는다.
- `Cards.deleted = 1`로 tombstone 처리한다.
- 복원은 tombstone을 뒤집되, 원래 슬롯이 비어 있으면 원위치 복원한다.
- 원래 슬롯이 이미 재사용되었으면 원래 좌표부터 시작하는 logical order 기준 가장 가까운 빈 슬롯으로 재배치한다.

초기 undo 전략:

- 1차는 UI 레벨 undo
- 저장소 레벨에서는 tombstone과 수정 시각을 남겨 복원 가능성을 확보

## 썸네일 생성

썸네일은 active non-deleted cards의 content bounds를 기준으로 `thumbnail.jpg`로 저장한다.

초기 방법:

- SwiftUI 렌더러 기반 보드 스냅샷 생성
- 전체 무한 보드가 아니라 active card 분포 bounds 기준 렌더링
- 너무 큰 문서는 clamp된 preview bounds 사용
- 갱신 시점은 `save debounce`와 `app background/save` 시점으로 고정한다.

## 구현 단계

### Phase 1. 저장소 리빌드

- SQLite 읽기/쓰기 경로를 추가한다.
- 패키지 문서 저장 기준을 SQLite로 바꾼다.
- SQLite schema bootstrap을 만든다.
- foreign key, presented-layer validation trigger, journal mode를 함께 고정한다.
- `assets/`와 `thumbnail.jpg` 저장 루틴을 만든다.

완료 기준:

- 새 문서를 만들면 패키지 구조가 생성된다.
- 문서를 다시 열면 SQLite에서 모델을 읽는다.
- 새 SQLite 경로가 검증된 뒤 기존 JSON 저장 경로를 제거한다.

### Phase 2. 모델 리빌드

- `CardNote` 중심 메모리 모델을 `card instance + content + layers`로 바꾼다.
- 현재 UI가 최소 1-layer 카드라도 새 모델 위에서 돌아가게 한다.

완료 기준:

- 카드 생성, 이동, 수정, 삭제가 새 DB 모델에 반영된다.

### Phase 3. 희소 슬롯 보드

- 고정 rows/columns 그리드를 제거한다.
- visible bounds 계산 기반 보드를 만든다.
- `keyboardCursorSlot`, `hoverSlot`, `selection`을 분리한다.

완료 기준:

- 짙은 키보드 커서 슬롯과 점선 hover 슬롯이 동시에 보인다.
- 선택 카드와 커서 슬롯이 서로 독립적으로 유지된다.

### Phase 4. 인라인 편집과 logical navigation

- Enter, Tab, Shift+Tab, 화살표 이동을 구현한다.
- 빈 슬롯 생성과 카드 인라인 수정 흐름을 맞춘다.

완료 기준:

- 키보드만으로 카드 생성, 편집, 이동이 가능하다.

### Phase 5. 선택과 드래그

- 단일 선택
- 다중 선택
- marquee 선택
- sequence 선택
- head 기준 sequence drag
- cluster vs sequence smart drag

완료 기준:

- 영상에서 본 선택/드래그 패턴이 대부분 재현된다.

### Phase 6. 문서 기능 마감

- soft delete/restore
- 검색과 Go To
- row/column 편집
- asset layer 연결
- thumbnail 갱신

완료 기준:

- 문서형 앱으로 쓸 수 있는 핵심이 닫힌다.

## 현재 코드 기준 주요 교체 지점

- [BWR/BWRModels.swift](/Users/three/app_build/wa/BWR/BWRModels.swift)
  현재 `CardNote + BoardCanvas` 구조를 폐기하고 새 문서 모델로 교체
- [BWR/BWRDocument.swift](/Users/three/app_build/wa/BWR/BWRDocument.swift)
  `manifest.json` 기반 저장을 SQLite 패키지 저장으로 교체
- [BWR/BWRBoardView.swift](/Users/three/app_build/wa/BWR/BWRBoardView.swift)
  `LazyVGrid` 고정 캔버스를 희소 슬롯 렌더링과 다중 상태 오버레이로 교체
- [BWR/BWRBoardScene.swift](/Users/three/app_build/wa/BWR/BWRBoardScene.swift)
  선택/편집/검색 상태를 interaction state 기반으로 재구성

## 범위 밖

- kanban 보드
- import 계열
- PDF 관련 기능
- 기존 데이터 호환성
- 오른쪽 기능 패널

## 먼저 구현할 때의 원칙

- 최소한의 UI로 저장소를 먼저 바꾼다.
- layer 수는 저장소에서 먼저 열고, UI는 1-layer부터 시작한다.
- 시각 표현은 "선택", "키보드 커서", "호버", "드래그 프리뷰"를 절대 섞지 않는다.
- JSON과 SQLite를 동시에 유지하지 않는다.
- migration 코드는 만들지 않는다.

## 첫 구현 순서

1. SQLite 패키지 문서 뼈대 작성
2. 새 메모리 모델 연결
3. 희소 슬롯 보드 렌더링
4. 키보드 커서와 hover 슬롯 분리
5. Enter/Tab 기반 생성 및 편집
6. soft delete와 검색
7. 다중 선택과 smart drag
8. asset layer와 thumbnail
