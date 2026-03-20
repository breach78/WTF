# 01 Architecture Diagnosis

## Scope

- Repository: `/Users/three/app_build/wa`
- App type: macOS SwiftUI + AppKit hybrid writing workspace
- User-behavior constraint: no visible behavior changes, no persistence breakage, no feature removal
- Analysis basis: current source tree as of PHASE 1

## Executive Assessment

Current architecture quality: **mixed**

What is working:
- The app already has a coherent persistence model centered on `.wtf` workspaces
- Large editing flows are functionally organized by feature extensions
- Several targeted performance protections already exist: render-state structs, `Equatable` hosts, layout caches, debounced saves, async loading
- Memory-cycle safety is partially respected: `SceneCard.scenario` is weak, several work items use `[weak self]`, async persistence is pushed off the main thread

What is not working well:
- The app is not clean MVVM; it is a view-heavy, feature-root architecture with one dominant stateful screen
- `ScenarioWriterView` is the de facto application coordinator for editing, focus mode, history, AI, export, dictation, split-pane behavior, persistence triggers, and AppKit event lifecycles
- `FileStore` is both persistence layer and domain/application service
- State is spread across local `@State`, `@StateObject`, `@AppStorage`, mutable domain models, and imperative runtime caches
- Several “shared” or coordinator types depend back on `ScenarioWriterView` nested types, creating boundary inversion

Overall diagnosis:
- The codebase is **incrementally refactorable**, but its long-term scalability is limited by concentration of responsibility, mixed state ownership, and weak layer boundaries.

---

## SYSTEM ARCHITECTURE

### Detected Architecture Pattern

Detected pattern:
- **Central Store + Direct Observable Domain Models + Feature-Root View Orchestration**

Closest formal label:
- **MVVM-adjacent**, but not a clean MVVM + Service Layer implementation

Why it is not clean MVVM:
- There are no dedicated screen-level `ViewModel` files
- Views directly mutate models and call services
- Multiple services and coordinators are embedded inside UI-oriented files
- The main editor feature is organized through `extension ScenarioWriterView` instead of modular state/view-model boundaries

### Layer Responsibilities

#### 1. App Shell

Files:
- `wa/waApp.swift`
- `wa/MainContainerView.swift`

Responsibilities currently handled:
- app entry
- workspace bootstrap
- security-scoped bookmark restore
- main window scene and reference window scene creation
- global command routing through `NotificationCenter`
- appearance application
- auto-backup on terminate
- split-pane activation routing
- scenario selection and sidebar behavior

Assessment:
- This layer is carrying both shell concerns and feature coordination concerns.

#### 2. Domain Model Layer

Files:
- `wa/Models.swift`

Core types:
- `Scenario`
- `SceneCard`
- `HistorySnapshot`

Responsibilities currently handled:
- editable domain state
- dirty tracking
- timestamp suppression and debouncing
- clone synchronization
- cached tree/index reconstruction
- linked-card tracking
- shared craft tree synchronization hooks

Assessment:
- Domain objects are not purely domain-focused; they already contain persistence-oriented and UI-sensitive behavior.

#### 3. Persistence / Repository Layer

Primary type:
- `FileStore`

Responsibilities currently handled:
- workspace load/save
- schema migration shaping
- scenario ordering
- template cloning
- scenario deletion
- shared craft synchronization
- AI thread/embedding persistence
- save caching and debounce orchestration

Assessment:
- `FileStore` is effectively repository + application service + domain coordinator.
- This is the largest single architectural bottleneck after `ScenarioWriterView`.

#### 4. Main Editor Feature Layer

Files:
- `wa/WriterViews.swift`
- `wa/WriterCardManagement.swift`
- `wa/WriterKeyboardHandlers.swift`
- `wa/WriterCaretAndScroll.swift`
- `wa/WriterFocusMode.swift`
- `wa/WriterHistoryView.swift`
- `wa/WriterUndoRedo.swift`
- `wa/WriterAI+ChatView.swift`
- `wa/WriterAI+PromptBuilder.swift`
- `wa/WriterAI+RAG.swift`
- `wa/WriterAI+ThreadStore.swift`
- `wa/WriterAI+CandidateActions.swift`
- `wa/WriterSpeech.swift`

Total span under the `ScenarioWriterView` feature root:
- **20,896 lines**

