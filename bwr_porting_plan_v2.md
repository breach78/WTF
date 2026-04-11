# BWR Porting Plan v2

## Scope

`wa`를 트리 기반 macOS 앱에서, 인덱스 보드 중심의 `Board Writer (.bwr)` 앱으로 재구성하고, iPadOS 26+를 기준으로 설계하되 Apple Silicon Mac에서도 바로 실행·검증 가능한 형태로 포팅한다.

## Board Realignment Override

보드 표면 의미는 더 이상 이 문서 단독으로 읽지 않는다.

1. `/Users/three/app_build/wa/bwr_index_board_realignment_plan.md`의 `R0` 결정 잠금 이후, 보드 모델과 상호작용의 source of truth는 그 문서다.
2. 이 문서에서 아래 충돌 구간은 superseded 상태다.
3. `Product Lock`의 자유배치 전제
4. `Data Model`의 `layout: CGPoint` 중심 카드 위치 정의
5. `Group`의 다중 live membership 전제
6. `Layout` 전체 섹션
7. `Board Experience` 전체 섹션
8. `Execution Milestones` 중 보드 표면과 자유배치 스파이크를 전제로 한 부분
9. 포커스, export, archive, 파일 앱 전략처럼 realignment 문서와 충돌하지 않는 비보드 항목만 계속 유효하다.

## Product Lock

이 섹션의 보드 의미 중 자유배치와 전역 좌표 순서를 전제로 한 항목은 `/Users/three/app_build/wa/bwr_index_board_realignment_plan.md`에 의해 superseded된다.

1. 앱 이름은 `Board Writer`, 문서 확장자는 `.bwr`다.
2. 새 앱은 단일 프로젝트 앱이다. 실행 직후 바로 보드로 진입한다.
3. 기존 `wtf` 포맷, 레거시 마이그레이션, 폴백 UI는 만들지 않는다.
4. 트리는 완전히 제거한다.
5. **시나리오는 완전히 제거한다.** 하나의 `.bwr` 문서에는 하나의 보드만 존재한다. 복수 시나리오, 시나리오 전환, 시나리오간 공유 크래프트 트리는 모두 폐기한다.
6. 보관용 기록, superseded: 메인 작업공간은 현재 인덱스 보드의 손맛을 계승한 자유 카드 보드다.
7. 그룹은 부모 카드가 아니라 별도 객체다. 그룹은 출력과 포커스의 단위이지 시나리오의 대체물이 아니다.
8. 보관용 기록, superseded: 그룹 내부 순서는 보드의 전역 좌표를 기준으로 `좌상단 -> 우측 -> 하단`으로 계산하되, 동점 해소를 위해 `stableSortKey`를 2차 키로 사용한다.
9. 카드는 제목 없이 본문만 가진다. 본문은 Markdown이며 렌더링된다.
10. 각 카드는 자체 레이어 집합을 가진다.
11. 기본 레이어 순서는 `본문 1 ... 본문 n > 트리트먼트 > 시나리오`다.
12. 카드 타일에는 항상 그 카드의 현재 레이어만 보인다.
13. 포커스 모드는 필수다. 모드는 `현재 레이어`, `트리트먼트`, `시나리오` 3개다.
14. 출력도 동일하게 `현재 레이어`, `트리트먼트`, `시나리오` 3축으로 한다.
15. AI, 레퍼런스 윈도, 트리 카테고리, temp lane/strip/detached 개념은 제거한다.
16. 삭제 기본 의미는 `아카이브`다. 찾기와 아카이브 복구 기능이 반드시 있어야 한다.
17. 단, 클론이 삭제되는 경우는 예외 규칙을 둔다. 아래 `Clone Semantics`를 기준으로 hard delete를 허용한다.
18. 외부 키보드와 트랙패드는 핵심 입력이다.
19. 기본 단축키 우선순위는 `Enter`, `Shift+Enter`, `Delete`, `Arrow Navigation`이다.
20. PDF/TXT 출력 엔진의 결과물은 현재 앱과 시각적으로 동일해야 한다.

## Platform Strategy

1. 제품 기준은 `iPad first`다.
2. 그러나 개발과 테스트 효율을 위해 Apple Silicon Mac에서도 직접 실행 가능해야 한다.
3. 구현 전략은 `iPad idiom 단일 코드베이스 + Apple Silicon Mac 실행 허용`이다.
4. 별도 macOS 전용 경험은 만들지 않는다.
5. Mac에서는 `Designed for iPad` 수준을 기준으로 먼저 맞추고, 테스트를 막는 입력/파일/출력 문제만 보정한다.
6. 이 결정 덕분에 iPad 상호작용을 흐리지 않으면서도 매번 실기기를 붙이지 않고 빠르게 검증할 수 있다.
7. Mac은 별도 제품이 아니라 `검증 호스트`다.
8. 기본 입력 계약은 `터치 + 외부 키보드 + 트랙패드`를 모두 1급으로 다루는 iPad 상호작용이다.
9. Mac acceptance bar는 `보드 편집`, `포커스 모드`, `파일 열기/저장`, `출력`, `undo/redo`가 막히지 않는 것이다.
10. Mac에서 AppKit다운 네이티브 감각까지 맞추는 것은 1차 목표가 아니다.

## Architecture Direction

