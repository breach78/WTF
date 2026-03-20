# 03 Release Checklist

검토 기준일: 2026-03-20
검토 대상: `/Users/three/app_build/wa`

## Overall Status

- Security: `Yellow`
- Privacy: `Yellow`
- App Store rejection risk: `Yellow-Red`
- Performance: `Yellow`
- Stability: `Yellow`
- Release readiness: `조건부 진행 가능`, 단 제출 전 배포 서명/entitlement 검증과 저장 실패 가시화가 필요

## Security

### Local data storage

- `FileStore`는 워크스페이스 패키지 내부에 시나리오/히스토리/링크/AI 데이터를 평문 파일로 저장한다. 저장 파일명은 `cards_index.json`, `history.json`, `linked_cards.json`, `ai_threads.json`, `ai_embedding_index.json`, `ai_vector_index.sqlite`다. 근거: `wa/Models.swift:818-823`
- 레퍼런스 창의 pinned card 목록은 `UserDefaults`의 `reference.card.entries.v1` 키에 저장된다. 내용 전문이 아니라 `scenarioID|cardID` 조합만 저장된다. 근거: `wa/ReferenceWindow.swift:22`, `wa/ReferenceWindow.swift:277-284`
- 자동 백업은 기본적으로 `~/Documents/wa-backups` 아래에 `.wtf.zip` 압축본을 남긴다. 백업은 회전 삭제 규칙이 있지만 암호화는 없다. 민감한 원고/개인 기록 앱 특성을 고려하면 FileVault 외 추가 보호는 없다. 근거: `wa/waApp.swift:68-163`

판정:
- 로컬 퍼시스턴스 자체는 앱 성격상 자연스럽다.
- 다만 저장 데이터가 모두 평문이라 민감 원고, 일지, AI 대화, 임베딩이 macOS 계정 수준 보호에만 의존한다.

### File access

- 앱은 `security-scoped bookmark`로 사용자가 고른 `.wtf` 위치에 읽기/쓰기를 수행한다. 근거: `wa/waApp.swift:59-64`, `wa/waApp.swift:798-811`
- 샌드박스 entitlements에는 `com.apple.security.files.user-selected.read-write`가 포함되어 있다. 근거: `.codex_release_check/Build/Intermediates.noindex/wa.build/Release/wa.build/WTF.app.xcent`
- 리스크: `startAccessingSecurityScopedResource()` 호출은 확인되지만 `stopAccessingSecurityScopedResource()` 호출은 없다. 워크스페이스 교체나 장시간 세션에서 파일 접근 토큰이 누적될 수 있다. 근거: `wa/waApp.swift:811`, 검색 결과 기준 stop 호출 없음

판정:
- 접근 모델은 App Sandbox 친화적이다.
- 그러나 보안 범위 수명 관리가 완결되지 않았다.

### Keychain usage

- Gemini API 키는 `KeychainStore`를 통해 Generic Password 항목으로 저장된다. 근거: `wa/KeychainStore.swift`
- 앱은 키체인 저장을 사용하고, 워크스페이스/백업 파일에 API 키를 직접 쓰지 않는다.
- 접근성은 `kSecAttrAccessibleAfterFirstUnlock`이다. 데스크톱 앱 기준 허용 가능하지만, 가장 엄격한 정책은 아니다. 근거: `wa/KeychainStore.swift:43`

판정:
- 현재 방식은 적절하다.
- 민감도만 보면 키체인 사용은 합격선이다.

### Sandbox compliance

- 빌드 산출물 entitlements에서 확인된 권한:
- `com.apple.security.device.audio-input`
- `com.apple.security.files.user-selected.read-write`
- `com.apple.security.network.client`
- 로컬 Release 빌드 산출물에도 `com.apple.security.get-task-allow = 1`이 포함되어 있다. 근거: `.codex_release_check/Build/Intermediates.noindex/wa.build/Release/wa.build/WTF.app.xcent`

판정:
- 마이크, 사용자 선택 파일 접근, 네트워크 클라이언트 권한은 기능상 타당하다.
- 하지만 현재 확인 가능한 Release 빌드는 개발 서명으로 생성되어 `get-task-allow`가 살아 있다. App Store 제출용 아카이브에서 이 값이 제거되는지 별도 검증이 필요하다.

## Privacy

### Personal data

