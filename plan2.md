# 연결 카드 기능 구현 계획

작성일: 2026-03-03  
기준 문서: `/Users/three/app_build/wa/research.md`  
기준 코드: `/Users/three/app_build/wa/wa/*.swift`

## 1) 요구사항 재정의 (합의안)

- 기능 시작 조건:
  - 스플릿 스크린에서 "왼쪽 포커스 카드"가 존재할 때,
  - 오른쪽 화면에서 실제로 편집 완료된 카드들을
  - 왼쪽 포커스 카드의 "연결 카드"로 누적 기억한다.
- 검색/조회:
  - 전체 카드 검색 패널(`timelineView`) 검색바 아래 왼쪽에 `연결 카드` 버튼을 추가한다.
  - 버튼을 누르면 "현재 메인 작업창 포커스 카드"에 연결된 카드만 필터링한다.
  - `연결 카드` 버튼 ON 상태에서는 타임라인 카드 클릭으로 편집은 가능해야 한다.
  - 단, 이때 메인 작업창의 포커스 카드(`activeCardID`)는 고정 유지되어야 한다.
- 시각 표시:
  - 어떤 카드가 "연결 카드들을 가진 카드(= 연결 소유 카드)"라면,
  - 카드 우상단 끝에 작은 사각형 배지를 표시한다.
  - 기존 클론 배지(좌상단)와 같은 크기/스타일을 재사용한다.
- 다중 포커스 연결:
  - 같은 카드가 여러 포커스 카드에 연결될 수 있어야 한다.
  - 예: 포커스 1 -> a,b,c / 포커스 2 -> b,c 를 동시에 유지.
- 정렬:
  - 연결 카드 필터 결과는 "해당 연결 기준 마지막 편집 시각" 내림차순(최신 우선) 정렬.

## 1.1 연결 카드 모드 포커스 고정 규칙

- `연결 카드` 필터를 ON 할 때 기준 포커스 카드를 anchor로 고정한다.
- 타임라인에서 연결 카드 항목을 클릭/편집해도 anchor는 변경하지 않는다.
- 즉, \"anchor 카드에 연결된 카드들을 보면서 편집\"하는 흐름을 유지한다.
- anchor 변경은 메인 캔버스에서 사용자가 명시적으로 포커스를 바꾼 경우에만 반영한다.

## 2) 현재 코드 기준 영향 범위

- 스플릿/포커스 상태: `wa/WriterViews.swift`, `wa/MainContainerView.swift`
- 카드 편집 커밋 경계: `wa/WriterCardManagement.swift`, `wa/WriterFocusMode.swift`, `wa/WriterCaretAndScroll.swift`
- 전체 카드 검색 패널: `wa/WriterHistoryView.swift` (`timelineView`)
- 카드 셀 배지 UI: `wa/WriterCardViews.swift`, `wa/WriterFocusMode.swift`
- 저장 포맷/로드: `wa/Models.swift` (`FileStore`, `CardRecord` 등)

## 3) 데이터 모델 설계

### 3.1 연결 관계 저장 구조

- 시나리오 단위 연결 맵을 추가한다.
- 권장 구조:
  - `focusCardID -> (linkedCardID -> lastEditedAt)`
- 목적:
  - 중복 없이 누적 저장
  - 정렬용 타임스탬프 직접 보유
  - 같은 linked 카드의 다중 focus 연결 지원

### 3.2 런타임 스플릿 포커스 공유 구조

- 두 `ScenarioWriterView`(좌/우)는 상태가 분리되어 있으므로,
- `Scenario`에 런타임용 "pane별 active card" 보관 맵을 추가한다.
- 권장 구조:
  - `splitPaneActiveCardByPaneID: [Int: UUID]` (비영속)
- 각 pane의 `changeActiveCard` 시점에 해당 pane ID로 업데이트.
- 오른쪽 편집 기록 시 왼쪽 포커스 카드를 이 맵에서 조회.

### 3.3 영속화 방식

- `FileStore`에 연결 관계 전용 JSON 파일을 시나리오 폴더별로 추가한다.
- 권장 파일명:
  - `linked_cards.json`
- 레코드 포맷(평탄화):
  - `focusCardID`, `linkedCardID`, `lastEditedAt`
- 이유:
  - 기존 `CardRecord`/Undo 구조를 크게 흔들지 않음
  - 기능 전용 데이터를 분리 저장 가능

### 3.4 정리(클린업) 규칙