1. 현재 macOS AppKit 트리를 연장하지 않고, BWR 전용 모델을 새로 만든다.
2. 현재 코드에서 재사용할 것은 `인덱스 보드의 규칙`, `포커스 모드의 감각`, `검색 토큰화`, `PDF/TXT 출력기`다.
3. 현재 코드에서 폐기할 것은 아래 전체 목록이다.
4. 새 앱의 원본 데이터는 보드 그 자체다. 더 이상 `source column -> board projection` 구조를 유지하지 않는다.

### 폐기 항목 전체 목록

현재 `Models.swift`의 `SceneCard` 및 `Scenario` 필드를 기준으로 정리한다.

| 현재 개념 | 처리 | 이유 |
|-----------|------|------|
| `Scenario` (복수 시나리오) | 완전 제거 | 단일 보드 앱 |
| `parent: SceneCard?` (부모 포인터) | 제거 | 트리 구조 폐기 |
| `orderIndex` (형제 순서) | `stableSortKey`로 대체 | 전역 좌표 1차 + stableSortKey 2차 |
| `category` ("플롯/노트/작법/미분류") | 제거 | 트리 카테고리 폐기 |
| `isFloating` | 제거 | 모든 카드가 자유 배치이므로 무의미 |
| `lastSelectedChildID` | 제거 | 트리 네비게이션용 |
| `isAICandidate` | 제거 | AI 폐기 |
| `linkedCardEditDatesByFocusCardID` | 제거 | AI RAG용 |
| `sharedCraftRootCardID` + 공유 크래프트 트리 | 제거 | 시나리오 간 공유 구조, 시나리오와 함께 폐기 |
| `cachedRoots`, `cachedChildrenByParent` | 제거 | 트리 캐시 |
| `cachedLevelCardsByCategory` | 제거 | 카테고리 기반 필터 |
| `HistorySnapshot` (스냅샷 기반 버전) | 제거 | BWR은 command undo로 대체 |
| `IndexBoardCardSummaryRecord` | 제거 | AI 요약 |
| `ai_threads.json`, `ai_vector_index.sqlite` | 제거 | AI 폐기 |
| `ReferenceWindow` | 제거 | 레퍼런스 윈도 폐기 |
| `temp lane/strip/detached` | 제거 | 임시 컨테이너 폐기 |
| `summary/back-face` | 제거 | 카드 뒷면 폐기 |

### 새 Card 모델 필드 매핑

| 현재 SceneCard | 새 Card | 비고 |
|---------------|---------|------|
| `id` | `id` | UUID 유지 |
| `content` | 제거 | `layers[].markdown`으로 분리 |
| — | `currentLayerID` | 신규: 현재 표시 레이어 |
| — | `layers: [CardLayer]` | 신규: 레이어 배열 |
| — | `layout: CGPoint` | 신규: 전역 보드 좌표 |
| — | `stableSortKey: UInt64` | 신규: 정렬 동점 해소용 2차 키 |
| `colorHex` | `color` | 유지 |
| `cloneGroupID` | `cloneGroupID` | 유지 |
| `isArchived` | `isArchived` | 유지 |
| — | `archivedAt` | 신규: 아카이브 시각 |
| `createdAt` | `createdAt` | 유지 |
| — | `updatedAt` | 신규: 마지막 수정 시각 |

## Target Module Seams

1. `BWRCoreModels`
   프로젝트, 카드, 레이어, 그룹, 링크, 아카이브, undo command 모델.
   **카드 분할 커맨드 설계를 이 모듈에서 정의한다** (M2, M3에서 UI만 연결).
2. `BWRPersistence`
   `.bwr` 패키지 입출력, 버전 관리, autosave, archive/search 인덱싱.
3. `BWRBoardCanvas`
   자유 배치 보드, 줌/팬, 선택, 드래그, 인라인 편집, 큰 카드 편집 진입.
4. `BWRBoardCommands`
   생성, 이동, 그룹화, 그룹 해제, 카드 분할, 삭제/복구, 색상, 레이어 조작.
5. `BWRFocusMode`
   현재 레이어/트리트먼트/시나리오 포커스 모드, typewriter, search, boundary navigation.
6. `BWRArchiveSearch`
   전체 검색, 아카이브 탐색, 복구, 검색 필터, 그룹/카드 복원 플로우.
7. `BWRExportBridge`
   그룹 선택과 레이어 모드를 텍스트 스트림으로 조합하고 기존 PDF/TXT 생성기로 넘긴다.

이 seam 분해를 먼저 고정해 두면 새 파일이 1500줄을 넘기지 않게 자를 수 있다.

## Data Model

### Project

1. 프로젝트 메타데이터 (`schemaVersion`, `createdAt`, `updatedAt`).
2. 카드 컬렉션.
3. 그룹 컬렉션.
4. 링크 컬렉션.
5. 아카이브 컬렉션.
6. undo/redo 메타데이터.
7. 향후 history/snapshot용 예약 메타데이터.

### Card

1. `id`
2. `cloneGroupID?`
3. `color`
4. `currentLayerID`
5. `layout: CGPoint` (전역 보드 좌표)
6. `stableSortKey: UInt64` (정렬 동점 해소용 2차 키)
7. `isArchived`
8. `archivedAt?`
9. `createdAt`
10. `updatedAt`
11. `layers`

### CardLayer

1. `id`
2. `kind`
   `body`, `treatment`, `scenario`
3. `name`
4. `markdown`
5. `order`

규칙:

1. `트리트먼트`, `시나리오`는 삭제 불가.
2. 추가 본문 레이어는 이름 변경 가능.
3. 추가 본문 레이어는 삭제 가능.
4. 추가 본문 레이어는 본문 계열 내부에서만 순서 변경 가능.
5. 마지막 두 칸은 항상 `트리트먼트`, `시나리오`다.

### Group

이 섹션은 그룹 객체 자체는 유효하지만, `카드는 여러 그룹에 동시에 속할 수 있다`는 live surface 전제는 `/Users/three/app_build/wa/bwr_index_board_realignment_plan.md`에 의해 superseded된다.

1. `id`
2. `name`
3. `memberCardIDs`
4. `isArchived`
5. `archivedAt?`

규칙:

1. 그룹은 별도 객체다.
2. 그룹은 출력과 포커스 모드의 단위다.
3. 그룹은 이름을 사용자가 직접 정한다.
4. 보관용 기록, superseded: **카드는 여러 그룹에 동시에 속할 수 있다.** `memberCardIDs`는 카드를 참조할 뿐, 배타적 소유가 아니다.

### Link

1. `id`
2. `sourceCardID`
3. `targetCardID`
4. `isArchived`

1차 릴리스에서는 데이터만 저장한다. 화살표 렌더링은 2차다.

### Layout

이 섹션 전체는 `/Users/three/app_build/wa/bwr_index_board_realignment_plan.md`의 `Card Placement`, `Group Layout`, `Parking Strip` 섹션으로 superseded된다.

1. 카드마다 전역 보드 좌표를 하나 가진다.
2. 클론 카드는 별도 카드이므로 별도 좌표를 가진다.
3. 그룹 출력 순서는 이 전역 좌표를 기준으로 계산한다.
4. **정렬 안정성**: row-major 정렬의 1차 키는 전역 좌표(y를 행 높이로 양자화 후 비교, 같은 행이면 x 비교)이고, 2차 키는 `stableSortKey`다. `stableSortKey`는 카드 생성 시 단조증가 카운터로 부여하며, 수동 재배치 시에도 변경하지 않는다. 이로써 float 반올림이나 동일 좌표에서도 정렬이 결정적이다.

## Layer Interaction Spec

레이어 조작은 **카드 컨텍스트 메뉴**를 통해 수행한다.

### 보드 위 레이어 조작

1. 카드 타일을 길게 누르기(iPad) 또는 우클릭(트랙패드/Mac)하면 컨텍스트 메뉴가 열린다.
2. 메뉴 항목:
   - `현재 레이어` → 서브메뉴로 레이어 목록 표시, 탭하여 전환
   - `본문 레이어 추가`
   - `본문 레이어 삭제` → 현재 레이어가 추가 본문일 때만 활성
   - `본문 레이어 이름 변경` → 현재 레이어가 추가 본문일 때만 활성
   - 그 외 카드 조작 (색상, 복제, 클론, 삭제 등)
3. 카드 타일에는 현재 레이어의 이름이 작은 뱃지로 표시된다 (기본 본문 1개만 있을 때는 숨김).
4. **멀티 선택 시**: 컨텍스트 메뉴의 `현재 레이어` 전환은 선택된 모든 카드에 동시 적용한다. 단, 대상 레이어가 없는 카드는 무시한다.

### 큰 카드 편집 모드에서의 레이어 조작

1. 큰 카드 편집 진입 시 상단에 레이어 세그먼트 컨트롤이 표시된다.
2. 세그먼트: `본문 1`, `본문 2`, ..., `트리트먼트`, `시나리오`.
3. 세그먼트 탭으로 전환. 이것이 카드의 `currentLayerID`를 변경한다.
4. 본문 레이어 추가/삭제/이름 변경은 세그먼트 컨트롤 옆 `...` 버튼으로 접근.

### 포커스 모드에서의 레이어

1. 포커스 모드 진입 시 3개 모드(현재 레이어/트리트먼트/시나리오) 중 하나를 선택.
2. 포커스 모드 안에서 개별 카드의 레이어를 전환하지 않는다.
3. 포커스 모드는 선택된 모드에 해당하는 레이어만 순차 표시한다.

### 단축키

1. `Ctrl+L` → 보드에서 선택 카드의 다음 레이어로 전환 (순환).
2. `Ctrl+Shift+L` → 이전 레이어로 전환 (역순환).

## Clone Semantics

1. 클론은 별도 카드 객체다.
2. clone group은 `동기화 인덱스`일 뿐 별도 master record가 아니다.
3. 각 클론 카드는 자기 레이어와 메타를 완전하게 저장한다.
4. 동기 대상 필드가 바뀌면 reducer가 같은 mutation을 live clone 전부에 fan-out 적용한다.
5. **재귀 방지**: fan-out 적용 중 `isSyncingClone` 플래그를 세워 2차 fan-out을 차단한다.
6. 클론 동기 범위는 `모든 레이어 본문`, `색상`, `공용 카드 메타`다.
7. 클론은 위치를 동기화하지 않는다.
8. 클론은 그룹 소속을 동기화하지 않는다.
9. autosave와 undo는 카드 단위 스냅샷을 저장하고, clone group membership으로 fan-out 결과를 복원한다.
10. 클론 삭제는 일반 카드 삭제와 같은 규칙으로 다루면 꼬인다.
11. 따라서 `클론 인스턴스가 제거되는 경우`는 별도 structural remove 규칙을 사용한다.
12. 제거 대상 클론은 hard delete 한다.
13. 남은 live clone이 1개라면 그 카드의 `cloneGroupID`를 제거해 단독 원본으로 승격한다.
14. 남은 live clone이 2개 이상이면 기존 clone 그룹을 유지한다.
15. 일반 카드 삭제는 아카이브로 보낸다.

