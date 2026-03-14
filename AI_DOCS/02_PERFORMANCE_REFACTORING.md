# Performance Refactoring

작성일: 2026-03-14

## 목표

이번 단계의 목표는 기능과 사용자 경험을 바꾸지 않고, 현재 코드베이스에서 실제로 안전하게 적용 가능한 성능/안정성 리팩토링을 수행하는 것이다.

중요한 제약은 다음과 같았다.

- 메인 작업창, 포커스 모드, 레퍼런스 창의 동작 방식은 유지
- 카드 모델, 저장 포맷, undo/redo 의미는 유지
- 화면 구조를 크게 바꾸는 고위험 리팩토링은 제외
- 대신 반복 비용이 큰 부분, 크래시 가능성이 있는 부분, 비동기 상태 경합 부분을 우선 정리

이번 단계에서 실제 반영한 변경은 다음 세 가지다.

1. 텍스트 높이 측정 공통화 + 측정 캐시 도입
2. 워크스페이스 비동기 로드 stale task 방지
3. 강제 언래핑 제거로 잠재 크래시 면적 축소

## 1. 렌더링 성능 및 메모리 분석

### 1-1. 불필요한 재렌더링 / 레이아웃 비용

#### A. `ScenarioWriterView` 상태 집중으로 인한 넓은 invalidation

현재 `ScenarioWriterView`는 매우 큰 상태 허브다. 실제 집계 기준으로 `@State` 176개, `@AppStorage` 25개, `@FocusState` 6개를 가진다.

이 구조의 문제는 다음과 같다.

- 작은 상태 변화도 큰 View 트리 재평가로 이어지기 쉽다.
- 편집/포커스/히스토리/AI 상태가 한 타입 안에 섞여 있어서 invalidation 범위가 넓다.
- SwiftUI가 body 재계산을 할 때, 실제 화면 변화와 관계없는 계산도 같이 끌려온다.

이 문제는 구조 개편이 필요하므로 이번 단계에서 전면 수정하지는 않았다. 다만, 실제 체감 비용이 컸던 하위 병목을 먼저 제거했다.

#### B. 텍스트 높이 측정의 중복 비용

가장 즉시 비용이 컸던 부분은 텍스트 높이 측정이다.

기존에는 다음 세 편집기 계층이 거의 같은 측정 로직을 각각 구현했다.

- 메인 카드 편집기
- 포커스 모드 편집기
- 레퍼런스 창 편집기

세 곳 모두 다음 패턴을 반복했다.

- `NSTextStorage`
- `NSLayoutManager`
- `NSTextContainer`
- `ensureLayout`
- `usedRect`

문제는 이 측정이 다음 타이밍마다 반복된다는 점이다.

- `onAppear`
- 폰트 크기 변경
- 줄간격 변경
- 카드 폭 변경
- 본문 변경
- 활성/비활성 전환

즉, 같은 텍스트/같은 폭/같은 폰트 조합에 대해 같은 레이아웃 계산이 여러 번 다시 일어날 수 있었다.

이번 단계에서 이 부분을 공통 측정기로 통합하고 `NSCache` 기반 캐시를 추가했다.

#### C. 포커스 모드의 구조적 고비용

포커스 모드는 여전히 구조적으로 entry cost가 큰 편이다.

- `focusModeCanvas`는 현재 컬럼 카드를 `VStack`으로 eager 생성한다.
- 각 카드가 `TextEditor`를 가진다.
- 진입 시 스크롤/캐럿/selection normalization이 추가로 돈다.

이건 이번 단계에서 일부 개선은 했지만, 완전한 해결은 아니다. 근본적으로는 다음 중 하나가 필요하다.

- 비활성 카드를 `Text` 기반 preview로 바꾸고 활성 카드만 editor로 유지
- 또는 focus-mode 전용 lazy editor stack 설계

