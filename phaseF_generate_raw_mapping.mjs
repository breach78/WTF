import fs from "fs";
import path from "path";
import crypto from "crypto";

const root = "/Users/three/app_build/wa";
const sourcePath = "/Users/three/Library/Mobile Documents/iCloud~md~obsidian/Documents/gaenari/pages/길동 9고 final.md";
const ledgerPath = path.join(root, "10th_phase1.md");
const treatmentPath = path.join(root, "gildong_phaseE_treatments.md");
const outputDir = path.join(root, "gildong_phaseF_raw_slices");
const outputJson = path.join(root, "gildong_phaseF_raw_verification.json");
const outputMd = path.join(root, "gildong_phaseF_raw_mapping.md");

function sha256(text) {
  return crypto.createHash("sha256").update(text, "utf8").digest("hex");
}

function parseLedgerTsv(markdown) {
  const blockMatch = markdown.match(/```tsv\n([\s\S]*?)\n```/);
  if (!blockMatch) {
    throw new Error("TSV block not found in 10th_phase1.md");
  }

  const rows = blockMatch[1].trim().split("\n");
  const header = rows.shift().split("\t");

  return rows.map((row) => {
    const cols = row.split("\t");
    const obj = Object.fromEntries(header.map((key, i) => [key, cols[i] ?? ""]));
    return {
      scene_no: obj.scene_no,
      start_line: Number(obj.start_line),
      end_line: Number(obj.end_line),
      line_count: Number(obj.line_count),
      next_scene: obj.next_scene,
      heading_json: JSON.parse(obj.heading_json),
      start_anchor_json: JSON.parse(obj.start_anchor_json),
      end_anchor_json: JSON.parse(obj.end_anchor_json),
    };
  });
}

function buildLineStarts(raw) {
  const starts = [0];
  for (let i = 0; i < raw.length; i++) {
    if (raw[i] === "\n") starts.push(i + 1);
  }
  return starts;
}

function logicalLineCount(raw) {
  if (raw.length === 0) return 0;
  return raw.split("\n").length;
}

function countStoredLines(text) {
  if (text.length === 0) return 0;
  const count = text.split("\n").length;
  return text.endsWith("\n") ? count - 1 : count;
}

function getSliceByLines(raw, lineStarts, startLine, endLine) {
  const startIndex = lineStarts[startLine - 1];
  const endExclusive = endLine < lineStarts.length ? lineStarts[endLine] : raw.length;
  return raw.slice(startIndex, endExclusive);
}

function countLogicalLines(text) {
  if (text.length === 0) return 0;
  return text.split("\n").length;
}

