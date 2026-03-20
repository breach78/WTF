import fs from "fs";
import crypto from "crypto";

const SOURCE_PATH =
  "/Users/three/Library/Mobile Documents/iCloud~md~obsidian/Documents/gaenari/pages/길동 9고 final.md";
const PACKAGE_PATH = "/Users/three/Documents/시나리오 작업/ver3/1st_app.wtf";
const SCENARIO_ID = "B6F21CB6-BC46-42FA-B500-6AA87BB2D468";
const AI_ID = "C0DAD9E7-4E76-4F03-9E3E-177D47B195B0";
const CARDS_DIR = `${PACKAGE_PATH}/scenario_${SCENARIO_ID}`;
const INDEX_PATH = `${CARDS_DIR}/cards_index.json`;
const IDS_PATH = "/Users/three/app_build/wa/10th_phase8_card_ids.json";

function sha256(text) {
  return crypto.createHash("sha256").update(text, "utf8").digest("hex");
}

function readJSON(path) {
  return JSON.parse(fs.readFileSync(path, "utf8"));
}

function splitScenes(source) {
  const matches = [...source.matchAll(/^(EXT|INT)\./gm)];
  return matches.map((match, index) => {
    const start = match.index;
    const end = index + 1 < matches.length ? matches[index + 1].index : source.length;
    const content = source.slice(start, end);
    return {
      number: index + 1,
      content,
      heading: content.split("\n", 1)[0],
      hash: sha256(content),
      bytes: Buffer.byteLength(content, "utf8"),
    };
  });
}

function getChildren(indexMap, parentID, { visibleOnly = true } = {}) {
  return [...indexMap.values()]
    .filter((card) => card.parentID === parentID && (!visibleOnly || !card.isArchived))
    .sort((a, b) => a.orderIndex - b.orderIndex);
}

const source = fs.readFileSync(SOURCE_PATH, "utf8");
const sourceStats = fs.statSync(SOURCE_PATH);
const sourceLines = (source.match(/\n/g) ?? []).length;
const sourceBytes = sourceStats.size;
const sourceHash = sha256(source);
const expectedSource = {
  lines: 3834,
  bytes: 151177,
  hash: "c1a3bea5a3b46a437e141472d4dbc78baecf7c550f75b731c9648f40417f6189",
};
if (
  sourceLines !== expectedSource.lines ||
  sourceBytes !== expectedSource.bytes ||
  sourceHash !== expectedSource.hash
) {
  throw new Error("source lock mismatch");
}

const scenes = splitScenes(source);
if (scenes.length !== 116) throw new Error("scene count mismatch");

const ids = readJSON(IDS_PATH);
const cards = readJSON(INDEX_PATH);
const indexMap = new Map(cards.map((card) => [card.id, card]));
const issues = [];

const aiCard = indexMap.get(AI_ID);
if (!aiCard || aiCard.isArchived) issues.push("ai root missing or archived");

const expectedActIDs = ids.ids.acts.map((item) => item.id);
const actualActIDs = getChildren(indexMap, AI_ID).map((card) => card.id);
if (JSON.stringify(expectedActIDs) !== JSON.stringify(actualActIDs)) {
  issues.push("ai visible child order mismatch");
}

for (const archivedID of [
  ...ids.ids.archived.branches,
  ...ids.ids.archived.outlines,
  ...ids.ids.archived.synopses,
]) {
  const card = indexMap.get(archivedID);
  if (!card || !card.isArchived) issues.push(`expected archived card not archived: ${archivedID}`);
}

for (const act of ids.ids.acts) {
  const actCard = indexMap.get(act.id);
  const outlineIDs = ids.ids.outlines.filter((item) => item.act === act.title).map((item) => item.id);
  const actualOutlineIDs = getChildren(indexMap, act.id).map((card) => card.id);
  if (JSON.stringify(outlineIDs) !== JSON.stringify(actualOutlineIDs)) {
    issues.push(`outline order mismatch under act ${act.title}`);
  }
  if (actCard?.lastSelectedChildID !== outlineIDs.at(-1)) {
    issues.push(`act lastSelectedChildID mismatch: ${act.title}`);
  }
}

for (const outline of ids.ids.outlines) {
  const outlineCard = indexMap.get(outline.id);
  if (!outlineCard || outlineCard.isArchived) {
    issues.push(`outline missing or archived: ${outline.number}`);
    continue;
  }
  const expectedSynopsisIDs = ids.ids.synopses
    .filter((synopsis) => outline.synopsisNumbers.includes(synopsis.number))
    .sort((a, b) => a.number - b.number)
    .map((synopsis) => synopsis.id);
  const actualSynopsisIDs = getChildren(indexMap, outline.id).map((card) => card.id);
  if (JSON.stringify(expectedSynopsisIDs) !== JSON.stringify(actualSynopsisIDs)) {
    issues.push(`synopsis order mismatch under outline ${outline.number}`);
  }
  if (outlineCard.lastSelectedChildID !== expectedSynopsisIDs.at(-1)) {
    issues.push(`outline lastSelectedChildID mismatch: ${outline.number}`);
  }
}

