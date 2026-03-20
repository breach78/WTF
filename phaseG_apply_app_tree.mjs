import fs from "fs";
import crypto from "crypto";

const SCENARIO_ID = "B6F21CB6-BC46-42FA-B500-6AA87BB2D468";
const AI_ID = "C0DAD9E7-4E76-4F03-9E3E-177D47B195B0";
const PACKAGE_DIR = "/Users/three/Documents/시나리오 작업/ver3/1st_app.wtf";
const SCENARIO_DIR = `${PACKAGE_DIR}/scenario_${SCENARIO_ID}`;
const INDEX_PATH = `${SCENARIO_DIR}/cards_index.json`;

const DOCS = {
  acts: "/Users/three/app_build/wa/gildong_phaseA_4acts.md",
  outlines: "/Users/three/app_build/wa/gildong_phaseB_outline.md",
  synopses: "/Users/three/app_build/wa/gildong_phaseC_synopsis.md",
  sequences: "/Users/three/app_build/wa/gildong_phaseD_sequences.md",
  treatments: "/Users/three/app_build/wa/gildong_phaseE_treatments.md",
  rawDir: "/Users/three/app_build/wa/gildong_phaseF_raw_slices",
  rawVerification: "/Users/three/app_build/wa/gildong_phaseF_raw_verification.json",
};

const REPORTS = {
  backup: "/Users/three/app_build/wa/gildong_phaseG_cards_index.backup.json",
  ids: "/Users/three/app_build/wa/gildong_phaseG_card_ids.json",
  verification: "/Users/three/app_build/wa/gildong_phaseG_app_verification.json",
  report: "/Users/three/app_build/wa/gildong_phaseG_app_apply.md",
};

const CATEGORY = "플롯";
const SCHEMA_VERSION = 3;
const now = new Date().toISOString().replace(/\.\d{3}Z$/, "Z");

function read(path) {
  return fs.readFileSync(path, "utf8");
}

function write(path, content) {
  fs.writeFileSync(path, content, "utf8");
}

function readJSON(path) {
  return JSON.parse(read(path));
}

function writeJSON(path, value) {
  write(path, `${JSON.stringify(value, null, 2)}\n`);
}

function makeID() {
  return crypto.randomUUID().toUpperCase();
}

function pad2(n) {
  return String(n).padStart(2, "0");
}

function pad3(n) {
  return String(n).padStart(3, "0");
}

function parseRange(rangeText) {
  const [start, end] = rangeText.split("-").map((part) => Number(part));
  return { start, end: end ?? start, rangeText };
}

function parseSections(text, regex, mapFn) {
  const matches = [...text.matchAll(regex)];
  return matches.map((match, index) => {
    const bodyStart = match.index + match[0].length;
    const bodyEnd = index + 1 < matches.length ? matches[index + 1].index : text.length;
    let body = text.slice(bodyStart, bodyEnd).trim();
    const nextLevel2 = body.indexOf("\n## ");
    if (nextLevel2 !== -1) body = body.slice(0, nextLevel2).trim();
    return mapFn(match, body);
  });
}

function cardPath(id) {
  return `${SCENARIO_DIR}/card_${id}.txt`;
}

function firstLine(text) {
  return text.split("\n", 1)[0] ?? "";
}

function buildById(cards) {
  return new Map(cards.map((card) => [card.id, card]));
}

function buildChildrenMap(cards) {
  const children = new Map();
  for (const card of cards) {
    if (!card.parentID) continue;
    if (!children.has(card.parentID)) children.set(card.parentID, []);
    children.get(card.parentID).push(card);
  }
  for (const list of children.values()) list.sort((a, b) => (a.orderIndex ?? 0) - (b.orderIndex ?? 0));
  return children;
}

function maxOrder(cards, parentID) {
  let max = -1;
  for (const card of cards) {
    if (card.parentID !== parentID) continue;
    max = Math.max(max, card.orderIndex ?? -1);
  }
  return max;
}

function descendantIDs(childrenMap, rootIDs) {
  const queue = [...rootIDs];
  const seen = new Set(rootIDs);
  const descendants = [];
  while (queue.length) {
    const current = queue.shift();
    const kids = childrenMap.get(current) ?? [];
    for (const kid of kids) {
      if (seen.has(kid.id)) continue;
      seen.add(kid.id);
      descendants.push(kid.id);
      queue.push(kid.id);
    }
  }
  return descendants;
}