### Clone + Undo 시나리오 정의

Undo는 **모든 영향받은 카드의 개별 스냅샷**을 저장한다. Fan-out은 undo 시 재계산하지 않는다.

| 시나리오 | Undo 동작 |
|---------|----------|
| 클론 A 편집 → B,C에 fan-out | Undo 시 A,B,C 모두 이전 스냅샷으로 복원 |
| 클론 B를 hard delete → 그룹 재정규화 | Undo 시 B를 복원하고 cloneGroupID를 재설정 |
| 클론 A 편집 → B에 fan-out → B를 hard delete → Undo | 1단계 Undo: B 복원 + cloneGroupID 복원. 2단계 Undo: A,B 모두 편집 전으로 복원 |
| 그룹 삭제로 일반카드 아카이브 + 클론카드 hard delete → Undo | 그룹 복원 + 일반카드 아카이브 해제 + 클론카드 복원 + clone group 재정규화 |

원칙: **Undo command는 fan-out 결과를 포함한 전체 영향 범위의 before 스냅샷을 저장한다.** Undo 시 before 스냅샷을 그대로 복원하므로 fan-out 재계산이 불필요하다.

## Archive And Search

1. 카드 삭제, 그룹 삭제, 링크 삭제의 기본 의미는 아카이브다.
2. 아카이브된 항목은 찾기/아카이브 화면에서 검색 가능해야 한다.
3. 아카이브된 카드와 그룹은 복구 가능해야 한다.
4. 검색은 현재 앱처럼 간단한 token normalization 규칙을 재사용한다.
5. iPad에서는 별도 창 대신 시트 또는 보조 패널 형태로 구현한다.
6. Mac 실행 시에도 동일한 정보 구조를 유지한다.
7. 삭제 의미는 `그룹 안에 있었는지`가 아니라 `일반 카드인지 clone instance인지`로만 갈린다.
8. 따라서 clone instance 제거는 단독 삭제든 그룹 삭제든 동일한 규칙으로 처리한다.

그룹 삭제 규칙:

1. 그룹 객체는 아카이브된다.
2. 그룹 안의 각 카드에 대해 **다른 live 그룹에도 속해 있는지** 확인한다.
3. 다른 live 그룹에도 속한 일반 카드는 **이 그룹의 membership만 제거**한다. 카드 자체는 아카이브하지 않는다.
4. 어떤 live 그룹에도 속하지 않게 되는 일반 카드는 아카이브한다.
5. 클론 카드는 다른 그룹 소속 여부와 무관하게 hard delete 대상으로 처리한다.
6. 그룹 삭제 후 살아남은 clone set은 즉시 재정규화한다.

## Undo And Redo

1. 문서 내부 텍스트 편집은 시스템 text undo를 우선 사용한다.
2. 구조 변경은 별도 command undo stack으로 처리한다.
3. undo 대상에는 아래가 모두 포함된다.
4. 카드 생성
5. 카드 분할
6. 카드 이동
7. 카드 삭제/복구
8. 그룹 생성
9. 그룹 삭제
10. 그룹화
11. 그룹 해제
12. 색상 변경
13. 레이어 생성/삭제/이름 변경/순서 변경
14. 현재 레이어 전환에 의해 발생하는 구조 상태 변화

### Text Undo vs Structural Undo 경계 규칙

1. Text undo는 `현재 활성 텍스트뷰의 현재 레이어 본문`에만 적용한다.
2. Structural undo는 `생성, 분할, 이동, 그룹화, 그룹 삭제, 아카이브, clone remove, 레이어 구조 변경`만 다룬다.
3. 검색 이동, 스크롤 이동, 선택 이동, 현재 레이어 보기 전환만으로는 undo 항목을 만들지 않는다.
4. **Structural command가 발생하기 직전에는 항상 진행 중 text coalescing을 finalize한다.** 이로써 text undo와 structural undo가 어긋나지 않는다.
5. 카드 분할은 text mutation이 아니라 structural command로 본다.
6. **Structural command의 before 스냅샷에는 clone fan-out 대상 카드를 모두 포함한다.**

### 포커스 모드 Undo 규칙

1. 현재 앱의 focus 전용 undo 감각을 가져온다.
2. idle gap, 카드 전환, 문단 경계, 문장 경계, split-card 시점을 boundary로 사용한다.
3. 포커스 모드의 텍스트 undo와 구조 undo가 서로 어긋나지 않게, reducer 기반 command stack과 native text undo를 명확히 분리한다.

## Board Experience

이 섹션 전체는 자유배치 보드 가정을 담고 있으므로, 현재 구현 기준 문서로 사용하지 않는다. 보드 손맛과 상호작용은 `/Users/three/app_build/wa/bwr_index_board_realignment_plan.md`가 우선한다.

1. 보드는 현재 인덱스 보드의 손맛을 최대한 살린다.
2. 새로 "다른 종류의 보드"를 만들지 않는다.
3. 1차 필수 기능은 아래다.
4. 자유 배치
5. 줌/팬
6. 멀티 선택
7. 드래그 이동
8. 인라인 편집
9. 큰 카드 편집
10. 색상 변경
11. 카드 분할
12. 그룹 생성/삭제
13. 그룹으로 묶기 / 그룹에서 빼기
14. 화살표 이동
15. Enter / Shift+Enter / Delete

