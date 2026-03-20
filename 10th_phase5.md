# 길동 10고 Phase 5 - 카드 기록 설계 잠금

- 기준 원고: `/Users/three/Library/Mobile Documents/iCloud~md~obsidian/Documents/gaenari/pages/길동 9고 final.md`
- 기준 고정값: `3834 lines / 151177 bytes / sha256 c1a3bea5a3b46a437e141472d4dbc78baecf7c550f75b731c9648f40417f6189`
- 대상 패키지: `/Users/three/Documents/시나리오 작업/ver3/1st_app.wtf`
- 대상 시나리오: `길동 10고`
- 시나리오 ID: `B6F21CB6-BC46-42FA-B500-6AA87BB2D468`
- 루트 카드: `길동 > 플롯 > ai`
- `ai` 카드 ID: `C0DAD9E7-4E76-4F03-9E3E-177D47B195B0`

## 1. 실제 `.wtf` 저장 구조

`1st_app.wtf`는 단일 파일이 아니라 디렉터리 패키지다.

핵심 구조:

- `/Users/three/Documents/시나리오 작업/ver3/1st_app.wtf/scenarios.json`
- `/Users/three/Documents/시나리오 작업/ver3/1st_app.wtf/scenario_B6F21CB6-BC46-42FA-B500-6AA87BB2D468/cards_index.json`
- `/Users/three/Documents/시나리오 작업/ver3/1st_app.wtf/scenario_B6F21CB6-BC46-42FA-B500-6AA87BB2D468/card_<CARD_ID>.txt`
- `/Users/three/Documents/시나리오 작업/ver3/1st_app.wtf/scenario_B6F21CB6-BC46-42FA-B500-6AA87BB2D468/history.json`
- `/Users/three/Documents/시나리오 작업/ver3/1st_app.wtf/scenario_B6F21CB6-BC46-42FA-B500-6AA87BB2D468/linked_cards.json`

실제 관찰 결과:

- 카드 본문은 `card_<CARD_ID>.txt` 파일의 raw UTF-8 텍스트다.
- 계층 구조는 `cards_index.json`의 배열 원소로 관리된다.
- 카드 제목을 따로 저장하는 필드는 없고, 카드가 보여 주는 텍스트는 결국 `card_<CARD_ID>.txt` 내용이다.
- `history.json`과 `linked_cards.json`은 기본 카드 표시/계층 로드에 필수는 아니었다.

## 2. `cards_index.json` 필수 필드

샘플 직접 삽입으로 확인한 최소 필드:

- `id`
- `category`
- `createdAt`
- `isArchived`
- `isFloating`
- `orderIndex`
- `parentID`
- `scenarioID`
- `schemaVersion`

부모 카드에 자식이 생길 때 추가/갱신하는 필드:

- `lastSelectedChildID`

실무 규칙:

- `scenarioID`는 항상 `B6F21CB6-BC46-42FA-B500-6AA87BB2D468`
- `schemaVersion`는 `3`
- 이번 트리의 카테고리는 전부 `플롯`
- `isFloating`는 `false`
- 새 카드의 `orderIndex`는 `같은 parentID를 가진 기존 카드들 전체(archived 포함)`의 최대값 + 1

## 3. 최종 카드 트리 규칙

최종 계층:

```text
길동
  플롯
    ai
      시작
        개요 01
          시놉시스 01
            시퀀스 01
              트리트먼트 01
                [원문 씬 카드]
```

고정 규칙:

- `ai` 아래 최상위 카드는 오직 `시작 / 중간1 / 중간2 / 끝`
- `4막 -> 개요 -> 시놉시스 -> 시퀀스 -> 트리트먼트 -> 원문` 순서만 허용
- `트리트먼트 다음에는 별도 씬 요약 카드 없음`
- 최종 말단은 `원문 씬 카드`만 존재

## 4. 카드 본문 규칙

### 4-1. 4막 카드

- 본문은 막 이름만 사용
- 예: `시작`

### 4-2. 개요 / 시놉시스 / 시퀀스 / 트리트먼트 카드

- 본문 포맷:

