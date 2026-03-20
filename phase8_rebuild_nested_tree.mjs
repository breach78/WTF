import fs from "fs";
import crypto from "crypto";

const SCENARIO_ID = "B6F21CB6-BC46-42FA-B500-6AA87BB2D468";
const AI_ID = "C0DAD9E7-4E76-4F03-9E3E-177D47B195B0";
const PACKAGE_DIR = "/Users/three/Documents/시나리오 작업/ver3/1st_app.wtf";
const SCENARIO_DIR = `${PACKAGE_DIR}/scenario_${SCENARIO_ID}`;
const INDEX_PATH = `${SCENARIO_DIR}/cards_index.json`;
const PHASE6_IDS_PATH = "/Users/three/app_build/wa/10th_phase6_card_ids.json";
const PHASE8_IDS_PATH = "/Users/three/app_build/wa/10th_phase8_card_ids.json";
const BACKUP_PATH = "/Users/three/app_build/wa/10th_phase8_cards_index.backup.json";

const now = new Date().toISOString().replace(/\.\d{3}Z$/, "Z");

function pad2(n) {
  return String(n).padStart(2, "0");
}

function pad3(n) {
  return String(n).padStart(3, "0");
}

function makeID() {
  return crypto.randomUUID().toUpperCase();
}

function readJSON(path) {
  return JSON.parse(fs.readFileSync(path, "utf8"));
}

function cardPath(id) {
  return `${SCENARIO_DIR}/card_${id}.txt`;
}

function readCardText(id) {
  return fs.readFileSync(cardPath(id), "utf8");
}

function readCardBody(id) {
  const text = readCardText(id);
  const splitAt = text.indexOf("\n\n");
  return splitAt === -1 ? "" : text.slice(splitAt + 2).trim();
}

function maxOrder(cards, parentID) {
  const children = cards.filter((card) => card.parentID === parentID);
  return children.length ? Math.max(...children.map((card) => card.orderIndex ?? 0)) : -1;
}

function addCard(cards, indexMap, writes, content, parentID, orderIndex) {
  const id = makeID();
  const entry = {
    category: "플롯",
    createdAt: now,
    id,
    isArchived: false,
    isFloating: false,
    orderIndex,
    parentID,
    scenarioID: SCENARIO_ID,
    schemaVersion: 3,
  };
  cards.push(entry);
  indexMap.set(id, entry);
  writes.push({ id, content });
  return entry;
}

function setLastSelected(card, childID) {
  if (childID) card.lastSelectedChildID = childID;
  else delete card.lastSelectedChildID;
}

const cards = readJSON(INDEX_PATH);
if (!fs.existsSync(BACKUP_PATH)) fs.copyFileSync(INDEX_PATH, BACKUP_PATH);
const indexMap = new Map(cards.map((card) => [card.id, card]));
const old = readJSON(PHASE6_IDS_PATH);

const aiCard = indexMap.get(AI_ID);
if (!aiCard) throw new Error("ai root card not found");

const oldOutlineByNumber = new Map(old.ids.outlines.map((item) => [item.number, item]));
const oldSynopsisByNumber = new Map(old.ids.synopses.map((item) => [item.number, item]));
const sequenceByNumber = new Map(old.ids.sequences.map((item) => [item.number, item]));
const treatmentByNumber = new Map(old.ids.treatments.map((item) => [item.number, item]));
const rawByNumber = new Map(old.ids.rawScenes.map((item) => [item.number, item]));
const actByTitle = new Map(old.ids.acts.map((item) => [item.title, item]));