### 보드 인터랙션 사양 (Interaction Spec)

현재 `WriterIndexBoardSurfaceAppKitPhaseTwo.swift`에서 추출한 수치 기준이다. M0 스파이크에서 iPad SwiftUI 환경에 맞게 조정하되, 아래를 출발점으로 사용한다.

| 항목 | 현재 값 | 비고 |
|------|---------|------|
| 드래그 활성화 임계치 | hysteresis 기반, 첫 이동 감지 후 활성 | iPad에서는 `minimumPressDuration` + `minimumDistance`로 매핑 |
| 자동 스크롤 진입 영역 | 가장자리에서 80pt 이내 | iPad에서도 동일 적용 |
| 자동 스크롤 최대 속도 | 22pt/frame | 60fps 기준 1320pt/s |
| 드래그 프레임 예산 | 4ms/frame (signpost 기준) | 성능 프로파일링 기준 유지 |
| 줌 범위 | 0.30 ~ 1.60, step 0.05 | 핀치 제스처 + 단축키(Cmd+/Cmd-) |
| 줌 기본값 | 1.0 | — |
| 인라인 편집 진입 | 더블탭 또는 Enter | — |
| 인라인 편집 이탈 | Escape 또는 카드 외부 탭 | — |
| 큰 카드 편집 진입 | 카드 더블탭 후 다시 더블탭, 또는 단축키 | 인라인 → 큰 편집 전환 |
| 드롭 타겟 종류 | groupSlot, groupBlock, 자유 배치 | tempStrip/detached 제거 |

**M0 스파이크에서 검증할 것**: 위 수치가 SwiftUI `DragGesture` + `MagnificationGesture` 조합으로 달성 가능한지. 불가능하면 `UIViewRepresentable` + `UIPanGestureRecognizer` 조합으로 전환한다.

## Focus Mode

1. 포커스 모드는 현재 macOS 앱에서 적극적으로 가져온다.
2. 단순 전체 문서 뷰가 아니라 `카드 묶음 글쓰기기`로 유지한다.
3. 그룹 단위로 진입한다.
4. 모드는 `현재 레이어`, `트리트먼트`, `시나리오` 3개다.
5. 카드 정렬은 그룹 내부 row-major 순서를 따른다.
6. 현재 앱의 다음 감각을 그대로 목표로 한다.
7. 큰 글자와 넓은 행간
8. 카드 사이 이동
9. typewriter mode
10. 검색 팝업과 결과 이동
11. 카드 경계 기반 caret/scroll 처리
12. 포커스 모드 안에서의 카드 분할

중요 규칙:

1. 포커스 모드에서 카드를 나누면 실제 보드 카드가 나뉜다.
2. 포커스 모드에서 일어난 구조 변경은 보드와 즉시 동기화된다.
3. 별도 트리 파생 데이터나 임시 컨테이너는 두지 않는다.

### 캐럿/스크롤 전략 (iPad)

현재 macOS 앱은 `NSTextView` first responder 타이밍 버그를 우회하기 위해 지수 백오프 12회 재시도(`applyFocusModeCaretWithRetry`)를 사용한다. iPad에서는 `UITextView`이므로 같은 버그는 없지만, UIKit 텍스트 시스템 고유의 타이밍 문제가 있을 수 있다.

대응 전략:

1. M0 스파이크에서 `UITextView` + SwiftUI 조합의 캐럿 설정 타이밍을 검증한다.
2. 캐럿 설정은 `UITextViewDelegate.textViewDidBeginEditing` 콜백 이후로 지연한다.
3. 재시도 메커니즘은 필요 시 도입하되, 처음부터 넣지 않는다.
4. Typewriter 스크롤은 `UITextView`의 `contentOffset` 직접 조작 + `scrollRangeToVisible` 조합으로 구현한다.

## Export Strategy

1. 현재 `ScriptPDFExport`의 레이아웃과 파서 로직은 최대한 그대로 가져간다.
2. 바뀌는 것은 입력 텍스트를 조합하는 규칙뿐이다.
3. 입력 소스는 `선택 그룹 + 출력 모드`다.
4. 출력 모드는 `현재 레이어`, `트리트먼트`, `시나리오`다.
5. 그룹 내부 카드 순서는 row-major 규칙을 따른다.
6. parity의 의미는 `같은 export text + 같은 설정`을 넣었을 때 렌더러 결과가 현재와 같은 것이다.
7. BWR의 문서 조합 규칙은 트리 앱과 다르므로, parity 목표는 `조합기`가 아니라 `렌더러`와 `설정 수학`에 둔다.
8. 출력 parity는 golden fixture로 잡는다.
9. "한 픽셀도 어긋나지 않음"은 renderer 계층의 성공 조건이다.

### Export Bridge 조합 규칙 (의사코드)

```
func exportText(groups: [Group], mode: ExportMode, allCards: [Card]) -> String:
    var fragments: [String] = []
    for group in groups:
        let memberCards = group.memberCardIDs
            .compactMap { id in allCards.first(where: { $0.id == id && !$0.isArchived }) }
            .sorted(by: rowMajorOrder)  // 좌상단→우→하, stableSortKey 2차

        for card in memberCards:
            let layer = switch mode:
                case .currentLayer: card.layers.first(where: { $0.id == card.currentLayerID })
                case .treatment:    card.layers.first(where: { $0.kind == .treatment })
                case .scenario:     card.layers.first(where: { $0.kind == .scenario })
            let text = layer?.markdown ?? ""
            if !text.isEmpty:
                fragments.append(text)

    return fragments.joined(separator: "\n\n")
```