Responsibilities currently handled:
- canvas layout
- card interaction
- focus mode
- history preview and restore
- undo/redo and typing coalescing
- selection and caret persistence
- split-pane activation
- AI prompt orchestration and candidate application
- dictation lifecycle
- edit-end auto-backup
- export UI flows
- AppKit monitor lifecycle

Assessment:
- This layer is too broad to serve as a stable long-term feature boundary.

#### 5. Supporting Coordinator / State Objects

Files:
- `wa/WriterSharedTypes.swift`
- `wa/MainCanvasScrollCoordinator.swift`
- `wa/FocusModeLayoutCoordinator.swift`
- `wa/ReferenceWindow.swift`

Types:
- `WriterInteractionRuntime`
- `MainCanvasViewState`
- `WriterAIFeatureState`
- `WriterEditEndAutoBackupState`
- `ScenarioWriterObservedState`
- `MainCanvasScrollCoordinator`
- `FocusModeLayoutCoordinator`
- `ReferenceCardStore`

Assessment:
- These objects are valuable and should be preserved.
- The issue is not their existence.
- The issue is that many of them still depend on, or are flattened back into, the root view instead of forming a clean intermediate layer.

### Data Flow

### Main Editing Flow

1. User input occurs in `ScenarioWriterView` or one of its child card views.
2. The view mutates:
   - local `@State`
   - `SceneCard`
   - `Scenario`
   - coordinator/state-object properties
3. `Scenario` / `SceneCard` bump dirty versions and timestamps.
4. `ScenarioWriterObservedState` observes selected scenario change streams and republishes simplified version counters.
5. `ScenarioWriterView` reacts through `onChange`, recomputes render-state fingerprints, and triggers subview updates.
6. `FileStore.saveAll()` or specialized AI persistence methods write to the `.wtf` workspace.

### AI Flow

1. User action starts inside `ScenarioWriterView` extension code.
2. The view loads API credentials through `KeychainStore`.
3. Prompt and scope are built in `WriterAI` helper code.
4. Network requests go directly to `GeminiService`.
5. Results are pushed back into `WriterAIFeatureState`, models, and `FileStore` AI persistence.

### Reference Window Flow

1. `ReferenceWindowView` resolves pinned entries using `ReferenceCardStore` + `FileStore`.
2. The reference row observes the same `SceneCard` objects used by the main editor.
3. Content edits go through `ReferenceCardStore.handleContentChange(...)`.
4. `ReferenceCardStore` requests `FileStore.saveAll()` directly.

Assessment of data flow:
- Functional, but the flow is mostly **View -> Model/Store/Service**, not **View -> ViewModel -> Service -> Model**.

---

## STATE MANAGEMENT

### Current Wrapper Usage

Project-wide distribution:

| Wrapper | Count |
| --- | ---: |
| `@State` | 185 |
| `@StateObject` | 7 |
| `@ObservedObject` | 8 |
| `@EnvironmentObject` | 5 |
| `@Environment` | 3 |
| `@FocusState` | 10 |
| `@AppStorage` | 99 |

`ScenarioWriterView` alone:

| Wrapper | Count |
| --- | ---: |
| `@State` | 140 |
| `@StateObject` | 6 |
| `@ObservedObject` | 2 |
| `@EnvironmentObject` | 2 |
| `@Environment` | 1 |
| `@FocusState` | 7 |
| `@AppStorage` | 36 |

### `@State`

Current usage:
- heavily concentrated in `ScenarioWriterView`
- also used in `MainContainerView`, `SettingsView`, `ReferenceWindow`, and `CardItem`

What is appropriate:
- local presentation flags
- ephemeral dialog state
- hover state
- temporary sheet/input state

What is problematic:
- `ScenarioWriterView` stores major editor session state, undo stacks, monitor references, viewport persistence caches, dictation workflow state, split-pane sync state, history editing state, and focus-mode transition state all in one struct
- this volume of state makes the root view function as a full state container rather than a view

Diagnosis:
- `@State` is being used as a catch-all storage mechanism.
- The main issue is not “too much state exists,” but “too much state is owned by the root view instead of feature-scoped controllers.”

### `@StateObject`

Current usage:
- `ReferenceCardStore`
- `MainCanvasViewState`
- `MainCanvasScrollCoordinator`
- `FocusModeLayoutCoordinator`
- `WriterAIFeatureState`
- `WriterEditEndAutoBackupState`
- `ScenarioWriterObservedState`

