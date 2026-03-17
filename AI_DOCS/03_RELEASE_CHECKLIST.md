# PHASE 3 — RELEASE CHECKLIST

Date: 2026-03-18

Scope:
- Local repository audit
- Build/configuration review
- Official Apple documentation review
- Official Google Gemini API documentation review

Overall release status:
- Direct distribution / notarized outside the Mac App Store: `YELLOW`
- Mac App Store submission in current form: `RED`

Reason:
- The app is functionally close to release quality for direct distribution, but privacy disclosure and several persistence hardening items remain.
- The current Xcode project is not Mac App Store ready because App Sandbox is disabled and the backup-folder permission model is not sandbox-safe.

## SECURITY

### Local data storage

Observed:
- Primary user content is stored in a user-selected `.wtf` workspace package.
- Scenario metadata, card indexes, history, linked-card metadata, AI thread history, AI embedding indexes, and a per-scenario vector index are persisted on disk.
- Gemini API credentials are stored in Keychain, not in `UserDefaults` or plain files.

Assessment:
- Keychain usage for the Gemini API key is good release practice.
- Workspace content is not encrypted at rest beyond the host file system.
- For a writing, journaling, or screenplay app, this is acceptable only if the product clearly does not promise encrypted local storage.

Release status:
- `YELLOW`

Notes:
- The most privacy-sensitive local artifacts are not only the card text, but also AI chat history, semantic embeddings, and backup archives.
- Users handling personal journals, client notes, or unreleased scripts should be told that data is stored locally in the selected workspace and backup folders.

### File access

Observed:
- Workspace access is restored from a security-scoped bookmark and activated with `startAccessingSecurityScopedResource()`.
- The codebase does not call `stopAccessingSecurityScopedResource()`.
- Auto-backup uses a plain stored path string, not a security-scoped bookmark.

Assessment:
- The workspace selection approach is directionally correct for sandboxed document access.
- Not balancing `startAccessingSecurityScopedResource()` with `stopAccessingSecurityScopedResource()` is a resource-leak risk under App Sandbox.
- The auto-backup folder model is not durable or sandbox-safe for Mac App Store distribution.

Release status:
- Direct distribution: `YELLOW`
- Mac App Store: `RED`

Blocking items for sandboxed release:
- Enable App Sandbox in the project.
- Add an explicit entitlements file.
- Convert the auto-backup folder selection to a security-scoped bookmark model.
- Balance every `startAccessingSecurityScopedResource()` with `stopAccessingSecurityScopedResource()`.

### Keychain usage

Observed:
- Gemini API keys are stored and loaded through the Security framework.
- The app deletes the key when the saved value is empty.

Assessment:
- This is the correct place for secret storage.
- One hardening gap remains: Gemini requests place the API key in the request URL query string.

Risk:
- Query-string API keys can appear in proxy logs, diagnostics, or intermediate request logging more easily than header-based credentials.

Release status:
- `YELLOW`

Recommended post-release hardening:
- Prefer header-based API authentication if the provider supports it.

### Sandbox compliance

Observed:
- `wa.xcodeproj/project.pbxproj` currently sets `ENABLE_APP_SANDBOX = NO`.
- There is no checked-in entitlements file in the repository root or target folder.

Assessment:
- Inference from Apple platform requirements: this project is not ready for Mac App Store submission as configured.
- The current file-access design suggests the app may have been moving toward sandbox-compatible behavior, but the build settings do not complete that transition.

Release status:
- `RED` for Mac App Store

## PRIVACY

### Personal data

Observed:
- The app stores user-authored text, history snapshots, linked-card structures, AI chat content, semantic embeddings, and backup archives.
- Dictation uses microphone and speech-recognition access.
- Apple Intelligence summarization can process dictation transcript content locally through `FoundationModels`.
- Gemini AI features send prompt/context data off-device.

Assessment:
- This app handles potentially sensitive personal writing data.
- For a journaling or screenplay workflow, users may reasonably assume drafts are private unless told otherwise.
- The current repo does not show an in-app privacy policy screen or an in-app disclosure flow before sending content to Gemini.

Release status:
- `YELLOW` for direct distribution
- `RED` for App Store submission unless privacy disclosures are completed in product metadata and user flow

### Tracking

Observed:
- No analytics SDKs, ad SDKs, crash-reporting SDKs, or ATT-related code were detected in the repository.
- No App Transport Security exceptions were found in `Info.plist`.

Assessment:
- No evidence of cross-app tracking was found.
- ATT does not appear to be required based on the current codebase.

Release status:
- `GREEN`

### Permissions

Observed:
- `NSMicrophoneUsageDescription` and `NSSpeechRecognitionUsageDescription` are present in `Info.plist`.
- Microphone and speech-recognition permissions are requested only when dictation starts.