- 앱은 시나리오 텍스트, 노트, 히스토리 스냅샷, 연결 카드 정보, AI 채팅 스레드, 임베딩 인덱스를 로컬에 저장한다. 이 데이터는 사용자의 개인 창작물/일지/계획 데이터가 될 수 있다. 근거: `wa/Models.swift:818-823`
- 자동 백업은 동일 데이터를 압축본으로 중복 저장한다. 근거: `wa/waApp.swift:68-163`

판정:
- 개인정보 또는 민감 창작 데이터 앱으로 취급하는 편이 안전하다.
- 개인정보 처리방침과 앱 내 설명에서 “로컬 저장”과 “외부 AI 전송 조건”을 분리해 명시해야 한다.

### Tracking

- Firebase, Sentry, Mixpanel, Amplitude, ATT, 광고 식별자 사용 흔적은 코드 기준 발견되지 않았다.
- `NSUserTrackingUsageDescription`도 없다.

판정:
- 추적 SDK/광고 추적 관점에서는 깨끗하다.

### Permissions

- `NSMicrophoneUsageDescription`, `NSSpeechRecognitionUsageDescription`가 `Info.plist`에 존재한다. 근거: `Info.plist`
- 실제 권한 요청은 받아쓰기 시작 시점에 지연 요청된다. 근거: `wa/WriterSpeech.swift:40-55`, `wa/WriterSpeech.swift:376-385`
- 카메라, 사진, 애플 이벤트, 위치 추적 권한 사용 흔적은 발견되지 않았다.

판정:
- 현재 권한 요청 타이밍은 적절하다.
- 심사 설명에도 “받아쓰기 기능 사용 시에만 요청”이라고 명확히 적는 편이 좋다.

### External data transmission

- AI 기능은 사용자가 입력한 카드/문맥 일부를 Gemini API로 전송한다. 근거: `wa/GeminiService.swift`, `wa/WriterAI+CandidateActions.swift`, `wa/WriterAI+RAG.swift`
- 전송은 `URLSession.shared.data(for:)`를 사용한 HTTPS 호출이며, API 키는 Keychain에서 읽는다. 근거: `wa/GeminiService.swift:312-393`, `wa/KeychainStore.swift`
- 로컬 Apple Intelligence 요약도 존재하지만, Gemini 기반 기능은 외부 네트워크 전송이 수반된다. 근거: `wa/WriterSpeech.swift:476-518`

판정:
- 프라이버시 핵심 이슈는 “마이크”보다 “원고/노트/개인 텍스트의 외부 AI 전송”이다.
- 제출 전 개인정보 처리방침, 앱 설명, 설정 화면 카피가 이 사실을 충분히 고지하는지 확인해야 한다.

## App Store Rejection Risks

### High concern

- `get-task-allow` 검증 공백: 로컬 Release 빌드 결과에도 `com.apple.security.get-task-allow = 1`이 남아 있다. 개발 서명 빌드 산출물이므로 최종 제출과 동일하다고 단정할 수는 없지만, App Store 배포 아카이브에서 이 entitlement가 남아 있으면 제출 차단 사유가 된다. 근거: `.codex_release_check/Build/Intermediates.noindex/wa.build/Release/wa.build/WTF.app.xcent`
- 외부 AI 전송 고지 부족 가능성: 앱이 창작물/메모/텍스트를 Gemini API에 보낼 수 있는데, 심사 메모나 개인정보 처리방침이 이를 누락하면 프라이버시 설명 부족으로 문제가 될 수 있다. 근거: `wa/GeminiService.swift`

### Medium concern

- 저장 실패의 조용한 무시: `FileStore.performSave`와 보조 저장 함수들이 `try?` 또는 빈 `catch`로 I/O 실패를 삼킨다. 제출 자체보다는 데이터 무결성/사용자 불만/리뷰 리스크로 이어질 가능성이 크다. 근거: `wa/Models.swift:1528-1625`, `wa/Models.swift:1815-1857`
- `security-scoped resource` 해제 누락: 장기 세션에서 리소스 누수로 이어질 수 있다. 제출 차단급은 아니지만 샌드박스 파일 접근 앱에서는 정리해 두는 편이 안전하다. 근거: `wa/waApp.swift:798-811`

### Low concern

