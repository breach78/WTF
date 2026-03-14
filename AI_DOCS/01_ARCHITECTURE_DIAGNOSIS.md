# Architecture Diagnosis

작성일: 2026-03-14

## 요약

현재 앱은 기능적으로는 매우 강력하다. 워크스페이스 저장, 카드 계층 편집, 포커스 모드, 히스토리, AI 보조, 레퍼런스 창, PDF 출력, Fountain 붙여넣기까지 하나의 흐름 안에서 동작한다.

하지만 구조적으로는 `ScenarioWriterView` 중심의 거대한 상태 허브 위에 많은 기능이 누적된 형태다. 파일 분리는 되어 있으나, 분리 기준이 "모듈 경계"가 아니라 "같은 View의 extension 파일 분산"에 가깝다. 즉, 소스 파일은 나뉘어도 런타임 책임은 한 곳에 집중되어 있다.

시나리오/대본 앱 관점에서 가장 큰 구조적 리스크는 두 가지다.

1. 편집기 상태, 키보드/캐럿/스크롤 제어, undo, 히스토리, AI, import/export가 모두 `ScenarioWriterView` 상태와 직접 결합되어 있다.
2. 대본 포맷 의미론이 도메인 모델이 아니라 대부분 `SceneCard.content`의 raw text와 import/export 시점 파서에 묻혀 있다.

즉, 지금 구조는 "빠르게 기능을 쌓기 좋은 구조"이지만, 앞으로 screenplay 문법 지원, 포맷 정규화, 협업 기능, 안정적 리팩토링까지 고려하면 반드시 중간 계층을 세워야 한다.

## 1. 시스템 아키텍처 및 데이터 흐름

### 1-1. 현재 아키텍처 개요

현재 런타임의 중심 흐름은 다음과 같다.

1. `waApp.swift`
   앱 진입점, 워크스페이스 북마크 복원, `FileStore` 생성/주입, 메뉴 명령 등록, 레퍼런스 창 생성 담당.

2. `MainContainerView.swift`
   시나리오 목록, 선택 상태, 사이드바, 스플릿 모드, 메인/보조 창 이동을 담당.

3. `ScenarioWriterView` (`WriterViews.swift` + 여러 extension 파일)
   실제 편집기의 거의 모든 인터랙션을 담당.

4. `Models.swift`
   `Scenario`, `SceneCard`, `HistorySnapshot`, `FileStore` 등 도메인 객체와 저장소 담당.

5. 부가 기능 파일
   `WriterCardManagement.swift`, `WriterFocusMode.swift`, `WriterKeyboardHandlers.swift`, `WriterUndoRedo.swift`, `WriterAI*.swift`, `WriterCaretAndScroll.swift`, `ReferenceWindow.swift`, `ScriptPDFExport.swift` 등.

### 1-2. 상태 관리 구조

좋은 점:

- 영속 데이터는 `Scenario`, `SceneCard`, `FileStore`가 들고 있다.
- `Scenario`는 카드 인덱스, 루트/자식 캐시, clone 캐시, linked-card 캐시를 내부에 유지한다.
- `FileStore`는 debounce save, dirty cache skip, parallel load를 구현해 두었다.
- 앱 전역 설정은 `@AppStorage`로 비교적 일관되게 관리한다.

문제점:

- `ScenarioWriterView` 하나에 상태가 과도하게 집중되어 있다.
- 실제 집계 결과 `ScenarioWriterView`에는 `@State` 176개, `@AppStorage` 25개, `@FocusState` 6개가 있다.
- 이 상태들은 단순 UI 상태를 넘어서 편집 세션 상태, undo stacks, keyboard monitor handles, AI request tasks, import dialog state, dictation state, caret memory, scroll normalization state까지 포함한다.

즉, 현재 상태 구조는 다음처럼 섞여 있다.

- UI 표시 상태: `showTimeline`, `showHistoryBar`, `showFocusMode`
- 선택/포커스 상태: `activeCardID`, `selectedCardIDs`, `editingCardID`, `focusModeEditorCardID`
- 편집 엔진 상태: caret 위치, selection tracking, text view responder mapping
- 명령 상태: delete alert, paste dialog, clone paste, fountain paste
- 데이터 파생 상태: preview diffs, AI digest cache, embedding index
- 비동기/작업 상태: `Task`, `DispatchWorkItem`, monitor handles