하지만 이 변경은 UX와 편집 semantics를 건드릴 위험이 커서, 이번 단계에서는 보류했다.

### 1-2. 메모리 분석

#### A. 명시적 메모리 누수

현재 코드에서 확인된 observer/monitor 해제 경로는 대체로 존재한다.

- `focusModeSelectionObserver`는 정리 함수에서 해제됨
- `historyKeyMonitor`, `mainNavKeyMonitor`, `splitPaneMouseMonitor`는 모두 해제 함수 보유
- `MainWindowSizePersistenceAccessor`는 `deinit`에서 observer 제거
- `SceneCard.scenario`는 `weak`

즉, 이번 점검 범위 안에서는 “명확한 retain cycle로 인한 상시 메모리 누수”는 크게 보이지 않았다.

다만 다음은 메모리 누수보다는 “메모리 churn”에 가깝다.

- 반복적인 `NSTextStorage`/`NSLayoutManager`/`NSTextContainer` 생성
- 반복적인 `DispatchWorkItem` 생성
- focus mode entry 시 다수의 `TextEditor`/`NSTextView` 동시 생성

이번 리팩토링은 이 중 첫 번째를 줄이는 데 초점을 맞췄다.

#### B. 캐시의 메모리 안전성

텍스트 높이 측정 캐시는 `Dictionary`가 아니라 `NSCache`를 사용했다.

이 선택의 이유:

- 메모리 압박 시 자동 purge 가능
- 키 수 제한 가능
- 장시간 편집 세션에서 무한 성장 억제 가능

또한 캐시 키에 원문 전체 문자열을 그대로 들고 있지 않고, 길이 + fingerprint 기반 key를 사용해 key 메모리 부담도 줄였다.

### 1-3. 잠재적 크래시 요인

실제 코드에 남아 있던 강제 언래핑/강제 캐스팅은 아래 유형이었다.

- 타이틀 페이지 파싱 중 `currentKey!`
- undo snapshot 생성 중 `overrideContent!`
- linked card anchor 사용 중 `disconnectAnchorID!`
- PDF export 중 `CTFrameGetLines(frame) as! [CTLine]`
- scene number 보간 중 `sceneNumber!`
- 설정 화면의 상수 URL 초기화 `URL(...)!`

이들은 대부분 “현재 로직상 안전하다고 가정”된 위치였지만, 유지보수 중 조건이 바뀌면 즉시 크래시 surface가 된다. 이번 단계에서는 이들을 모두 안전한 optional 처리로 교체했다.

## 2. 실행 가능한 리팩토링 코드

아래 코드는 실제 반영된 코드다. 중간 생략 없이 그대로 기록한다.

### 2-1. 공통 텍스트 높이 측정기 + 캐시