for (const synopsis of ids.ids.synopses) {
  const synopsisCard = indexMap.get(synopsis.id);
  if (!synopsisCard || synopsisCard.isArchived) {
    issues.push(`synopsis missing or archived: ${synopsis.number}`);
    continue;
  }
  const expectedSequenceIDs = ids.ids.sequences
    .filter((sequence) => synopsis.sequenceNumbers.includes(sequence.number))
    .sort((a, b) => a.number - b.number)
    .map((sequence) => sequence.id);
  const actualSequenceIDs = getChildren(indexMap, synopsis.id).map((card) => card.id);
  if (JSON.stringify(expectedSequenceIDs) !== JSON.stringify(actualSequenceIDs)) {
    issues.push(`sequence order mismatch under synopsis ${synopsis.number}`);
  }
  if (synopsisCard.lastSelectedChildID !== expectedSequenceIDs.at(-1)) {
    issues.push(`synopsis lastSelectedChildID mismatch: ${synopsis.number}`);
  }
}

for (const sequence of ids.ids.sequences) {
  const sequenceCard = indexMap.get(sequence.id);
  if (!sequenceCard || sequenceCard.isArchived) {
    issues.push(`sequence missing or archived: ${sequence.number}`);
    continue;
  }
  const expectedTreatmentIDs = ids.ids.treatments
    .filter((treatment) => sequence.start <= treatment.start && treatment.end <= sequence.end)
    .sort((a, b) => a.number - b.number)
    .map((treatment) => treatment.id);
  const actualTreatmentIDs = getChildren(indexMap, sequence.id).map((card) => card.id);
  if (JSON.stringify(expectedTreatmentIDs) !== JSON.stringify(actualTreatmentIDs)) {
    issues.push(`treatment order mismatch under sequence ${sequence.number}`);
  }
  if (sequenceCard.lastSelectedChildID !== expectedTreatmentIDs.at(-1)) {
    issues.push(`sequence lastSelectedChildID mismatch: ${sequence.number}`);
  }
}

for (const treatment of ids.ids.treatments) {
  const treatmentCard = indexMap.get(treatment.id);
  if (!treatmentCard || treatmentCard.isArchived) {
    issues.push(`treatment missing or archived: ${treatment.number}`);
    continue;
  }
  const expectedRawIDs = ids.ids.rawScenes
    .filter((scene) => treatment.start <= scene.number && scene.number <= treatment.end)
    .sort((a, b) => a.number - b.number)
    .map((scene) => scene.id);
  const actualRawIDs = getChildren(indexMap, treatment.id).map((card) => card.id);
  if (JSON.stringify(expectedRawIDs) !== JSON.stringify(actualRawIDs)) {
    issues.push(`raw scene order mismatch under treatment ${treatment.number}`);
  }
  if (treatmentCard.lastSelectedChildID !== expectedRawIDs.at(-1)) {
    issues.push(`treatment lastSelectedChildID mismatch: ${treatment.number}`);
  }
}

const rawMismatches = [];
for (const raw of ids.ids.rawScenes) {
  const entry = indexMap.get(raw.id);
  if (!entry || entry.isArchived) {
    issues.push(`raw scene missing or archived: ${raw.number}`);
    continue;
  }
  const text = fs.readFileSync(`${CARDS_DIR}/card_${raw.id}.txt`, "utf8");
  const scene = scenes[raw.number - 1];
  const hash = sha256(text);
  const bytes = Buffer.byteLength(text, "utf8");
  if (text !== scene.content || hash !== raw.hash || bytes !== raw.bytes || raw.heading !== scene.heading) {
    rawMismatches.push(raw.number);
  }
}
if (rawMismatches.length) issues.push(`raw mismatches: ${rawMismatches.join(",")}`);

const visibleDescendants =
  ids.ids.acts.length +
  ids.ids.outlines.length +
  ids.ids.synopses.length +
  ids.ids.sequences.length +
  ids.ids.treatments.length +
  ids.ids.rawScenes.length;

const summary = {
  source: {
    lines: sourceLines,
    bytes: sourceBytes,
    hash: sourceHash,
    scenes: scenes.length,
  },
  counts: {
    acts: ids.ids.acts.length,
    outlines: ids.ids.outlines.length,
    synopses: ids.ids.synopses.length,
    sequences: ids.ids.sequences.length,
    treatments: ids.ids.treatments.length,
    rawScenes: ids.ids.rawScenes.length,
    expectedVisibleDescendants: visibleDescendants,
  },
  archived: {
    branches: ids.ids.archived.branches.length,
    oldOutlines: ids.ids.archived.outlines.length,
    oldSynopses: ids.ids.archived.synopses.length,
  },
  rawIntegrity: {
    validated: ids.ids.rawScenes.length,
    mismatches: rawMismatches,
    firstScene: ids.ids.rawScenes[0],
    lastScene: ids.ids.rawScenes.at(-1),
  },
  issues,
  ok: issues.length === 0,
};

console.log(JSON.stringify(summary, null, 2));