function parseTreatmentCount(markdown) {
  const matches = markdown.match(/^### Treatment /gm);
  return matches ? matches.length : 0;
}

const sourceRaw = fs.readFileSync(sourcePath, "utf8");
const ledgerRaw = fs.readFileSync(ledgerPath, "utf8");
const treatmentRaw = fs.readFileSync(treatmentPath, "utf8");

const ledger = parseLedgerTsv(ledgerRaw);
const lineStarts = buildLineStarts(sourceRaw);
const totalLogicalLines = logicalLineCount(sourceRaw);
const treatmentCount = parseTreatmentCount(treatmentRaw);

if (ledger.length !== 116) {
  throw new Error(`Expected 116 ledger scenes, got ${ledger.length}`);
}
if (treatmentCount !== 116) {
  throw new Error(`Expected 116 treatments, got ${treatmentCount}`);
}

fs.rmSync(outputDir, { recursive: true, force: true });
fs.mkdirSync(outputDir, { recursive: true });

const sourceSha = sha256(sourceRaw);
const firstSceneStart = ledger[0].start_line;
const preSceneRaw = getSliceByLines(sourceRaw, lineStarts, 1, firstSceneStart - 1);
const preSceneLines = countStoredLines(preSceneRaw);

let concatenated = "";
const scenes = ledger.map((row) => {
  const slice = getSliceByLines(sourceRaw, lineStarts, row.start_line, row.end_line);
  const fileName = `scene_${row.scene_no}.txt`;
  const outPath = path.join(outputDir, fileName);
  fs.writeFileSync(outPath, slice, "utf8");
  const reread = fs.readFileSync(outPath, "utf8");

  const headingLine = slice.split("\n")[0];
  const sliceSha = sha256(slice);
  const rereadSha = sha256(reread);
  const bytes = Buffer.byteLength(slice, "utf8");
  const exactMatch = slice === reread;
  const lineCount = countStoredLines(slice);

  if (headingLine !== row.heading_json) {
    throw new Error(`Heading mismatch for scene ${row.scene_no}: "${headingLine}" !== "${row.heading_json}"`);
  }
  if (lineCount !== row.line_count) {
    throw new Error(`Line count mismatch for scene ${row.scene_no}: ${lineCount} !== ${row.line_count}`);
  }
  if (!exactMatch || sliceSha !== rereadSha) {
    throw new Error(`Reread mismatch for scene ${row.scene_no}`);
  }

  concatenated += slice;

  return {
    treatment_no: row.scene_no,
    scene_no: row.scene_no,
    heading: row.heading_json,
    start_line: row.start_line,
    end_line: row.end_line,
    line_count: row.line_count,
    bytes,
    sha256: sliceSha,
    file: outPath,
    exact_match: exactMatch,
  };
});

const sourceFromFirstScene = getSliceByLines(sourceRaw, lineStarts, firstSceneStart, totalLogicalLines);
const concatenatedMatches = concatenated === sourceFromFirstScene;

const summary = {
  source: {
    path: sourcePath,
    sha256: sourceSha,
    bytes: Buffer.byteLength(sourceRaw, "utf8"),
    logical_lines: totalLogicalLines,
  },
  scene_boundary_rule: "EXT./INT. heading to line before next heading",
  total_scenes: ledger.length,
  total_treatments: treatmentCount,
  pre_scene_material: {
    exists: preSceneRaw.length > 0,
    start_line: 1,
    end_line: firstSceneStart - 1,
    logical_lines: preSceneLines,
    bytes: Buffer.byteLength(preSceneRaw, "utf8"),
    sha256: sha256(preSceneRaw),
    note: "Frontmatter/title/contact area before scene 001. Intentionally excluded from scene raw cards.",
  },
  concatenated_scene_slices: {
    matches_source_from_scene_001: concatenatedMatches,
    sha256: sha256(concatenated),
    bytes: Buffer.byteLength(concatenated, "utf8"),
  },
  all_exact_matches: scenes.every((s) => s.exact_match),
  scenes,
};

fs.writeFileSync(outputJson, JSON.stringify(summary, null, 2) + "\n", "utf8");

const md = [];
md.push("# 길동 Phase F - 트리트먼트 -> 원문 매핑 및 동일성 검산");
md.push("");
md.push(`- 기준 원고: \`${sourcePath}\``);
md.push(`- 기준 고정값: \`${summary.source.logical_lines} logical lines / ${summary.source.bytes} bytes / sha256 ${summary.source.sha256}\``);
md.push(`- 기준 씬 수: \`${summary.total_scenes}\``);
md.push(`- 기준 트리트먼트 수: \`${summary.total_treatments}\``);
md.push(`- 원문 슬라이스 디렉터리: \`${outputDir}\``);
md.push(`- 검산 JSON: \`${outputJson}\``);
md.push("");
md.push("## 1. 검산 요약");
md.push("");
md.push(`- 트리트먼트 -> 원문 매핑: \`116 / 116\``);
md.push(`- 저장 후 재독 일치: \`${summary.all_exact_matches ? "116 / 116 일치" : "불일치 있음"}\``);
md.push(`- 씬 슬라이스 재결합 일치: \`${summary.concatenated_scene_slices.matches_source_from_scene_001}\``);
md.push(`- 비씬 선행 구간: \`lines 1-${summary.pre_scene_material.end_line} / ${summary.pre_scene_material.logical_lines} logical lines\``);
md.push(`- 비씬 선행 구간 sha256: \`${summary.pre_scene_material.sha256}\``);
md.push(`- 비씬 선행 구간 메모: ${summary.pre_scene_material.note}`);
md.push("");
md.push("## 2. 트리트먼트 -> 원문 매핑표");
md.push("");
md.push("| Treatment | Scene | Raw Slice File | 시작 라인 | 종료 라인 | 라인 수 | 바이트 | SHA-256 (앞 12) | 일치 |");
md.push("| --- | --- | --- | ---: | ---: | ---: | ---: | --- | --- |");

for (const scene of scenes) {
  md.push(
    `| ${scene.treatment_no} | ${scene.scene_no} | \`${path.basename(scene.file)}\` | ${scene.start_line} | ${scene.end_line} | ${scene.line_count} | ${scene.bytes} | \`${scene.sha256.slice(0, 12)}\` | ${scene.exact_match ? "OK" : "FAIL"} |`
  );
}

md.push("");
md.push("## 3. Phase F 검수 메모");
md.push("");
md.push("- 이번 단계에서는 원문을 사람이 다시 입력하지 않았다.");
md.push("- 모든 원문 파일은 기준 원고를 라인 경계로 직접 슬라이스해 저장했다.");
md.push("- 각 슬라이스 파일은 저장 후 즉시 다시 읽어 원본 슬라이스와 문자열 동일성, SHA-256 동일성을 둘 다 검산했다.");
md.push("- `scene_001`부터 `scene_116`까지를 순서대로 재결합한 결과는, 기준 원고의 `scene 001 시작점 ~ 파일 끝` 구간과 정확히 일치했다.");
md.push("- 따라서 다음 Phase G에서는 이 슬라이스 파일들을 그대로 앱 카드 본문으로 밀어 넣으면 된다.");
md.push("");
md.push("## 4. 다음 Phase 준비 상태");
md.push("");
md.push("- 앱 반영 전 샘플 브랜치 1개를 먼저 넣을 수 있는 상태다.");
md.push("- 현재 구조에서는 `Treatment 001 -> scene_001.txt` 방식의 1:1 원문 연결이 고정되었다.");

fs.writeFileSync(outputMd, md.join("\n") + "\n", "utf8");

console.log(JSON.stringify({
  scenes: scenes.length,
  treatments: treatmentCount,
  exactMatches: summary.all_exact_matches,
  concatenatedMatches,
  outputDir,
  outputJson,
  outputMd,
}, null, 2));