이 `exportText` 결과를 현재 `ScriptMarkdownParser`에 그대로 넘긴다. 파서는 수정하지 않는다.

**M0에서 검증**: 현재 앱에서 카드 content를 연결한 텍스트와, 위 조합 규칙으로 만든 텍스트를, 동일 파서에 넣었을 때 같은 element 배열이 나오는지 harness로 확인한다.

## File Format

1. 확장자는 `.bwr`
2. 패키지 구조를 사용한다.
3. 내부 포맷은 `metadata JSON + 레이어별 Markdown`이다.

예시 구조:

1. `project.json`
2. `groups.json`
3. `links.json`
4. `archive.json`
5. `cards/<card-id>/card.json`
7. `cards/<card-id>/layers/body-1.md`
8. `cards/<card-id>/layers/treatment.md`
9. `cards/<card-id>/layers/scenario.md`

원칙:

1. 사람이 열어도 이해 가능한 포맷이어야 한다.
2. 레거시 호환 코드는 넣지 않는다.
3. 향후 버전 업용 `schemaVersion`을 반드시 둔다.

## Viewport State

뷰포트 상태(줌 레벨, 스크롤 위치)는 **문서 파일에 저장하지 않는다.** 이유:

1. iPad 멀티윈도우, Stage Manager, Mac 검증 호스트에서 같은 문서를 여러 창으로 열 수 있다. 문서에 단일 viewport를 넣으면 창끼리 서로 덮어쓴다.
2. 스크롤/줌만으로 문서가 dirty 마킹되면 불필요한 autosave가 발생한다.
3. 현재 앱도 `scenario:\(id)|pane:\(paneKey)` 형식으로 viewport를 window/pane별로 분리 저장한다.

저장 전략:

1. 뷰포트 상태는 **scene/window 단위로 앱 로컬에 저장**한다.
2. 저장 키는 `documentURL + sceneSessionID` 조합이다. 같은 문서라도 창마다 독립 뷰포트를 유지한다.
3. 저장 위치는 `UserDefaults` 또는 앱 컨테이너 내 경량 JSON이다. `.bwr` 패키지 안에는 넣지 않는다.
4. 문서를 처음 여는 창은 기본 뷰포트(줌 1.0, 원점 중심)로 시작한다.
5. 창이 닫힐 때 뷰포트를 저장하고, 같은 문서를 다시 열면 마지막 뷰포트를 복원한다.

## App Shell / Document Lifecycle

새 앱은 `.bwr` 패키지 문서 앱이다. SwiftUI `DocumentGroup` 기반으로 문서 lifecycle을 처리한다.

### 첫 실행

1. 앱을 처음 실행하면 시스템 문서 브라우저가 표시된다.
2. 사용자가 "새 문서"를 탭하면 빈 `.bwr`가 생성되고 즉시 보드로 진입한다.
3. 빈 문서에는 빈 카드 1장이 보드 중앙에 배치된다.

### 문서 열기

1. 문서 브라우저에서 기존 `.bwr`를 탭하면 해당 보드로 진입한다.
2. Files 앱이나 외부 앱에서 `.bwr`를 탭하면 Board Writer가 열리면서 해당 문서를 로드한다.
3. `UTType` 선언: `com.boardwriter.bwr`, conforms to `com.apple.package`.

### 마지막 문서 재열기

1. iPad `DocumentGroup`은 시스템이 마지막 문서를 자동으로 복원한다 (State Restoration).
2. 별도 "최근 문서" UI는 1차에서 만들지 않는다. 시스템 문서 브라우저에 의존한다.

### 충돌/복제 처리

1. iCloud Drive 충돌 시 시스템의 conflict resolution UI를 수용한다. 별도 merge 로직은 만들지 않는다.
2. 파일 복제는 시스템 "복제" 기능에 의존한다. `.bwr`가 패키지이므로 디렉토리 단위로 복제된다.

### autosave 연동

1. `DocumentGroup`의 `FileDocument` 또는 `ReferenceFileDocument` 프로토콜을 구현한다.
2. `ReferenceFileDocument`가 적합: 인메모리 모델을 참조로 들고, 변경 시 `snapshot()` → `fileWrapper(snapshot:)` 경로로 delta save를 수행한다.
3. autosave debounce는 `UndoManager` 등록과 연동하여 시스템이 save 타이밍을 결정하게 한다.
4. 추가로 앱 자체 debounce(0.55초)를 두어 빈번한 타이핑 중 과도한 save를 방지한다.

## Execution Milestones

### Milestone 0, Spike And Harness

이 마일스톤의 자유배치 보드 스파이크 전제는 superseded되었다. 보드 관련 kill gate는 `/Users/three/app_build/wa/bwr_index_board_realignment_plan.md`의 `R0-R3` 순서를 따른다.

**목표**: 핵심 기술 리스크를 제거하고, 이후 마일스톤의 자동 검증 기반을 구축한다.

#### 기술 스파이크 (Kill-or-Proceed 게이트)

