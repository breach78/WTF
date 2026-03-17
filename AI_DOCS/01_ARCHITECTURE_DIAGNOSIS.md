# 01 Architecture Diagnosis

Date: 2026-03-18

Phase scope:
- Repository analysis only
- No production code changes in this phase
- Goal: diagnose the current architecture and define an incremental refactor path that preserves behavior, persistence, and UI

Project type fit:
- This is a complex text-editing / screenplay-oriented macOS app with structured hierarchical data, history snapshots, AI assistance, export pipelines, and workspace persistence
- The diagnosis below is written from that perspective, not from a generic CRUD-app perspective

## Executive Assessment

Architecture quality:
- Functional and feature-rich
- Moderately optimized in specific hotspots
- Structurally fragile for long-term growth

What is already good:
- There is a real persistence core in `FileStore`
- `Scenario` maintains useful derived caches and version markers
- `ScenarioWriterObservedState` projects domain changes into narrower render signals
- `MainCanvasHost`, `TrailingWorkspacePanelHost`, `HistoryOverlayHost`, `WorkspaceToolbarHost`, and `BottomHistoryBarHost` use `Equatable` render-state gating
- The code already separates some heavy domains into files: AI, export, speech, reference window, history

What is fundamentally weak:
- The app is not actually MVVM; it is a view-heavy central-session architecture
- `ScenarioWriterView` is a single feature root with very large state ownership and many cross-cutting responsibilities
- Split mode duplicates that entire editor root for the same `Scenario`
- Views still mutate models directly, trigger persistence directly, and manage AppKit event plumbing directly
- Screenplay semantics exist mostly at import/export time, not as a first-class editing model

Overall diagnosis:
- The current architecture is strong enough to ship features and preserve data
- It is not strong enough for low-risk long-term scaling without incremental extraction of feature controllers and service boundaries

## SYSTEM ARCHITECTURE

### Detected architecture pattern

Detected pattern:
- Hybrid SwiftUI architecture with observable domain models and a central store
- Best description: MVVM-adjacent, but not true MVVM

Actual runtime shape:
- `waApp.swift` bootstraps the workspace, owns app-wide dependencies, and routes commands
- `MainContainerView.swift` owns scenario selection and split-pane shell behavior
- `ScenarioWriterView` is the dominant feature root for the editor
- `Scenario` and `SceneCard` are mutable `ObservableObject` domain models used directly by views
- `FileStore` is a combined repository, persistence coordinator, and application service
- Additional capabilities such as AI, dictation, export, and history are attached through `extension ScenarioWriterView` files rather than through isolated feature view models

### Layer responsibilities

| Layer | Primary files | Current responsibility | Diagnosis |
| --- | --- | --- | --- |
| App shell | `waApp.swift` | App lifecycle, window setup, workspace bootstrapping, commands, appearance, backup on terminate | Too many app-level concerns are mixed in one file |
| Workspace shell | `MainContainerView.swift` | Scenario list, selection, split mode, workspace switching, sidebar behavior | Reasonable shell role, but still owns notification routing and split-pane focus orchestration |
| Domain model | `Models.swift` | `Scenario`, `SceneCard`, history snapshots, caches, persistence schema | Strong core, but models are mutable and directly edited by views |
| Main editor feature | `WriterViews.swift` + 11 extension files | Editing, selection, keyboard, caret, focus mode, history, AI, dictation, export, backup triggers | Over-centralized; this is the primary architectural bottleneck |
| Secondary editor | `ReferenceWindow.swift` | Pinned-card editing, local undo/redo, persistence of reference entries | Re-implements editor behaviors that already exist elsewhere |
| Services | `GeminiService.swift`, `KeychainStore.swift`, `ScriptPDFExport.swift`, `WriterSpeech.swift`, `waApp.swift` helpers | Network, keychain, export, speech, backup, bookmark flows | Useful separation exists, but views still call services directly |
| External schema client | `mcp/` | Reads and writes `.wtf` workspace data outside the app target | Makes schema evolution more sensitive because there are two writers of the same storage format |

### Data flow

Current data flow is mostly:

1. UI event occurs in a SwiftUI view or AppKit-backed editor.
2. View code mutates `SceneCard` or `Scenario` directly.
3. Model `didSet` handlers mark dirty state, version counters, timestamps, and clone propagation.
4. `ScenarioWriterObservedState` or direct `@ObservedObject` invalidates SwiftUI rendering.
5. View code decides when to snapshot, autosave, request backup, or issue AI/export/dictation work.
6. `FileStore` persists to the `.wtf` workspace package.

This is not a clean `View -> ViewModel -> Service -> Model` pipeline.

It is closer to:

`View -> Model/Store/Service/AppKit bridge -> persistence`

### Strengths in the current architecture

- `FileStore` already implements debounced saves, dirty-cache skipping, concurrent I/O, schema versioning, and separate per-scenario artifacts.
- `SceneCard.scenario` is `weak`, which avoids a direct retain cycle with `Scenario`.
- The app already introduced render gating through version projection and `Equatable` host views, which means the team has already started to address invalidation costs.
- AppKit integration is justified for this category of app; rich keyboard, caret, and selection behavior on macOS often requires it.

### Core structural gaps

- No dedicated writer session layer exists between views and the domain model.
- No dedicated per-feature view models exist for history, AI chat, dictation, split-pane coordination, or reference editing.
- No shared editor engine exists across main mode, focus mode, and reference mode.
- Screenplay semantics are not first-class editing models; they are inferred from raw card text during import/export and AI prompt construction.

## STATE MANAGEMENT

### Current usage summary

Wrapper counts in the heaviest view files:

| File | `@State` | `@StateObject` | `@ObservedObject` | `@EnvironmentObject` | `@AppStorage` | `@FocusState` | `.onChange` | `.onReceive` |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `wa/WriterViews.swift` | 157 | 2 | 1 | 2 | 33 | 7 | 20 | 4 |
| `wa/MainContainerView.swift` | 13 | 0 | 0 | 1 | 3 | 1 | 4 | 11 |
| `wa/SettingsView.swift` | 15 | 0 | 0 | 0 | 27 | 0 | 2 | 0 |
| `wa/ReferenceWindow.swift` | 3 | 0 | 1 | 2 | 5 | 2 | 5 | 1 |
| `wa/WriterCardViews.swift` | 12 | 0 | 2 | 0 | 13 | 2 | 8 | 0 |
| `wa/waApp.swift` | 3 | 1 | 0 | 0 | 13 | 0 | 3 | 1 |

Interpretation:
- The app does not have too many environment objects.
- It has too much local state in the main writer root.
- It also has too much duplicated settings state through repeated `@AppStorage` access.

### `@State`

Current use:
- `@State` in `ScenarioWriterView` is carrying ephemeral UI, long-lived session state, undo stacks, focus plumbing, async tasks, monitor handles, backup scheduling, AI state, dictation state, clipboard state, and cached derived layout state.

Diagnosis:
- This is the single largest ownership problem in the project.
- `@State` is appropriate for small, view-local presentation state.
- It is not the right long-term owner for editor engines, feature controllers, background work scheduling, or multi-subsystem coordination.

Examples of state that should not permanently live in the root view:
- AI persistence work items and request tasks
- Undo/redo stacks for multiple editing modes
- Dictation recorder lifecycle
- Focus monitor handles and text-view responder maps
- Auto-backup scheduling state
- Split-pane inactive snapshot state

### `@StateObject`

Current use:
- `MainCanvasViewState`
- `ScenarioWriterObservedState`
- `ReferenceCardStore` at the app root

Diagnosis:
- These are some of the better ownership decisions in the codebase.
- `ScenarioWriterObservedState` is especially useful because it narrows rendering to version signals instead of observing the whole `Scenario`.

Gap:
- The project uses `@StateObject` sparingly, but that is exactly where a real MVVM/service-layer refactor should expand.
- The app needs more session-scoped controllers, not more raw `@State`.

### `@ObservedObject`

Current use:
- `ScenarioRow` observes `Scenario`
- `CardItem` and `FocusModeCardEditor` observe `SceneCard`
- `ReferenceCardEditorRow` observes `SceneCard`
- `MainCanvasHost` observes `MainCanvasViewState`

Diagnosis:
- `MainCanvasViewState` observation is targeted and acceptable.
- `Scenario` and `SceneCard` observation is broad.