Positive assessment:
- This is the strongest part of the current architecture.
- These types are the natural seeds of a cleaner MVVM/service-layer design.

Current limitation:
- `ScenarioWriterView` immediately re-exposes large parts of these objects through dozens of computed proxy properties.
- That weakens encapsulation and keeps the root view as the effective orchestrator.

Diagnosis:
- Ownership is mostly correct, but encapsulation is weak.

### `@ObservedObject`

Current usage:
- `ScenarioRow` observes `Scenario`
- card/editor views observe `SceneCard`
- host views observe coordinators in `WriterViews`
- `ReferenceCardEditorRow` observes `SceneCard`

Benefits:
- direct mutation feedback is simple
- avoids manual binding plumbing

Risks:
- the UI is directly coupled to mutable domain models
- changes to a `SceneCard` propagate into every surface observing that card
- domain changes and rendering invalidation are tightly linked

Diagnosis:
- This is acceptable for small scopes, but at this scale it increases invalidation breadth and makes boundary cleanup harder.

### `@Environment`

Current usage:
- mostly `openWindow`

Assessment:
- usage is limited and reasonable
- no major issue here

### `@EnvironmentObject`

Current usage:
- `FileStore`
- `ReferenceCardStore`

Assessment:
- there is no numerical abuse
- there is semantic overreach

Why:
- `FileStore` is a very broad object with persistence, mutation, AI persistence, and cross-scenario sync responsibilities
- injecting it widely means many views can bypass any service boundary and mutate persistence state directly

Diagnosis:
- not an `EnvironmentObject` count problem
- it is an **object breadth / authority problem**

### State Duplication

Detected duplication patterns:

1. **Preference duplication through repeated `@AppStorage` bindings**
- the same user preference keys are repeated across `waApp`, `SettingsView`, `WriterViews`, `WriterCardViews`, and `ReferenceWindow`
- examples: `fontSize`, `appearance`, `mainCardLineSpacingValueV2`, `cardActiveColorHex`

2. **Live focus state duplicated into persisted focus state**
- `activeCardID`, `editingCardID`, caret positions, viewport offsets, and focus-mode flags are mirrored into `lastFocused*` and `lastEdited*` `@AppStorage` keys

3. **Interaction state split between root `@State` and imperative runtime caches**
- `ScenarioWriterView` stores major state directly while also proxying many values into `WriterInteractionRuntime`, `MainCanvasViewState`, and other coordinators

4. **Undo/coalescing state machine duplication**
- main editor typing undo
- focus-mode typing undo
- reference window typing undo
- these flows are conceptually similar but implemented in separate places

### State Leakage

Detected leakage:

1. **Transient session UI state in `@AppStorage`**
- `focusModeWindowBackgroundActive` is persisted even though it is a live window-session concern, not a user preference

2. **Cross-view command signaling via persisted flags**
- `forceWorkspaceReset` is used as a cross-screen trigger between Settings and the App shell

3. **Reference entries are globally persisted rather than workspace-scoped**
- `ReferenceCardStore` persists entry IDs in `UserDefaults`
- it prunes invalid cards later, but the ownership is still global rather than clearly attached to a workspace session

### Incorrect Ownership

Incorrect or weak ownership boundaries:

- `ScenarioWriterView` owns backup scheduling, focus persistence, AI persistence triggers, monitor lifecycle, and many editor policies
- `SettingsView` directly owns keychain operations and workspace replacement commands
- `MainContainerView` directly mirrors scenario title changes into the root card content
- `Scenario` owns both domain state and persistence-dirty/version logic

Important counterpoint:
- some ownership is already correct:
  - `ReferenceCardStore` as app-owned `@StateObject`
  - `ScenarioWriterObservedState` as scenario-scoped `@StateObject`
  - weak `SceneCard -> Scenario` back-reference for memory safety

---

## VIEW COMPLEXITY

### Massive Views

Primary complexity hotspots:

| File | Lines |
| --- | ---: |
| `wa/WriterCardManagement.swift` | 5,572 |
| `wa/WriterFocusMode.swift` | 3,494 |
| `wa/WriterViews.swift` | 3,269 |
| `wa/SettingsView.swift` | 1,500 |
| `wa/WriterCardViews.swift` | 1,416 |
| `wa/WriterHistoryView.swift` | 1,848 |
| `wa/WriterKeyboardHandlers.swift` | 1,839 |