const outlineDefinitions = [
  {
    number: 1,
    act: "시작",
    start: 1,
    end: 13,
    title: "프롤로그 / 문제 제기",
    prose: readCardBody(oldOutlineByNumber.get(1).id),
    synopsisNumbers: [1],
  },
  {
    number: 2,
    act: "시작",
    start: 14,
    end: 27,
    title: "잠재된 발화점 / 사건의 발단",
    prose:
      "`율도국`과 `길동전`이 토굴에서 태어나지만, 기춘의 포착으로 그 상상은 곧장 정치 사건이 된다. 양갑과 친구들의 체포, 그리고 왕 앞에서 역모로 뒤집힌 서얼 허통 요구는 결국 숙청 명령을 불러오며 영화 전체의 발화점을 실제 파국으로 밀어 넣는다.",
    synopsisNumbers: [2],
  },
  {
    number: 3,
    act: "시작",
    start: 28,
    end: 40,
    title: "1막의 끝 / 추락",
    prose: readCardBody(oldOutlineByNumber.get(4).id),
    synopsisNumbers: [3],
  },
  {
    number: 4,
    act: "중간1",
    start: 41,
    end: 60,
    title: "새로운 세계 진입 / 홍길동 탄생",
    prose:
      "외가와 화전민촌을 거치며 길은 자신이 몰랐던 민중의 현실에 던져지고, `길동전`의 `우리`가 누구인지라는 질문 앞에 선다. 관아 마당의 폭정과 장터의 현실을 통과한 끝에 길은 처음으로 `홍길동`을 자처하며 새 이름과 새 위치를 얻는다.",
    synopsisNumbers: [4, 5],
  },
  {
    number: 5,
    act: "중간1",
    start: 61,
    end: 70,
    title: "논쟁 / 미드포인트 - 율도국 선언",
    prose:
      "산채 사람들은 왕 제거론을 넘어 자신들을 노비와 굶주림으로 몰아넣은 질서를 먼저 묻고, 길은 한글 `길동전`과 붉은 탈의 힘 위에서 `율도국`을 선언한다. 논쟁은 미드포인트의 결단으로 폭발하며 싸움의 목표를 조선 체제 전체의 전복으로 바꾼다.",
    synopsisNumbers: [6],
  },
  {
    number: 6,
    act: "중간2",
    start: 71,
    end: 80,
    title: "반격과 상승",
    prose: readCardBody(oldOutlineByNumber.get(9).id),
    synopsisNumbers: [7],
  },
  {
    number: 7,
    act: "중간2",
    start: 81,
    end: 96,
    title: "위기 고조 / 한양 함정",
    prose: readCardBody(oldOutlineByNumber.get(10).id),
    synopsisNumbers: [8],
  },
  {
    number: 8,
    act: "끝",
    start: 97,
    end: 101,
    title: "붕괴의 시작 / 남대문 덫",
    prose:
      "남대문 앞의 거대한 환영은 조정을 흔들지만, 성루의 왕은 미끼였고 허균의 성안 작전은 역덫에 걸린다. 수도 공략이 처음으로 무너지는 순간이자, 영화의 최종 승부가 성밖 추격으로 급격히 이동하는 분기점이다.",
    synopsisNumbers: [9],
  },
  {
    number: 9,
    act: "끝",
    start: 102,
    end: 110,
    title: "최종 돌입 / 왕 포획과 희생",
    prose:
      "길은 끝내 왕을 포획하지만, 후금의 기마와 10만 대군의 허상이 드러나는 순간 승리는 곧바로 위기로 뒤집힌다. 왕 포획의 성취는 본대를 살리기 위한 자기소멸의 결단으로 전환되며 영화의 비극적 클라이맥스를 만든다.",
    synopsisNumbers: [10],
  },
  {
    number: 10,
    act: "끝",
    start: 111,
    end: 116,
    title: "결말 / 새 질서의 탄생",
    prose: readCardBody(oldOutlineByNumber.get(12).id),
    synopsisNumbers: [11],
  },
];