Why it is risky:
- `SceneCard` has many `@Published` properties: content, order index, parent, category, floating/archive flags, selection memory, color, clone group.
- A leaf view that only needs visible text still invalidates when unrelated card metadata changes.
- `ScenarioRow` observes a full `Scenario`, which includes a frequently updated `timestamp`. Because scenarios are resorted by `timestamp`, the sidebar can churn during active editing.

Conclusion:
- The project observes whole mutable objects where narrower projections would scale better.

### `@Environment` and `@EnvironmentObject`

Current use:
- Environment access is light
- `FileStore` and `ReferenceCardStore` are injected as environment objects
- `openWindow` is used directly where needed

Diagnosis:
- This is not an `EnvironmentObject` count problem.
- It is an environment breadth problem.

Why:
- `FileStore` is injected widely and used as a god object for persistence, scenario mutation triggers, AI storage, shared craft synchronization, and workspace state.
- Views are still reaching directly into the repository layer instead of going through feature-owned controllers.

### State duplication

The most important duplicated state areas are below.

| Duplicated state | Location | Impact | Preferred owner |
| --- | --- | --- | --- |
| Full writer session state in split mode | `MainContainerView` creates two `ScenarioWriterView` instances for one `Scenario` | Heavy duplication, sync complexity, higher invalidation cost, more lifecycle surfaces | Shared `WriterSessionViewModel` plus pane-scoped view state |
| Undo/coalescing state for main mode, focus mode, and reference window | `WriterUndoRedo.swift`, `WriterViews.swift`, `ReferenceWindow.swift` | Behavioral drift and bug-fix duplication | Shared editor-undo engine service |
| AI thread state, embedding index state, and persistence work items | `ScenarioWriterView` local state | View owns persistent feature state and scheduling | `AIChatViewModel` / `AIThreadStoreService` |
| Focus snapshots and viewport restore state | `ScenarioWriterView` state plus `@AppStorage` keys | Multiple sources of truth, stale restoration complexity | Workspace-scoped editor session persistence object |
| Inactive split-pane snapshot cache | `inactivePaneSnapshotState` | Derived render data copied into view state | Split-pane coordinator |
| Repeated settings keys across views | `WriterViews`, `WriterCardViews`, `ReferenceWindow`, `SettingsView`, `waApp` | Cross-layer coupling and broad invalidation on settings changes | Central `AppPreferences` service or view model |

### State leakage

Observed leakage patterns:

- `ReferenceCardStore` persists pinned entries to a single global `UserDefaults` key and is not workspace-scoped.
- Focus and viewport restoration keys are global `@AppStorage` keys rather than workspace-scoped records.
- Many delayed work items and monitor handles are view-owned, which increases the risk of stale lifecycle behavior when views appear/disappear or when split panes are toggled.

These do not necessarily produce immediate bugs today, but they reduce correctness margins as the app grows.

### Incorrect ownership

Most important ownership mismatches:

- `ScenarioWriterView` owns backup scheduling, although backup is an application/workspace concern.
- `ScenarioWriterView` owns dictation recorder lifecycle, although dictation is a service/controller concern.
- `ScenarioWriterView` owns AI request task state and persistence scheduling, although AI threads and embeddings are durable feature data.
- Leaf rendering views read settings directly from `@AppStorage`, which means configuration ownership is spread across the rendering layer.

Correct ownership examples already present:

- `FileStore` owning workspace persistence
- `ReferenceCardStore` owning reference-card list state
- `ScenarioWriterObservedState` owning projected render versions

## VIEW COMPLEXITY

### Massive Views

Largest current source files:

| File | Lines |
| --- | ---: |
| `wa/WriterCardManagement.swift` | 3961 |
| `wa/WriterFocusMode.swift` | 2945 |
| `wa/WriterViews.swift` | 2646 |
| `wa/Models.swift` | 1920 |
| `wa/WriterHistoryView.swift` | 1848 |
| `wa/WriterKeyboardHandlers.swift` | 1750 |
| `wa/SettingsView.swift` | 1500 |
| `wa/WriterSharedTypes.swift` | 1458 |