Assessment:
- This follows expected Apple permission timing.
- Permission copy is serviceable, though still generic.

Release status:
- `GREEN`

Recommended improvement:
- Add clearer user-facing disclosure that dictation text may also be summarized with Apple Intelligence, and AI chat content may be sent to Gemini when those features are used.

### Third-party AI data sharing

Observed:
- AI chat and RAG flows build prompt context from card snapshots, scoped card selections, rolling summaries, and semantic retrieval context.
- Gemini API calls are sent to `https://generativelanguage.googleapis.com/...`.
- The app uses a user-supplied Gemini API key.

Assessment:
- This is third-party data sharing for user-authored content.
- Apple privacy review expectations apply even if the user supplies the API key.
- App Store Connect privacy answers must reflect the app’s behavior and any third-party partner behavior involved in request handling.

Important nuance:
- Official Google Gemini API documentation indicates that retention and product-improvement behavior depends on the user’s Gemini API tier and logging configuration.
- Inference: if a user supplies a free-tier Gemini project, prompts/responses may have materially different privacy characteristics than a billed project with stricter logging defaults.

Release status:
- `RED` until the product ships with:
- A privacy policy covering Gemini data transmission.
- Accurate App Store Connect privacy disclosures.
- Clear user disclosure before sending personal content to Gemini.

## APP STORE REJECTION RISKS

### High-risk

1. App Sandbox disabled
- The project is currently not configured as a sandboxed Mac App Store app.
- This is the clearest release blocker for Mac App Store submission.

2. Third-party AI privacy disclosure gap
- The app sends user-authored content to Gemini, but the repository does not show an in-app disclosure or privacy-policy entry point.
- Apple’s privacy guidance requires accurate disclosure of data collection/sharing and third-party partner behavior.

3. AI feature completeness during review
- Prominent AI functionality depends on a user-provided Gemini API key.
- Inference from App Review completeness expectations: if App Review cannot exercise those features, review notes or a reviewer test credential path will be needed.

### Medium-risk

1. Backup-folder permission model under sandbox
- The app stores the backup folder as a plain path string.
- Once sandboxing is enabled, that path will not be a durable permission grant.

2. Preview / deprecated model dependence
- Default model IDs include preview Gemini models.
- `SettingsView` also exposes `gemini-2.0-flash`.
- Google’s pricing documentation currently states that Gemini 2.0 Flash is deprecated and scheduled for shutdown on June 1, 2026.
- Release consequence: an App Review build or production build can fail AI requests even when the app code is otherwise correct.

3. Cloud-sync marketing vs persistence implementation
- The onboarding copy explicitly recommends Dropbox or iCloud Drive workspace locations.
- The persistence layer performs direct file writes and does not use file coordination or file presenters.
- This is more likely to become a support/data-consistency problem than an App Review rejection, but it is still release-significant for this app category.

### Low-risk

1. Private API usage
- No private API patterns such as `NSSelectorFromString`, `dlopen`, or dynamic private-framework access were detected.

2. Permission usage strings
- Required microphone and speech-recognition usage descriptions are present.

3. Network transport
- No ATS exceptions were found.

## PERFORMANCE

### Large text editing

Strengths observed:
- Per-card text files reduce the need to rewrite one monolithic document on every edit.
- The app uses background save queues, payload caching, and atomic writes.
- Phase 2 reduced some root-view invalidation pressure around AI state.

Risks:
- The writer feature is still structurally large and state-dense.
- The app has no detected automated performance or regression test target.
- Silent persistence failures remain possible because many I/O paths use `try?` or empty `catch` blocks.

Release status:
- `YELLOW`

### List rendering

Strengths observed:
- Several views already use lazy stacks and cached measurement helpers.

Risks:
- Main-canvas complexity remains high.
- Very large scenario trees, AI candidate overlays, and history overlays still need manual stress testing.

Release status:
- `YELLOW`

### Memory spikes

Risks:
- AI embedding/index generation can scale with the visible card set.
- AI thread history, prompt context, and vector artifacts can increase memory use on large workspaces.
- Quit-time backup runs compression synchronously, which can amplify memory and responsiveness issues on large workspaces.

Release status:
- `YELLOW`

Recommended pre-release manual tests:
- 10k+ cards across multiple scenarios
- long-card editing sessions with undo/redo churn
- repeated AI chat sessions on large workspaces
- repeated edit-end auto-backup and app-quit backup on large `.wtf` packages
- workspace stored in Dropbox and iCloud Drive to test conflict behavior

## STABILITY

### Crash risks

Observed:
- No `try!`, `as!`, or widespread force-unwrapping patterns were detected.
- One force unwrap exists for a static UUID constant in `FileStore`; this is low risk because the literal is compile-time controlled.

Assessment:
- Direct crash risk is moderate-to-low.
- Hidden failure risk is more significant than explicit crash risk.

