import fs from 'fs';
import crypto from 'crypto';

const SCENARIO_ID = 'B6F21CB6-BC46-42FA-B500-6AA87BB2D468';
const AI_ID = 'C0DAD9E7-4E76-4F03-9E3E-177D47B195B0';
const PACKAGE_DIR = '/Users/three/Documents/시나리오 작업/ver3/1st_app.wtf';
const SCENARIO_DIR = `${PACKAGE_DIR}/scenario_${SCENARIO_ID}`;
const INDEX_PATH = `${SCENARIO_DIR}/cards_index.json`;
const SOURCE_PATH = '/Users/three/Library/Mobile Documents/iCloud~md~obsidian/Documents/gaenari/pages/길동 9고 final.md';
const PHASE3_PATH = '/Users/three/app_build/wa/10th_phase3.md';
const PHASE4_PATH = '/Users/three/app_build/wa/10th_phase4.md';
const BACKUP_PATH = '/Users/three/app_build/wa/10th_phase6_cards_index.backup.json';
const IDS_PATH = '/Users/three/app_build/wa/10th_phase6_card_ids.json';

function parseSections(regex, text, mapper) {
  const out = [];
  for (const match of text.matchAll(regex)) out.push(mapper(match));
  return out;
}

function pad(n) {
  return String(n).padStart(2, '0');
}

function scenePad(n) {
  return String(n).padStart(3, '0');
}

function hashText(text) {
  return crypto.createHash('sha256').update(text, 'utf8').digest('hex');
}

function makeID() {
  return crypto.randomUUID().toUpperCase();
}

function nextOrder(cards, parentID) {
  const children = cards.filter((c) => c.parentID === parentID);
  return children.length ? Math.max(...children.map((c) => c.orderIndex ?? 0)) + 1 : 0;
}

function makeEntry({ id, parentID, orderIndex, lastSelectedChildID }) {
  const entry = {
    category: '플롯',
    createdAt: now,
    id,
    isArchived: false,
    isFloating: false,
    orderIndex,
    parentID,
    scenarioID: SCENARIO_ID,
    schemaVersion: 3,
  };
  if (lastSelectedChildID) entry.lastSelectedChildID = lastSelectedChildID;
  return entry;
}

const now = new Date().toISOString().replace(/\.\d{3}Z$/, 'Z');

const cards = JSON.parse(fs.readFileSync(INDEX_PATH, 'utf8'));
if (!fs.existsSync(BACKUP_PATH)) fs.copyFileSync(INDEX_PATH, BACKUP_PATH);

const visibleAiChildren = cards.filter((c) => c.parentID === AI_ID && !c.isArchived);
if (visibleAiChildren.length > 0) {
  throw new Error(`ai root is not empty; visible child count=${visibleAiChildren.length}`);
}

const aiCard = cards.find((c) => c.id === AI_ID);
if (!aiCard) throw new Error('ai root card not found');

const phase3 = fs.readFileSync(PHASE3_PATH, 'utf8');
const phase4 = fs.readFileSync(PHASE4_PATH, 'utf8');
const source = fs.readFileSync(SOURCE_PATH, 'utf8');

const treatmentRegex = /^## Treatment (\d+) \| (\d+)-(\d+) \| (.+)\n\n- 산문형 트리트먼트 본문: ([\s\S]*?)\n- 드라마 기능:/gm;
const sequenceRegex = /^### Sequence (\d+) \| (\d+)-(\d+) \| (.+)\n\n- 산문형 요약: ([\s\S]*?)\n- 시퀀스 기능:/gm;
const synopsisRegex = /^### Synopsis (\d+) \| (\d+)-(\d+) \| (.+)\n\n- 산문형 요약: ([\s\S]*?)\n- 기능:/gm;
const outlineRegex = /^### 개요 (\d+) \| (\d+)-(\d+) \| (.+)\n\n- 요약: ([\s\S]*?)\n- 기능 설명:/gm;
const actRegex = /^### (시작|중간1|중간2|끝) \| (\d+)-(\d+)\n\n- 산문형 요약: ([\s\S]*?)\n- 막 기능:/gm;

const treatments = parseSections(treatmentRegex, phase3, (m) => ({
  type: 'treatment',
  number: Number(m[1]),
  start: Number(m[2]),
  end: Number(m[3]),
  title: m[4].trim(),
  prose: m[5].trim(),
}));