아래 3개 스파이크는 **M0의 첫 번째 작업**이다. 각각 독립된 프로토타입으로, 성공 기준을 통과하지 못하면 해당 영역의 기술 전략을 재검토한다.

1. **자유 배치 보드 스파이크**
   - 내용: 200장 더미 카드를 SwiftUI Canvas 또는 `UIViewRepresentable` 위에 자유 배치하고, 핀치 줌(0.3~1.6), 팬, 드래그 이동을 구현한다.
   - 성공 기준: 200장에서 드래그 시 16ms/frame 이내. 핀치 줌이 끊김 없이 동작.
   - 실패 시: SwiftUI `Canvas` 대신 `UIKit` + `UIScrollView` + `CATiledLayer` 조합으로 전환.

2. **텍스트 편집 중 키 가로채기 스파이크**
   - 내용: `UITextView`를 SwiftUI에 embed하고, 텍스트 입력 중 `Enter` → 카드 분할, `Shift+Enter` → 줄바꿈으로 분기하는 키 핸들러를 구현한다.
   - 성공 기준: 외부 키보드에서 Enter/Shift+Enter/Cmd+Z가 텍스트뷰 기본 동작을 가로채고 정확히 분기. IME 한글 입력 중에도 안정적.
   - 실패 시: `UITextView` 서브클래스의 `pressesBegan`/`pressesEnded` 오버라이드로 전환.

3. **Autosave 성능 스파이크**
   - 내용: card-per-directory 구조로 카드 300장 × 레이어 3개를 `.bwr` 패키지에 쓰고, 단일 카드 변경 시 delta save 소요 시간을 측정한다.
   - 성공 기준: delta save 1회 < 50ms (iPad Air M2 기준).
   - 실패 시: 레이어를 별도 `.md` 파일이 아닌 `card.json` 안에 인라인으로 저장하는 구조로 전환.

#### 테스트 Harness

스파이크 통과 후 아래 harness를 작성한다.

1. `.bwr` 패키지 read/write round-trip harness.
2. **export golden fixture harness**: 현재 앱의 `ScriptPDFExport`를 그대로 가져온 상태에서, 현재 앱에서 추출한 reference input→output 쌍을 캡처하여 golden fixture로 저장한다. BWR 조합기는 아직 없으므로, 이 단계에서는 "동일 input text → 동일 renderer output" 관계만 검증한다.
3. clone normalization harness.
4. group row-major ordering harness.
5. archive/search reducer harness.
6. structural undo/redo reducer harness (clone fan-out 포함 시나리오 반드시 포함).
7. text undo vs structural undo 경계 harness.
8. Mac acceptance smoke harness.

### Milestone 1, Core Model And Persistence

이 마일스톤 중 보드 placement 모델은 superseded되었다. persistence 작업은 `/Users/three/app_build/wa/bwr_index_board_realignment_plan.md`의 `R1. Persistence And Shadow Placement`를 따른다.

1. 새 BWR 모델 구현 (`stableSortKey` 포함).
2. **카드 분할 커맨드 설계 및 구현** (UI 없이 모델+reducer 단).
3. **`DocumentGroup` + `ReferenceFileDocument` 앱 셸 구현.** 새 문서 생성, 기존 문서 열기, UTType 선언.
4. `.bwr` 저장 구조 구현.
5. autosave 구현 (debounce + delta save).
6. archive/search 저장 구조 구현.
7. clone normalization 구현 (재귀 방지 플래그 포함).
8. **뷰포트 상태 scene/window 저장 구현** (앱 로컬, `documentURL + sceneSessionID` 키).

### Milestone 2, Board Canvas

이 마일스톤의 자유배치 캔버스 전제는 superseded되었다. 보드 surface 작업은 `/Users/three/app_build/wa/bwr_index_board_realignment_plan.md`의 `R2-R4`를 따른다.

1. 보드 렌더링.
2. 카드 선택/이동.
3. 인라인 편집.
4. 큰 카드 편집 (상단 레이어 세그먼트 컨트롤 포함).
5. **레이어 전환 UI**: 카드 컨텍스트 메뉴, 레이어 뱃지 표시, 단축키(`Ctrl+L`, `Ctrl+Shift+L`).
6. **레이어 관리 UI**: 본문 레이어 추가/삭제/이름 변경 (컨텍스트 메뉴 + 큰 편집 모드 `...` 버튼).
7. 그룹 생성/삭제/멤버십 관리.
8. 색상 변경.
9. 카드 분할 (M1에서 만든 커맨드에 보드 UI 연결).

### Milestone 3, Focus Mode

1. 3개 모드 구현.
2. typewriter 구현.
3. 카드 경계 이동 구현.
4. **캐럿/스크롤 동기화 구현**: M0 스파이크 결과를 기반으로 UITextView 캐럿 타이밍 처리.
5. 검색 팝업 구현.
6. 포커스 모드 카드 분할 구현 (M1 커맨드에 포커스 UI 연결).
7. focus-specific undo coalescing 구현.

### Milestone 4, Export Parity

1. BWR export bridge 구현 (Export Bridge 조합 규칙 섹션의 의사코드 기반).
2. 기존 PDF/TXT 출력기 이식 (`ScriptPDFExport.swift`에서 AppKit 의존 제거, PDFKit은 iOS에서도 사용 가능).
3. **조합기 검증**: BWR 조합 규칙으로 만든 텍스트가 파서에서 동일한 element 배열을 생성하는지 확인.
4. golden output 비교.
5. 설정 parity 확인.