파일: [WriterSharedTypes.swift](/Users/three/app_build/wa/wa/WriterSharedTypes.swift#L119)

```swift
private let sharedTextHeightMeasurementCache = SharedTextHeightMeasurementCache()

final class SharedTextHeightMeasurementCache: @unchecked Sendable {
    private let cache = NSCache<NSString, NSNumber>()

    init() {
        cache.countLimit = 4096
    }

    func measureBodyHeight(
        text: String,
        fontSize: CGFloat,
        lineSpacing: CGFloat,
        width: CGFloat,
        lineFragmentPadding: CGFloat,
        safetyInset: CGFloat
    ) -> CGFloat {
        let measuringText = normalizedMeasurementText(text)
        let constrainedWidth = max(1, width)
        let cacheKey = measurementCacheKey(
            text: measuringText,
            fontSize: fontSize,
            lineSpacing: lineSpacing,
            width: constrainedWidth,
            lineFragmentPadding: lineFragmentPadding,
            safetyInset: safetyInset
        )

        if let cached = cache.object(forKey: cacheKey) {
            return CGFloat(cached.doubleValue)
        }

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = lineSpacing
        paragraphStyle.lineBreakMode = .byWordWrapping

        let font = NSFont(name: "SansMonoCJKFinalDraft", size: fontSize)
            ?? NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)

        let storage = NSTextStorage(
            string: measuringText,
            attributes: [
                .font: font,
                .paragraphStyle: paragraphStyle
            ]
        )
        let layoutManager = NSLayoutManager()
        let textContainer = NSTextContainer(
            size: CGSize(width: constrainedWidth, height: CGFloat.greatestFiniteMagnitude)
        )
        textContainer.lineFragmentPadding = lineFragmentPadding
        textContainer.lineBreakMode = .byWordWrapping
        textContainer.maximumNumberOfLines = 0
        textContainer.widthTracksTextView = false
        textContainer.heightTracksTextView = false
        layoutManager.addTextContainer(textContainer)
        storage.addLayoutManager(layoutManager)
        layoutManager.ensureLayout(for: textContainer)

        let usedHeight = layoutManager.usedRect(for: textContainer).height
        let measured = max(1, ceil(usedHeight + safetyInset))
        cache.setObject(NSNumber(value: Double(measured)), forKey: cacheKey)
        return measured
    }

    private func normalizedMeasurementText(_ text: String) -> String {
        if text.isEmpty {
            return " "
        }
        if text.hasSuffix("\n") {
            return text + " "
        }
        return text
    }

    private func measurementCacheKey(
        text: String,
        fontSize: CGFloat,
        lineSpacing: CGFloat,
        width: CGFloat,
        lineFragmentPadding: CGFloat,
        safetyInset: CGFloat
    ) -> NSString {
        let fingerprint = stableTextFingerprint(text)
        let fontBits = Double(fontSize).bitPattern
        let spacingBits = Double(lineSpacing).bitPattern
        let widthBits = Double(width).bitPattern
        let paddingBits = Double(lineFragmentPadding).bitPattern
        let insetBits = Double(safetyInset).bitPattern
        let key = "\(fontBits)|\(spacingBits)|\(widthBits)|\(paddingBits)|\(insetBits)|\(text.utf16.count)|\(fingerprint)"
        return key as NSString
    }

    private func stableTextFingerprint(_ text: String) -> UInt64 {
        var hash: UInt64 = 1469598103934665603
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1099511628211
        }
        return hash
    }
}

func sharedMeasuredTextBodyHeight(
    text: String,
    fontSize: CGFloat,
    lineSpacing: CGFloat,
    width: CGFloat,
    lineFragmentPadding: CGFloat,
    safetyInset: CGFloat
) -> CGFloat {
    sharedTextHeightMeasurementCache.measureBodyHeight(
        text: text,
        fontSize: fontSize,
        lineSpacing: lineSpacing,
        width: width,
        lineFragmentPadding: lineFragmentPadding,
        safetyInset: safetyInset
    )
}

func sharedLiveTextViewBodyHeight(
    _ textView: NSTextView,
    safetyInset: CGFloat = 0,
    includeTextContainerInset: Bool = false
) -> CGFloat? {
    guard let layoutManager = textView.layoutManager,
          let textContainer = textView.textContainer else { return nil }

    let textLength = (textView.string as NSString).length
    if textLength > 0 {
        let fullRange = NSRange(location: 0, length: textLength)
        layoutManager.ensureGlyphs(forCharacterRange: fullRange)
        layoutManager.ensureLayout(forCharacterRange: fullRange)
    }
    layoutManager.ensureLayout(for: textContainer)

    let usedHeight = layoutManager.usedRect(for: textContainer).height
    guard usedHeight > 0 else { return nil }

    let insetHeight = includeTextContainerInset ? (textView.textContainerInset.height * 2) : 0
    return max(1, ceil(usedHeight + insetHeight + safetyInset))
}
```

### 2-2. 포커스 모드 편집기에서 공통 측정기 사용

파일: [WriterCardViews.swift](/Users/three/app_build/wa/wa/WriterCardViews.swift#L196)

```swift
private func liveFocusModeResponderBodyHeight() -> CGFloat? {
    guard isActive else { return nil }
    guard focusModeEditorCardID == card.id else { return nil }
    guard let textView = NSApp.keyWindow?.firstResponder as? NSTextView else { return nil }
    return sharedLiveTextViewBodyHeight(
        textView,
        safetyInset: focusModeBodySafetyInset
    )
}

private func refreshMeasuredHeights() {
    guard cardWidth > 1 else {
        return
    }
    let deterministicBodyHeight = sharedMeasuredTextBodyHeight(
        text: sizingText,
        fontSize: focusModeFontSize,
        lineSpacing: focusModeLineSpacing,
        width: textEditorMeasureWidth,
        lineFragmentPadding: FocusModeLayoutMetrics.focusModeLineFragmentPadding,
        safetyInset: focusModeBodySafetyInset
    )
    let resolvedBodyHeight: CGFloat
    let observedRangeMin: CGFloat
    let observedRangeMax: CGFloat

    if let liveBodyHeight = liveFocusModeResponderBodyHeight(), liveBodyHeight > 1 {
        resolvedBodyHeight = liveBodyHeight
    } else if let observedBodyHeight, observedBodyHeight > 1 {
        observedRangeMin = max(1, (deterministicBodyHeight * 0.65) - 80)
        observedRangeMax = (deterministicBodyHeight * 1.6) + 120
        let observedAccepted = observedBodyHeight >= observedRangeMin && observedBodyHeight <= observedRangeMax
        if observedAccepted {
            resolvedBodyHeight = observedBodyHeight
        } else {
            resolvedBodyHeight = deterministicBodyHeight
        }
    } else {
        let noObservedScale: CGFloat = deterministicBodyHeight > 180 ? 0.95 : 1.0
        resolvedBodyHeight = max(1, deterministicBodyHeight * noObservedScale)
    }
    
    if abs(measuredBodyHeight - resolvedBodyHeight) > 0.25 {
        measuredBodyHeight = resolvedBodyHeight
    }
}
```

### 2-3. 메인 카드 편집기에서 공통 측정기 사용

파일: [WriterCardViews.swift](/Users/three/app_build/wa/wa/WriterCardViews.swift#L436)

```swift
private func liveMainResponderBodyHeight() -> CGFloat? {
    guard isEditing else { return nil }
    guard editorFocus else { return nil }
    guard let textView = NSApp.keyWindow?.firstResponder as? NSTextView else { return nil }
    guard textView.string == card.content else { return nil }
    return sharedLiveTextViewBodyHeight(textView)
}

private func measureMainEditorBodyHeight(text: String, width: CGFloat) -> CGFloat {
    sharedMeasuredTextBodyHeight(
        text: text,
        fontSize: CGFloat(fontSize),
        lineSpacing: mainCardLineSpacing,
        width: width,
        lineFragmentPadding: mainEditorLineFragmentPadding,
        safetyInset: 0
    )
}
```

### 2-4. 레퍼런스 창 편집기에서 공통 측정기 사용

파일: [ReferenceWindow.swift](/Users/three/app_build/wa/wa/ReferenceWindow.swift#L568)

```swift
private func refreshMeasuredBodyHeight(for text: String? = nil) {
    let resolvedText = text ?? card.content
    let measured: CGFloat
    if focusedEntryID == entryID,
       let textView = NSApp.keyWindow?.firstResponder as? NSTextView,
       textView.window?.identifier?.rawValue == ReferenceWindowConstants.windowID,
       textView.string == resolvedText,
       let liveMeasured = liveFocusedBodyHeight(for: textView) {
        measured = liveMeasured
    } else {
        measured = sharedMeasuredTextBodyHeight(
            text: resolvedText,
            fontSize: fontSize,
            lineSpacing: lineSpacing,
            width: measuredEditorWidth,
            lineFragmentPadding: MainEditorLayoutMetrics.mainEditorLineFragmentPadding,
            safetyInset: measurementSafetyInset
        )
    }
    if abs(measuredBodyHeight - measured) > 0.25 {
        var noAnimation = Transaction()
        noAnimation.animation = nil
        withTransaction(noAnimation) {
            measuredBodyHeight = measured
        }
    }
}

private func liveFocusedBodyHeight(for textView: NSTextView) -> CGFloat? {
    sharedLiveTextViewBodyHeight(
        textView,
        safetyInset: measurementSafetyInset,
        includeTextContainerInset: true
    )
}
```

### 2-5. 워크스페이스 비동기 로드 stale task 방지

파일: [waApp.swift](/Users/three/app_build/wa/wa/waApp.swift#L480), [waApp.swift](/Users/three/app_build/wa/wa/waApp.swift#L676)

```swift
@State private var storeSetupRequestID: Int = 0

private func setupStore() {
    storeSetupRequestID += 1
    let requestID = storeSetupRequestID

    store?.flushPendingSaves()
    store = nil

    guard let bookmark = storageBookmark else { return }

    Task { @MainActor in
        do {
            var isStale = false
            let url = try URL(
                resolvingBookmarkData: bookmark,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            
            if isStale {
                let newBookmark = try url.bookmarkData(
                    options: .withSecurityScope,
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
                storageBookmark = newBookmark
            }
            
            _ = url.startAccessingSecurityScopedResource()

            let newStore = FileStore(folderURL: url)
            await newStore.load()
            guard requestID == storeSetupRequestID else { return }

            self.store = newStore
        } catch {
            guard requestID == storeSetupRequestID else { return }
            storageBookmark = nil
        }
    }
}
```

### 2-6. 강제 언래핑 제거

#### Fountain title page 파서

파일: [WriterSharedTypes.swift](/Users/three/app_build/wa/wa/WriterSharedTypes.swift#L440)

```swift
if let field = parseFountainTitlePageField(trimmed) {
    let normalizedKey = normalizedFountainTitlePageFieldKey(field.key)
    currentKey = normalizedKey
    if !field.value.isEmpty {
        fields[normalizedKey, default: []].append(field.value)
    } else if fields[normalizedKey] == nil {
        fields[normalizedKey] = []
    }
    continue
}

guard let currentKey else { continue }
fields[currentKey, default: []].append(trimmed)
```

#### Undo state capture

파일: [WriterUndoRedo.swift](/Users/three/app_build/wa/wa/WriterUndoRedo.swift#L44)

```swift
for card in sourceCards {
    let content = (card.id == overrideCardID) ? (overrideContent ?? card.content) : card.content
    cards.append(CardState(
        id: card.id,
        content: content,
        orderIndex: card.orderIndex,
        createdAt: card.createdAt,
        parentID: card.parent?.id,
        category: card.category,
        isFloating: card.isFloating,
        isArchived: card.isArchived,
        lastSelectedChildID: card.lastSelectedChildID,
        colorHex: card.colorHex,
        cloneGroupID: card.cloneGroupID
    ))
}
```

#### Linked card anchor

파일: [WriterCardManagement.swift](/Users/three/app_build/wa/wa/WriterCardManagement.swift#L148)

```swift
let canDisconnectLinkedCard =
    linkedCardsFilterEnabled &&
    disconnectAnchorID.flatMap { anchorID in
        scenario.linkedCardEditDate(
            focusCardID: anchorID,
            linkedCardID: card.id
        )
    } != nil
```

#### PDF export

파일: [ScriptPDFExport.swift](/Users/three/app_build/wa/wa/ScriptPDFExport.swift#L907)

```swift
private func drawSplittedText(_ attrString: NSAttributedString, in context: CGContext, width: CGFloat, xPos: CGFloat, cursorY: inout CGFloat, pageNumber: inout Int) -> NSAttributedString? {
    let framesetter = CTFramesetterCreateWithAttributedString(attrString as CFAttributedString)
    let path = CGPath(rect: CGRect(x: 0, y: 0, width: width, height: 10000), transform: nil)
    let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), path, nil)
    let lines = (CTFrameGetLines(frame) as? [CTLine]) ?? []

    var currentY = cursorY
    for line in lines {
        var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
        CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
        let lineHeight = ascent + descent + ScriptExportLayoutConfig.KoreanLayout.lineSpacing

        if currentY + lineHeight > pageHeight - ScriptExportLayoutConfig.KoreanLayout.marginBottom {
            context.endPDFPage()
            context.beginPDFPage(nil)
            setupGraphicsContext(context)
            currentY = ScriptExportLayoutConfig.KoreanLayout.marginTop
            pageNumber += 1
            drawPageNumber(pageNumber, in: context)
        }
        let yPos = pageHeight - currentY - ascent
        context.textPosition = CGPoint(x: xPos, y: yPos)
        CTLineDraw(line, context)
        currentY += lineHeight
    }
    cursorY = currentY
    return nil
}

private func processElement(at index: Int, elements: [ScriptExportElement], sceneNumber: Int?) -> (NSAttributedString, CGFloat, Int, ScriptExportElementType) {
    let element = elements[index]
    if element.type == .character { return createKoreanDialogueBlock(startIndex: index, elements: elements) }

    if element.type == .sceneHeading {
        let text = element.text.uppercased()
        let sceneText = sceneNumber.map { "\($0). \(text)" } ?? text

        var font = NSFont(name: fontName, size: config.koreanFontSize) ?? NSFont.monospacedSystemFont(ofSize: config.koreanFontSize, weight: .regular)
        if config.koreanIsSceneBold {
            font = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
        }

        let style = createParagraphStyle(alignment: .left)
        let attrStr = NSAttributedString(string: sceneText, attributes: [.font: font, .paragraphStyle: style, .foregroundColor: NSColor.black])
        return (attrStr, contentWidth(for: .sceneHeading), 1, .sceneHeading)
    }

    let attrStr = createAttributedString(for: element)
    return (attrStr, contentWidth(for: element.type), 1, element.type)
}
```

#### Settings URL

파일: [SettingsView.swift](/Users/three/app_build/wa/wa/SettingsView.swift#L274)

```swift
private var oflLicenseURL: URL {
    URL(string: "https://openfontlicense.org/open-font-license-official-text/")
        ?? URL(fileURLWithPath: "/")
}
```

## 3. 데이터 무결성 점검

### 3-1. 실제 차단한 위험

#### A. 오래된 비동기 워크스페이스 로드가 새 상태를 덮어쓰는 문제

기존 `setupStore()`는 다음 순서를 가졌다.

1. 북마크 A로 `Task` 시작
2. 사용자가 빠르게 북마크 B 선택
3. 북마크 B의 `Task`도 시작
4. 느리게 끝난 A가 마지막에 `self.store = newStore` 실행 가능

이 경우 UI는 B를 선택했는데 내부 store는 A로 되돌아가는 상태 불일치가 가능했다.

이번 단계에서 generation guard를 넣어, 가장 마지막 요청만 store를 반영하게 했다.

이 변경은 다음 종류의 데이터 손상/상태 혼선을 막는다.

- 잘못된 워크스페이스가 열리는 문제
- 저장 대상 폴더가 사용자 기대와 다른 문제
- AI thread / history / reference window가 다른 workspace 기준으로 로드되는 문제

#### B. undo snapshot 생성 시 optional override 미존재로 인한 비정상 종료

`captureScenarioState`의 `overrideContent!`는 호출부 변경에 취약했다. 지금은 override가 없으면 원문으로 자연스럽게 fallback 하므로, snapshot 생성 중 비정상 종료를 피한다.

#### C. import/export 파서의 nil 조건 변화로 인한 크래시

title page parsing, PDF export, linked-card resolution은 모두 “현재 로직상 nil이 아닐 것”이라는 가정이 있었는데, 이런 가정은 기능 확장 시 가장 먼저 깨진다. 강제 언래핑 제거로 파서/출력 경로 안정성을 높였다.

### 3-2. 기존 구조에서 이미 양호한 부분

이번 점검에서 다음은 비교적 잘 되어 있었다.

- `FileStore.saveQueue`가 serial queue로 저장 순서를 보장
- `pendingPayload` 방식으로 최신 payload만 저장 대상으로 유지
- `Scenario`와 `SceneCard`는 `@MainActor` 기반이라 UI 경합이 제한됨
- `SceneCard.scenario`가 `weak`라서 강한 순환 참조 위험이 낮음

즉, 저장 계층 자체는 이미 어느 정도 무결성 방어가 되어 있었고, 이번 단계는 “앱 셸에서의 비동기 state race”를 추가로 막은 것이다.

### 3-3. 아직 남아 있는 구조적 위험

이번 단계에서 일부러 건드리지 않은 고위험 지점도 있다.

1. `ScenarioWriterView` 상태 집중
   상태가 너무 많아, 잘못된 순서의 상태 전이가 생기면 특정 모드에서 일시적인 불일치가 생길 수 있다.

2. direct `SceneCard.content` mutation
   편집 이벤트가 곧바로 모델에 반영되기 때문에, 장기적으로는 command/use-case 계층이 필요하다.

3. 포커스 모드의 eager `TextEditor` 생성
   이건 성능 문제이면서 동시에 responder/selection 경합의 구조적 원인이다.

이 세 가지는 아키텍처 리팩토링 단계에서 별도 해결해야 한다.

## 4. 적용 효과

이번 변경의 기대 효과는 다음과 같다.

- 메인/포커스/레퍼런스 편집기에서 동일 텍스트 재측정 비용 감소
- 긴 카드/반복 진입 시 `NSLayoutManager` churn 감소
- 메모리 압박 시 캐시 자동 purge 가능
- 워크스페이스 전환/재선택 시 stale async overwrite 차단
- import/export/undo 경로의 잠재 크래시 감소

체감상 가장 직접적인 이득은 다음 두 군데다.

- 카드 편집 중 높이 재계산 반복
- 레퍼런스 창과 포커스 모드 진입 시 텍스트 레이아웃 계산 반복

## 5. 검증

실제 코드 변경 후 아래 빌드를 통과했다.

```bash
xcodebuild -project wa.xcodeproj -scheme wa -configuration Debug build
```

결과:

- `BUILD SUCCEEDED`

수동 런타임 검증은 아직 별도 수행하지 않았다. 따라서 다음 항목은 앱 실행 상태에서 추가 확인하는 것이 좋다.

- 메인 카드 편집 시 높이 증가/감소 동작
- 포커스 모드 진입/편집/종료
- 레퍼런스 창 편집 시 캐럿 가시성
- 워크스페이스를 빠르게 연속 변경할 때 마지막 선택만 반영되는지
- Fountain 붙여넣기/undo/PDF export 정상 여부

## 결론

이번 단계는 “대규모 구조 개편”이 아니라 “실제 병목과 크래시 면적을 줄이는 안전한 리팩토링”에 집중했다.

핵심 성과는 다음이다.

1. 텍스트 레이아웃 측정의 중복 제거와 공통 캐시 도입
2. 비동기 워크스페이스 로드 race 차단
3. 강제 언래핑 제거로 편집/파서/출력 경로 안정화

즉, UX나 동작을 바꾸지 않으면서도 성능과 무결성 측면에서 다음 단계 리팩토링의 기반을 마련한 상태다.
