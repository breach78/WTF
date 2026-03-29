# Main Workspace Phase 1 Stabilization Plan

상태:
- 이 문서는 `main_workspace_gingko_rearchitecture_plan.md`의 Phase 1 구현 후 발견된 회귀를 정리한 안정화 계획이다.
- 이 문서가 완료되기 전에는 `Phase 2`로 넘어가지 않는다.

현재 진행 순서:
- 1순위: 자식 없는 카드의 `Right` double-press fallback 복구
- 2순위: 메인 작업창 일반 화살표 이동의 세로 정렬 복구
- 3순위: 편집 경계 이동 후 active/scroll 재결합 복구
- 다음 페이즈: 위 3개가 모두 끝난 뒤에만 `Phase 2`

작업 범위 한 줄:
- 메인 작업창 Phase 1 적용 후 깨진 세로 정렬, 자식 없는 카드의 오른쪽 fallback, 편집 경계 이동 후 정렬 분리를 원인별로 복구한다.

왜 지금 멈추는가:
- 지금 상태는 "NavigationModel 분리"는 들어갔지만, 메인 작업창 주 경로의 parity가 깨져 있다.
- 이 상태에서 `ScrollPlan`으로 넘어가면, 이미 분리된 active/scroll 경로 위에 새 executor를 얹게 되어 회귀를 더 깊게 묻는다.
- 따라서 지금 필요한 것은 다음 페이즈 진입이 아니라 `Phase 1 안정화`다.

## 사용자 검증에서 확인된 회귀

1. 메인 작업창 세로 정렬 불안정
- 카드 포커스는 바뀌는데 세로 컬럼 정렬이 자주 따라오지 않는다.
- 즉, active change와 vertical focus apply가 다시 느슨하게 분리되었다.

2. 자식 없는 카드의 `Right` fallback 불능
- 첫 입력은 정상적으로 "무반응/arm"처럼 보이지만, 두 번째 입력에도 fallback 진입이 일어나지 않는다.
- 즉, 기존 2단계 right fallback 의미 체계가 새 navigation model에 온전히 복제되지 않았다.

3. 편집 경계 이동 후 정렬 완전 분리
- 편집기에 들어간 뒤 `Up/Down/Left/Right` 경계 이동을 하면 포커스만 움직이고 열 정렬은 맨 위 카드가 보이는 상태로 고착된다.
- 이후 어떤 조작을 해도 정렬 복구가 되지 않는다는 점에서 가장 위험한 회귀다.

## 범위

이 문서의 대상:
- `showFocusMode == false` 인 메인 작업창
- `performMainArrowNavigation`
- `changeActiveCard`
- 메인 작업창 active change -> vertical focus 경로
- 메인 편집 경계 이동 -> active/scroll 연결 경로

이 문서의 비범위:
- 포커스 모드
- 인덱스카드 뷰
- 히스토리 뷰
- `MainWorkspaceScrollPlan`
- `MainWorkspaceScrollExecutor`
- 활성 editor overwrite guard

주 작업 파일:
- `wa/WriterKeyboardHandlers.swift`
- `wa/WriterCardManagement.swift`
- `wa/WriterViews.swift`
- `wa/WriterSharedTypes.swift`

## 현재 판단

### A. 세로 정렬 불안정의 의미
- `publishPreemptiveMainColumnFocusNavigationIntent`는 제거되었고, 이 자체는 맞는 방향이다.
- 하지만 active change 이후 `publishMainColumnFocusNavigationIntent -> focusNavigationTick -> per-column focus apply` 경로가 모든 메인 작업창 전환을 안정적으로 다시 잡아주지 못하고 있다.
- 특히 메인 편집 경계 이동이나 일부 vertical transition에서 `pendingMainEditing...` 상태와 focus intent 소비 타이밍이 어긋나는 것으로 보인다.

### B. 오른쪽 fallback 불능의 의미
- 기존 동작은 "첫 입력 arm, 두 번째 입력 fallback"이었다.
- 새 model은 `activeHistory`를 쓰기 시작했지만, right fallback arm state와 최종 target 계산의 parity가 아직 맞지 않는다.
- 이 문제를 해결할 때 `activeHistory`는 유지하되, 기존 double-press 의미 체계는 그대로 복원해야 한다.

### C. 편집 경계 이동 붕괴의 의미
- `switchMainEditingTarget`은 원래 "active change + editing transition + vertical keep-visible"을 묶는 경로였다.
- 지금은 NavigationModel 분리 후 일반 navigation path와 editing boundary path의 계약이 다시 맞지 않는다.
- 이 경로를 복구하지 못하면 Phase 1은 실패다.

