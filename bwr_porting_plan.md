# BWR Porting Plan

## Scope

`wa`를 트리 기반 macOS 앱에서, 인덱스 보드 중심의 `Board Writer (.bwr)` 앱으로 재구성하고, iPadOS 26+를 기준으로 설계하되 Apple Silicon Mac에서도 바로 실행·검증 가능한 형태로 포팅한다.

## Product Lock

1. 앱 이름은 `Board Writer`, 문서 확장자는 `.bwr`다.
2. 새 앱은 단일 프로젝트 앱이다. 실행 직후 바로 보드로 진입한다.
3. 기존 `wtf` 포맷, 레거시 마이그레이션, 폴백 UI는 만들지 않는다.
4. 트리는 완전히 제거한다.
5. 메인 작업공간은 현재 인덱스 보드의 손맛을 계승한 자유 카드 보드다.
6. 그룹은 부모 카드가 아니라 별도 객체다.
7. 그룹 내부 순서는 보드의 전역 좌표를 기준으로 `좌상단 -> 우측 -> 하단`으로 계산한다.
8. 카드는 제목 없이 본문만 가진다. 본문은 Markdown이며 렌더링된다.
9. 각 카드는 자체 레이어 집합을 가진다.
10. 기본 레이어 순서는 `본문 1 ... 본문 n > 트리트먼트 > 시나리오`다.
11. 카드 타일에는 항상 그 카드의 현재 레이어만 보인다.
12. 포커스 모드는 필수다. 모드는 `현재 레이어`, `트리트먼트`, `시나리오` 3개다.
13. 출력도 동일하게 `현재 레이어`, `트리트먼트`, `시나리오` 3축으로 한다.
14. AI, 레퍼런스 윈도, 트리 카테고리, temp lane/strip/detached 개념은 제거한다.
15. 삭제 기본 의미는 `아카이브`다. 찾기와 아카이브 복구 기능이 반드시 있어야 한다.
16. 단, 클론이 삭제되는 경우는 예외 규칙을 둔다. 아래 `Clone Semantics`를 기준으로 hard delete를 허용한다.
17. 외부 키보드와 트랙패드는 핵심 입력이다.
18. 기본 단축키 우선순위는 `Enter`, `Shift+Enter`, `Delete`, `Arrow Navigation`이다.
19. PDF/TXT 출력 엔진의 결과물은 현재 앱과 시각적으로 동일해야 한다.

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
3. 현재 코드에서 폐기할 것은 `parent/child 트리`, `category 체계`, `AI`, `reference window`, `summary/back-face`, `temp container`, `wtf 호환`이다.
4. 새 앱의 원본 데이터는 보드 그 자체다. 더 이상 `source column -> board projection` 구조를 유지하지 않는다.

## Target Module Seams

1. `BWRCoreModels`
   프로젝트, 카드, 레이어, 그룹, 링크, 아카이브, undo command 모델.
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

1. 프로젝트 메타데이터.
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
5. `layout`
6. `isArchived`
7. `archivedAt?`
8. `createdAt`
9. `updatedAt`
10. `layers`

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

1. `id`
2. `name`
3. `memberCardIDs`
4. `isArchived`
5. `archivedAt?`

규칙:

1. 그룹은 별도 객체다.
2. 그룹은 출력과 포커스 모드의 단위다.
3. 그룹은 이름을 사용자가 직접 정한다.

### Link

1. `id`
2. `sourceCardID`
3. `targetCardID`
4. `isArchived`

1차 릴리스에서는 데이터만 저장한다. 화살표 렌더링은 2차다.

### Layout

1. 카드마다 전역 보드 좌표를 하나 가진다.
2. 클론 카드는 별도 카드이므로 별도 좌표를 가진다.
3. 그룹 출력 순서는 이 전역 좌표를 기준으로 계산한다.

## Clone Semantics

1. 클론은 별도 카드 객체다.
2. clone group은 `동기화 인덱스`일 뿐 별도 master record가 아니다.
3. 각 클론 카드는 자기 레이어와 메타를 완전하게 저장한다.
4. 동기 대상 필드가 바뀌면 reducer가 같은 mutation을 live clone 전부에 fan-out 적용한다.
5. 클론 동기 범위는 `모든 레이어 본문`, `색상`, `공용 카드 메타`다.
6. 클론은 위치를 동기화하지 않는다.
7. 클론은 그룹 소속을 동기화하지 않는다.
8. autosave와 undo는 카드 단위 스냅샷을 저장하고, clone group membership으로 fan-out 결과를 복원한다.
9. 클론 삭제는 일반 카드 삭제와 같은 규칙으로 다루면 꼬인다.
10. 따라서 `클론 인스턴스가 제거되는 경우`는 별도 structural remove 규칙을 사용한다.
11. 제거 대상 클론은 hard delete 한다.
12. 남은 live clone이 1개라면 그 카드의 `cloneGroupID`를 제거해 단독 원본으로 승격한다.
13. 남은 live clone이 2개 이상이면 기존 clone 그룹을 유지한다.
14. 일반 카드 삭제는 아카이브로 보낸다.

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
2. 그룹 안의 일반 카드는 아카이브된다.
3. 그룹 안의 클론 카드는 hard delete 대상으로 처리한다.
4. 그룹 삭제 후 살아남은 clone set은 즉시 재정규화한다.

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