Diagnosis:
- The file count is not the core problem.
- The type count is the core problem.
- Most of the heavy files are still extensions on one root type: `ScenarioWriterView`.

That means the code is split physically, but not architecturally.

### Business logic inside views

Business or service logic currently living in view code includes:
- saving and backup triggering
- snapshot creation and history retention
- AI thread persistence scheduling
- export generation orchestration
- dictation flow orchestration
- keyboard routing and command dispatch
- AppKit selection/caret normalization
- split-pane focus activation

For this app category, some platform-specific view glue is expected.

The problem is not that view code touches AppKit.

The problem is that view code also owns:
- domain mutation rules
- persistence triggers
- async orchestration
- command semantics

### Duplicated view structures

The editor exists in three forms:
- main card editor
- focus mode editor
- reference window editor

Shared concerns handled separately in multiple places:
- text binding and content mutation
- editor height measurement
- caret visibility
- line spacing updates
- typing coalescing
- undo behavior
- selection observers

This duplication is a major maintainability risk because every bug fix in text behavior now has multiple landing sites.

### Poor component boundaries

Current boundary problems:
- feature files are grouped by extension, not by ownership
- UI containers still know about persistence and services
- editing modes are separate code paths without a shared editing engine
- settings and preferences are read from inside leaf views

Positive note:
- `CardItem`, `FocusModeCardEditor`, and the equatable host views are useful subcomponents
- The issue is not lack of any componentization
- The issue is that the top-level responsibilities are still not decomposed

## DEPENDENCY STRUCTURE

### Current relationship model

Actual relationship:

`View -> Store / Model / Service / AppKit bridge`

Target relationship:

`View -> ViewModel / Feature Controller -> Service / Repository -> Model`

### Strong coupling

Most important couplings:

- `ScenarioWriterView` depends directly on `FileStore`, `Scenario`, `SceneCard`, `GeminiService`, `KeychainStore`, `WorkspaceAutoBackupService`, `ScriptPDFGenerator`, speech services, AppKit text views, notifications, and event monitors.
- `ReferenceWindowView` depends directly on `FileStore`, `SceneCard`, and its own editor/undo logic.
- `SettingsView` touches keychain, bookmark selection, backup policy, export config, and global preferences directly.
- `MainContainerView` creates two editor roots and coordinates pane activation through notifications.

This means most features are coupled to both domain objects and platform plumbing at the same time.

### Circular dependencies

No compile-time import cycle is obvious in the Swift source organization.

Behavioral cycles do exist:

| Cycle | Description | Risk |
| --- | --- | --- |
| `SceneCard` -> `Scenario` -> render versions -> `ScenarioWriterView` -> direct `SceneCard` mutation | Model and view are tightly co-dependent | Harder reasoning about side effects |
| `waApp` -> notification -> `ScenarioWriterView` / `MainContainerView` -> notification back for split-pane activation/focus | Command routing is indirect and multi-hop | Harder to trace ownership and event order |
| Split pane A and split pane B -> same `Scenario` with separate local session state | Two editor roots operate on one model | Drift between pane-local state and shared model |

### Missing abstraction layers

The project is missing at least these architectural layers:

- `WriterSessionViewModel` or equivalent session controller
- `SplitPaneCoordinator`
- `HistoryViewModel`
- `AIChatViewModel`
- `DictationController`
- shared text-editor bridge/coordinator
- central `AppPreferences` abstraction
- screenplay semantics layer between raw cards and export/import formatting

### Domain-specific gap for screenplay-style editing

For a screenplay/writing tool, the current editing model is too raw-text-centric.

Current state:
- import and export understand structured script concepts
- editing does not operate on a first-class screenplay block model

Implication:
- any future feature like block-aware formatting, title page editing, dialogue validation, scene numbering, or round-trip Fountain fidelity will be harder than it should be

This is a scalability issue, not an immediate bug.

## SWIFTUI PERFORMANCE RISKS

### Existing mitigation already present

These are worth preserving:
- `ScenarioWriterObservedState` narrows scenario invalidation
- `MainCanvasHost` and other hosts use `Equatable` render states
- `WriterInteractionRuntime` stores imperative caches outside `@Published`
- `FileStore` avoids unnecessary disk writes

