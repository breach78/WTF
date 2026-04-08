# 📝 시나리오/웹소설 작가를 위한 전문 에디터 앱 청사진 (Blueprint)

이 문서는 제공된 소스코드(`Models.swift`, `WriterViews.swift`, `WriterFocusMode.swift`, `WriterAI...`)를 바탕으로 앱의 모든 기능, 데이터 구조, 렌더링 방식 및 고급 기능(AI, RAG 등)을 밑바닥부터 심층까지 해부한 마스터플랜입니다.

---

## 🗺️ 1. 앱 시스템 아키텍처 다이어그램 (Tree Structure)

이 앱은 단순한 텍스트 에디터가 아닌 **"노드(Card) 기반의 계층형 텍스트 에디터 + AI RAG 시스템"**입니다.

```text
📦 시나리오 작가 앱 (Scenario Writer)
 ┣ 📂 1. 데이터 레이어 (Data & Persistence)
 ┃ ┣ 💾 FileStore (디스크 저장소: JSON, SQLite 백업)
 ┃ ┣ 📜 Scenario (프로젝트 단위: 상태 관리, 델타 변경 추적, 히스토리)
 ┃ ┗ 📇 SceneCard (최소 단위 노드: 트리 구조, 클론 연동, 부모-자식 관계)
 ┃
 ┣ 📂 2. 코어 워크스페이스 (Main UI & Layout)
 ┃ ┣ 🪟 ScenarioWriterView (God View - 전체 레이아웃 조정)
 ┃ ┣ ✂️ Split Pane Mode (좌우 화면 분할 모드)
 ┃ ┣ 툴바 (상단 툴바: 모드 전환, AI, 타임라인 등 접근)
 ┃ ┗ 📊 Index Board / Timeline (구조화된 뷰: 사이드바 및 보드 형태)
 ┃
 ┣ 📂 3. 에디팅 및 상호작용 (Interaction & Editing)
 ┃ ┣ ✏️ Main Canvas (노드 트리 뷰: 카드 더블클릭 편집, 드래그앤드롭)
 ┃ ┣ 📋 Clipboard/Paste (클론 복사, 트리 복사, Fountain 스크립트 분할 붙여넣기)
 ┃ ┗ 🎙️ Dictation (음성 인식 받아쓰기 모드)
 ┃
 ┣ 📂 4. 📝 포커스 모드 (Focus Mode - 깊은 몰입 기능)
 ┃ ┣ 📜 Continuous Scroll (개별 카드를 하나의 문서처럼 연결하여 렌더링)
 ┃ ┣ ⌨️ Typewriter Mode (타자기 모드: 캐럿(커서)을 화면 중앙에 고정)
 ┃ ┣ ↕️ Boundary Navigation (방향키로 카드 간 심리스 이동)
 ┃ ┗ 🔍 Focus Mode Search (포커스 모드 전용 인라인 검색 및 하이라이트)
 ┃
 ┗ 📂 5. 🤖 AI 및 RAG 시스템 (Deepest Layer)
   ┣ 💬 AI Chat (상담 스레드, 컨텍스트 스코프 설정)
   ┣ 🧠 Semantic RAG (Gemini 임베딩 API 활용)
   ┣ 🗄️ Vector SQLite Store (카드 내용을 벡터화하여 로컬 SQLite에 저장)
   ┗ ⚙️ Action Generator (AI 답변을 현재 카드에 병합하거나 자식 카드로 생성)


🧱 2. 코어 데이터 모델 (가장 기초 단계)

앱의 모든 기능은 이 데이터 모델 위에서 동작합니다. @​Published와 수동 버전 트래킹(cards​Version)을 혼합하여 대규모 데이터에서도 뷰 업데이트 병목을 막습니다.

2.1. Scene​Card (씬 카드)
• 개념: 글의 최소 단위 (문단, 씬, 설정 등).
• 구조: 부모(parent)와 자식(children)을 가지는 트리 노드입니다.
• 주요 속성:
   • content: 카드의 텍스트 내용. 변경 시 클론 그룹(clone​Group​ID)에 동기화 전파.
   • order​Index: 형제 노드 간의 정렬 순서.
   • category: 플롯, 노트, 캐릭터, 세계관 등 카드의 종류.
   • clone​Group​ID: 같은 그룹 ID를 가진 카드들은 텍스트 수정 시 내용과 색상(color​Hex)이 실시간 동기화됨.

2.2. Scenario (시나리오)
• 개념: 하나의 프로젝트(책, 대본)를 나타냅니다.
• 주요 역할:
   • 모든 Scene​Card를 리스트로 보유하고, 메모리 내에서 인덱스(캐싱)를 구축하여 루트/자식 트리를 빠르게 반환합니다.
   • Debounced Mutation: 변경 사항(mark​Modified)을 모아두었다가 일정 시간(0.14초) 후 한 번에 타임스탬프를 업데이트하여 디스크 I/O 과부하를 방지합니다.
   • 히스토리 & 링크: 스냅샷(History​Snapshot), 연결된 카드(linked​Card​Edit​Dates​By​Focus​Card​ID), 분할 화면 활성 상태 관리.

2.3. File​Store (파일 시스템)
• 저장 방식: JSON 파일(scenarios​.json, cards​_index​.json, card_*.txt) 기반이며, 각 카드 내용은 별도의 .txt 파일로 저장하여 깃(Git)과 같은 버전 관리에 유리하도록 설계되었습니다.
• 비동기 I/O: Dispatch​Queue를 활용한 백그라운드 저장. 스키마 버전을 추적하며 변경된 카드/시나리오만 델타(Delta) 저장.
• Auto Backup: 작업 종료 시 작업 폴더 전체를 압축(Zip/Archive)하여 지정된 백업 폴더에 저장.

⸻

🖥️ 3. UI 레이아웃 및 워크스페이스 아키텍처

거대한 Scenario​Writer​View가 중앙 컨트롤 타워 역할을 하며 모드에 따라 뷰를 교체합니다.

3.1. 화면 분할 (Split Pane Mode)
• 좌/우 두 개의 패널(1번, 2번)로 나누어 같은 시나리오의 다른 부분을 동시에 볼 수 있습니다.
• is​Split​Pane​Active 상태를 통해 현재 키보드 입력을 받는 활성 창을 추적.
• Auto-Link (자동 연결): 분할 화면에서 한쪽 카드를 보고 다른 쪽을 편집하면, 두 카드 간의 관계(Linked)를 자동으로 기록합니다.

3.2. 렌더링 최적화 패턴 (Fingerprinting)
• SwiftUI의 뷰 재계산을 최소화하기 위해 Main​Canvas​Render​State 같은 상태 구조체를 만들고, 데이터 상태를 정수 해시(content​Fingerprint, navigation​Fingerprint)로 변환하여 뷰에 주입합니다.

3.3. 사이드 패널 및 보조 뷰
• Timeline: 글의 전체 흐름(트리)을 왼쪽/오른쪽 패널에서 계층적으로 보여줍니다.
• Index Board: 시나리오를 코르크보드 형식의 격자로 배치하여 시각적으로 플롯을 구조화하는 모드.
• History Bar: 하단에 표시되는 타임라인 UI로, 과거 스냅샷으로 롤백하거나 프리뷰(Diff)를 볼 수 있습니다.

⸻

✍️ 4. 코어 에디팅 상호작용 (Interaction & Control)

4.1. 포커스, 캐럿(커서) 관리
• MainCanvasScrollCoordinator: 편집 중인 카드의 위치를 추적해 화면을 부드럽게 스크롤해주는 매니저.
• 마우스 클릭 시 카드가 활성화되며(active​Card​ID), 더블 클릭하거나 엔터키를 누르면 텍스트 편집 모드(editing​Card​ID)로 진입.
• 편집 종료 시(Tab 키 등) 형제/자식 카드가 자동으로 생성되거나 포커스가 다음으로 넘어감.

4.2. 클립보드 및 페이스트 (Clipboard)
• Tree Copy/Paste: 특정 카드를 복사하면 자식 카드들까지 트리 채로 복사하여 붙여넣기(자식으로 붙일지, 형제로 붙일지 팝업 제공).
• Fountain Paste: 시나리오 표준 형식인 Fountain 텍스트를 복사해서 붙여넣으면, 앱이 자동으로 씬 헤딩(Scene Heading)을 감지해 여러 장의 카드로 쪼개어 붙여넣어 줍니다.

⸻

🎯 5. 포커스 모드 (Focus Mode) - 심화 기능

방해 요소를 모두 끄고, 파편화된 노드(카드)들을 마치 한 장의 긴 워드 문서처럼 세로로 나열하여 글을 쓰는 모드입니다. WriterFocusMode.swift􀰓가 이를 전담합니다.

• Typewriter Effect (타자기 모드):
   • 글을 쓸 때 캐럿(커서)의 Y좌표가 항상 화면 중앙(focus​Typewriter​Baseline)에 오도록 스크롤 뷰(Focus​Mode​Vertical​Scroll​Authority)를 실시간으로 밀어 올립니다.
• Boundary Navigation (경계 간 부드러운 이동):
   • A 카드의 맨 끝에서 '아래 방향키'를 누르면, 스크롤을 유지한 채 B 카드의 맨 처음으로 커서가 자연스럽게 이동합니다.
   • NSText​View의 텍스트 컨테이너 높이와 폰트 사이즈 등을 수학적으로 계산(focus​Mode​Caret​Rect​In​Document)하여 두 카드 간의 시각적 단절을 막습니다.
• Typing Coalescing & Undo:
   • 사용자가 타이핑을 잠시 멈추면(1.5초) 자동으로 Undo 스택(Scenario​State)을 저장합니다. 엔터키(문단 나눔) 등 큰 변화가 있을 때도 강제 백업을 남깁니다.

⸻

🧠 6. AI 및 RAG (Retrieval-Augmented Generation) 시스템 - 최상위 복잡도

단순한 ChatGPT 연동이 아니라, 사용자가 작성한 글의 전체 맥락을 이해하고 필요한 정보만 검색(Retrieve)하여 AI에게 제공하는 고도화된 RAG 시스템이 탑재되어 있습니다.

6.1. AI Chat & Thread Store (WriterAI+ThreadStore.swift􀰓)
• 여러 개의 상담 스레드(AIChat​Thread)를 관리하며 JSON 파일로 디스크에 유지.
• Scope (컨텍스트 범위 지정): AI에게 전달할 맥락을 "선택한 카드들", "플롯 라인만", "노트 라인만" 등으로 한정지을 수 있습니다.
• Rolling Summary (지속 요약): 대화가 길어지면 토큰 한도를 넘지 않도록, 매 4턴마다 이전 대화의 요약본(rolling​Summary)을 자동으로 갱신하여 프롬프트에 압축해 넣습니다.

6.2. Semantic RAG 엔진 (WriterAI+RAG.swift􀰓)
• 1단계 - 임베딩 (Embedding): 카드의 내용을 Gemini Embedding API(gemini​-embedding​-001 또는 text​-embedding​-004)를 이용해 다차원 벡터 배열([​Float])로 변환합니다.
• 2단계 - 벡터 저장 (Vector SQLite Store): 변환된 벡터와 카드의 해시, 키워드 토큰을 로컬 SQLite 데이터베이스에 캐싱(AIVector​SQLite​Store)합니다.
• 3단계 - 코사인 유사도 검색 (Cosine Similarity): 사용자가 채팅창에 "이 이야기 결말 어떻게 해?"라고 물으면, 해당 질문을 임베딩 벡터로 변환한 뒤, 기존 카드들의 벡터와 cosine​Similarity를 계산하여 가장 연관성 높은 Top 8개의 카드를 찾습니다.
• 4단계 - 컨텍스트 주입: 찾은 카드의 내용(다이제스트)을 프롬프트에 백그라운드 지식으로 삽입하여 환각(Hallucination) 없이 내 시나리오 설정에 맞는 답변을 하도록 유도합니다.

6.3. AI 답변을 실제 글로 반영 (WriterAI+ChatView.swift􀰓)
• 채팅창에서 얻은 답변을 복사/붙여넣기 할 필요 없이, 버튼 하나(선택 카드에 반영, 자식 카드로 추가)를 누르면 진행 중인 시나리오의 특정 카드로 즉시 텍스트가 삽입됩니다.

⸻

🛠️ 개발자를 위한 조언 (앱을 다시 만들 때 핵심 포인트)

이 앱을 클론(Rebuild)하려 한다면 다음 순서로 개발을 진행해야 합니다.

1. 데이터 아키텍처 (Models): Scene​Card 클래스를 구현하고 트리 순회(DFS/BFS)와 계층화 로직(rebuild​Index​If​Needed)을 가장 먼저 완벽히 짜야 합니다.
2. 파일 시스템 동기화 (FileStore): 메모리 객체를 디스크와 동기화하는 로직. 이때 card​Mutation​Batch​Depth 같은 배치 처리 및 Debounce를 구현하지 않으면 타이핑마다 디스크 I/O가 발생해 앱이 멈춥니다.
3. 메인 캔버스 뷰 (Main Canvas): SwiftUI의 Scroll​View와 Geometry​Reader를 활용하여 무한히 확장되는 노드 트리를 렌더링합니다. 성능을 위해 화면에 보이는 카드만 렌더링하는 Windowing/LazyVStack 최적화가 필수적입니다.
4. 포커스 텍스트 에디터: SwiftUI 기본 Text​Editor로는 커서 추적과 방향키 경계 이동을 구현할 수 없습니다. 반드시 AppKit의 NSText​View (또는 iOS의 UIText​View)를 NSView​Representable로 감싸서 TextStorage, LayoutManager 레이어까지 제어해야 합니다.
5. AI 로컬 벡터화 (SQLite): RAG를 구현할 때 외부 벡터 DB(Pinecone 등)를 쓰지 않고 CoreData나 로컬 SQLite를 사용하여 사용자의 데이터를 외부 서버에 장기 저장하지 않도록 프라이버시를 보장해야 합니다.