이렇게 서로 다른 수명의 상태가 한 View 레벨에 같이 존재하면 다음 문제가 생긴다.

- 변경 영향 범위를 예측하기 어렵다.
- 특정 기능을 수정할 때 다른 기능의 lifecycle을 쉽게 깨뜨린다.
- 편집기 성능 문제와 상태 전이 버그가 같이 발생한다.
- 테스트 가능한 단위로 떼어내기 어렵다.

### 1-3. 데이터 흐름

현재 데이터 흐름은 "단방향 데이터 흐름"이라기보다 "View 중심 양방향 제어"에 가깝다.

대표 흐름은 다음과 같다.

1. 사용자가 카드 편집
2. `TextEditor` binding이 `SceneCard.content` 직접 변경
3. View extension이 old/new diff 계산
4. 동일 extension이 undo coalescing, caret 보정, line spacing 적용, scroll normalization, linked-card 기록, snapshot 승격, autosave scheduling을 같이 수행
5. 마지막에 `FileStore.saveAll()` 또는 debounce 저장으로 연결

즉, UI 이벤트 처리와 도메인 변경, 저장 트리거가 한 call chain 안에서 섞여 있다.

### 1-4. 명령 전달 방식

명령 전달은 주로 두 가지 방식이 섞여 있다.

- SwiftUI binding / direct method call
- `NotificationCenter` + `NSEvent` local monitor

예:

- `waApp.swift` 메뉴 명령은 `NotificationCenter`로 undo/redo/focus toggle을 전송한다.
- `ScenarioWriterView`는 `.onReceive`와 local key monitor 둘 다 사용한다.
- `MainContainerView`도 split pane, reference window, fullscreen 상태를 notification 기반으로 처리한다.

이 방식은 빠르게 붙이기에는 좋지만, 명령의 소유자와 소비자가 코드상 명확하지 않다. 특히 포커스 모드처럼 keyboard monitor와 lifecycle이 섞이는 구간에서 유지보수 비용이 크다.

### 1-5. 텍스트 포맷팅 앱 관점의 구조 진단

이 앱은 screenplay/Fountain 스타일의 복잡한 텍스트 의미론을 다룬다. 그런데 현재 편집 도메인의 기본 단위는 "구조화된 screenplay node"가 아니라 `SceneCard.content` 문자열이다.

현재 의미론이 적용되는 대표 지점:

- export: `buildExportText()` -> `ScriptMarkdownParser` -> `ScriptPDFGenerator`
- import: `parseFountainClipboardImport()` -> 카드 생성

좋은 점:

- import/export 파서와 PDF 생성기는 별도 파일로 분리되어 있다.
- Fountain 붙여넣기 파싱 로직은 `WriterSharedTypes.swift`에 분리되어 있다.

한계:

- 편집 중인 문서는 typed screenplay AST가 아니다.
- 제목 페이지, scene heading, dialogue block, parenthetical 같은 개념이 에디터 내부 모델에 없다.
- 그래서 규칙 적용 시점이 편집 중이 아니라 import/export 시점에 치우친다.
- 결국 기능이 늘수록 "raw text 추론" 로직이 여기저기 추가될 가능성이 높다.

대본 앱으로 확장하려면 최소한 다음 수준의 의미 계층이 필요하다.

- `TitlePage`
- `ScriptBlock`
- `SceneHeading`
- `Action`
- `CharacterCue`
- `Dialogue`
- `Parenthetical`
- `Transition`
- `CenteredText`

지금 구조는 "카드 에디터 앱"으로는 괜찮지만, "screenplay-aware editor"로 가기엔 중간 의미 계층이 비어 있다.

## 2. 코드 복잡도 및 강한 의존성

### 2-1. Massive View / Massive Extension 문제

큰 파일은 다음과 같다.

