# Main Workspace Editing State Cleanup Plan

작성일: 2026-03-28

## 목적

메인 작업창의 `가짜 편집 상태`를 보정으로 덮지 않고 구조적으로 정리한다.

이번 계획의 목표는 세 가지다.

- `Enter` 후 바로 실제 편집 상태가 된다.
- 편집 중 방향키, `Esc`, 경계 이동이 모두 같은 진실값을 따른다.
- row 렌더링과 외부 AppKit editor host가 서로 중복 소유하지 않는다.

## 현재 문제의 본질

지금 회귀의 핵심은 `하이브리드 ownership`이다.

- SwiftUI row는 여전히 카드 본문과 높이, 포커스 표시를 일부 소유한다.
- 외부 AppKit host는 실제 `NSTextView`와 caret, first responder를 소유한다.
- 키보드 라우팅은 전역 모니터와 editor command가 동시에 개입한다.

이 셋이 한 프레임만 어긋나도 바로 아래 증상이 나온다.

- 커서는 보이지만 편집이 아니다.
- `Enter`는 먹었는데 방향키는 카드 포커스를 움직인다.
- `Esc`가 종료가 아니라 삑 소리로 간다.
- 편집 카드에서 글자가 겹치거나 shell/editor가 동시에 보인다.

정리 방향은 단순하다.

- 편집 authority를 하나로 줄인다.
- row는 geometry owner로만 남긴다.
- 키보드는 실제 editor responder만 믿는다.

## 단계 1. Editing Authority 단일화

### 목표

편집 상태의 진실값을 `실제 편집 가능한 NSTextView responder + mainEditorSession` 하나로 고정한다.

### 작업

- `editingCardID`를 단독 진실값으로 쓰지 않는다.
- `mainEditorSession`을 아래 상태로 명시한다.
  - `requestedCardID`
  - `mountedCardID`
  - `textViewIdentity`
  - `caretSeedLocation`
  - `isFirstResponderReady`
  - `liveBodyHeight`
- `isFirstResponderReady`는 `실제 editable NSTextView가 key window first responder인지` 기준으로만 갱신한다.
- `resolvedActiveMainEditorTextView(...)`와 키보드 편집 판정은 같은 helper를 사용한다.
- `finishEditing()`은 모두 이유를 가진 경로로 통일한다.
  - `explicitExit`
  - `transition`
  - `generic`
- `generic` 종료는 계측상 허용된 경우만 통과시키고, 나머지는 억제 또는 경고 로그를 남긴다.

### 완료 기준

- `Enter` 후 `editingCardID != nil`, `mountedCardID != nil`, `firstResponder == NSTextView`가 같은 카드로 맞는다.
- 편집 중 좌우 방향키는 caret 이동으로만 처리되고 카드 포커스 이동은 일어나지 않는다.
- `Esc`는 항상 편집 종료로 수렴한다.

### 제외

- scroll behavior 재설계
- detached overlay 구조 변경

## 단계 2. Render Ownership 정리

### 목표

편집 카드의 본문 렌더링을 row와 외부 host가 동시에 소유하지 않게 만든다.

### 작업

- row는 `geometry owner + placeholder owner`만 담당한다.
- 외부 host가 `requested/mounted/active`인 카드 row는 본문 텍스트를 직접 그리지 않는다.
- 편집 카드에서 row가 가질 수 있는 것은 아래 둘뿐이다.
  - 빈 placeholder
  - slot frame reporter
- host visibility 조건을 명시한다.
  - `requested`부터 scaffold는 유지
  - `mounted` 이후 host frame은 안정적으로 유지
  - `active`일 때만 실편집 상태 styling을 노출
- shell과 editor typography 차이로 생기는 겹침을 막기 위해, 편집 중 row는 텍스트 glyph를 절대 갖지 않는다.

### 완료 기준

- 편집 진입 직후 텍스트가 하얗게 사라지거나 겹치지 않는다.
- 편집 카드에서 shell 텍스트와 AppKit editor 텍스트가 동시에 보이지 않는다.
- host remount 없이 같은 editor instance가 유지되는 동안 row height만 따라간다.

### 제외

- shell과 editor typography 완전 통합
- 새 디자인 작업

## 단계 3. Keyboard/Scroll Boundary 격리

### 목표

편집 중 키보드 경계 이동과 일반 카드 포커스 이동, 그리고 scroll reveal을 서로 섞이지 않게 분리한다.

### 작업

- 전역 방향키 모니터는 `실제 editor responder가 있을 때` 즉시 빠진다.
- 편집 경계 이동은 `NSTextView doCommandBy` 또는 boundary helper만 통해 처리한다.
- 편집 중 `activeCardID`가 바뀌는 경우는 아래 둘만 허용한다.
  - 명시적 boundary transition
  - 명시적 편집 종료 후 일반 포커스 이동
- edit entry / boundary transition 중에는 일반 auto-align, restore, settle scroll을 잠시 중지한다.
- caret reveal, active card align, viewport restore의 authority를 동시에 실행하지 않는다.

### 완료 기준

- 편집 중 방향키는 카드 포커스를 움직이지 않는다.
- 카드 간 경계 이동 시에도 새 카드가 즉시 실제 편집 상태로 이어진다.
- 편집 진입/경계 이동/종료에서 스크롤 튐이 재현되지 않는다.

### 제외

- WorkspaceSurfaceV2 전체 재추진
- index board/timeline 편집 경로 통합

## 실행 순서

1. 단계 1을 먼저 끝낸다.
2. 단계 1 완료 전에는 단계 2의 시각 보정만 단독으로 넣지 않는다.
3. 단계 2 완료 후 단계 3으로 넘어간다.

이 순서를 지켜야 하는 이유는 다음과 같다.

- 단계 1 없이 단계 2만 하면 `보이는 문제`만 줄고 키보드/포커스 회귀가 남는다.
- 단계 2 없이 단계 3만 하면 경계 이동은 줄어도 겹침/잔상이 남는다.

## 작업 원칙

- 메인 작업창 범위 밖 수정 금지
- `single source of truth`를 늘리지 말고 줄인다
- 같은 의미의 편집 판정 helper를 중복 만들지 않는다
- row subtree와 host subtree의 책임을 명확히 분리한다

## 성공 판정

아래 다섯 가지가 모두 만족되면 이번 정리 작업은 완료다.

- 포커스 카드에서 `Enter` 한 번으로 바로 깜빡이는 caret이 나온다.
- 편집 중 좌우 방향키는 caret 이동만 한다.
- 편집 중 `Esc`는 바로 종료된다.
- 편집 카드에서 글자 겹침이나 잔상이 없다.
- 로그상 `activeCardID`, `editingCardID`, `mainEditorSession`, `firstResponder`가 같은 카드로 수렴한다.