const synopsisDefinitions = [
  {
    number: 1,
    act: "시작",
    start: 1,
    end: 13,
    title: "활빈당의 등장과 국가적 위기의 개시",
    prose: readCardBody(oldSynopsisByNumber.get(1).id),
    sequenceNumbers: [1],
  },
  {
    number: 2,
    act: "시작",
    start: 14,
    end: 27,
    title: "율도국과 길동전의 씨앗이 피로 봉인되다",
    prose: readCardBody(oldSynopsisByNumber.get(2).id),
    sequenceNumbers: [2],
  },
  {
    number: 3,
    act: "시작",
    start: 28,
    end: 40,
    title: "길의 몰락과 살아남은 자의 결별",
    prose: readCardBody(oldSynopsisByNumber.get(3).id),
    sequenceNumbers: [3],
  },
  {
    number: 4,
    act: "중간1",
    start: 41,
    end: 53,
    title: "화전민촌과 홍길동의 탄생",
    prose:
      "외가와 화전민촌을 거친 길은 막똥과 개똥을 통해 자신이 외면해 온 계급 현실과 `길동전`의 `우리`가 누구인지라는 질문을 정면으로 마주한다. 관아 마당의 폭정 앞에서 그는 처음으로 화전민의 편에 서며 `홍길동`을 자처한다.",
    sequenceNumbers: [4],
  },
  {
    number: 5,
    act: "중간1",
    start: 54,
    end: 60,
    title: "허균의 귀환과 민중 서사의 재정렬",
    prose:
      "장터의 탈춤과 소문은 홍길동을 이미 민중 서사의 주인공으로 만들고, 허균은 그 전설 속에서 길의 생존을 확인한다. 무덤과 장터를 오가는 재회 속에서 두 사람은 앞으로 싸워야 할 민중의 두려움과 체념을 다시 본다.",
    sequenceNumbers: [5],
  },
  {
    number: 6,
    act: "중간1",
    start: 61,
    end: 70,
    title: "왕을 넘어서 조선 자체를 겨누다",
    prose: readCardBody(oldSynopsisByNumber.get(5).id),
    sequenceNumbers: [6],
  },
  {
    number: 7,
    act: "중간2",
    start: 71,
    end: 80,
    title: "장성 승리와 남도 장악",
    prose: readCardBody(oldSynopsisByNumber.get(6).id),
    sequenceNumbers: [7],
  },
  {
    number: 8,
    act: "중간2",
    start: 81,
    end: 96,
    title: "한양 함정과 잠입의 피값",
    prose: readCardBody(oldSynopsisByNumber.get(7).id),
    sequenceNumbers: [8],
  },
  {
    number: 9,
    act: "끝",
    start: 97,
    end: 101,
    title: "남대문 덫과 작전의 붕괴",
    prose:
      "남대문 앞 `10만 활빈당`의 환영은 조정을 흔들지만, 성루의 왕은 미끼였고 허균의 성안 작전은 역덫에 걸린다. 수도 공략이 무너지는 순간에도, 진짜 승부는 이미 성밖의 추격으로 넘어간다.",
    sequenceNumbers: [9],
  },
  {
    number: 10,
    act: "끝",
    start: 102,
    end: 110,
    title: "왕 포획, 외세 개입, 길의 희생",
    prose:
      "길은 끝내 왕을 포획하지만, 후금의 개입과 10만 대군의 허상이 드러나면서 승리는 곧장 위기로 뒤집힌다. 그는 본대를 살리기 위해 왕을 풀어주고 자신의 몸을 미끼로 내던진다.",
    sequenceNumbers: [10],
  },
  {
    number: 11,
    act: "끝",
    start: 111,
    end: 116,
    title: "길동의 집단적 귀환",
    prose:
      "길이 사라진 아침, 왕은 민가와 군중 앞에서 마지막 권위까지 잃고 활빈당은 돌아오지 않을 대장을 받아들인다. 남대문 앞에서 사람들은 `홍길동`을 한 사람의 이름이 아니라 모두의 이름으로 되살린다.",
    sequenceNumbers: [11],
  },
];

const writes = [];
const created = {
  acts: old.ids.acts,
  outlines: [],
  synopses: [],
  sequences: old.ids.sequences,
  treatments: old.ids.treatments,
  rawScenes: old.ids.rawScenes,
  archived: {
    branches: old.ids.branches.map((item) => item.id),
    outlines: old.ids.outlines.map((item) => item.id),
    synopses: old.ids.synopses.map((item) => item.id),
  },
};

for (const id of [...created.archived.branches, ...created.archived.outlines, ...created.archived.synopses]) {
  const card = indexMap.get(id);
  if (card) card.isArchived = true;
}