Release status:
- `YELLOW`

### Thread safety

Observed:
- `FileStore` is `@MainActor`, but it also uses background queues, `DispatchGroup`, `NSLock`, and several `nonisolated(unsafe)` caches.
- Background save/load paths are sophisticated but rely on convention rather than strict isolation.

Assessment:
- This is workable, but it raises long-term maintenance risk.
- The largest stability concern is not an obvious race already reproducing in code review; it is that future edits can easily break save ordering or cache coherence.

Release status:
- `YELLOW`

### Data integrity

Observed:
- Many persistence paths swallow errors with `try?` or empty `catch` blocks.
- Auto-backup on quit is synchronous and only logs failures to stdout.
- Cloud-synced workspace usage is encouraged by UI copy, but the app does not implement file coordination.

Assessment:
- The primary integrity risk is silent data-loss or silent backup failure rather than immediate crashing.

Release status:
- `YELLOW`

### Async safety

Observed:
- AI task cancellation and persistence flushing improved in Phase 2.
- Some heavy operations still use `Task.detached`.
- Quit-time backup remains synchronous on the main thread.

Assessment:
- Async behavior is improved but not fully hardened for large-data shutdown paths.

Release status:
- `YELLOW`

## FINAL DEVELOPMENT GUIDELINES

### Adding new features

- Preserve `.wtf` workspace backward compatibility; add schema migrations instead of ad hoc format changes.
- Treat AI features as optional services, not as the core persistence path.
- Do not add new filesystem destinations without a clear sandbox and bookmark strategy.
- For any feature that sends writing content off-device, add explicit user disclosure and policy coverage first.

### Writing views

- Keep SwiftUI views presentation-focused.
- Move long-lived feature state into dedicated `ObservableObject` owners or ViewModels.
- Avoid growing `ScenarioWriterView` further; new feature flows should be extracted into feature controllers or coordinators.

### State management

- Keep a single source of truth for workspace data inside the store/model layer.
- Keep transient UI state local to feature state objects.
- Avoid storing non-UI caches in `@State` or `@Published` unless UI invalidation is required.

### Service usage

- Keep secrets in Keychain only.
- Prefer header-based auth over query-string auth when the remote API allows it.
- Stop swallowing persistence errors in release builds; surface them to logs or user-visible recovery UI.
- Keep all sandbox-external URLs behind security-scoped bookmarks.

### Module structure

- Continue moving toward `View -> ViewModel/Coordinator -> Service -> Store/Model`.
- Isolate AI, backup, speech, and workspace-permission concerns into explicit service boundaries.
- Keep persistence code separate from view/event code.

### Release gates for future builds

Before shipping a Mac App Store build:
- Enable App Sandbox and add entitlements.
- Convert backup folder access to a bookmark-based permission model.
- Balance security-scoped access lifetimes.
- Add privacy policy metadata and in-app privacy access.
- Review and update App Store Connect privacy answers.
- Verify every AI feature path with a reviewer-usable configuration.

Before shipping any production build:
- Stress-test large workspaces.
- Test quit-time backup on large projects.
- Test workspace restore after stale bookmark refresh.
- Validate Gemini model defaults against currently supported Google model IDs.

## CONCLUSION

Current conclusion:
- The app is not Mac App Store ready.
- The app can be prepared for direct distribution sooner than for Mac App Store release.
- The biggest blockers are not UI quality or obvious crashes; they are privacy disclosure, sandbox compliance, backup permission design, and silent-failure behavior in persistence paths.

## REFERENCES

Apple:
- [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
- [User Privacy and Data Use](https://developer.apple.com/app-store/user-privacy-and-data-use/)
- [App Privacy Details](https://developer.apple.com/app-store/app-privacy-details/)
- [Manage App Privacy in App Store Connect](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy)
- [Human Interface Guidelines: Privacy](https://developer.apple.com/design/human-interface-guidelines/privacy/)
- [startAccessingSecurityScopedResource()](https://developer.apple.com/documentation/foundation/nsurl/startaccessingsecurityscopedresource%28%29)
- [fileImporter documentation note on security-scoped access](https://developer.apple.com/documentation/swiftui/view/fileimporter%28ispresented%3Aallowedcontenttypes%3Aallowsmultipleselection%3Aoncompletion%3A%29)
- [NSMicrophoneUsageDescription](https://developer.apple.com/documentation/bundleresources/information-property-list/nsmicrophoneusagedescription)
- [NSSpeechRecognitionUsageDescription](https://developer.apple.com/documentation/bundleresources/information-property-list/nsspeechrecognitionusagedescription)

Google:
- [Gemini API Logs Policy Guide](https://ai.google.dev/gemini-api/docs/logs-policy-guide)
- [Gemini API Pricing](https://ai.google.dev/gemini-api/docs/pricing)