- private API 사용 흔적은 찾지 못했다.
- 백그라운드 실행 에이전트, 로그인 아이템, 임의 권한 승격 흐름도 보이지 않는다.
- 권한 문구는 존재하고 요청 시점도 기능 호출 시점에 가깝다.

## Performance

### Large text editing performance

- 장점:
- 메인 캔버스는 카드 높이/레이아웃 캐시를 사용한다.
- PHASE 2에서 카드 반복 행의 row-level `@AppStorage` 관찰을 줄였다.
- Release 빌드가 성공했다.

- 리스크:
- 워크스페이스 로드 시 모든 시나리오, 히스토리, 링크 데이터, 카드 텍스트를 한 번에 메모리로 읽는다. 대형 워크스페이스에서 런치 시간과 메모리 피크가 커질 수 있다. 근거: `wa/Models.swift:1201-1267`
- `withTaskGroup`로 병렬 로드하므로 CPU/IO는 빠를 수 있지만, 카드 수와 히스토리 수가 큰 경우 메모리 급증 가능성이 있다. 근거: `wa/Models.swift:1222-1258`

판정:
- 일반 규모 문서 편집에는 충분히 실용적일 가능성이 높다.
- “대형 저널/대본 작업 파일” 시나리오에서는 실제 기기 스트레스 테스트가 필요하다.

### List rendering

- 메인 컬럼은 `LazyVStack`을 사용한다. 근거: `wa/WriterCardManagement.swift:707`
- 카드 높이와 레이아웃을 캐시하는 구조가 있어 스크롤 재계산 비용을 완화한다. 근거: `wa/WriterCardManagement.swift:1601-1685`, `wa/WriterCardManagement.swift:2370-2464`
- 레퍼런스 창도 반복 행 단위 `@AppStorage`를 제거해 작은 재렌더 낭비를 줄였다. 근거: PHASE 2 반영 사항

판정:
- 현재 구조는 SwiftUI 순정 구현 대비 꽤 방어적인 편이다.
- 병목은 리스트 자체보다 “초기 전체 로드”와 “대형 히스토리/AI 인덱스” 쪽이다.

### Memory spikes

- 히스토리 스냅샷, AI 스레드, 임베딩, SQLite 벡터 인덱스가 모두 워크스페이스별로 유지된다. 근거: `wa/Models.swift:818-823`
- 자동 백업은 별도 zip 산출물을 생성하므로 디스크 사용량은 빠르게 늘 수 있다. pruning 규칙은 있으나 암호화는 없다. 근거: `wa/waApp.swift:68-163`

판정:
- 메모리보다는 디스크/로드 피크 관리가 핵심이다.

## Stability

### Crash risks

- 확인된 강제 언래핑은 `sharedCraftRootCardID`의 하드코딩 UUID 1건이다. 값 자체는 정적이어서 즉시 위험은 낮지만, 수정 실수 시 런치 크래시가 된다. 근거: `wa/Models.swift:812`
- `try!`, `as!` 패턴은 코드 기준 발견하지 못했다.

판정:
- 전형적인 강제 언래핑 남발 앱은 아니다.
- 즉시 크래시보다 “저장 실패 후 상태 불일치” 위험이 더 크다.

### Thread safety

- 핵심 모델(`FileStore`, 다수 상태 객체)은 `@MainActor`로 묶여 있고, I/O는 별도 queue와 `Task.detached`를 사용한다. 근거: `wa/Models.swift`, `wa/WriterSharedTypes.swift`
- `FileStore.flushPendingSaves()`는 save queue와 동기화하여 종료 시점 저장을 밀어 넣는다. 근거: `wa/Models.swift:1334-1339`
- 그러나 저장 실패를 조용히 무시하므로, thread-safe 하더라도 결과는 silent failure가 될 수 있다.

판정:
- 경쟁 상태보다는 오류 가시성 부족이 더 큰 안정성 문제다.

### Silent failure paths

- `FileStore.performSave`의 최상위 `catch { }`는 시나리오 인덱스/카드/히스토리 저장 실패를 사용자에게 알리지 않는다. 근거: `wa/Models.swift:1528-1625`
- 개별 카드 파일, AI 스레드, AI 임베딩 저장도 `try?`/빈 `catch`가 많다. 근거: `wa/Models.swift:1553-1592`, `wa/Models.swift:1815-1857`
- 자동 백업 실패는 `print`만 하고 UI에 노출하지 않는다. 근거: `wa/waApp.swift:947-958`, `wa/WriterViews.swift:1715-1727`