const sequences = parseSections(sequenceRegex, phase4, (m) => ({
  type: 'sequence',
  number: Number(m[1]),
  start: Number(m[2]),
  end: Number(m[3]),
  title: m[4].trim(),
  prose: m[5].trim(),
}));

const synopses = parseSections(synopsisRegex, phase4, (m) => ({
  type: 'synopsis',
  number: Number(m[1]),
  start: Number(m[2]),
  end: Number(m[3]),
  title: m[4].trim(),
  prose: m[5].trim(),
}));

const outlines = parseSections(outlineRegex, phase4, (m) => ({
  type: 'outline',
  number: Number(m[1]),
  start: Number(m[2]),
  end: Number(m[3]),
  title: m[4].trim(),
  prose: m[5].trim(),
}));

const acts = parseSections(actRegex, phase4, (m) => ({
  type: 'act',
  title: m[1].trim(),
  start: Number(m[2]),
  end: Number(m[3]),
  prose: m[4].trim(),
}));

if (treatments.length !== 21) throw new Error(`expected 21 treatments, got ${treatments.length}`);
if (sequences.length !== 11) throw new Error(`expected 11 sequences, got ${sequences.length}`);
if (synopses.length !== 8) throw new Error(`expected 8 synopses, got ${synopses.length}`);
if (outlines.length !== 12) throw new Error(`expected 12 outlines, got ${outlines.length}`);
if (acts.length !== 4) throw new Error(`expected 4 acts, got ${acts.length}`);

const headingMatches = [...source.matchAll(/^(EXT|INT)\./gm)];
if (headingMatches.length !== 116) throw new Error(`expected 116 scene headings, got ${headingMatches.length}`);
const scenes = headingMatches.map((m, idx) => {
  const start = m.index;
  const end = idx + 1 < headingMatches.length ? headingMatches[idx + 1].index : source.length;
  const raw = source.slice(start, end);
  return {
    number: idx + 1,
    raw,
    heading: raw.split('\n')[0],
    hash: hashText(raw),
    bytes: Buffer.byteLength(raw, 'utf8'),
  };
});

function findActForRange(start, end) {
  const act = acts.find((a) => a.start <= start && end <= a.end);
  if (!act) throw new Error(`no act for range ${start}-${end}`);
  return act.title;
}

const byAct = new Map(acts.map((a) => [a.title, { act: a, outlines: [], synopses: [], sequences: [], treatments: [] }]));
for (const item of outlines) byAct.get(findActForRange(item.start, item.end)).outlines.push(item);
for (const item of synopses) byAct.get(findActForRange(item.start, item.end)).synopses.push(item);
for (const item of sequences) byAct.get(findActForRange(item.start, item.end)).sequences.push(item);
for (const item of treatments) byAct.get(findActForRange(item.start, item.end)).treatments.push(item);

const created = {
  acts: [],
  branches: [],
  outlines: [],
  synopses: [],
  sequences: [],
  treatments: [],
  rawScenes: [],
};

const textWrites = [];

function queueCard(content, parentID, orderIndex, withChildren = true) {
  const id = makeID();
  const entry = makeEntry({ id, parentID, orderIndex });
  cards.push(entry);
  textWrites.push({ id, content });
  return { id, entry };
}

const actStartOrder = nextOrder(cards, AI_ID);
const branchTitles = ['개요', '시놉시스', '시퀀스', '트리트먼트'];

for (const [actIndex, act] of acts.entries()) {
  const actCard = queueCard(act.title, AI_ID, actStartOrder + actIndex);
  created.acts.push({ id: actCard.id, title: act.title, start: act.start, end: act.end });
}

aiCard.lastSelectedChildID = created.acts.at(-1).id;

