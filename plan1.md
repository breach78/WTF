# 설정 화면 단순화 및 고만족 UI/UX 적용 계획

작성일: 2026-03-02  
기준 문서: `/Users/three/app_build/wa/research.md`  
기준 코드: `/Users/three/app_build/wa/wa/SettingsView.swift`

## 1) 목표

- 설정 화면의 인지 부담을 낮춰 사용자가 원하는 항목을 빠르게 찾고 바로 변경할 수 있게 한다.
- 유사 항목을 기능/빈도 중심으로 재분류해 정보구조(IA)를 단순화한다.
- “만족도 높은 UX”를 추상 감이 아니라, 공신력 있는 가이드 + 측정 지표(과업 성공/시간/SUS/SEQ)로 검증 가능하게 만든다.

## 2) 현재 구조 진단 (As-Is)

`SettingsView`는 현재 `설정` + `단축키` 2개 탭 구조이며, `설정` 탭 내부에 3열 카드가 한 화면에 동시에 노출된다.

현재 주요 카드:

- 편집기 설정
- 포커스 모드 설정
- 데이터 저장소
- 자동 백업
- 폰트 라이선스 (OFL)
- 출력 설정
- AI 설정
- 색상 테마 프리셋
- 색상 설정
- 색상 초기화
- 단축키(공통/메인/포커스/히스토리)

핵심 문제:

- 서로 다른 목적(작업 설정/데이터 안전/법적 고지)이 한 레벨에 혼재.
- 저빈도/정보성 항목(라이선스)이 고빈도 조정 항목과 같은 시각적 우선순위를 가짐.
- 3열 동시 노출로 스캔 비용이 높고, 처음 보는 사용자 기준 탐색 경로가 불명확.
- 의존 관계(예: 상위 스위치와 하위 옵션) 표현이 약해 상태 이해가 어렵다.

## 3) 조사 근거 요약 (High-satisfaction 패턴)

절대적 “최고 만족도 UI”는 제품/사용자군마다 달라서 단일 레퍼런스로 확정할 수 없다. 대신 아래 공통 원칙을 채택한다.

- Android Settings 가이드: 설정은 예측 가능하게 그룹화하고, 15개 이상이면 서브스크린으로 분리, 깊은 구조에는 검색 제공.
- Windows App Settings 가이드: 상위 그룹 수를 작게 유지(대체로 4~5), 이진 옵션은 토글 우선, 변경 즉시 반영.
- Apple System Settings 패턴: 사이드바 기반 카테고리 탐색 + 검색/추천으로 빠른 접근.
- Google HEART 프레임워크(CHI 2010): UX 품질은 Happiness/Task Success 등 사용자 중심 지표로 지속 측정.
- MeasuringU 벤치마크: 평균 Task Completion 78%, 평균 SUS 68, 평균 SEQ 5.5를 기준선으로 개선 목표를 설정 가능.

## 4) 유사 항목 재분류 (To-Be Taxonomy)

### A. 작업 환경 (고빈도)

- 편집기 설정: 메인 행간, 카드 간격
- 포커스 설정: 포커스 행간, 타이프라이터 기준선
- 단축키 안내

### B. 외관

- 색상 테마 프리셋
- 색상 상세(배경/기본/선택/연결)
- 색상 초기화

### C. AI

- Gemini 모델 선택/직접 입력
- API 키 저장/업데이트/삭제

### D. 출력

- 중앙정렬식 PDF 옵션
- 한국식 PDF 옵션

### E. 데이터 및 백업

- 작업 파일 열기/생성/초기화
- 저장 경로 표시
- 자동 백업 on/off
- 백업 경로/보관 정책 안내

### F. 정보 및 법적 (저빈도)

- 폰트 라이선스(OFL)
- 앱 정보/버전(추가 권장)

## 5) 목표 UI 구조

### 5.1 정보구조

- 기존 3열 카드 병렬 노출을 중단하고, `좌측 카테고리 사이드바 + 우측 상세 패널`로 전환.
- 상위 카테고리는 5개를 기본으로 운영:
  - 작업 환경
  - 외관
  - AI
  - 출력
  - 데이터 및 백업
- `정보 및 법적`은 별도 About/Legal 화면(또는 사이드바 하단 링크)으로 분리해 주 흐름에서 격리.

### 5.2 탐색/검색

- 설정 상단 검색 필드 추가 (`.searchable`): 라벨/설명/동의어 기반 필터.
- 최근/자주 변경 항목 3~5개를 “빠른 설정” 영역으로 상단 고정.

### 5.3 화면 밀도와 점진적 공개

- 기본 화면에는 핵심 설정만 노출.
- 상세 설명, 라이선스 전문, 고급 옵션은 `DisclosureGroup` 또는 하위 화면으로 이동.
- 15개 이상 항목이 모이는 카테고리는 하위 섹션으로 분리.