포커스 모드 undo 규칙:

1. 현재 앱의 focus 전용 undo 감각을 가져온다.
2. idle gap, 카드 전환, 문단 경계, 문장 경계, split-card 시점을 boundary로 사용한다.
3. 포커스 모드의 텍스트 undo와 구조 undo가 서로 어긋나지 않게, reducer 기반 command stack과 native text undo를 명확히 분리한다.
4. text undo는 `현재 활성 텍스트뷰의 현재 레이어 본문`에만 적용한다.
5. structural undo는 `생성, 분할, 이동, 그룹화, 그룹 삭제, 아카이브, clone remove, 레이어 구조 변경`만 다룬다.
6. 검색 이동, 스크롤 이동, 선택 이동, 현재 레이어 보기 전환만으로는 undo 항목을 만들지 않는다.
7. structural command가 발생하기 직전에는 항상 진행 중 text coalescing을 finalize한다.
8. 카드 분할은 text mutation이 아니라 structural command로 본다.

## Board Experience

1. 보드는 현재 인덱스 보드의 손맛을 최대한 살린다.
2. 새로 “다른 종류의 보드”를 만들지 않는다.
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

## Export Strategy

1. 현재 `ScriptPDFExport`의 레이아웃과 파서 로직은 최대한 그대로 가져간다.
2. 바뀌는 것은 입력 텍스트를 조합하는 규칙뿐이다.
3. 입력 소스는 `선택 그룹 + 출력 모드`다.
4. 출력 모드는 `현재 레이어`, `트리트먼트`, `시나리오`다.
5. 그룹 내부 카드 순서는 row-major 규칙을 따른다.
6. parity의 의미는 `같은 export text + 같은 설정`을 넣었을 때 렌더러 결과가 현재와 같은 것이다.
7. BWR의 문서 조합 규칙은 트리 앱과 다르므로, parity 목표는 `조합기`가 아니라 `렌더러`와 `설정 수학`에 둔다.
8. 출력 parity는 golden fixture로 잡는다.
9. “한 픽셀도 어긋나지 않음”은 renderer 계층의 성공 조건이다.

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
6. `cards/<card-id>/layers/body-1.md`
7. `cards/<card-id>/layers/treatment.md`
8. `cards/<card-id>/layers/scenario.md`

원칙:

1. 사람이 열어도 이해 가능한 포맷이어야 한다.
2. 레거시 호환 코드는 넣지 않는다.
3. 향후 버전 업용 `schemaVersion`을 반드시 둔다.

## Execution Milestones

### Milestone 0, Harness First

1. BWR target shell 생성.
2. `.bwr` 패키지 read/write round-trip harness 작성.
3. export golden fixture harness 작성.
4. clone normalization harness 작성.
5. group row-major ordering harness 작성.
6. archive/search reducer harness 작성.
7. structural undo/redo reducer harness 작성.
8. text undo vs structural undo 경계 harness 작성.
9. Mac acceptance smoke harness 작성.

### Milestone 1, Core Model And Persistence

1. 새 BWR 모델 구현.
2. `.bwr` 저장 구조 구현.
3. autosave 구현.
4. archive/search 저장 구조 구현.
5. clone normalization 구현.

### Milestone 2, Board Canvas

1. 보드 렌더링.
2. 카드 선택/이동.
3. 인라인 편집.
4. 큰 카드 편집.
5. 레이어 전환 UI와 단축키.
6. 그룹 생성/삭제/멤버십 관리.

### Milestone 3, Focus Mode

1. 3개 모드 구현.
2. typewriter 구현.
3. 카드 경계 이동 구현.
4. 검색 팝업 구현.
5. 포커스 모드 카드 분할 구현.
6. focus-specific undo coalescing 구현.

### Milestone 4, Export Parity

1. BWR export bridge 구현.
2. 기존 PDF/TXT 출력기 이식.
3. golden output 비교.
4. 설정 parity 확인.

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

## Main Risks

1. 인덱스 보드 손맛을 AppKit 없이 다시 만드는 일.
2. 포커스 모드의 caret/scroll/typewriter 감각 이식.
3. 클론 삭제 예외 규칙과 archive 규칙이 충돌할 가능성.
4. export parity를 유지하면서 입력 모델만 바꾸는 브리지 설계.
5. iPad-first 앱을 Mac에서도 실행 가능하게 유지하면서 입력 체감이 망가질 가능성.

## Review Status

1. 2026-04-08 적대적 `codex` 리뷰를 수행했다.
2. 반영한 지적은 `clone source of truth 명시`, `clone delete 규칙 일관화`, `export parity 범위 재정의`, `undo 경계 명시`, `Mac acceptance 기준 명시`다.
