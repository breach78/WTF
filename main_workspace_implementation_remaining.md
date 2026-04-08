# Main Workspace 구현 잔여 작업 계획

상태: `main_workspace_gingko_parity_plan_v2.md`의 Phase 0-6 완료 이후, 현재 코드 기준으로 다시 정리한 잔여 작업 문서.

기준:
- 메인 작업창 일반 모드는 이미 `MainWorkspaceSurface + MainWorkspaceDocRuntime.changeMode + MainWorkspaceDirectScroll` 경로를 사용한다.
- 이 문서는 "이미 끝난 phase를 다시 설명"하지 않고, 지금 실제로 남아 있는 문제만 다룬다.

작업 범위 한 줄:
- 메인 작업창 일반 모드에서 아직 남아 있는 parity gap과 사용자 기능 gap만 정리하고 우선순위를 다시 잡는다.

## 이미 끝난 항목

아래는 이 문서에서 다시 추진하지 않는다.

| 항목 | 상태 |
|------|------|
| `MainWorkspaceDocRuntime.changeMode` 도입 | ✅ 완료 |
| `MainWorkspaceTreeProjection` 도입 | ✅ 완료 |
| `MainWorkspaceSurface` AppKit canvas 도입 | ✅ 완료 |
| `MainWorkspaceDirectScroll` 단일 경로화 | ✅ 완료 |
| 메인 작업창 일반 모드 feature flag 제거 | ✅ 완료 |
| 메인 작업창 일반 모드 old hot path 제거 | ✅ 완료 |
| `MainWorkspaceEditSession` 기반 인라인 편집 | ✅ 완료 |
| 편집 중 native text undo / 비편집 history checkout 분리 | ✅ 완료 |

주의:
- 코드베이스 전체에서 legacy helper가 완전히 사라진 것은 아니다.
- 다만 메인 작업창 일반 모드의 활성 전환 hot path를 다시 legacy 쪽으로 되돌리는 작업은 금지한다.

## 현재 남아 있는 일

남은 일은 네 묶음이다.

1. 스크롤 parity의 마지막 로직 차이
2. parity를 자동으로 검증할 수 있는 harness 보강
3. 편집/조작 완성도 보강
4. 제품 기능 parity 보강

## 1. 즉시 수정해야 할 parity gap

### R1. 세로 스크롤 animation 전달 누락

위치:
- `wa/MainWorkspaceDirectScroll.swift`

현재 상태:
- `performMainWorkspaceDirectScroll(..., animated:)` 시그니처는 존재한다.
- 하지만 세로 적용 단계에서는 실제로 항상 instant path만 사용한다.

영향:
- 가로와 세로의 전환 감각이 다르다.
- click / keyboard navigation에서 세로가 항상 점프처럼 보일 수 있다.

수정 방향:
- `MainWorkspaceColumnScrollAlignment`에 `animated`를 포함한다.
- alignment 생성 시 outer `animated` 값을 그대로 전달한다.
- vertical apply에서 animated면 animated path를, 아니면 instant path를 사용한다.
- viewport capture suspend duration도 animated/instant에 맞춰 나눈다.

완료 기준:
- 같은 입력에 대해 가로/세로 모두 animation 의도가 동일하게 전달된다.

### R2. `between` target이 gap midpoint를 반영하지 않음

위치:
- `wa/MainWorkspaceDirectScroll.swift`

현재 상태:
- `.between(afterID, beforeID)`에서도 사실상 `afterID` frame bottom만 기준으로 삼는다.

영향:
- 카드 사이 gap이 큰 경우 target offset이 징코 의미와 어긋난다.

수정 방향:
- `afterFrame.maxY`와 `beforeFrame.minY` 사이의 midpoint를 anchor로 계산한다.
- 겹침이 있으면 기존처럼 `afterFrame.maxY` fallback을 유지한다.

완료 기준:
- `between` policy가 "둘 사이"를 실제로 의미한다.

### R3. descendant selection이 subtree flat history sort로 남아 있음

위치:
- `wa/MainWorkspaceDirectScroll.swift`

현재 상태:
- root 아래 전체 subtree를 flat하게 history rank 정렬한 뒤 첫 visible card를 고른다.

문제:
- 징코는 depth별로 한 단계씩 내려가며 child를 고른다.
- 지금 방식은 깊은 열 대신 얕은 열의 history 상위 카드가 먼저 선택될 수 있다.