The code is not naive.

The performance risk comes from how much complexity is still attached to the root view.

### 1. Large root invalidation surface

Risk:
- `ScenarioWriterView` has 157 `@State`, 33 `@AppStorage`, 7 `@FocusState`, 20 `.onChange`, and 4 `.onReceive`

Impact:
- The root view recomputes often
- Render reasoning becomes difficult
- More changes cross the entire feature tree than necessary

Current mitigation:
- Equatable host views and content fingerprints

Remaining issue:
- The view is still acting as the central state machine, so containment is partial rather than structural

### 2. Whole-object observation of `SceneCard` and `Scenario`

Risk:
- Card leaf views observe full `SceneCard` objects with many published properties
- Sidebar rows observe full `Scenario` objects

Impact:
- Non-visual model changes can invalidate visual leaves
- Frequent scenario timestamp changes can churn the sidebar list

### 3. Split mode doubles the heaviest render tree

Risk:
- Split mode instantiates two full `ScenarioWriterView` trees for the same `Scenario`

Impact:
- Duplicated state
- Duplicated monitors
- Duplicated feature controllers in practice, even though they are implemented as raw view state
- Higher memory and render cost in the most complex mode

This is one of the highest-priority architecture findings.

### 4. Direct settings reads from rendering leaves

Risk:
- `fontSize`, `appearance`, line spacing, and card colors are read directly through `@AppStorage` in multiple leaves

Impact:
- Preference changes invalidate many parts of the tree directly
- Configuration ownership is spread across unrelated view files

### 5. High use of event monitors and delayed work items

Risk:
- The editor uses many `DispatchWorkItem`, `NotificationCenter` publishers, local event monitors, timers, and delayed async calls

Impact:
- Harder lifecycle correctness
- Harder performance reasoning
- More chance of redundant work during mode transitions

This is especially important in a rich text-editor app where focus and IME behavior are already sensitive.

### 6. Unused batched mutation capability

Observation:
- `Scenario` contains a `performBatchedCardMutation(_:)` primitive
- It is currently not used by the rest of the codebase

Impact:
- Large model mutations still fan out multiple dirty/version updates and more invalidation than necessary

### 7. List churn rather than unstable card identity

Identity quality:
- Card identity is generally good because UUIDs are used consistently

Main risk:
- The main problem is not unstable card identity
- The main problem is scenario-list resorting and broad invalidation caused by timestamp-driven updates

### 8. Type-erased host content

Observation:
- `AnyView` is used inside the equatable host wrappers

Diagnosis:
- This is a secondary concern, not a primary one
- The bigger issue is that content fingerprints and type erasure are compensating for a state-heavy root instead of eliminating the root’s breadth

## TECHNICAL DEBT

### Architecture violations

- Views mutate domain models directly
- Views trigger persistence directly
- Views orchestrate service calls directly
- Views own long-lived feature/session state directly
- Screenplay semantics are not modeled as a dedicated domain layer
- Global settings are accessed from multiple unrelated layers

### Maintainability risks

- Very large files and extension-based mega-types
- Duplicate editor logic across main, focus, and reference modes
- Indirect event routing through notifications and AppKit monitors
- High cognitive load for any change touching editing behavior
- Existing diagnosis document had already become stale, which is a sign that the architecture is difficult to keep documented accurately

### Scalability risks

- Split mode duplicates the editor state machine rather than sharing it
- New AI features will continue to add state to `ScenarioWriterView` unless ownership is extracted
- New script-formatting features will continue to rely on raw-text inference unless a semantics layer is added
- Workspace schema evolution must remain aligned with the Node MCP tooling in `mcp/`
- Multi-workspace or multi-window growth would stress the current global `@AppStorage` approach

### Testing debt

Observed gap:
- No XCTest target or automated regression coverage is present in the repository

Highest-risk untested areas:
- load/save and schema migration behavior
- history snapshot diffing and restore
- focus mode keyboard behavior
- undo/redo behavior
- import/export fidelity
- split-pane synchronization behavior

## ARCHITECTURE REFACTOR PLAN

Target principle:
- Keep behavior identical
- Keep persistence identical
- Refactor by ownership extraction, not by rewrite

### Rules for View responsibilities