## 수정 순서

### Step 1. `Right` fallback parity 복구

목표:
- 자식 없는 카드에서 `Right` 첫 입력은 arm만 하고,
- 바로 이어 두 번째 입력에서는 기존 fallback target으로 실제 진입해야 한다.

수정 원칙:
- 새 `MainWorkspaceNavigationModel`은 유지한다.
- `activeHistory -> lastSelectedChildID` 우선순위는 유지한다.
- double-press arm semantics는 새 model과 호출부 사이에서 정확히 복원한다.

완료 기준:
- 자식 없는 카드에서 `Right` 2회 입력 시 기존 fallback과 동일하게 target이 활성된다.

### Step 2. 메인 작업창 active change -> 세로 정렬 계약 복구

목표:
- 메인 작업창에서 active card가 바뀌면 vertical focus apply가 다시 일관되게 따라오게 한다.

수정 원칙:
- preemptive scroll은 되살리지 않는다.
- 대신 "active change 이후 단일 focus intent"가 빠지지 않도록 메인 작업창 경로를 정리한다.
- `changeActiveCard`의 책임은 활성 적용까지만 유지하되, active change 직후 어떤 상태에서 vertical path가 깨지는지 명확히 좁힌다.

완료 기준:
- 메인 작업창 일반 화살표 이동에서 세로 정렬이 누락되지 않는다.
- 포커스만 움직이고 컬럼 정렬이 남는 상태가 재현되지 않는다.

### Step 3. 편집 경계 이동 경로 재결합

목표:
- 편집 중 `Up/Down/Left/Right` 경계 이동이 기존처럼 active card 이동과 vertical alignment를 함께 일으키게 한다.

수정 원칙:
- `switchMainEditingTarget`을 중심으로 복구한다.
- 편집 경계 이동은 일반 idle navigation과 같은 model을 일부 공유할 수는 있어도,
  active/editing/keep-visible 계약은 별도 경로로 명확히 유지한다.
- 편집 경계 이동을 일반 main navigation path에 억지로 합쳐서 봉합하지 않는다.

완료 기준:
- 편집기에 들어간 뒤 경계 이동을 해도 정렬이 깨지지 않는다.
- 한 번 깨진 뒤 열이 맨 위 카드에 고정되는 상태가 재현되지 않는다.

## 구현 순서별 체크포인트

### 체크포인트 1
- `Right` fallback이 먼저 복구되었는가
- 이 시점에는 vertical alignment 회귀가 남아 있어도 된다

### 체크포인트 2
- 메인 작업창 일반 화살표 이동에서 vertical alignment가 안정적인가
- preemptive 느낌 없이 active 이후에만 움직이는가

### 체크포인트 3
- 편집 진입 후 경계 이동에서 active/scroll이 다시 붙는가
- 이후 일반 navigation으로 돌아와도 정렬 상태가 깨지지 않는가

## 수용 기준

1. 메인 작업창 일반 화살표 이동에서 세로 정렬 누락이 재현되지 않는다.
2. 자식 없는 카드에서 `Right` 두 번째 입력 fallback이 기존처럼 동작한다.
3. 편집 중 경계 이동 `Up/Down/Left/Right` 후에도 정렬이 깨지지 않는다.
4. 정렬이 깨진 뒤 맨 위 카드가 보인 채 고착되는 상태가 재현되지 않는다.
5. `publishPreemptiveMainColumnFocusNavigationIntent` 같은 preemptive scroll 경로는 되살아나지 않는다.
6. `MainWorkspaceNavigationModel` 분리 자체는 유지된다.
7. 포커스 모드, 히스토리, 인덱스카드 뷰는 수정 범위에 끌려오지 않는다.

## 구현 중 금지

- 세로 정렬 회귀를 suppress flag 추가로 봉합하는 것
- `Right` fallback을 임시 하드코딩 분기로만 되살리는 것
- 편집 경계 이동 문제를 retry ladder로 덮는 것
- preemptive horizontal/vertical scroll을 다시 hot path에 넣는 것
- "일단 이 회귀는 Phase 2에서 함께 고치자"며 다음 페이즈로 넘기는 것

## 작업 완료 후 판단

- 이 문서의 수용 기준이 모두 통과하면 그때 다음 단계는 `Phase 2`다.
- 하나라도 실패하면 아직 `Phase 1 안정화` 상태이며, `Phase 2`로 가지 않는다.