수정 방향:
- depth-by-depth continuation 선택으로 바꾼다.
- `MainWorkspaceTreeProjection.preferredContinuationChild`와 같은 의미의 선택 규칙을 재사용하거나 공통 함수로 뺀다.
- 규칙은 `history 우선 -> lastSelectedChildID -> stable first child` 순서를 유지한다.

완료 기준:
- descendant 선택이 "subtree 전체 우선순위"가 아니라 "컬럼별 continuation 경로"를 따른다.

### R4. dead code `recordMainWorkspaceActiveHistory` 제거

위치:
- `wa/WriterCardManagement.swift`

현재 상태:
- `changeMode` 도입 이후 owner가 바뀌었는데, 함수 정의만 남아 있다.

수정 방향:
- 호출처가 없음을 확인한 뒤 삭제한다.

완료 기준:
- active history owner는 문서와 코드 모두 `changeMode` 하나로 정리된다.

## 2. 검증 인프라 보강

### V1. Phase 0 parity harness에 validator 추가

위치:
- `wa/MainWorkspacePhase0ParityHarness.swift`

현재 상태:
- reference JSON과 checklist는 생성한다.
- 현재 구현을 reference와 대조하는 validator는 없다.

필요한 이유:
- R1-R3 같은 parity 수정은 눈으로만 확인하면 다시 흔들리기 쉽다.

작업:
- reference JSON을 읽어서 현재 계산 결과와 비교하는 validator를 추가한다.
- fixture별 policy 비교를 넣는다.
- target offset 비교를 넣는다.
- tolerance는 소수점/픽셀 rounding을 고려해 작게 둔다.
- 실패 결과는 별도 JSON으로 떨군다.

완료 기준:
- scroll parity 수정 후 자동으로 mismatch를 볼 수 있다.

권장 산출물:
- `/tmp/wa_main_workspace_phase0_failures.json`

## 3. 편집 완성도 보강

### E1. 편집기 키보드 단축키 보강

위치:
- `wa/MainWorkspaceEditSession.swift`

현재 상태:
- Escape 성격의 cancel은 처리된다.
- `Cmd+Enter`, `Tab` 등 편집 종료/이동 관련 단축키는 아직 표면적으로 없다.

작업:
- `doCommandBy` 또는 `TextView.keyDown`에서 필요한 명령만 명시적으로 처리한다.
- `Cmd+Enter`는 편집 완료로 연결한다.
- `Tab`의 의미는 현재 WA 편집 모델과 충돌하지 않게 좁게 정의한다.

완료 기준:
- 편집 세션 종료가 mouse 중심이 아니라 keyboard에서도 완결된다.

### E2. card metrics parity 고정

대상:
- `MainWorkspaceSurfaceCardView`
- 카드 측정/예측 frame 계산 경로

현재 상태:
- 기본 metrics는 맞춰져 있지만, scroll target 정확도 관점에서 golden 검증이 아직 없다.

작업:
- 실제 렌더 metrics와 predicted frame 계산이 같은 font, line spacing, padding 규칙을 공유하도록 정리한다.
- magic number가 흩어져 있으면 공통 metric source로 모은다.

완료 기준:
- predicted frame과 observed frame 차이가 scroll parity를 흔들지 않는다.

## 4. 제품 기능 parity

### P1. 컨텍스트 메뉴

대상:
- `wa/MainWorkspaceSurface.swift`
- `wa/MainWorkspaceSnapshot.swift`
- 기존 writer action 연결부

현재 상태:
- surface card view는 좌클릭/더블클릭만 처리한다.

작업:
- card view에 우클릭 진입점을 추가한다.
- surface callback에 context menu action hook을 추가한다.
- 기존 delete/copy/paste/color 등 writer action을 surface 경로에 연결한다.

완료 기준:
- main workspace surface 카드에서 우클릭 조작이 가능하다.

### P2. 드래그 앤 드롭

대상:
- `wa/MainWorkspaceSurface.swift`
- 기존 move/drop action 연결부

현재 상태:
- main workspace surface 경로에는 drag/drop이 아직 없다.

작업:
- dragging source / destination을 surface 경로에 붙인다.
- drop indicator와 drop target 계산을 만든다.
- 기존 `handleGeneralDrop`, `executeMoveSelection`을 최대한 재사용한다.

완료 기준:
- 카드 이동이 새 surface 경로에서도 가능하다.