```text
<라벨 + 번호 + 제목 + 범위>

<산문형 본문>
```

- 즉, 첫 줄은 식별용 제목
- 둘째 줄은 빈 줄
- 그 아래는 산문형 본문

예:

```text
트리트먼트 01 | 칼의 기억과 불타는 조창 | 001-006

어린 길은 문경 시장에서...
```

### 4-3. 원문 씬 카드

- 본문은 원문만 사용
- 번호, 라벨, 설명, 범위, 접두어, 접미어를 절대 덧붙이지 않음
- 카드 본문 = `해당 씬 헤딩 시작 ~ 다음 씬 헤딩 직전` 슬라이스
- 공백, 빈 줄, 줄바꿈까지 그대로 유지

## 5. 직접 쓰기 검증 결과

### 5-1. 샘플 직접 삽입

직접 파일 수정으로 아래 샘플 체인을 만들었고, 앱 재실행 후 정상 로드됨을 확인했다.

- 샘플 4막: `A3D821E8-E20A-43D1-B152-97933E2065F0`
- 샘플 개요: `AC7C7BAB-B7CD-4593-8E13-53161079E6AF`
- 샘플 시놉시스: `82EE2C9A-E81A-4010-BA5F-440D0C5EB705`
- 샘플 시퀀스: `67F425E3-A4B6-45B4-AFAF-A1D6F8EF95A3`
- 샘플 트리트먼트: `7DEBDD22-6C1C-4C23-92FF-7B4EEC73504C`
- 샘플 원문 카드: `C300426E-2A23-49C3-BB7E-735A4A5FEDB5`

검증 방식:

- `cards_index.json`에 메타데이터 6개 직접 추가
- `card_<id>.txt` 6개 직접 생성
- `history.json`, `linked_cards.json`은 수정하지 않음
- 앱 재실행 후 샘플 체인 전체가 실제 카드 트리로 로드됨 확인

### 5-2. 원문 무결성 해시 검증

샘플 원문 카드는 `씬 056`을 사용했다.

- 원문 카드 경로:
  `/Users/three/Documents/시나리오 작업/ver3/1st_app.wtf/scenario_B6F21CB6-BC46-42FA-B500-6AA87BB2D468/card_C300426E-2A23-49C3-BB7E-735A4A5FEDB5.txt`
- 기준 원고 슬라이스 SHA-256:
  `6379f4ec5e12e40798bd277ce582ae52cf623186cd5b228826a76e2099143691`
- 기록된 카드 SHA-256:
  `6379f4ec5e12e40798bd277ce582ae52cf623186cd5b228826a76e2099143691`
- 결과:
  `match = true`

의미:

- direct file write 경로는 최소한 `씬 056` 샘플에서 줄바꿈과 빈 줄까지 그대로 보존했다.
- 따라서 최종 원문 카드는 앱 API가 아니라 `card_<id>.txt` 직접 기록 방식으로 쓰는 것이 안전하다.

## 6. 정리 상태

- 샘플 카드는 검증 후 모두 `archived = true`로 전환했다.
- `ai` 루트의 `lastSelectedChildID`는 기존 값 `B8F10649-6D1F-47C6-8F50-87FC6BE7B39D`로 복구했다.
- 샘플 본문 파일은 증빙용으로 남겨 두었다.
- 백업 파일:
  `/Users/three/app_build/wa/10th_phase5_cards_index.backup.json`
- 샘플 메타 기록:
  `/Users/three/app_build/wa/10th_phase5_sample.json`

## 7. Phase 5 결론

- `.wtf` 직접 수정 경로를 파악했다.
- 원문 카드의 안전 경로는 `cards_index.json + card_<id>.txt 직접 기록`이다.
- 최종 카드 작성 시 `history.json`, `linked_cards.json`은 건드리지 않아도 기본 트리 로드는 가능하다.
- 다음 페이즈에서는 이 규칙대로 `4막 -> 개요 -> 시놉시스 -> 시퀀스 -> 트리트먼트 -> 원문` 전체를 `ai` 아래에 실제 카드로 쓴다.