Views should:
- declare layout and bind to already-owned state
- own only short-lived presentation state
- forward user intent as commands
- contain AppKit bridge code only when it is strictly view-local

Views should not:
- call `FileStore.saveAll()` directly
- schedule backups directly
- own AI persistence state
- own long-lived undo/session engines
- be responsible for cross-feature orchestration

### Rules for ViewModel responsibilities

Introduce explicit feature controllers/view models:

| Proposed type | Responsibility |
| --- | --- |
| `ScenarioListViewModel` | Scenario selection, rename/create/delete/template actions, sidebar state |
| `WriterSessionViewModel` | Single source of truth for one scenario session |
| `SplitPaneCoordinator` | Active pane, shared session state, pane-specific focus/render state |
| `HistoryViewModel` | Snapshot selection, preview state, named snapshot editing |
| `AIChatViewModel` | Thread state, request lifecycle, embeddings, persistence scheduling |
| `DictationController` | Recorder lifecycle, permission flow, summary production |
| `ReferenceWindowViewModel` | Reference entry list and workspace-scoped persistence |

Important rule:
- Split panes must share one writer session model per scenario
- Pane-specific view state can remain separate, but session state must not be duplicated

### Rules for Service layer usage

Service boundaries should be explicit:

| Service | Target role |
| --- | --- |
| `FileStore` | Repository only, not UI command coordinator |
| `WorkspaceBackupService` | Own backup scheduling and execution |
| `EditorUndoService` | Shared undo/coalescing logic for main, focus, and reference editors |
| `AIService` + `AIThreadStoreService` | Separate request execution from persisted thread state |
| `ScriptFormattingService` | Own Fountain/script parsing and formatting semantics |
| `AppPreferences` | Centralize `@AppStorage` access behind a typed facade |

### Rules for state ownership

State should be owned by the layer whose lifetime matches it:

| State category | Correct owner |
| --- | --- |
| Persistent document data | `Scenario`, `SceneCard`, history models |
| Workspace persistence | `FileStore` |
| App-wide preferences | `AppPreferences` or equivalent |
| Scenario session state | `WriterSessionViewModel` |
| Pane-local focus/render state | Pane coordinator or pane-local state object |
| Text-view bridging, selection observation, caret coordination | Shared editor bridge/coordinator types |
| One-off presentation booleans | SwiftUI view `@State` |

### Rules for module boundaries

Recommended module/folder boundaries inside `wa/`:

- `AppShell/`
- `Workspace/`
- `Domain/`
- `Features/ScenarioList/`
- `Features/Writer/`
- `Features/History/`
- `Features/AI/`
- `Features/Reference/`
- `Features/Settings/`
- `Services/`
- `EditorInfrastructure/`
- `SharedUI/`

These can be introduced incrementally without changing runtime behavior.

### Incremental refactor sequence

Recommended order for Phase 2 and later:

1. Introduce `AppPreferences` and stop reading repeated `@AppStorage` keys from leaf views.
2. Introduce one `WriterSessionViewModel` for a scenario and move AI/history/dictation/backup scheduling out of `ScenarioWriterView`.
3. Introduce a `SplitPaneCoordinator` so both panes share one session model.
4. Extract shared editor bridge logic used by main mode, focus mode, and reference mode.
5. Convert direct save/snapshot triggers into session commands instead of view-owned side effects.
6. Extract screenplay/Fountain semantics into a dedicated formatting domain layer.
7. Add regression tests around persistence, history restore, keyboard behavior, and import/export before deeper refactors.

### Refactor guardrails

Non-negotiable guardrails:
- No visible behavior changes
- No persistence schema breakage
- No UI redesign
- No big-bang rewrite
- Preserve current compile behavior while moving ownership gradually

## Phase 1 Conclusion

Current architecture status:
- Strong feature breadth
- Medium quality in persistence and some render containment
- Weak ownership boundaries in the main editor
- High long-term maintenance risk if the current `ScenarioWriterView` root keeps accumulating responsibilities

Primary strategic conclusion:
- The right path is not a rewrite
- The right path is incremental extraction of a real writer session layer, shared editor infrastructure, and typed app preferences, while preserving the existing domain model and storage format

