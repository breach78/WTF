# wa 사용자 가이드

`wa`는 macOS용 시나리오/스토리 카드 작성 앱입니다. 카드 트리(부모-자식) 구조로 이야기를 관리하고, 히스토리 스냅샷, AI 보조(Gemini), 음성 받아쓰기(Whisper), PDF/텍스트 내보내기를 제공합니다.

## 1) 앱이 하는 일

- 시나리오를 카드 단위로 작성/정리
- 카드 계층(부모/자식/형제) 이동 및 편집
- 스냅샷 기반 히스토리 탐색/복구
- AI 후보 생성 및 선택 반영
- 음성 받아쓰기 -> 원문/요약 카드 자동 추가
- 텍스트/PDF(중앙정렬식, 한국식) 출력

## 2) 시스템 요구사항

- macOS + Xcode 환경에서 빌드/실행
- Swift 5.0 (`wa.xcodeproj/project.pbxproj`)
- 프로젝트 타겟/스킴: `wa`
- 배포 타겟: `MACOSX_DEPLOYMENT_TARGET = 26.2` (프로젝트 설정값 기준)

## 3) 실행 방법

### Xcode로 실행

1. `wa.xcodeproj`를 Xcode에서 엽니다.
2. Scheme을 `wa`로 선택합니다.
3. Run (`Cmd + R`)으로 앱을 실행합니다.

### CLI로 빌드 확인

```bash
xcodebuild -project "wa.xcodeproj" -scheme "wa" -configuration Debug build
```

## 4) 첫 실행: 작업 파일(.wtf) 선택

앱은 시나리오 저장소를 `.wtf` 패키지 파일로 관리합니다.

- `기존 작업 파일 열기`: 이미 있는 `.wtf` 선택
- `새 작업 파일 만들기`: 새 `.wtf` 생성

선택한 경로는 보안 북마크(Security-Scoped Bookmark)로 저장되어 다음 실행 때 자동 복원됩니다.

## 5) 기본 사용 흐름

### 5-1. 시나리오 만들기

- 좌측 사이드바에서 `새 시나리오 추가`
- 생성 방식
  - `클린 시나리오`
  - `템플릿에서 생성`

### 5-2. 카드 편집

- `Return`: 선택 카드 편집 시작
- `Tab`: 자식 카드 추가
- `Cmd + Up/Down`: 위/아래 형제 카드 추가
- `Cmd + Right`: 자식 카드 추가
- 드래그 앤 드롭으로 카드 이동

### 5-3. 집중 모드

- `Cmd + Shift + F`: 집중 모드 토글
- 집중 모드에서 카드 간 키보드 이동/편집 가능
- `Cmd + Shift + T`: 타이프라이터 모드 토글

### 5-4. 히스토리/체크포인트

- 상단 `깃발` 버튼: 이름 있는 분기점(체크포인트) 생성
- 상단 `히스토리` 버튼: 타임라인 열기
- 이전 상태 미리보기 후 해당 시점으로 복구 가능

### 5-5. AI 보조 (Gemini)

- 타임라인 패널에서 AI 액션 실행
  - 구체화, 다음 장면, 대안, 요약
- 후보 카드 생성 후 원하는 후보를 선택해 반영
- API 키는 설정 창에서 Keychain에 저장/삭제

### 5-6. 받아쓰기 (Whisper)

- 마이크 버튼으로 받아쓰기 시작/종료
- 처리 완료 시
  - `받아쓰기 원문` 카드
  - `받아쓰기 요약` 카드
  가 부모 카드 아래에 자동 생성

### 5-7. 출력

- 타임라인 패널의 `출력` 메뉴
  - 클립보드 복사
  - 텍스트 파일 저장
  - 중앙정렬식 PDF 저장
  - 한국식 PDF 저장

## 6) 주요 단축키

아래는 앱 내 단축키 도움말에 정의된 핵심 조합입니다.

### 공통