### 5.4 상호작용 원칙

- 즉시 반영 가능한 옵션은 즉시 저장(토글/슬라이더).
- 파괴적 작업(작업 파일 초기화, 키 삭제)은 확인 다이얼로그 + 결과 메시지 표준화.
- 의존 설정은 비활성 + 이유 문구를 가까운 위치에 표시.

## 6) 구현 단계 계획

## Phase 0. 기준선 측정 (1일)

- 현재 화면 기준으로 대표 과업 5개 시간/성공률 측정.
- 대상 과업:
  - 메인 행간 변경
  - 백업 폴더 변경
  - Gemini API 키 교체
  - 색상 프리셋 적용
  - PDF 캐릭터 정렬 변경
- 산출물: Baseline 리포트(성공률, 완료 시간, 오류 횟수, SEQ)

## Phase 1. IA 리팩토링 설계 (1일)

- `SettingsItem` 인벤토리 작성(빈도/중요도/위험도 태깅).
- 6개 분류를 기준으로 최종 메뉴 트리 확정.
- 마이크로카피 통일(라벨 시작어/상태 문구/경고 문구).

## Phase 2. 레이아웃 전환 (2일)

- `SettingsRootView`를 `NavigationSplitView` 기반으로 전환.
- 좌측 카테고리 목록 + 우측 상세 섹션 구조 구현.
- 기존 카드 컴포넌트는 카테고리별 재사용 가능한 섹션 컴포넌트로 분해.

## Phase 3. 검색/빠른 설정/의존성 UX (2일)

- 검색 인덱스 추가(라벨 + 보조설명 + 동의어).
- 빠른 설정 영역 도입(사용 빈도 높은 항목 우선).
- 상위 스위치-하위 옵션 의존성 표현/비활성 안내 일관화.

## Phase 4. 저빈도/법적 정보 분리 (1일)

- OFL 전문 카드를 메인 설정에서 분리해 About/Legal로 이동.
- 설정 본문은 “변경 가능한 항목” 중심으로 축소.

## Phase 5. 검증 및 튜닝 (2일)

- Phase 0 동일 과업으로 재측정.
- 목표치 달성 여부 점검 후 카피/배치 미세 조정.

## 7) 완료 기준 (Definition of Done)

- 사용자가 설정 과업 5개를 평균 2클릭(또는 1 depth) 이내로 진입 가능.
- 과업 성공률 95% 이상.
- 기준선 대비 과업 완료 시간 30% 이상 단축.
- SEQ 평균 6.0 이상(기준선 5.5 이상을 “평균”으로 보고 상향 목표 설정).
- SUS 80 이상(상위권 사용성 목표).
- 주 설정 화면에서 법적 전문 텍스트 직접 노출 제거.

## 8) 코드 구조 적용안

- 현 파일: `/Users/three/app_build/wa/wa/SettingsView.swift`
- 분리 권장:
  - `SettingsRootView.swift`
  - `SettingsCategorySidebar.swift`
  - `SettingsGeneralEditorView.swift`
  - `SettingsAppearanceView.swift`
  - `SettingsAIView.swift`
  - `SettingsExportView.swift`
  - `SettingsDataBackupView.swift`
  - `SettingsAboutLegalView.swift`
- 공통 모델:
  - `SettingsCategory`
  - `SettingsEntry`(id, title, keywords, priority, dependency)

## 9) 리스크 및 대응

- 리스크: 기존 사용자의 근육기억 깨짐
- 대응: 1버전 동안 “기존 위치에서 새 위치로 이동” 안내 배지 제공

- 리스크: 설정 분리 후 발견성 저하
- 대응: 검색 + 빠른 설정 + 최근 변경 항목 노출

- 리스크: 구현 중 상태 저장 회귀
- 대응: `@AppStorage` 키 유지, UI만 재배치하고 저장 키는 변경 금지

## 10) 참고 소스

- [Android Developers - Settings Pattern](https://developer.android.com/design/ui/mobile/guides/patterns/settings)
- [Microsoft Learn - Guidelines for app settings](https://learn.microsoft.com/en-us/windows/apps/design/app-settings/guidelines-for-app-settings)
- [Apple Support - Find options in System Settings on Mac](https://support.apple.com/en-asia/guide/mac-help/mchl8d10839d/mac)
- [Apple Support - Customize your Mac with System Settings](https://support.apple.com/en-us/HT201726)
- [Google Research (CHI 2010) - HEART Framework](https://research.google/pubs/measuring-the-user-experience-on-a-large-scale-user-centered-metrics-for-web-applications/)
- [MeasuringU - 10 Benchmarks for UX Metrics](https://measuringu.com/ux-benchmarks/)
- [MeasuringU - Four UX Metrics (Task Completion/SEQ 등)](https://measuringu.com/get-comfortable-with-four-ux-metrics/)