판정:
- 릴리즈 안정성의 가장 큰 실제 리스크는 여기다.
- 기능이 멈추지 않아도 데이터 손실을 사용자가 뒤늦게 알 수 있다.

### Test coverage / release process

- Xcode 프로젝트에는 앱 타깃만 있고 테스트 타깃이 없다. 근거: `wa.xcodeproj/project.pbxproj`
- 따라서 현재 릴리즈 검증은 수동 실행과 빌드 성공에 의존한다.
- 이번 검토에서는 Debug/Release 빌드 성공까지는 확인했다.

판정:
- 테스트가 없기 때문에 “회귀 없음”을 자동으로 보장할 수 없다.

## Submission Checklist

- [ ] App Store 배포용 `Archive`를 생성하고 최종 entitlements에서 `get-task-allow`가 제거되는지 확인
- [ ] 개인정보 처리방침에 “로컬 저장 데이터”와 “Gemini로 전송되는 텍스트”를 분리 명시
- [ ] 앱 설명/심사 메모에 마이크 권한은 받아쓰기 기능에서만 사용된다고 명시
- [ ] 저장 실패/백업 실패가 사용자에게 보이는지 최종 수동 점검
- [ ] 대형 워크스페이스로 런치/스크롤/포커스 모드/히스토리 이동 스트레스 테스트
- [ ] 백업 폴더, 워크스페이스 변경, 권한 재선택 시 security-scoped access 동작 확인

## Final Development Guidelines

### Adding new features

- 사용자 텍스트가 외부 서비스로 나가는 기능은 항상 opt-in 성격과 고지 문구를 먼저 설계한다.
- 기능 추가 시 Debug 빌드만 보지 말고 Release/Archive entitlement까지 같이 검증한다.
- 로컬 저장 포맷을 늘릴 때는 파일명, 보존 기간, 백업 포함 여부를 문서화한다.

### Writing views

- 반복 렌더링되는 row/card view에는 `@AppStorage`, 무거운 계산, 직접 I/O를 넣지 않는다.
- 편집기 뷰는 표시와 입력 조율만 담당하고, 저장/백업/네트워크는 서비스 계층으로 보낸다.
- SwiftUI 뷰는 세션 상태와 영속 상태를 분리한다. 영속되지 않는 창/포커스 상태는 저장하지 않는다.

### State management

- 한 상태에는 한 소유자만 둔다. 앱 전역/창 전역/시나리오 전역 범위를 먼저 정하고 배치한다.
- `@EnvironmentObject`는 “공유 세션 상태”와 “루트 store”에 한정하고, 반복 자식 뷰로 내려갈수록 값 스냅샷을 선호한다.
- 저장 가능한 상태와 일시적 UI 상태를 섞지 않는다.

### Service usage

- 파일 저장 서비스는 실패를 삼키지 말고 사용자 가시 상태 또는 로깅 채널로 올린다.
- `security-scoped resource`는 시작/종료 수명을 명시적으로 관리한다.
- API 키는 계속 Keychain 전용으로 유지하고, 워크스페이스/백업에는 절대 포함시키지 않는다.
- 외부 AI 요청에는 최소한의 문맥만 보내고, 가능한 경우 사용자가 범위를 제어하게 한다.

### Module structure

- `View -> ViewModel/Coordinator -> Service -> Persistence` 흐름을 유지한다.
- `FileStore`는 장기적으로 persistence/repository 책임에 가깝게 축소하고, 정책/워크플로는 별도 서비스로 분리한다.
- 공유 타입은 feature root view에 중첩하지 않고, 재사용 계층에서 독립적으로 선언한다.

## Final Verdict

- 보안/프라이버시 기본선은 나쁘지 않다. 키체인 사용, 샌드박스 파일 접근, 지연 권한 요청은 적절하다.
- 현재 릴리즈의 실제 차단 요소는 “배포 서명/entitlement 최종 검증 미완료”와 “저장 실패가 사용자에게 보이지 않는 구조”다.
- 제출 전 마지막 게이트로는 `Archive entitlement 확인`, `대형 워크스페이스 수동 QA`, `AI 전송 고지 검수`가 가장 중요하다.