- `WriterCardManagement.swift`: 2835 lines
- `WriterFocusMode.swift`: 2496 lines
- `WriterHistoryView.swift`: 1810 lines
- `WriterViews.swift`: 1625 lines
- `SettingsView.swift`: 1497 lines
- `WriterKeyboardHandlers.swift`: 1456 lines
- `Models.swift`: 1325 lines

핵심 문제는 단순히 파일이 크다는 점이 아니다. 실제 문제는 이 큰 파일들이 대부분 `ScenarioWriterView`의 extension이라는 점이다.

즉, 파일이 나뉘어 있어도 다음 책임이 여전히 하나의 타입에 묶여 있다.

- 메인 카드 편집
- 포커스 모드
- 히스토리/스냅샷
- 키보드 라우팅
- drag & drop
- copy/paste/import/export
- undo/redo
- AI thread persistence
- dictation
- auto backup 트리거

이 구조는 "읽기 분산"만 되고 "책임 분산"은 되지 않는다.

### 2-2. View 와 비즈니스 로직의 강한 결합

특히 강하게 결합된 부분은 다음과 같다.

1. `WriterCardManagement.swift`
   카드 변경, drag/drop, export, paste, delete, summary prompt 생성, reference window 전달까지 모두 포함한다.

2. `WriterFocusMode.swift`
   포커스 모드 UI뿐 아니라 selection tracking, text view geometry, scroll normalization, keyboard event routing, caret ensure가 모두 들어 있다.

3. `WriterUndoRedo.swift`
   undo 모델은 별도이지만 실제 capture/restore가 `ScenarioWriterView` 상태와 `NSApp.keyWindow?.firstResponder`에 직접 의존한다.

4. `ReferenceWindow.swift`
   별도 편집기/undo/coalescing/caret ensure 로직을 다시 구현하고 있다.

5. `WriterCardViews.swift`
   뷰 파일이면서 `NSLayoutManager` 기반 텍스트 높이 측정, live responder 측정, 편집기 geometry 계산을 수행한다.

즉, View가 다음 질문에 모두 답하고 있다.

- 무엇을 보여줄까
- 무엇을 저장할까
- 변경을 undo에 어떻게 적재할까
- 타이핑 경계를 어떻게 판정할까
- 캐럿을 어디로 보내야 할까
- 언제 autosave/snapshot 해야 할까

이건 유지보수 측면에서 과도한 책임 집중이다.

### 2-3. 편집기 구현 중복

현재 텍스트 편집기 계층은 최소 세 군데에서 유사한 문제를 각자 푼다.

- 메인 카드 편집기
- 포커스 모드 편집기
- 레퍼런스 창 편집기

공통으로 중복되는 것:

- `TextEditor` wrapper
- live `NSTextView` 높이 측정
- deterministic text height 계산
- caret visibility ensure
- line spacing / container width 조절
- typing coalescing / undo 처리

이 중복은 단순 코드량 문제보다 더 위험하다. 한 편집기에서 고친 버그가 다른 편집기에 남기 쉽고, 동작 일관성이 깨진다.

### 2-4. 이벤트/포커스 계층의 암묵적 의존성

포커스, 키보드, split pane, reference window는 다음 메커니즘이 혼합되어 있다.

- `@FocusState`
- `NSApp.keyWindow?.firstResponder`
- `NotificationCenter`
- `NSEvent.addLocalMonitorForEvents`
- `NSTextView.didChangeSelectionNotification`

이 조합은 macOS 텍스트 편집에서는 어느 정도 불가피하지만, 현재는 이를 감싸는 명확한 coordinator 계층이 없다. 그래서 다음과 같은 현상이 구조적으로 자주 발생할 가능성이 높다.

- 모드 전환 시 중복 teardown/startup
- shortcut 처리와 menu command 처리의 충돌
- composition 중 selection/caret 오작동
- split pane 비활성 상태와 active responder 불일치

### 2-5. 대본 도메인 의미론의 분산

대본 의미론은 현재 세 군데 이상으로 분산되어 있다.

- export parser (`ScriptPDFExport.swift`)
- Fountain import parser (`WriterSharedTypes.swift`)
- 카드 문자열 조합 (`buildExportText()` 등)

이것은 "같은 screenplay 규칙"이 여러 진입점에서 중복 정의될 가능성을 만든다.