주의:
- 이 항목은 구현량이 크다.
- `MainWorkspaceSurface.swift`가 비대해지기 전에 drag/drop seam 분리가 선행되어야 한다.

### P3. 카드 chrome 보강

대상:
- `wa/MainWorkspaceSurface.swift`

현재 상태:
- 현재 카드는 text + active tint 중심의 최소 표현이다.

후순위 이유:
- scroll parity나 조작 parity보다 시급하지 않다.

후보:
- 링크 카드 badge
- AI 상태 표시
- clone 표시
- 색상 tag

완료 기준:
- 시각 정보가 기존 production card와 필요한 수준까지 맞는다.

## 5. undo에 대한 현재 판단

이 항목은 "즉시 해야 하는 남은 일"이 아니라 별도 판단이 필요한 후속 과제다.

현재 상태:
- 메인 작업창 일반 모드에서 command routing은 이미 분리됐다.
- 편집 중은 native text undo를 사용한다.
- 비편집 상태는 `MainWorkspaceHistoryStore`를 통해 history head checkout을 수행한다.

남아 있는 구조적 차이:
- 현재 `MainWorkspaceHistoryStore`는 disk-backed immutable commit store가 아니라, 기존 snapshot timeline을 감싼 head 관리 레이어에 가깝다.

의사결정:
- 목표가 "사용자 체감 parity"면 이 항목은 뒤로 미뤄도 된다.
- 목표가 "징코의 저장/복원 철학까지 구조적으로 동일"이면 별도 설계 문서로 분리해서 진행한다.

이 문서에서는:
- true commit store 전환을 즉시 착수 항목으로 두지 않는다.
- 대신 scroll/interaction parity를 먼저 끝낸다.

## 권장 실행 순서

### 1차: parity 정확도 고정

- R1 세로 animation 전달
- R2 between midpoint
- R3 depth-by-depth descendant selection
- R4 dead code 제거
- V1 parity validator

이 묶음의 목표:
- "지금 direct scroll이 거의 맞다"를 "자동으로 검증 가능한 상태"로 바꾼다.

### 2차: 편집 완결성

- E1 편집기 키보드 단축키
- E2 card metrics parity 고정

이 묶음의 목표:
- 편집 경험과 scroll target 정확도를 함께 안정화한다.

### 3차: 제품 parity

- P1 컨텍스트 메뉴
- P2 드래그 앤 드롭

이 묶음의 목표:
- surface 경로를 기능적으로도 기존 작업 흐름의 주력 경로로 완성한다.

### 4차: 후속 판단

- P3 카드 chrome
- true immutable commit store 전환 여부

## 이번 문서에서 명시적으로 제외하는 것

다음 항목은 이 문서의 "남은 일"로 다시 넣지 않는다.

- Phase 1-6 재서술
- 메인 작업창 일반 모드 feature flag 제거
- 메인 작업창 일반 모드 old path 최종 삭제
- `MainWorkspaceHistoryStore`라는 이름의 새 타입을 다시 만드는 일

## 파일별 예상 수정 범위

| 항목 | 파일 | 예상 규모 |
|------|------|----------|
| R1 | `wa/MainWorkspaceDirectScroll.swift` | 소규모 |
| R2 | `wa/MainWorkspaceDirectScroll.swift` | 소규모 |
| R3 | `wa/MainWorkspaceDirectScroll.swift` | 중간 |
| R4 | `wa/WriterCardManagement.swift` | 매우 작음 |
| V1 | `wa/MainWorkspacePhase0ParityHarness.swift` | 중간 |
| E1 | `wa/MainWorkspaceEditSession.swift` | 소규모 |
| E2 | `wa/MainWorkspaceSurface.swift` 외 metrics 공유부 | 중간 |
| P1 | `wa/MainWorkspaceSurface.swift`, `wa/MainWorkspaceSnapshot.swift` | 중간 |
| P2 | `wa/MainWorkspaceSurface.swift` 중심, 필요 시 분리 | 큼 |

## 최종 판단

현재 가장 좋은 다음 작업은 새 기능을 더 붙이는 것이 아니라, direct scroll parity의 마지막 세 차이와 validator를 먼저 끝내는 것이다.

이유:
- 이 구간이 고정돼야 이후 context menu / drag-drop 추가 중에도 scroll regression을 바로 잡아낼 수 있다.
- 반대로 여기서 검증 없이 기능을 먼저 얹으면 다시 "겉보기로는 동작하지만 parity는 흔들리는 상태"로 돌아가기 쉽다.
