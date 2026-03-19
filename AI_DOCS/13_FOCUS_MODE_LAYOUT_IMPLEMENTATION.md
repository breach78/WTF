# Focus Mode Layout Implementation

작성일: 2026-03-18

## 범위

`12_FOCUS_MODE_LAYOUT_REFACTOR_PLAN.md` 기준으로 포커스 모드 layout refactor의 첫 구조 전환을 반영했다.

이번 단계의 목표는 클릭 순간 카드 shell 높이가 흔들리는 직접 원인을 끊는 것이다.

## 이번에 반영한 구조 변경

### 1. Single layout authority 도입

- 새 파일: `/Users/three/app_build/wa/wa/FocusModeLayoutCoordinator.swift`
- 포커스 모드 카드 높이는 이제 카드 content fingerprint + width/font/line-spacing bucket 기준의 explicit cache에서 계산한다.
- inactive/active shell 높이는 모두 coordinator의 deterministic record를 사용한다.

### 2. Single active editor 전환

- `/Users/three/app_build/wa/wa/WriterCardViews.swift`
- `FocusModeCardEditor`는 더 이상 모든 카드에 대해 live measurement source를 고르지 않는다.
- active card만 `TextEditor`를 렌더링한다.
- inactive 카드는 같은 typography/padding을 유지한 read-only `Text` renderer를 사용한다.
- shell height는 `measuredHeight`로 고정되고, 클릭 전후에 shell identity는 유지된다.

### 3. Inactive click caret handoff 단순화

- `/Users/three/app_build/wa/wa/WriterFocusMode.swift`
- inactive 카드를 클릭할 때는 현재 responder `NSTextView`를 억지로 재활용하지 않고,
  deterministic text layout으로 click point를 caret location으로 변환한다.
- active editor인 경우에만 기존 responder 기반 caret 계산을 유지한다.

### 4. Multi-editor scan 경로 축소

- `/Users/three/app_build/wa/wa/WriterFocusMode.swift`
- 포커스 모드 text-view 해석은 이제 “focused column의 여러 editor”를 가정하지 않고, single active editor를 우선한다.
- `resolveFocusModeTextView(for:)`는 active editor card에 대해서만 실제 `NSTextView`를 해석한다.
- offset normalization도 root 전체의 editable text view scan 대신 active editor 하나만 기준으로 수행한다.
- `active-card-change` 시점의 선행 normalization 호출을 제거했다.

### 5. Inactive renderer도 AppKit text engine으로 통일

- `/Users/three/app_build/wa/wa/WriterCardViews.swift`
- inactive 카드는 더 이상 SwiftUI `Text`로 렌더링하지 않는다.
- 대신 read-only `NSTextView` 기반 `NSViewRepresentable` renderer를 사용한다.
- line fragment padding, line spacing, text container width를 active editor와 같은 AppKit layout model에 맞췄다.
- 클릭 전후에 `Text` 엔진과 `NSTextView` 엔진 사이를 오가며 생기던 horizontal shift를 구조적으로 제거하는 목적이다.

## 기대 효과

- 카드 클릭 시 inactive renderer가 active editor로 바뀌더라도 shell 높이는 유지된다.
- 클릭 순간 previous editor / next editor / observed height cache가 서로 다른 authority를 주장하지 않는다.
- 포커스 모드의 runtime cost가 “여러 NSTextView scan + remap + observed update”에서 “단일 active editor sync”로 줄어든다.
- inactive/active가 같은 AppKit text engine을 쓰므로, 클릭 순간 텍스트가 좌우로 밀리는 현상도 줄어든다.

## 아직 남아 있는 항목

- `focusObservedBodyHeightByCardID` 관련 옛 helper와 normalization 보조 코드가 파일 안에 남아 있다.
- 현재 동작 경로에서는 primary authority가 아니지만, 다음 단계에서 제거 대상으로 정리할 수 있다.
- `FocusModeEditorSession` 수준의 runtime 분리는 아직 시작하지 않았다.

## 검증

- `xcodebuild -project wa.xcodeproj -scheme wa -configuration Debug build`
- 결과: `BUILD SUCCEEDED`