Feature concentration:
- the main editor feature spans 13 files and **20,896 lines** centered on one root view type

Diagnosis:
- The architecture does not have one massive file.
- It has one **massive screen type** split across many files.

### Business Logic Inside Views

Examples of business/application logic currently living in views:

- `ScenarioWriterView.handleWorkspaceAppear()`
- `ScenarioWriterView.handleShowFocusModeChange(_:)`
- `ScenarioWriterView.scheduleEditEndAutoBackup()`
- `ScenarioWriterView.startEditEndAutoBackupNow()`
- AI request initiation in `WriterAI+CandidateActions.swift`
- export/save panel handling in `WriterCardManagement.swift`
- workspace opening/creation in `SettingsView`
- scenario rename propagation in `MainContainerView`

Diagnosis:
- Many views are not just composing UI.
- They are coordinating workflows, external services, persistence timing, and cross-feature policies.

### Duplicated View Structures / Interaction State Machines

Duplicated patterns observed:

- text editing measurement logic across main cards, focus-mode editor, and reference rows
- typing-coalescing undo logic across main editor, focus mode, and reference window
- repeated preference access patterns in multiple view files
- repeated AppKit monitor lifecycle handling in main workspace, focus mode, history, drag tracking, and split-pane mode

Diagnosis:
- The duplication is mostly behavioral duplication, not just layout duplication.
- This is a maintainability problem because bug fixes will need to be replicated across parallel flows.

### Poor Component Boundaries

Notable boundary issues:

1. `CardItem` has too many responsibilities
- selection
- editing
- drag/drop
- inline insertion
- AI actions
- clone/link actions
- dictation entry
- delete flows
- style resolution

2. `SettingsView` is effectively multiple screens inside one 1,500-line view

3. `ScenarioWriterView` hides feature decomposition behind extension files rather than real component boundaries

4. “Shared” coordinator types depend back on view-layer nested types
- `WriterInteractionRuntime` stores `ScenarioWriterView.LevelData`
- `WriterInteractionRuntime` stores `ScenarioWriterView.MainColumnFocusRequest`
- `WriterInteractionRuntime` stores `ScenarioWriterView.MainColumnLayoutCacheKey`
- `WriterAIFeatureState` stores `ScenarioWriterView.AICandidateTrackingState`

Diagnosis:
- This is the clearest sign that the architecture boundary currently runs through source files, not through stable module contracts.

---

## DEPENDENCY STRUCTURE

### Intended Dependency Shape

Preferred shape:
- `View -> ViewModel -> Service -> Model`

### Actual Dependency Shape

Frequently observed in current code:
- `View -> Model`
- `View -> Store`
- `View -> Service`
- `View -> Coordinator -> Model`

Examples:

- `ScenarioRow -> Scenario`
- `CardItem -> SceneCard`
- `ScenarioWriterView -> FileStore`
- `ScenarioWriterView -> GeminiService`
- `ScenarioWriterView -> KeychainStore`
- `ScenarioWriterView -> WorkspaceAutoBackupService`
- `SettingsView -> KeychainStore`
- `SettingsView -> WorkspaceBookmarkService`
- `ReferenceWindowView -> FileStore + ReferenceCardStore + SceneCard`

### Strong Coupling

Strong coupling detected in these areas:

1. **Writer feature coupling**
- 12 extension files rely on state declared in `WriterViews.swift`
- any large refactor of root state layout will impact all writer feature files

2. **Store coupling**
- `FileStore` is depended on by app shell, main workspace, settings-adjacent flows, and reference window

3. **Domain/UI coupling**
- `Scenario` and `SceneCard` are observed and mutated directly by views

4. **Shared layer coupling**
- `WriterSharedTypes.swift` depends on `ScenarioWriterView` nested types, which reverses the expected direction

### Circular Dependencies

No hard multi-module circular dependency exists because the app is one target, but there are **conceptual layer cycles**:

1. **View <-> Shared/Coordinator cycle**
- `WriterViews.swift` depends on `WriterSharedTypes.swift`
- `WriterSharedTypes.swift` stores multiple `ScenarioWriterView.*` nested types