- 카드 삭제/하드삭제/보관 정리 루틴에서 연결 맵도 정리한다.
- 정리 기준:
  - 존재하지 않는 focusCardID 제거
  - 존재하지 않는 linkedCardID 제거
  - 비어버린 focus 엔트리 제거

## 4) 기록 규칙 (언제 연결로 기록할지)

### 4.1 기록 대상 조건

- `splitModeEnabled == true`
- 현재 편집 pane이 오른쪽(`splitPaneID == 2`)
- 왼쪽 포커스 카드 존재(`splitPaneActiveCardByPaneID[1]`)
- 실제 텍스트 변경이 커밋됨(편집 시작 대비 내용 변경)

### 4.2 기록 시점

- 타이핑 중 매 글자마다 기록하지 않고,
- 편집 커밋 경계(`finishEditing` -> `commitNonEmptyEditingCard`)에서 1회 기록.
- 같은 연결이 다시 편집되면 덮어쓰기(타임스탬프 갱신).
- `연결 카드` 모드 ON에서 타임라인 편집 중이라도 기록 기준 focusCard는 \"현재 편집 카드\"가 아니라 \"고정 anchor 카드\"를 사용한다.

### 4.3 제외 규칙

- 왼쪽 포커스 카드와 오른쪽 편집 카드가 같은 카드 ID면 기본적으로 연결 기록 제외.
- 변경 없는 편집 세션은 기록하지 않음.
- 스플릿 비활성/단일 화면 모드에서는 기록하지 않음.

## 5) UI/UX 구현 계획

### 5.1 카드 우상단 연결 배지

- `CardItem`에 `hasLinkedCards` 플래그 추가.
- 클론 배지(좌상단)는 유지하고,
- 연결 배지는 우상단 끝에 작은 사각형으로 별도 렌더링.
- `isSummarizingChildren` 로딩 인디케이터와 겹치지 않도록 우상단 오버레이를 `HStack/VStack`로 정렬 통합.

### 5.2 포커스 모드 배지 반영

- `focusModeCardBlock`에도 같은 조건 배지 적용.
- 포커스 모드에서도 "연결 소유 카드" 인지가 가능하게 유지.

### 5.3 검색 패널 `연결 카드` 버튼

- 위치: `timelineView` 검색바 바로 아래 행의 왼쪽.
- 상태:
  - 기본 OFF
  - 토글 ON 시 강조 스타일
- 동작:
  - ON: 현재 포커스 카드의 연결 카드만 표시
  - OFF: 기존 전체/검색 결과 로직 유지
- 검색어(`searchText`)와는 AND 조건으로 결합.

### 5.4 연결 카드 필터 정렬

- 연결 모드 ON일 때:
  - `lastEditedAt` 내림차순
  - 동률 시 기존 보조 정렬(`createdAt` 등) 사용
- 연결 모드 OFF일 때:
  - 기존 정렬(현재 `createdAt` 최신순) 유지

### 5.5 빈 결과 UX

- 연결 모드 ON + 결과 없음이면 전용 문구 표시:
  - 포커스 카드가 없을 때
  - 연결 카드가 아직 없을 때
  - 검색어로 추가 필터되어 0건일 때

### 5.6 연결 카드 모드 타임라인 클릭 동작

- 연결 모드 OFF(기존 동작):
  - 타임라인 카드 클릭 시 기존처럼 `changeActiveCard`를 통해 메인 포커스가 이동한다.
- 연결 모드 ON(신규 동작):
  - 타임라인 카드 클릭 시 메인 포커스는 이동시키지 않는다.
  - 대신 클릭한 타임라인 카드에 대해 편집 상태(`editingCardID`)를 열어 즉시 편집 가능하게 한다.
  - 편집 종료 후에도 메인 포커스는 anchor 카드로 유지한다.

## 6) 파일 단위 작업 계획

1. `wa/Models.swift`
- `Scenario`에 연결 맵 API 추가:
  - `recordLinkedCard(focusCardID:linkedCardID:at:)`
  - `linkedCards(for focusCardID:)`
  - `hasLinkedCards(_ focusCardID:)`
  - `pruneLinkedCards(validCardIDs:)`
- `FileStore` 로드/저장에 `linked_cards.json` 추가.
- Codable 레코드(`LinkedCardRecord`) 추가.