function sha256(content) {
  return crypto.createHash("sha256").update(content).digest("hex");
}

function normalizeActContent(act) {
  return `${act.title} | ${act.rangeText}\n\n${act.body}`;
}

function normalizeOutlineContent(outline) {
  return `개요 ${outline.number} | ${outline.rangeText} | ${outline.title}\n\n${outline.body}`;
}

function normalizeSynopsisContent(synopsis) {
  return `시놉시스 ${synopsis.number} | 개요 ${synopsis.outlineNumber} | ${synopsis.rangeText} | ${synopsis.title}\n\n${synopsis.body}`;
}

function normalizeSequenceContent(sequence) {
  return `시퀀스 ${sequence.number} | 시놉시스 ${sequence.synopsisNumber} | ${sequence.rangeText} | ${sequence.title}\n\n${sequence.body}`;
}

function normalizeTreatmentContent(treatment) {
  return `트리트먼트 ${treatment.number} | 시퀀스 ${treatment.sequenceNumber} | 씬 ${treatment.sceneNumber} | ${treatment.sceneHeading}\n\n${treatment.body}`;
}

function groupBy(items, keyFn) {
  const grouped = new Map();
  for (const item of items) {
    const key = keyFn(item);
    if (!grouped.has(key)) grouped.set(key, []);
    grouped.get(key).push(item);
  }
  return grouped;
}

function parseDocuments() {
  const actText = read(DOCS.acts);
  const outlineText = read(DOCS.outlines);
  const synopsisText = read(DOCS.synopses);
  const sequenceText = read(DOCS.sequences);
  const treatmentText = read(DOCS.treatments);

  const acts = parseSections(
    actText,
    /^### (시작|중간1|중간2|끝) \| (\d{3}-\d{3})$/gm,
    (match, body) => {
      const title = match[1];
      const { start, end, rangeText } = parseRange(match[2]);
      return { title, start, end, rangeText, body };
    },
  );

  const outlines = parseSections(
    outlineText,
    /^### 개요 (\d{2}) \| (\d{3}-\d{3}) \| (.+)$/gm,
    (match, body) => {
      const number = match[1];
      const { start, end, rangeText } = parseRange(match[2]);
      const act = acts.find((item) => start >= item.start && end <= item.end);
      if (!act) throw new Error(`개요 ${number} act 매핑 실패`);
      return {
        number,
        start,
        end,
        rangeText,
        title: match[3].trim(),
        body,
        actTitle: act.title,
      };
    },
  );

  const synopses = parseSections(
    synopsisText,
    /^### Synopsis (\d{2}) \| 개요 (\d{2}) \| (\d{3}(?:-\d{3})?) \| (.+)$/gm,
    (match, body) => {
      const number = match[1];
      const outlineNumber = match[2];
      const { start, end, rangeText } = parseRange(match[3]);
      return {
        number,
        outlineNumber,
        start,
        end,
        rangeText,
        title: match[4].trim(),
        body,
      };
    },
  );

  const sequences = parseSections(
    sequenceText,
    /^### Sequence (\d{2}) \| Synopsis (\d{2}) \| (\d{3}(?:-\d{3})?) \| (.+)$/gm,
    (match, body) => {
      const number = match[1];
      const synopsisNumber = match[2];
      const { start, end, rangeText } = parseRange(match[3]);
      return {
        number,
        synopsisNumber,
        start,
        end,
        rangeText,
        title: match[4].trim(),
        body,
      };
    },
  );

  const treatments = parseSections(
    treatmentText,
    /^### Treatment (\d{3}) \| Sequence (\d{2}) \| Scene (\d{3}) \| (.+)$/gm,
    (match, body) => ({
      number: match[1],
      sequenceNumber: match[2],
      sceneNumber: match[3],
      sceneHeading: match[4].trim(),
      body,
    }),
  );

  for (const treatment of treatments) {
    const rawPath = `${DOCS.rawDir}/scene_${treatment.sceneNumber}.txt`;
    if (!fs.existsSync(rawPath)) throw new Error(`원문 씬 파일 없음: ${rawPath}`);
    treatment.rawPath = rawPath;
    treatment.rawText = fs.readFileSync(rawPath, "utf8");
  }

  return { acts, outlines, synopses, sequences, treatments };
}