2. **View <-> AI state cycle**
- `WriterViews.swift` owns `WriterAIFeatureState`
- `WriterAIFeatureState` stores `ScenarioWriterView.AICandidateTrackingState`

3. **Domain graph cycle**
- `Scenario` owns `SceneCard` collections
- `SceneCard` points back to `Scenario`
- this is memory-safe because the back-reference is weak, but it still raises graph complexity

### Missing Abstraction Layers

Missing or weak abstractions:

- no `WriterSessionViewModel`
- no `WorkspaceController` / `WorkspaceSessionController`
- no `PreferencesStore`
- no `HistoryController`
- no unified `UndoCoordinator`
- no isolated `AIAssistantService` layer between view and Gemini APIs
- no boundary between persistence schema concerns and domain mutation concerns

---

## SWIFTUI PERFORMANCE RISKS

### 1. Root View Invalidation Pressure

Risk:
- `ScenarioWriterView` owns 140 `@State` values and many lifecycle modifiers
- any of these changes can re-enter the root render path

Mitigating work already present:
- `MainCanvasHost`, `TrailingWorkspacePanelHost`, `HistoryOverlayHost`, `WorkspaceToolbarHost`, and `BottomHistoryBarHost` use `Equatable` render-state wrappers

Remaining problem:
- the root still computes the render-state inputs and lifecycle logic
- invalidation pressure is reduced, not eliminated

### 2. Heavy Render-State Fingerprinting

Risk:
- `mainCanvasContentFingerprint()`
- `trailingWorkspacePanelContentFingerprint()`
- `historyOverlayContentFingerprint()`
- `workspaceToolbarContentFingerprint()`

These repeatedly hash:
- selected IDs
- AI thread structures
- preview diffs
- inactive pane snapshots
- per-thread message counts and metadata

Assessment:
- This is a deliberate optimization strategy, but it shifts work from subtree rendering to repeated fingerprint computation.
- It is defensible now, but it becomes more expensive as thread counts, card counts, and feature surface grow.

### 3. Direct `SceneCard` Observation In Repeated Views

Risk:
- `CardItem`, `FocusModeCardEditor`, and `ReferenceCardEditorRow` directly observe `SceneCard`
- content changes will invalidate every surface observing that card

Assessment:
- Appropriate for local responsiveness
- risky for scaling because the domain object is broad and mutable

### 4. Non-Lazy Main Canvas Column Composition

Risk:
- the main horizontal editor canvas is built with `HStack`, not `LazyHStack`
- all visible column shells are materialized through the editor’s own layout pipeline

Assessment:
- this may be acceptable for the current interaction model
- it remains a scalability risk for large card trees and multi-pane editing

### 5. Global Preference Fan-Out Through `@AppStorage`

Risk:
- preference changes such as appearance, font size, spacing, and colors are bound in many view files
- a single preference update fans out across multiple layers

Assessment:
- acceptable for simple settings
- expensive when the same keys are read by editor rows, reference rows, app shell, and settings simultaneously

### 6. AppKit Event Monitor Density

Risk:
- many local/global monitors and delayed work items are managed across main editor, focus mode, split panes, drag tracking, and history

Assessment:
- this is more of a maintainability and correctness risk than pure render cost
- however, it can still create inconsistent timing behavior and hidden invalidation paths

---

## TECHNICAL DEBT

### Architecture Violations

- Views directly call persistence and external services
- Shared/coordinator layer depends on view-layer nested types
- Domain models include persistence-dirty and editor-sensitive behavior
- `FileStore` owns too many policies outside pure persistence

### Maintainability Risks

- root editor behavior is spread across 13 files but still depends on one giant shared state surface
- similar workflows are reimplemented in multiple feature areas
- preference state is repeated widely
- app shell, workspace shell, and editor session logic are not clearly separated

### Scalability Risks

- adding a new editor feature likely means touching `ScenarioWriterView` state, lifecycle, command handling, and multiple extension files
- large scenario sizes will increase content-fingerprint cost and broad invalidation probability
- split-pane mode multiplies editor-session complexity without introducing separate session controllers
- AI, history, focus mode, and dictation are all attached to the same feature root

### Release-Readiness Risks With Architecture Impact

- no test target to protect refactors
- cross-feature behavior relies on `NotificationCenter`, delayed work items, and shared mutable state
- persistence and UI timing are tightly interleaved, increasing regression risk during future optimization work

---

