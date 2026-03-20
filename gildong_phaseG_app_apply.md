# 길동 Phase G - 앱 트리 반영

- 기준 패키지: `/Users/three/Documents/시나리오 작업/ver3/1st_app.wtf`
- 대상 시나리오 ID: `B6F21CB6-BC46-42FA-B500-6AA87BB2D468`
- ai 루트 ID: `C0DAD9E7-4E76-4F03-9E3E-177D47B195B0`
- 백업 인덱스: `/Users/three/app_build/wa/gildong_phaseG_cards_index.backup.json`

## 1. 수행 내용

- 기존 `시작/중간1/중간2/끝` 하위의 visible 브랜치를 전부 archive 처리했다.
- 4막 카드는 재사용하고, 각 카드 본문을 Phase A의 막 요약으로 교체했다.
- 샘플 브랜치로 `개요 01` 전체 하위 구조를 먼저 구성해 검증한 뒤 나머지 개요 브랜치를 확장했다.
- 최종 구조는 `4막 -> 개요 -> 시놉시스 -> 시퀀스 -> 트리트먼트 -> 원문`이다.

## 2. 생성 결과

- 4막 재사용: 4
- 개요: 11
- 시놉시스: 22
- 시퀀스: 48
- 트리트먼트: 116
- 원문: 116
- 이번에 archive된 기존 visible descendant: 169

## 3. 검증

- 원문 카드 해시 불일치: 0
- Phase F 기준 원문 일치 상태 승계: true
- 샘플 브랜치: 개요 01 / 시놉시스 2 / 시퀀스 5 / 트리트먼트 13 / 원문 13

## 4. 4막 visible child 수

- 시작: 3
- 중간1: 2
- 중간2: 3
- 끝: 3