const outlineEntryByNumber = new Map();
for (const act of old.ids.acts) {
  const actCard = indexMap.get(act.id);
  const actOutlines = outlineDefinitions.filter((item) => item.act === act.title);
  let orderIndex = maxOrder(cards, act.id) + 1;
  const createdInAct = [];
  for (const item of actOutlines) {
    const content = `개요 ${pad2(item.number)} | ${item.title} | ${pad3(item.start)}-${pad3(item.end)}\n\n${item.prose}`;
    const entry = addCard(cards, indexMap, writes, content, act.id, orderIndex++);
    outlineEntryByNumber.set(item.number, entry);
    created.outlines.push({
      id: entry.id,
      number: item.number,
      start: item.start,
      end: item.end,
      act: item.act,
      synopsisNumbers: item.synopsisNumbers,
    });
    createdInAct.push(entry.id);
  }
  setLastSelected(actCard, createdInAct.at(-1));
}

const synopsisEntryByNumber = new Map();
for (const outline of outlineDefinitions) {
  const parent = outlineEntryByNumber.get(outline.number);
  let orderIndex = 0;
  const createdInOutline = [];
  for (const synopsisNo of outline.synopsisNumbers) {
    const item = synopsisDefinitions.find((synopsis) => synopsis.number === synopsisNo);
    const content = `시놉시스 ${pad2(item.number)} | ${item.title} | ${pad3(item.start)}-${pad3(item.end)}\n\n${item.prose}`;
    const entry = addCard(cards, indexMap, writes, content, parent.id, orderIndex++);
    synopsisEntryByNumber.set(item.number, entry);
    created.synopses.push({
      id: entry.id,
      number: item.number,
      start: item.start,
      end: item.end,
      act: item.act,
      sequenceNumbers: item.sequenceNumbers,
    });
    createdInOutline.push(entry.id);
  }
  setLastSelected(parent, createdInOutline.at(-1));
}

for (const synopsis of synopsisDefinitions) {
  const synopsisEntry = synopsisEntryByNumber.get(synopsis.number);
  const sequenceIDs = [];
  synopsis.sequenceNumbers.forEach((sequenceNo, idx) => {
    const sequence = sequenceByNumber.get(sequenceNo);
    const sequenceEntry = indexMap.get(sequence.id);
    sequenceEntry.parentID = synopsisEntry.id;
    sequenceEntry.orderIndex = idx;
    sequenceIDs.push(sequenceEntry.id);
  });
  setLastSelected(synopsisEntry, sequenceIDs.at(-1));
}

for (const sequence of old.ids.sequences) {
  const sequenceEntry = indexMap.get(sequence.id);
  const childTreatments = old.ids.treatments
    .filter((treatment) => sequence.start <= treatment.start && treatment.end <= sequence.end)
    .sort((a, b) => a.number - b.number);
  childTreatments.forEach((treatment, idx) => {
    const treatmentEntry = indexMap.get(treatment.id);
    treatmentEntry.parentID = sequence.id;
    treatmentEntry.orderIndex = idx;
  });
  setLastSelected(sequenceEntry, childTreatments.at(-1)?.id);
}

for (const treatment of old.ids.treatments) {
  const treatmentEntry = indexMap.get(treatment.id);
  const childRaw = old.ids.rawScenes
    .filter((scene) => treatment.start <= scene.number && scene.number <= treatment.end)
    .sort((a, b) => a.number - b.number);
  childRaw.forEach((scene, idx) => {
    const rawEntry = indexMap.get(scene.id);
    rawEntry.parentID = treatment.id;
    rawEntry.orderIndex = idx;
  });
  setLastSelected(treatmentEntry, childRaw.at(-1)?.id);
}

setLastSelected(aiCard, old.ids.acts.at(-1)?.id);

for (const write of writes) {
  fs.writeFileSync(cardPath(write.id), write.content, "utf8");
}

fs.writeFileSync(INDEX_PATH, JSON.stringify(cards), "utf8");

const report = {
  scenarioID: SCENARIO_ID,
  aiID: AI_ID,
  counts: {
    acts: created.acts.length,
    outlines: created.outlines.length,
    synopses: created.synopses.length,
    sequences: created.sequences.length,
    treatments: created.treatments.length,
    rawScenes: created.rawScenes.length,
    archivedBranches: created.archived.branches.length,
    archivedOldOutlines: created.archived.outlines.length,
    archivedOldSynopses: created.archived.synopses.length,
    newCards: created.outlines.length + created.synopses.length,
  },
  ids: created,
};

fs.writeFileSync(PHASE8_IDS_PATH, JSON.stringify(report, null, 2), "utf8");
console.log(JSON.stringify(report, null, 2));