2. `wa/WriterCardManagement.swift`
- `changeActiveCard`에서 pane별 active card를 시나리오 런타임 맵에 동기화.
- `commitNonEmptyEditingCard`에서 연결 기록 트리거 추가(우측 pane 조건 포함).
- 카드 삭제 루틴 이후 연결 맵 정리 호출.

3. `wa/WriterHistoryView.swift`
- `timelineView`에 `연결 카드` 토글 버튼 UI 추가.
- 타임라인 데이터 계산 로직을
  - 기본 목록
  - 검색 필터
  - 연결 필터
  - 연결 정렬
  순서로 재구성.
- 연결 모드 ON일 때 타임라인 row의 `onSelect`/`onDoubleClick`을
  - \"포커스 이동\" 경로가 아닌
  - \"포커스 고정 편집 시작\" 경로로 분기.

4. `wa/WriterViews.swift`
- 연결 필터 UI 상태(`@State`) 추가.
- 연결 모드 anchor 상태(`linkedCardAnchorID`) 추가.
- 패널 닫기/열기 시 상태 리셋 정책 정의(기본: 닫을 때 OFF).

5. `wa/WriterCardViews.swift`
- `CardItem` 입력 파라미터에 `hasLinkedCards` 추가.
- 우상단 연결 배지 렌더링.

6. `wa/WriterFocusMode.swift`
- 포커스 카드 블록 우상단 연결 배지 렌더링.

## 7) 검증 시나리오 (구현 후 체크리스트)

1. 기본 기록
- 스플릿 ON, 왼쪽 카드 1 포커스, 오른쪽에서 a/b/c 편집 후 종료
- 카드 1의 연결 목록이 a/b/c로 저장되는지 확인

2. 다중 포커스
- 왼쪽 카드 2 포커스로 전환 후 오른쪽에서 b/c만 편집
- 카드 1은 a/b/c 유지, 카드 2는 b/c만 갖는지 확인

3. 최신순 정렬
- 같은 focus에서 b를 다시 편집
- 연결 카드 필터 결과에서 b가 최상단으로 오는지 확인

4. 배지 표시
- 연결 소유 카드만 우상단 배지 표시되는지
- 클론 배지(좌상단)와 충돌 없는지

5. 검색 결합
- 연결 필터 ON + 검색어 입력 시 교집합만 표시되는지

6. 삭제 정리
- focus 카드 삭제 시 해당 연결 엔트리 제거
- linked 카드 삭제 시 모든 focus에서 해당 카드 연결 제거

7. 비활성 조건
- 단일 화면 모드에서 편집해도 연결이 기록되지 않는지

8. 포커스 고정 동작
- 연결 모드 ON 후 타임라인에서 b/c 편집해도 메인 포커스 카드가 anchor로 유지되는지
- 연결 모드 OFF로 전환하면 기존 클릭-포커스 이동 동작이 복원되는지

## 8) 위험 요소 및 대응

- 위험: split pane 상태 경쟁으로 잘못된 focusCardID가 기록될 수 있음
- 대응: 편집 커밋 시점에 왼쪽 pane active ID를 재검증하고 nil이면 스킵

- 위험: 우상단 인디케이터 겹침(요약 로더/배지)
- 대응: `topTrailing` 오버레이를 단일 컨테이너로 통합해 레이아웃 우선순위 명확화

- 위험: 연결 데이터가 undo/redo 기대와 어긋날 수 있음
- 대응: 연결 데이터는 "작업 메타데이터"로 간주해 undo 대상에서 제외(명시)

- 위험: 타임라인 편집 카드(`editingCardID`)와 메인 포커스(`activeCardID`) 분리로 기존 가정이 깨질 수 있음
- 대응: 연결 모드 ON에서만 분리 허용하고, 관련 분기(`onSelect`, `beginCardEditing`, finish 이후 포커스 복원)를 명시적으로 분리

## 9) 완료 정의 (DoD)

- 연결 카드 기록/조회/정렬/배지가 모두 동작한다.
- 다중 포커스 연결이 정확히 분리 저장된다.
- `연결 카드` 버튼으로 포커스 기반 필터가 적용된다.
- 삭제/정리 후 고아 연결 데이터가 남지 않는다.
- 기존 기능(검색, 히스토리, 포커스, 스플릿 입력 제어)에 회귀가 없다.

## 10) 이번 턴 실행 범위

- 본 문서(`plan2.md`) 작성만 수행.
- 코드 구현/빌드/테스트는 사용자의 "실행" 지시 전까지 진행하지 않음.