## ARCHITECTURE REFACTOR PLAN

Principle:
- **Incremental extraction, not rewrite**
- preserve visible behavior
- preserve file schema and persistence paths
- preserve current feature set

### Refactor Direction

Phase 2 should move toward:
- `View -> Feature State/ViewModel -> Service -> Model`

but incrementally, using the existing state/coordinator objects as anchors.

### View Responsibilities

Rules:

1. Views should render and forward intents.
2. Views may keep ephemeral presentation state only.
3. Views should not directly own:
- persistence flush policy
- auto-backup scheduling
- keychain workflows
- AI request orchestration
- cross-window command routing

4. Reusable views such as `CardItem` should accept compact state/config objects instead of dozens of callbacks and flags over time.

### ViewModel / Feature-State Responsibilities

Rules:

1. Introduce screen-scoped feature state objects instead of growing root `@State`.
2. Start by extracting from `ScenarioWriterView` into bounded controllers:
- workspace session state
- history session state
- focus mode session state
- AI chat/candidate session state
- dictation session state

3. Keep `ScenarioWriterObservedState`, `MainCanvasViewState`, `MainCanvasScrollCoordinator`, and `FocusModeLayoutCoordinator` as seeds for this extraction.
4. Stop exposing large coordinator internals back through root-view computed proxies wherever possible.

### Service Layer Usage

Rules:

1. `FileStore` should gradually narrow toward persistence/repository concerns.
2. Non-persistence workflows should move out of `FileStore` over time:
- shared craft synchronization policy
- template/scenario creation policy
- scenario ordering policy
- AI artifact save orchestration

3. External integrations should stay behind dedicated services:
- `GeminiService`
- `KeychainStore`
- speech/dictation services
- workspace bookmark / backup services

4. Views should call feature controllers, not external services directly.

### State Ownership Rules

Rules:

1. Persisted user preferences belong in a dedicated preferences abstraction, not duplicated `@AppStorage` across many feature views.
2. Session-only UI state must not live in `@AppStorage`.
3. Domain state belongs in models.
4. Rendering caches and transient AppKit coordination state belong in coordinators/runtime objects.
5. Root views should own as little business-session state as possible.

Immediate ownership targets:
- move `focusModeWindowBackgroundActive` out of persisted state
- reduce duplicated preference bindings over time
- isolate startup focus/viewport restore state away from the root feature view

### Module Boundary Rules

Recommended module/folder direction inside the same target:

1. `App/`
- app shell
- workspace bootstrap
- global command routing

2. `Domain/`
- `Scenario`
- `SceneCard`
- history value types

3. `Persistence/`
- `FileStore`
- serializers / schema records

4. `Features/Writer/`
- root writer screen
- writer session state
- canvas/focus/history/AI/dictation subfeatures

5. `Features/Reference/`
- reference window
- reference window state

6. `Features/Settings/`
- settings UI
- settings-specific state

7. `Services/`
- Gemini
- Keychain
- speech
- bookmark/backup
- export

8. `SharedUI/`
- card views
- AppKit wrappers
- layout metrics

### Recommended Incremental Extraction Order

1. Extract session-only editor state out of `ScenarioWriterView`.
2. Introduce a dedicated preferences abstraction to reduce repeated `@AppStorage`.
3. Detach shared/coordinator types from `ScenarioWriterView` nested types.
4. Split `FileStore` policy responsibilities from pure persistence.
5. Move direct service calls behind feature controllers/use-case helpers.

---

## Recommended PHASE 2 Focus

The highest-value, lowest-risk architecture refactor targets are:

1. Reduce root-view state concentration without changing UI behavior.
2. Improve ownership of transient vs persisted state.
3. Untangle `WriterSharedTypes` from `ScenarioWriterView` nested-type dependencies.
4. Preserve the current render-state optimization pattern while reducing recomputation pressure.
5. Keep `FileStore` persistence semantics intact while reducing its policy surface.

## Bottom Line

This project already contains serious engineering work and several thoughtful performance optimizations.

The main architectural problem is not lack of effort.
It is that too much of the system’s intelligence is concentrated in:
- `ScenarioWriterView`
- `FileStore`
- repeated direct view-to-service/model pathways

The correct refactor strategy is therefore:
- **preserve the current behavior**
- **retain the existing optimized substructures**
- **extract responsibilities around the current seams instead of rewriting the system**