예를 들어 앞으로 다음 요구가 생기면 리스크가 커진다.

- scene number 자동 부여
- character cue validation
- title page 편집 UI
- block type별 스타일 프리뷰
- Fountain round-trip fidelity 보장

현재 구조로는 raw text parser를 여러 군데에 덧대는 방향으로 갈 가능성이 높다.

### 2-6. 테스트 부재

프로젝트 안에 XCTest 타깃이나 테스트 코드가 없다.

이 상태에서 다음 영역을 리팩토링하면 회귀 위험이 매우 높다.

- focus mode / keyboard
- undo / redo
- import / export
- save / load
- AI persistence
- clone card synchronization

현재 구조에서는 테스트 부재가 기술 부채를 증폭시키는 핵심 요인이다.

## 3. 구조적 기술 부채 및 개선 계획

### 3-1. 반드시 지켜야 할 아키텍처 규칙

앞으로 확장을 위해 다음 규칙은 강제하는 것이 좋다.

1. `View`는 장기 수명의 편집 워크플로 상태를 직접 소유하지 않는다.
   `ScenarioWriterView`는 표시와 action dispatch만 담당하고, 편집 세션 상태는 별도 store/coordinator가 소유해야 한다.

2. 도메인 변경은 반드시 명시적 action/use case를 통해서만 일어난다.
   예: `insertSibling`, `deleteSelection`, `applyFountainImport`, `commitTextEdit`, `toggleFocusMode`.

3. 키보드/포커스/캐럿/스크롤 보정은 `EditorInteractionCoordinator` 계층으로 분리한다.
   View extension 내부에서 직접 `NSApp.keyWindow`와 `NSTextView`를 뒤지는 구조를 줄여야 한다.

4. 대본 의미론은 raw text 추론이 아니라 typed document layer로 수렴시킨다.
   import/export/parser/preview 모두 같은 중간 모델을 공유해야 한다.

5. persistence는 `Repository` 계층으로 고정한다.
   `FileStore`는 이미 저장소 역할을 하고 있으므로, 앞으로는 View에서 직접 저장 전략을 알지 않게 해야 한다.

6. 레퍼런스 창, 메인 편집기, 포커스 모드는 공통 editor engine을 공유한다.
   높이 측정, caret visibility, line spacing, typing boundary 판정은 하나의 서비스로 모아야 한다.

7. cross-feature command는 NotificationCenter 남용 대신 typed command router 또는 action dispatcher를 사용한다.

### 3-2. 권장 목표 구조

권장 구조는 다음과 같다.

- `Domain`
  `Scenario`, `SceneCard`, `ScriptDocument`, `ScriptBlock`, undo snapshot types

- `Persistence`
  `ScenarioRepository`, `WorkspaceRepository`, `AIThreadRepository`

- `Application`
  `WriterSessionStore`, `WriterAction`, `WriterReducer` 또는 command handlers

- `EditorEngine`
  `MainEditorCoordinator`, `FocusEditorCoordinator`, `ReferenceEditorCoordinator`, 공통 `TextLayoutService`

- `Formatting`
  `FountainImportService`, `ScriptExportService`, `ScriptNormalizationService`

- `Presentation`
  `ScenarioWriterView`, `MainCanvasView`, `FocusModeView`, `HistoryPanelView`, `AIChatPanelView`

핵심은 "지금의 extension 분리"를 "타입과 계층 분리"로 바꾸는 것이다.

### 3-3. 단계별 리팩토링 전략

#### Phase 1. 상태 분리

가장 먼저 해야 할 일:

- `ScenarioWriterView`의 상태를 기능별 세션 객체로 이동
- 최소 단위로 다음 store를 분리
  - `WriterSelectionState`
  - `WriterEditingState`
  - `WriterHistoryState`
  - `WriterAIState`
  - `WriterFocusModeState`

추천 구현:

- 처음부터 대규모 Redux로 갈 필요는 없다.
- `@MainActor final class WriterSessionStore: ObservableObject` 하나를 만들고, 내부에 위 state slices를 나누는 방식이 현실적이다.

효과:

- `@State` 폭발을 줄일 수 있다.
- lifecycle과 business logic을 View 밖으로 뺄 수 있다.
- 테스트 가능한 메서드 단위가 생긴다.

#### Phase 2. 편집기 엔진 통합

다음으로 해야 할 일:

- 메인/포커스/레퍼런스 편집기에서 중복된 높이 측정, caret ensure, line spacing 적용 코드를 공통 서비스로 추출
- 예: `TextLayoutService`, `TextViewGeometryService`, `CaretVisibilityCoordinator`

특히 중요한 규칙:

- `NSTextView` 직접 제어는 coordinator 내부에서만 한다.
- View는 "이 카드 편집 시작", "이 카드 caret 보장" 같은 intent만 보낸다.

효과:

- 포커스 모드와 메인 편집기 간 버그 수정이 동기화된다.
- 성능 최적화 포인트가 한 곳에 모인다.

#### Phase 3. screenplay 도메인 계층 도입

대본 앱으로 확장하려면 반드시 필요한 단계다.

해야 할 일:

- `ScriptDocument` 중간 모델 추가
- title page, scene heading, dialogue block 등을 typed block으로 표현
- Fountain import/export, PDF export, clipboard import가 이 모델을 공유하게 변경

추천 방식:

- 기존 카드 시스템은 당장 버리지 않는다.
- 1차로는 `SceneCard.content` <-> `ScriptDocument` 변환기를 둔다.
- 이후 점진적으로 편집 기능도 typed block 기반 validation을 받게 한다.

효과:

- screenplay 문법 기능을 안전하게 늘릴 수 있다.
- import/export 규칙이 한 군데로 모인다.
- 대본 전용 UI 기능을 붙이기 쉬워진다.

#### Phase 4. 명령 계층 정리

해야 할 일:

- undo/redo, focus toggle, split pane activate, reference open 같은 전역 명령을 typed action으로 통일
- `NotificationCenter`는 외부 window integration 같은 제한된 용도만 남긴다.

효과:

- 누가 명령을 발행하고 소비하는지 추적이 쉬워진다.
- 모드 전환 버그가 줄어든다.

#### Phase 5. 테스트 기반 확보

리팩토링 전에 최소한 아래 테스트는 반드시 생겨야 한다.

- `Scenario` index/cache rebuild tests
- `FileStore` save/load round-trip tests
- Fountain import parsing tests
- PDF export element parsing tests
- undo/redo state restore tests
- clone synchronization tests
- typing boundary detection tests

UI 테스트까지는 당장 없어도 되지만, 최소한 도메인/서비스 테스트는 먼저 만들어야 한다.

## 결론

현재 구조는 "기능 누적형 SwiftUI 앱"으로서 상당히 높은 완성도를 보여준다. 특히 다음은 분명한 강점이다.

- `Scenario`와 `FileStore`가 어느 정도 도메인/persistence 중심축 역할을 한다.
- 저장은 debounce + parallel load + dirty-skip로 꽤 현실적으로 설계되어 있다.
- import/export 파서와 PDF 생성기는 최소한 별도 파일로 분리되어 있다.
- 화면 기능은 많지만 실제 사용자 워크플로 관점에서 통합감이 있다.

하지만 유지보수성 관점에서는 이미 한계 구간에 들어왔다.

- `ScenarioWriterView`는 너무 많은 책임을 가진다.
- 편집 엔진 로직이 View extension 안에 과도하게 들어 있다.
- 포맷 의미론이 도메인 모델이 아니라 raw text 추론에 의존한다.
- 레퍼런스 창과 메인/포커스 편집기의 중복 구현이 커지고 있다.
- 테스트가 없어 구조 개편 리스크가 높다.

따라서 권장 전략은 "한 번에 전면 재작성"이 아니라 다음 순서다.

1. 상태를 세션 store로 분리
2. 편집기 엔진 공통화
3. screenplay typed document 계층 도입
4. 명령 라우팅 정리
5. 서비스/도메인 테스트 추가

이 순서를 지키면 현재 기능을 유지하면서도, 앞으로 screenplay 특화 기능과 복잡한 텍스트 포맷팅을 안정적으로 확장할 수 있다.