### Milestone 5, Mac Runability And Input Polish

1. Apple Silicon Mac 실행 검증.
2. 외부 키보드와 트랙패드 조정.
3. Stage Manager, split sizes, portrait/landscape 검증.
4. 링크 모델 저장 연결.

## Harness Plan

1. Reducer tests
   카드/그룹/레이어/아카이브/undo state transition을 모델 단에서 검증한다.
2. Clone tests
   clone fan-out sync, clone delete, clone group collapse, group delete 시 clone remove를 검증한다.
   **추가**: clone edit → fan-out → clone delete → undo 시나리오를 반드시 포함한다.
3. Ordering tests
   그룹 내부 row-major 정렬과 export 대상 조합을 검증한다.
4. Export golden tests
   동일 export text와 동일 설정에서 TXT/PDF 렌더링 결과가 현재 앱과 같은지 검증한다.
5. Focus mode tests
   split, boundary undo, current/treatment/scenario mode 조합, text undo와 structural undo 경계를 검증한다.
6. Manual smoke matrix
   iPad simulator, `My Mac (Designed for iPad)`, portrait, landscape, split widths, Stage Manager.

## Non Goals

1. `wtf` 읽기
2. 기존 데이터 마이그레이션
3. AI
4. 레퍼런스 윈도
5. 트리 시각화
6. temp lane/strip/detached
7. summary/back-face 복구
8. 링크 화살표 렌더링 1차 구현
9. **시나리오(복수 보드) 지원**
10. **AppKit 네이티브 Mac 경험**

## Main Risks

1. 인덱스 보드 손맛을 AppKit 없이 다시 만드는 일.
   **대응**: M0 자유 배치 보드 스파이크. 실패 시 UIKit fallback 전략 준비됨.
2. 포커스 모드의 caret/scroll/typewriter 감각 이식.
   **대응**: M0 텍스트 편집 키 가로채기 스파이크. UITextView 캐럿 타이밍 전략 정의됨.
3. 클론 삭제 예외 규칙과 archive 규칙이 충돌할 가능성.
   **대응**: Clone + Undo 시나리오 테이블로 엣지 케이스 정의 완료. Before 스냅샷 기반 undo로 fan-out 재계산 회피.
4. export parity를 유지하면서 입력 모델만 바꾸는 브리지 설계.
   **대응**: Export Bridge 조합 규칙을 의사코드로 정의. M0에서 파서 input→element 배열 동일성 harness 작성.
5. iPad-first 앱을 Mac에서도 실행 가능하게 유지하면서 입력 체감이 망가질 가능성.
   **대응**: Mac acceptance bar를 5개 항목으로 명시. M5에서 검증.
6. **card-per-directory autosave가 iPad 파일시스템에서 느릴 가능성.**
   **대응**: M0 autosave 성능 스파이크. 실패 시 인라인 저장 구조로 전환.
7. **SwiftUI 드래그/줌 제스처의 정밀도가 AppKit CALayer 수준에 미치지 못할 가능성.**
   **대응**: M0 스파이크에서 실측. 실패 시 UIViewRepresentable + UIPanGestureRecognizer 조합으로 전환.

## Review Status

1. 2026-04-08 적대적 `codex` 리뷰를 수행했다.
2. 반영한 지적은 `clone source of truth 명시`, `clone delete 규칙 일관화`, `export parity 범위 재정의`, `undo 경계 명시`, `Mac acceptance 기준 명시`다.
3. 2026-04-09 적대적 코드리뷰 v2를 수행했다.
4. 반영한 지적 목록:
   - 시나리오 개념 처리 명시 (완전 제거)
   - 폐기 항목 전체 목록을 현재 코드 기반으로 작성
   - 새 Card 모델 필드 매핑 테이블 추가
   - M0에 기술 스파이크 3개 추가 (보드/키보드/autosave), 각각 성공 기준과 실패 시 대안 명시
   - 보드 인터랙션 사양 수치 테이블 추가
   - 레이어 인터랙션 사양 섹션 신설 (보드/큰 편집/포커스 각각)
   - Export Bridge 조합 규칙 의사코드 추가
   - Clone + Undo 시나리오 테이블 추가
   - 뷰포트 상태 저장 위치 명시 (.bwr 패키지 내 viewport.json)
   - 카드 분할 커맨드 설계를 M1 scope로 이동
   - export golden fixture harness의 역할 명확화
   - 리스크 항목마다 대응 전략 추가
5. 2026-04-09 외부 적대적 리뷰 반영 (5개 지적).
6. 반영한 지적 목록:
   - [P1] 그룹 삭제 규칙을 다중 그룹 카드에 안전하게 수정. 삭제 = membership 제거, 남은 live membership 0일 때만 아카이브.
   - [P1] 뷰포트 상태를 문서에서 분리. scene/window 단위 앱 로컬 저장으로 변경. viewport.json 제거.
   - [P2] 정렬 안정성 확보. `stableSortKey: UInt64`를 2차 정렬 키로 추가. row-major 양자화 규칙 명시.
   - [P2] export bridge 의사코드에서 빈 레이어 필터링 추가. `joined(separator:)` 방식으로 현재 앱과 동일하게 수정.
   - [P2] App Shell / Document Lifecycle 섹션 신설. DocumentGroup, 첫 실행, 문서 열기, 충돌 처리, autosave 연동 정의.