function main() {
  const docs = parseDocuments();
  const rawVerification = readJSON(DOCS.rawVerification);
  const cards = readJSON(INDEX_PATH);
  if (!Array.isArray(cards)) throw new Error("cards_index.json must be an array");
  if (!fs.existsSync(REPORTS.backup)) fs.copyFileSync(INDEX_PATH, REPORTS.backup);

  const byId = buildById(cards);
  const childrenMap = buildChildrenMap(cards);
  const aiChildren = (childrenMap.get(AI_ID) ?? []).filter((card) => !card.isArchived);

  const actCards = new Map();
  for (const actTitle of ["시작", "중간1", "중간2", "끝"]) {
    const card = aiChildren.find((item) => {
      const path = cardPath(item.id);
      const text = fs.existsSync(path) ? read(path) : "";
      return firstLine(text).startsWith(actTitle);
    });
    if (!card) throw new Error(`상위 act 카드 없음: ${actTitle}`);
    actCards.set(actTitle, card);
  }

  const actIds = [...actCards.values()].map((card) => card.id);
  const oldDescendantIds = descendantIDs(childrenMap, actIds);
  const archivedNow = [];
  for (const id of oldDescendantIds) {
    const card = byId.get(id);
    if (!card) continue;
    if (!card.isArchived) archivedNow.push(id);
    card.isArchived = true;
  }

  const nextOrderByParent = new Map();
  function claimOrder(parentID) {
    if (!nextOrderByParent.has(parentID)) nextOrderByParent.set(parentID, maxOrder(cards, parentID) + 1);
    const next = nextOrderByParent.get(parentID);
    nextOrderByParent.set(parentID, next + 1);
    return next;
  }

  const writes = new Map();
  const created = {
    outlines: [],
    synopses: [],
    sequences: [],
    treatments: [],
    rawScenes: [],
  };

  const outlineByAct = groupBy(docs.outlines, (item) => item.actTitle);
  const synopsisByOutline = groupBy(docs.synopses, (item) => item.outlineNumber);
  const sequenceBySynopsis = groupBy(docs.sequences, (item) => item.synopsisNumber);
  const treatmentBySequence = groupBy(docs.treatments, (item) => item.sequenceNumber);

  function addCard(content, parentID, bucket, meta) {
    const id = makeID();
    const entry = {
      category: CATEGORY,
      createdAt: now,
      id,
      isArchived: false,
      isFloating: false,
      orderIndex: claimOrder(parentID),
      parentID,
      scenarioID: SCENARIO_ID,
      schemaVersion: SCHEMA_VERSION,
    };
    cards.push(entry);
    byId.set(id, entry);
    writes.set(id, content);
    bucket.push({ id, ...meta });
    return entry;
  }

  function setLastSelected(parentID, childID) {
    const parent = byId.get(parentID);
    if (!parent) return;
    if (childID) parent.lastSelectedChildID = childID;
    else delete parent.lastSelectedChildID;
  }

  function createOutlineBranch(outline) {
    const actCard = actCards.get(outline.actTitle);
    const outlineCard = addCard(normalizeOutlineContent(outline), actCard.id, created.outlines, {
      number: outline.number,
      actTitle: outline.actTitle,
      rangeText: outline.rangeText,
      title: outline.title,
    });

    const synopses = synopsisByOutline.get(outline.number) ?? [];
    let lastSynopsisId;
    for (const synopsis of synopses) {
      const synopsisCard = addCard(normalizeSynopsisContent(synopsis), outlineCard.id, created.synopses, {
        number: synopsis.number,
        outlineNumber: synopsis.outlineNumber,
        rangeText: synopsis.rangeText,
        title: synopsis.title,
      });
      lastSynopsisId = synopsisCard.id;

      const sequences = sequenceBySynopsis.get(synopsis.number) ?? [];
      let lastSequenceId;
      for (const sequence of sequences) {
        const sequenceCard = addCard(normalizeSequenceContent(sequence), synopsisCard.id, created.sequences, {
          number: sequence.number,
          synopsisNumber: sequence.synopsisNumber,
          rangeText: sequence.rangeText,
          title: sequence.title,
        });
        lastSequenceId = sequenceCard.id;

        const treatments = treatmentBySequence.get(sequence.number) ?? [];
        let lastTreatmentId;
        for (const treatment of treatments) {
          const treatmentCard = addCard(normalizeTreatmentContent(treatment), sequenceCard.id, created.treatments, {
            number: treatment.number,
            sequenceNumber: treatment.sequenceNumber,
            sceneNumber: treatment.sceneNumber,
            sceneHeading: treatment.sceneHeading,
          });
          lastTreatmentId = treatmentCard.id;

          const rawCard = addCard(treatment.rawText, treatmentCard.id, created.rawScenes, {
            sceneNumber: treatment.sceneNumber,
            treatmentNumber: treatment.number,
            sha256: sha256(treatment.rawText),
          });
          setLastSelected(treatmentCard.id, rawCard.id);
        }
        setLastSelected(sequenceCard.id, lastTreatmentId);
      }
      setLastSelected(synopsisCard.id, lastSequenceId);
    }
    setLastSelected(outlineCard.id, lastSynopsisId);
    return outlineCard;
  }

  for (const act of docs.acts) {
    const actCard = actCards.get(act.title);
    writes.set(actCard.id, normalizeActContent(act));
    delete actCard.lastSelectedChildID;
  }

  const outlineOrder = docs.outlines.slice().sort((a, b) => Number(a.number) - Number(b.number));
  const sampleOutline = outlineOrder[0];
  const sampleOutlineCard = createOutlineBranch(sampleOutline);
  const sampleOutlineSynopsisNumbers = new Set((synopsisByOutline.get(sampleOutline.number) ?? []).map((item) => item.number));

  const expectedSample = {
    synopses: sampleOutlineSynopsisNumbers.size,
    sequences: docs.sequences.filter((item) => sampleOutlineSynopsisNumbers.has(item.synopsisNumber)).length,
    treatments: docs.treatments.filter((item) => Number(item.number) >= sampleOutline.start && Number(item.number) <= sampleOutline.end).length,
  };

  const sampleSynopsisCards = created.synopses.filter((item) => item.outlineNumber === sampleOutline.number);
  const sampleSequenceCards = created.sequences.filter((item) => {
    const synopsis = docs.synopses.find((entry) => entry.number === item.synopsisNumber);
    return synopsis?.outlineNumber === sampleOutline.number;
  });
  const sampleTreatmentCards = created.treatments.filter((item) => Number(item.number) >= sampleOutline.start && Number(item.number) <= sampleOutline.end);
  const sampleRawCards = created.rawScenes.filter((item) => Number(item.sceneNumber) >= sampleOutline.start && Number(item.sceneNumber) <= sampleOutline.end);

  if (
    sampleSynopsisCards.length !== expectedSample.synopses ||
    sampleSequenceCards.length !== expectedSample.sequences ||
    sampleTreatmentCards.length !== expectedSample.treatments ||
    sampleRawCards.length !== expectedSample.treatments
  ) {
    throw new Error("샘플 브랜치 생성 검증 실패");
  }

  for (const outline of outlineOrder.slice(1)) createOutlineBranch(outline);

  for (const act of docs.acts) {
    const actCard = actCards.get(act.title);
    const actOutlineCards = created.outlines.filter((item) => item.actTitle === act.title);
    setLastSelected(actCard.id, actOutlineCards.at(-1)?.id);
  }

  for (const [id, content] of writes.entries()) write(cardPath(id), content);
  writeJSON(INDEX_PATH, cards);

  const createdRawByScene = new Map(created.rawScenes.map((item) => [item.sceneNumber, item]));
  const rawMismatches = [];
  for (const treatment of docs.treatments) {
    const rawCard = createdRawByScene.get(treatment.sceneNumber);
    const rawCardText = read(cardPath(rawCard.id));
    if (rawCardText !== treatment.rawText) {
      rawMismatches.push({
        sceneNumber: treatment.sceneNumber,
        expectedSha256: sha256(treatment.rawText),
        actualSha256: sha256(rawCardText),
      });
    }
  }

  const visibleActChildren = {};
  for (const act of docs.acts) {
    const card = actCards.get(act.title);
    visibleActChildren[act.title] = cards.filter((item) => item.parentID === card.id && !item.isArchived).length;
  }

  const verification = {
    ok:
      docs.acts.length === 4 &&
      docs.outlines.length === 11 &&
      docs.synopses.length === 22 &&
      docs.sequences.length === 48 &&
      docs.treatments.length === 116 &&
      created.outlines.length === 11 &&
      created.synopses.length === 22 &&
      created.sequences.length === 48 &&
      created.treatments.length === 116 &&
      created.rawScenes.length === 116 &&
      rawMismatches.length === 0,
    source: {
      rawVerificationPath: DOCS.rawVerification,
      sourceSha256: rawVerification.source_sha256,
      sourceBytes: rawVerification.source_bytes,
      totalScenes: rawVerification.total_scenes,
      allExactMatchesFromPhaseF: rawVerification.all_exact_matches,
    },
    archivedVisibleDescendants: archivedNow.length,
    createdCounts: {
      actsReused: docs.acts.length,
      outlines: created.outlines.length,
      synopses: created.synopses.length,
      sequences: created.sequences.length,
      treatments: created.treatments.length,
      rawScenes: created.rawScenes.length,
    },
    visibleActChildren,
    sampleBranch: {
      outlineNumber: sampleOutline.number,
      outlineCardID: sampleOutlineCard.id,
      synopses: sampleSynopsisCards.length,
      sequences: sampleSequenceCards.length,
      treatments: sampleTreatmentCards.length,
      rawScenes: sampleRawCards.length,
    },
    rawMismatches,
  };

  const idsPayload = {
    scenarioID: SCENARIO_ID,
    aiID: AI_ID,
    actCards: [...actCards.entries()].map(([title, card]) => ({ title, id: card.id })),
    archivedDescendantIDs: archivedNow,
    created,
  };

  const report = [
    "# 길동 Phase G - 앱 트리 반영",
    "",
    `- 기준 패키지: \`${PACKAGE_DIR}\``,
    `- 대상 시나리오 ID: \`${SCENARIO_ID}\``,
    `- ai 루트 ID: \`${AI_ID}\``,
    `- 백업 인덱스: \`${REPORTS.backup}\``,
    "",
    "## 1. 수행 내용",
    "",
    "- 기존 `시작/중간1/중간2/끝` 하위의 visible 브랜치를 전부 archive 처리했다.",
    "- 4막 카드는 재사용하고, 각 카드 본문을 Phase A의 막 요약으로 교체했다.",
    `- 샘플 브랜치로 \`개요 ${sampleOutline.number}\` 전체 하위 구조를 먼저 구성해 검증한 뒤 나머지 개요 브랜치를 확장했다.`,
    "- 최종 구조는 `4막 -> 개요 -> 시놉시스 -> 시퀀스 -> 트리트먼트 -> 원문`이다.",
    "",
    "## 2. 생성 결과",
    "",
    `- 4막 재사용: ${docs.acts.length}`,
    `- 개요: ${created.outlines.length}`,
    `- 시놉시스: ${created.synopses.length}`,
    `- 시퀀스: ${created.sequences.length}`,
    `- 트리트먼트: ${created.treatments.length}`,
    `- 원문: ${created.rawScenes.length}`,
    `- 이번에 archive된 기존 visible descendant: ${archivedNow.length}`,
    "",
    "## 3. 검증",
    "",
    `- 원문 카드 해시 불일치: ${rawMismatches.length}`,
    `- Phase F 기준 원문 일치 상태 승계: ${rawVerification.all_exact_matches}`,
    `- 샘플 브랜치: 개요 ${sampleOutline.number} / 시놉시스 ${sampleSynopsisCards.length} / 시퀀스 ${sampleSequenceCards.length} / 트리트먼트 ${sampleTreatmentCards.length} / 원문 ${sampleRawCards.length}`,
    "",
    "## 4. 4막 visible child 수",
    "",
    ...Object.entries(visibleActChildren).map(([title, count]) => `- ${title}: ${count}`),
    "",
  ].join("\n");

  writeJSON(REPORTS.ids, idsPayload);
  writeJSON(REPORTS.verification, verification);
  write(REPORTS.report, `${report}\n`);

  if (!verification.ok) {
    throw new Error(`Phase G verification failed: ${REPORTS.verification}`);
  }
}

main();
