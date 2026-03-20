import fs from "fs";
import crypto from "crypto";

const SOURCE_PATH =
  "/Users/three/Library/Mobile Documents/iCloud~md~obsidian/Documents/gaenari/pages/길동 9고 final.md";
const PACKAGE_PATH = "/Users/three/Documents/시나리오 작업/ver3/1st_app.wtf";
const SCENARIO_ID = "B6F21CB6-BC46-42FA-B500-6AA87BB2D468";
const AI_ID = "C0DAD9E7-4E76-4F03-9E3E-177D47B195B0";
const CARDS_DIR = `${PACKAGE_PATH}/scenario_${SCENARIO_ID}`;
const INDEX_PATH = `${CARDS_DIR}/cards_index.json`;
const IDS_PATH = "/Users/three/app_build/wa/10th_phase6_card_ids.json";

function sha256(text) {
  return crypto.createHash("sha256").update(text, "utf8").digest("hex");
}

function fail(message, details = {}) {
  const error = new Error(message);
  error.details = details;
  throw error;
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
    const heading = content.split("\n", 1)[0];
    return {
      number: index + 1,
      heading,
      content,
      bytes: Buffer.byteLength(content, "utf8"),
      hash: sha256(content),
    };
  });
}

function collectDescendants(indexMap, rootID) {
  const seen = new Set();
  const stack = [rootID];
  while (stack.length) {
    const current = stack.pop();
    for (const card of indexMap.values()) {
      if (card.parentID !== current) continue;
      if (seen.has(card.id)) continue;
      seen.add(card.id);
      stack.push(card.id);
    }
  }
  return seen;
}

function getChildren(indexMap, parentID, { visibleOnly = true } = {}) {
  return [...indexMap.values()]
    .filter((card) => card.parentID === parentID && (!visibleOnly || !card.isArchived))
    .sort((a, b) => a.orderIndex - b.orderIndex);
}

function validateRangeSeries(series, totalScenes, label) {
  const errors = [];
  const sorted = [...series].sort((a, b) => a.number - b.number);
  sorted.forEach((item, idx) => {
    if (item.number !== idx + 1) {
      errors.push(`${label} 번호 불연속: expected ${idx + 1}, got ${item.number}`);
    }
    const prevEnd = idx === 0 ? 0 : sorted[idx - 1].end;
    if (item.start !== prevEnd + 1) {
      errors.push(`${label} 범위 불연속: #${item.number} start ${item.start}, expected ${prevEnd + 1}`);
    }
    if (item.end < item.start) {
      errors.push(`${label} 범위 역전: #${item.number} ${item.start}-${item.end}`);
    }
  });
  const last = sorted.at(-1);
  if (!sorted.length || sorted[0].start !== 1 || last.end !== totalScenes) {
    errors.push(`${label} 전체 범위 미폐쇄`);
  }
  return errors;
}

function visibleIDs(indexMap, ids) {
  return ids.filter((id) => {
    const card = indexMap.get(id);
    return card && !card.isArchived;
  });
}