for (const actRec of created.acts) {
  const actData = byAct.get(actRec.title);
  const branchIDs = {};
  branchTitles.forEach((title, idx) => {
    const branch = queueCard(title, actRec.id, idx);
    branchIDs[title] = branch.id;
    created.branches.push({ id: branch.id, parentActID: actRec.id, title });
  });

  const outlineCards = actData.outlines.map((item, idx) => {
    const content = `개요 ${pad(item.number)} | ${item.title} | ${scenePad(item.start)}-${scenePad(item.end)}\n\n${item.prose}`;
    const card = queueCard(content, branchIDs['개요'], idx);
    created.outlines.push({ id: card.id, number: item.number, start: item.start, end: item.end, act: actRec.title });
    return card.id;
  });
  const synopsisCards = actData.synopses.map((item, idx) => {
    const content = `시놉시스 ${pad(item.number)} | ${item.title} | ${scenePad(item.start)}-${scenePad(item.end)}\n\n${item.prose}`;
    const card = queueCard(content, branchIDs['시놉시스'], idx);
    created.synopses.push({ id: card.id, number: item.number, start: item.start, end: item.end, act: actRec.title });
    return card.id;
  });
  const sequenceCards = actData.sequences.map((item, idx) => {
    const content = `시퀀스 ${pad(item.number)} | ${item.title} | ${scenePad(item.start)}-${scenePad(item.end)}\n\n${item.prose}`;
    const card = queueCard(content, branchIDs['시퀀스'], idx);
    created.sequences.push({ id: card.id, number: item.number, start: item.start, end: item.end, act: actRec.title });
    return card.id;
  });

  const treatmentCards = actData.treatments.map((item, idx) => {
    const content = `트리트먼트 ${pad(item.number)} | ${item.title} | ${scenePad(item.start)}-${scenePad(item.end)}\n\n${item.prose}`;
    const card = queueCard(content, branchIDs['트리트먼트'], idx);
    created.treatments.push({ id: card.id, number: item.number, start: item.start, end: item.end, act: actRec.title });

    const treatmentEntry = cards.find((c) => c.id === card.id);
    const rawIDs = [];
    for (let sceneNo = item.start; sceneNo <= item.end; sceneNo++) {
      const scene = scenes[sceneNo - 1];
      const rawCard = queueCard(scene.raw, card.id, rawIDs.length);
      rawIDs.push(rawCard.id);
      created.rawScenes.push({
        id: rawCard.id,
        number: scene.number,
        heading: scene.heading,
        hash: scene.hash,
        bytes: scene.bytes,
        treatment: item.number,
      });
    }
    if (rawIDs.length) treatmentEntry.lastSelectedChildID = rawIDs.at(-1);
    return card.id;
  });

  const branchMap = new Map(cards.filter((c) => Object.values(branchIDs).includes(c.id)).map((c) => [c.id, c]));
  if (outlineCards.length) branchMap.get(branchIDs['개요']).lastSelectedChildID = outlineCards.at(-1);
  if (synopsisCards.length) branchMap.get(branchIDs['시놉시스']).lastSelectedChildID = synopsisCards.at(-1);
  if (sequenceCards.length) branchMap.get(branchIDs['시퀀스']).lastSelectedChildID = sequenceCards.at(-1);
  if (treatmentCards.length) branchMap.get(branchIDs['트리트먼트']).lastSelectedChildID = treatmentCards.at(-1);

  const actEntry = cards.find((c) => c.id === actRec.id);
  actEntry.lastSelectedChildID = branchIDs['트리트먼트'];
}

for (const { id, content } of textWrites) {
  fs.writeFileSync(`${SCENARIO_DIR}/card_${id}.txt`, content, 'utf8');
}

fs.writeFileSync(INDEX_PATH, JSON.stringify(cards), 'utf8');

const verifyMismatches = [];
for (const raw of created.rawScenes) {
  const p = `${SCENARIO_DIR}/card_${raw.id}.txt`;
  const written = fs.readFileSync(p, 'utf8');
  const writtenHash = hashText(written);
  if (writtenHash !== raw.hash) {
    verifyMismatches.push({
      scene: raw.number,
      id: raw.id,
      expected: raw.hash,
      actual: writtenHash,
    });
  }
}

const report = {
  scenarioID: SCENARIO_ID,
  aiID: AI_ID,
  counts: {
    acts: created.acts.length,
    branches: created.branches.length,
    outlines: created.outlines.length,
    synopses: created.synopses.length,
    sequences: created.sequences.length,
    treatments: created.treatments.length,
    rawScenes: created.rawScenes.length,
    totalNewCards: created.acts.length + created.branches.length + created.outlines.length + created.synopses.length + created.sequences.length + created.treatments.length + created.rawScenes.length,
  },
  verification: {
    rawHashMismatches: verifyMismatches.length,
    ok: verifyMismatches.length === 0,
  },
  ids: created,
};

fs.writeFileSync(IDS_PATH, JSON.stringify(report, null, 2), 'utf8');

console.log(JSON.stringify(report, null, 2));