- `Cmd + Z`: 실행 취소
- `Cmd + Shift + Z`: 다시 실행
- `Cmd + F`: 검색창 열기/닫기
- `Cmd + Shift + F`: 집중 모드 토글
- `Cmd + Shift + ]`: 전체 카드(타임라인) 패널 토글

### 메인 작업 모드

- `Arrow`: 카드 이동
- `Return`: 편집 시작
- `Tab`: 자식 카드 추가
- `Cmd + Up/Down`: 형제 카드 추가
- `Cmd + Return`: 편집 종료 후 아래 형제 카드 추가
- `Cmd + Shift + Delete`: 선택 카드(묶음) 삭제
- `Cmd + Shift + Arrow`: 카드 계층 이동

### 히스토리 모드

- `Left/Right`: 이전/다음 시점
- `Cmd + Left/Right`: 이전/다음 네임드 스냅샷
- `Esc`: 검색/편집 종료 또는 히스토리 닫기

### 레퍼런스 창

- `Cmd + Option + R`: 레퍼런스 창 열기

## 7) 설정(Preferences)

설정 창에서 다음 항목을 관리할 수 있습니다.

- 편집/테마
  - 다크 모드
  - 폰트 크기
  - 메인 줌
  - 메인/포커스 행간
  - 색상 프리셋/직접 색상 선택
- 출력/AI/저장
  - PDF 출력 옵션(중앙정렬식/한국식)
  - Gemini 모델 선택, API 키 저장/삭제
  - Whisper 경로 저장/설치 상태 확인/자동 설치
  - 작업 파일(.wtf) 열기/생성/초기화
- 단축키 목록

## 8) 데이터 저장 구조

작업 파일 `.wtf` 내부(패키지)는 시나리오별 JSON/텍스트 파일로 구성됩니다.

- `scenarios.json`: 시나리오 메타 정보
- `scenario_<UUID>/cards_index.json`: 카드 인덱스
- `scenario_<UUID>/history.json`: 히스토리 스냅샷
- `scenario_<UUID>/card_<UUID>.txt`: 카드 본문 텍스트

앱은 변경사항을 디바운스 저장하고, 종료 시점에 pending save를 flush합니다.

## 9) 권한/네트워크

- 마이크/음성 인식 권한 필요(받아쓰기 사용 시)
- Gemini API 호출을 위한 외부 네트워크 사용
- Whisper 자동 설치 시 `git`, `cmake` 및 모델 다운로드 네트워크 필요

## 10) 문제 해결

### Q1. 작업 파일이 안 열립니다.

- `.wtf` 확장자 파일인지 확인
- 설정에서 `작업 파일 초기화(다시 선택)` 후 다시 열기
- 파일 접근 권한이 끊긴 경우(북마크 stale) 다시 선택하면 복구됨

### Q2. AI가 동작하지 않습니다.

- 설정에서 Gemini API 키 저장 여부 확인
- 모델 ID를 기본값(`gemini-3-pro-preview`) 또는 지원 모델로 변경

### Q3. 받아쓰기가 안 됩니다.

- macOS 마이크/음성 인식 권한 허용 확인
- 설정 -> Whisper 상태 확인
- CLI/모델 경로 점검 또는 `자동 설치 / 업데이트` 실행

### Q4. PDF 출력이 비어 있습니다.

- 활성 카드가 있는지 확인
- 출력 대상 텍스트가 비어 있지 않은지 확인

## 11) 참고 파일

- 앱 진입/설정/단축키/워크스페이스: `wa/waApp.swift`
- 메인 편집 화면: `wa/WriterViews.swift`
- 카드 편집/이동/출력: `wa/WriterCardManagement.swift`
- 히스토리/타임라인: `wa/WriterHistoryView.swift`
- AI 보조: `wa/WriterAI.swift`, `wa/GeminiService.swift`, `wa/KeychainStore.swift`
- 받아쓰기: `wa/WriterSpeech.swift`, `wa/WhisperSupport.swift`
- 저장 모델: `wa/Models.swift`
- Xcode 빌드 설정: `wa.xcodeproj/project.pbxproj`