function main() {
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
    fail("기준 원고 고정값이 달라졌습니다.", {
      expectedSource,
      actualSource: { lines: sourceLines, bytes: sourceBytes, hash: sourceHash },
    });
  }

  const idsDoc = readJSON(IDS_PATH);
  const index = readJSON(INDEX_PATH);
  const indexMap = new Map(index.map((card) => [card.id, card]));
  const sourceScenes = splitScenes(source);
  if (sourceScenes.length !== 116) {
    fail("원고 씬 수가 116이 아닙니다.", { scenes: sourceScenes.length });
  }

  const issues = [];

  const aiCard = indexMap.get(AI_ID);
  if (!aiCard || aiCard.isArchived) {
    issues.push("ai 루트 카드가 없거나 archived 상태입니다.");
  }

  const expectedIDs = new Set(
    [
      ...idsDoc.ids.acts,
      ...idsDoc.ids.branches,
      ...idsDoc.ids.outlines,
      ...idsDoc.ids.synopses,
      ...idsDoc.ids.sequences,
      ...idsDoc.ids.treatments,
      ...idsDoc.ids.rawScenes,
    ].map((item) => item.id),
  );

  const descendantIDs = collectDescendants(indexMap, AI_ID);
  const visibleDescendantIDs = [...descendantIDs].filter((id) => !indexMap.get(id)?.isArchived);
  const archivedDescendantIDs = [...descendantIDs].filter((id) => indexMap.get(id)?.isArchived);

  const unexpectedVisible = visibleDescendantIDs.filter((id) => !expectedIDs.has(id));
  const missingVisible = [...expectedIDs].filter((id) => !visibleDescendantIDs.includes(id));
  if (unexpectedVisible.length) {
    issues.push(`예상 외 visible descendant ${unexpectedVisible.length}개`);
  }
  if (missingVisible.length) {
    issues.push(`누락된 visible descendant ${missingVisible.length}개`);
  }

  const actRangeErrors = validateRangeSeries(idsDoc.ids.acts.map((item, idx) => ({ ...item, number: idx + 1 })), 116, "4막");
  const outlineErrors = validateRangeSeries(idsDoc.ids.outlines, 116, "개요");
  const synopsisErrors = validateRangeSeries(idsDoc.ids.synopses, 116, "시놉시스");
  const sequenceErrors = validateRangeSeries(idsDoc.ids.sequences, 116, "시퀀스");
  const treatmentErrors = validateRangeSeries(idsDoc.ids.treatments, 116, "트리트먼트");
  issues.push(...actRangeErrors, ...outlineErrors, ...synopsisErrors, ...sequenceErrors, ...treatmentErrors);

  const rawNumbers = idsDoc.ids.rawScenes.map((item) => item.number);
  rawNumbers.forEach((number, idx) => {
    if (number !== idx + 1) {
      issues.push(`원문 씬 번호 불연속: expected ${idx + 1}, got ${number}`);
    }
  });

  const visibleActs = getChildren(indexMap, AI_ID).map((card) => card.id);
  const expectedActIDs = idsDoc.ids.acts.map((item) => item.id);
  if (JSON.stringify(visibleActs) !== JSON.stringify(expectedActIDs)) {
    issues.push("ai visible 자식 순서가 4막 순서와 다릅니다.");
  }

  const branchTitles = ["개요", "시놉시스", "시퀀스", "트리트먼트"];
  for (const act of idsDoc.ids.acts) {
    const actCard = indexMap.get(act.id);
    if (!actCard || actCard.parentID !== AI_ID || actCard.isArchived) {
      issues.push(`4막 카드 이상: ${act.title}`);
      continue;
    }
    const children = getChildren(indexMap, act.id);
    const childTitles = children.map((card) => fs.readFileSync(`${CARDS_DIR}/card_${card.id}.txt`, "utf8").split("\n", 1)[0]);
    if (JSON.stringify(childTitles) !== JSON.stringify(branchTitles)) {
      issues.push(`${act.title} 하위 분기 순서/제목 불일치`);
    }
  }

  for (const [seriesName, items] of Object.entries({
    outlines: idsDoc.ids.outlines,
    synopses: idsDoc.ids.synopses,
    sequences: idsDoc.ids.sequences,
    treatments: idsDoc.ids.treatments,
  })) {
    for (const item of items) {
      const card = indexMap.get(item.id);
      if (!card || card.isArchived) {
        issues.push(`${seriesName} 카드 누락: ${item.id}`);
        continue;
      }
      const branch = idsDoc.ids.branches.find(
        (entry) => entry.parentActID === idsDoc.ids.acts.find((act) => act.title === item.act)?.id && entry.title === ({
          outlines: "개요",
          synopses: "시놉시스",
          sequences: "시퀀스",
          treatments: "트리트먼트",
        })[seriesName],
      );
      if (!branch || card.parentID !== branch.id) {
        issues.push(`${seriesName} 부모 분기 불일치: #${item.number}`);
      }
    }
  }

  const rawValidation = [];
  for (const raw of idsDoc.ids.rawScenes) {
    const sourceScene = sourceScenes[raw.number - 1];
    const card = indexMap.get(raw.id);
    if (!card || card.isArchived) {
      issues.push(`원문 카드 누락/archived: ${raw.number}`);
      continue;
    }
    const cardPath = `${CARDS_DIR}/card_${raw.id}.txt`;
    if (!fs.existsSync(cardPath)) {
      issues.push(`원문 파일 누락: ${raw.number}`);
      continue;
    }
    const content = fs.readFileSync(cardPath, "utf8");
    const hash = sha256(content);
    const bytes = Buffer.byteLength(content, "utf8");
    const match = content === sourceScene.content;
    if (!match) {
      issues.push(`원문 본문 불일치: ${raw.number}`);
    }
    if (raw.hash !== hash) {
      issues.push(`원문 해시 메타 불일치: ${raw.number}`);
    }
    if (raw.bytes !== bytes) {
      issues.push(`원문 바이트 메타 불일치: ${raw.number}`);
    }
    if (raw.heading !== sourceScene.heading) {
      issues.push(`원문 헤딩 메타 불일치: ${raw.number}`);
    }
    rawValidation.push({
      number: raw.number,
      id: raw.id,
      heading: sourceScene.heading,
      bytes,
      hash,
      matchesSource: match,
    });
  }

  for (const treatment of idsDoc.ids.treatments) {
    const treatmentCard = indexMap.get(treatment.id);
    const treatmentChildren = getChildren(indexMap, treatment.id);
    const expectedRaw = idsDoc.ids.rawScenes
      .filter((item) => item.number >= treatment.start && item.number <= treatment.end)
      .map((item) => item.id);
    const actualRaw = treatmentChildren.map((card) => card.id);
    if (JSON.stringify(expectedRaw) !== JSON.stringify(actualRaw)) {
      issues.push(`트리트먼트 ${String(treatment.number).padStart(2, "0")} 원문 자식 순서 불일치`);
    }
    if (!treatmentCard || treatmentCard.isArchived) {
      issues.push(`트리트먼트 카드 누락/archived: ${treatment.number}`);
    }
  }

  const summary = {
    source: {
      lines: sourceLines,
      bytes: sourceBytes,
      hash: sourceHash,
      scenes: sourceScenes.length,
    },
    counts: {
      acts: idsDoc.ids.acts.length,
      branches: idsDoc.ids.branches.length,
      outlines: idsDoc.ids.outlines.length,
      synopses: idsDoc.ids.synopses.length,
      sequences: idsDoc.ids.sequences.length,
      treatments: idsDoc.ids.treatments.length,
      rawScenes: idsDoc.ids.rawScenes.length,
      expectedVisibleDescendants: expectedIDs.size,
      actualVisibleDescendants: visibleDescendantIDs.length,
      archivedDescendantsUnderAI: archivedDescendantIDs.length,
    },
    continuity: {
      acts: actRangeErrors.length === 0,
      outlines: outlineErrors.length === 0,
      synopses: synopsisErrors.length === 0,
      sequences: sequenceErrors.length === 0,
      treatments: treatmentErrors.length === 0,
      rawScenes: rawNumbers.length === 116 && rawNumbers.every((n, idx) => n === idx + 1),
    },
    appTree: {
      aiVisibleChildren: visibleActs,
      expectedActIDs,
      branchTitles,
    },
    rawIntegrity: {
      validated: rawValidation.length,
      mismatches: rawValidation.filter((item) => !item.matchesSource).map((item) => item.number),
      firstScene: rawValidation[0],
      lastScene: rawValidation.at(-1),
    },
    issues,
    ok: issues.length === 0,
  };

  console.log(JSON.stringify(summary, null, 2));
}

try {
  main();
} catch (error) {
  console.error(
    JSON.stringify(
      {
        ok: false,
        error: error.message,
        details: error.details ?? null,
      },
      null,
      2,
    ),
  );
  process.exit(1);
}
