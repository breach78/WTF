import fs from 'node:fs/promises';
import path from 'node:path';
import { randomUUID } from 'node:crypto';

export const CATEGORY_LABELS = Object.freeze({
  plot: '플롯',
  note: '노트',
  craft: '작법',
  uncategorized: '미분류'
});

const CATEGORY_RANK = new Map([
  [CATEGORY_LABELS.plot, 0],
  [CATEGORY_LABELS.note, 1],
  [CATEGORY_LABELS.craft, 2]
]);

const CATEGORY_ALIASES = new Map([
  ['plot', CATEGORY_LABELS.plot],
  ['플롯', CATEGORY_LABELS.plot],
  ['plotline', CATEGORY_LABELS.plot],
  ['story', CATEGORY_LABELS.plot],
  ['note', CATEGORY_LABELS.note],
  ['notes', CATEGORY_LABELS.note],
  ['노트', CATEGORY_LABELS.note],
  ['memo', CATEGORY_LABELS.note],
  ['craft', CATEGORY_LABELS.craft],
  ['작법', CATEGORY_LABELS.craft],
  ['writing', CATEGORY_LABELS.craft],
  ['uncategorized', CATEGORY_LABELS.uncategorized],
  ['미분류', CATEGORY_LABELS.uncategorized]
]);

const CURRENT_SCHEMA_VERSION = 3;
const SHARED_CRAFT_ROOT_CARD_ID = 'F2EE98E5-93B4-4F58-85A3-3D0C89B1C3E1';

function normalizeLineEndings(text) {
  return String(text ?? '').replace(/\r\n/g, '\n').replace(/\r/g, '\n');
}

function normalizeSearchText(text) {
  return normalizeLineEndings(text).toLowerCase().replace(/\s+/g, '');
}

function normalizeDuplicateKey(text) {
  return normalizeLineEndings(text)
    .toLowerCase()
    .replace(/[\p{P}\p{S}\s]+/gu, '');
}

function normalizeSummaryText(text) {
  return normalizeLineEndings(text)
    .split('\n')
    .map(line => line.trim())
    .filter(Boolean)
    .join(' ')
    .replace(/\s+/g, ' ')
    .trim();
}

function stableSortValue(value) {
  if (Array.isArray(value)) {
    return value.map(stableSortValue);
  }
  if (value && typeof value === 'object' && !(value instanceof Date)) {
    return Object.keys(value)
      .sort()
      .reduce((result, key) => {
        const nextValue = value[key];
        if (nextValue !== undefined) {
          result[key] = stableSortValue(nextValue);
        }
        return result;
      }, {});
  }
  return value;
}

function toStableJson(value) {
  return JSON.stringify(stableSortValue(value));
}

async function readJsonFile(filePath, fallbackValue) {
  try {
    const raw = await fs.readFile(filePath, 'utf8');
    return JSON.parse(raw);
  } catch (error) {
    if (error && error.code === 'ENOENT') {
      return fallbackValue;
    }
    throw error;
  }
}

async function readTextFile(filePath, fallbackValue = '') {
  try {
    return await fs.readFile(filePath, 'utf8');
  } catch (error) {
    if (error && error.code === 'ENOENT') {
      return fallbackValue;
    }
    throw error;
  }
}

async function ensureDirectory(dirPath) {
  await fs.mkdir(dirPath, { recursive: true });
}

async function writeFileAtomic(filePath, content) {
  const tempPath = `${filePath}.tmp-${process.pid}-${randomUUID()}`;
  await fs.writeFile(tempPath, content, 'utf8');
  await fs.rename(tempPath, filePath);
}

function compareIsoDatesAsc(lhs, rhs) {
  return String(lhs ?? '').localeCompare(String(rhs ?? ''));
}

function compareCards(lhs, rhs) {
  if ((lhs.orderIndex ?? 0) !== (rhs.orderIndex ?? 0)) {
    return (lhs.orderIndex ?? 0) - (rhs.orderIndex ?? 0);
  }
  const dateComparison = compareIsoDatesAsc(lhs.createdAt, rhs.createdAt);
  if (dateComparison !== 0) {
    return dateComparison;
  }
  return String(lhs.id).localeCompare(String(rhs.id));
}

function compareScenarios(lhs, rhs) {
  if (Boolean(lhs.isTemplate) !== Boolean(rhs.isTemplate)) {
    return lhs.isTemplate ? 1 : -1;
  }
  const timestampComparison = String(rhs.timestamp ?? '').localeCompare(String(lhs.timestamp ?? ''));
  if (timestampComparison !== 0) {
    return timestampComparison;
  }
  return String(lhs.id).localeCompare(String(rhs.id));
}

function makeBigrams(text) {
  const chars = Array.from(text);
  if (chars.length <= 1) {
    return chars.length === 0 ? [] : [chars[0]];
  }
  const bigrams = [];
  for (let index = 0; index < chars.length - 1; index += 1) {
    bigrams.push(chars[index] + chars[index + 1]);
  }
  return bigrams;
}

function diceCoefficient(lhs, rhs) {
  const left = makeBigrams(lhs);
  const right = makeBigrams(rhs);
  if (left.length === 0 || right.length === 0) {
    return 0;
  }

  const counts = new Map();
  for (const token of left) {
    counts.set(token, (counts.get(token) ?? 0) + 1);
  }

  let overlap = 0;
  for (const token of right) {
    const count = counts.get(token) ?? 0;
    if (count > 0) {
      overlap += 1;
      counts.set(token, count - 1);
    }
  }

  return (2 * overlap) / (left.length + right.length);
}

function findDuplicateMatch(content, candidates) {
  const normalized = normalizeDuplicateKey(content);
  if (!normalized) {
    return null;
  }

  let bestMatch = null;
  for (const candidate of candidates) {
    const candidateKey = normalizeDuplicateKey(candidate.content);
    if (!candidateKey) {
      continue;
    }

    if (candidateKey === normalized) {
      return { ...candidate, score: 1, kind: 'exact' };
    }

    const shorterLength = Math.min(candidateKey.length, normalized.length);
    const longerLength = Math.max(candidateKey.length, normalized.length);
    if (
      shorterLength >= 8 &&
      longerLength > 0 &&
      shorterLength / longerLength >= 0.88 &&
      (candidateKey.includes(normalized) || normalized.includes(candidateKey))
    ) {
      return { ...candidate, score: shorterLength / longerLength, kind: 'containment' };
    }

    const score = diceCoefficient(candidateKey, normalized);
    if (score >= 0.94 && (!bestMatch || score > bestMatch.score)) {
      bestMatch = { ...candidate, score, kind: 'similar' };
    }
  }

  return bestMatch;
}

function categoryLabelFromInput(value) {
  const normalized = String(value ?? '').trim().toLowerCase();
  const resolved = CATEGORY_ALIASES.get(normalized);
  if (!resolved) {
    throw new Error(`Unknown category: ${value}`);
  }
  return resolved;
}

function summarizeCardForList(card) {
  return {
    id: card.id,
    content: card.content,
    category: card.category ?? CATEGORY_LABELS.uncategorized,
    parentId: card.parentID ?? null,
    orderIndex: card.orderIndex,
    createdAt: card.createdAt,
    isArchived: Boolean(card.isArchived)
  };
}

function normalizeScenarioRecord(record) {
  return {
    id: String(record.id),
    title: String(record.title ?? '제목 없음'),
    isTemplate: Boolean(record.isTemplate),
    timestamp: String(record.timestamp ?? new Date().toISOString()),
    changeCountSinceLastSnapshot: Number(record.changeCountSinceLastSnapshot ?? 0),
    folderName: record.folderName ? String(record.folderName) : null,
    schemaVersion: Number(record.schemaVersion ?? CURRENT_SCHEMA_VERSION)
  };
}

function normalizeCardRecord(record, content) {
  return {
    id: String(record.id),
    scenarioID: String(record.scenarioID),
    parentID: record.parentID ? String(record.parentID) : null,
    orderIndex: Number(record.orderIndex ?? 0),
    createdAt: String(record.createdAt ?? new Date().toISOString()),
    category: record.category ? String(record.category) : null,
    isFloating: Boolean(record.isFloating),
    isArchived: Boolean(record.isArchived),
    lastSelectedChildID: record.lastSelectedChildID ? String(record.lastSelectedChildID) : null,
    schemaVersion: Number(record.schemaVersion ?? CURRENT_SCHEMA_VERSION),
    colorHex: record.colorHex ? String(record.colorHex) : null,
    cloneGroupID: record.cloneGroupID ? String(record.cloneGroupID) : null,
    content: normalizeLineEndings(content ?? '')
  };
}

function normalizeHistoryRecord(record) {
  return {
    id: String(record.id),
    timestamp: String(record.timestamp ?? new Date().toISOString()),
    name: record.name == null ? null : String(record.name),
    scenarioID: String(record.scenarioID),
    cardSnapshots: Array.isArray(record.cardSnapshots) ? record.cardSnapshots : [],
    isDelta: Boolean(record.isDelta),
    deletedCardIDs: Array.isArray(record.deletedCardIDs) ? record.deletedCardIDs.map(String) : [],
    isPromoted: Boolean(record.isPromoted),
    promotionReason: record.promotionReason == null ? null : String(record.promotionReason),
    noteCardID: record.noteCardID == null ? null : String(record.noteCardID),
    schemaVersion: Number(record.schemaVersion ?? CURRENT_SCHEMA_VERSION)
  };
}

function normalizeLinkedCardRecord(record) {
  return {
    focusCardID: String(record.focusCardID),
    linkedCardID: String(record.linkedCardID),
    lastEditedAt: String(record.lastEditedAt ?? new Date().toISOString())
  };
}

function buildScenarioIndexes(scenario, includeArchived = false) {
  const cardById = new Map();
  const childrenByParent = new Map();
  const rootCards = [];

  for (const card of scenario.cards) {
    cardById.set(card.id, card);
    if (!includeArchived && card.isArchived) {
      continue;
    }

    if (card.parentID) {
      const existing = childrenByParent.get(card.parentID) ?? [];
      existing.push(card);
      childrenByParent.set(card.parentID, existing);
    } else if (!card.isFloating) {
      rootCards.push(card);
    }
  }

  rootCards.sort(compareCards);
  for (const cards of childrenByParent.values()) {
    cards.sort(compareCards);
  }

  return { cardById, childrenByParent, rootCards };
}

function buildCardPath(card, indexes) {
  const pathCards = [];
  let current = card;
  while (current) {
    pathCards.push({
      id: current.id,
      content: current.content,
      category: current.category ?? CATEGORY_LABELS.uncategorized
    });
    current = current.parentID ? indexes.cardById.get(current.parentID) ?? null : null;
  }
  return pathCards.reverse();
}

function serializeTreeNode(card, indexes, maxDepth, currentDepth = 0) {
  const children = indexes.childrenByParent.get(card.id) ?? [];
  const shouldExpandChildren = maxDepth == null || currentDepth < maxDepth;
  return {
    id: card.id,
    content: card.content,
    category: card.category ?? CATEGORY_LABELS.uncategorized,
    parentId: card.parentID ?? null,
    orderIndex: card.orderIndex,
    createdAt: card.createdAt,
    isArchived: Boolean(card.isArchived),
    childCount: children.length,
    children: shouldExpandChildren
      ? children.map(child => serializeTreeNode(child, indexes, maxDepth, currentDepth + 1))
      : [],
    hasMoreChildren: !shouldExpandChildren && children.length > 0
  };
}

function collectDescendantIds(cardId, indexes, accumulator = new Set()) {
  const children = indexes.childrenByParent.get(cardId) ?? [];
  for (const child of children) {
    accumulator.add(child.id);
    collectDescendantIds(child.id, indexes, accumulator);
  }
  return accumulator;
}

function reindexChildren(scenario, parentId) {
  const siblings = scenario.cards
    .filter(card => (card.parentID ?? null) === (parentId ?? null))
    .sort(compareCards);

  siblings.forEach((card, index) => {
    card.orderIndex = index;
  });
}

function makeCardSnapshot(card) {
  return {
    cardID: card.id,
    content: card.content,
    orderIndex: card.orderIndex,
    parentID: card.parentID ?? null,
    category: card.category ?? null,
    isFloating: Boolean(card.isFloating),
    isArchived: Boolean(card.isArchived),
    cloneGroupID: card.cloneGroupID ?? null
  };
}

function pruneLinkedCardRecords(scenario) {
  const validIds = new Set(scenario.cards.map(card => card.id));
  scenario.linkedCardRecords = scenario.linkedCardRecords.filter(record => {
    return (
      validIds.has(record.focusCardID) &&
      validIds.has(record.linkedCardID) &&
      record.focusCardID !== record.linkedCardID
    );
  });
}

function cloneGroupPeers(scenario, sourceCard) {
  if (!sourceCard.cloneGroupID) {
    return [];
  }
  return scenario.cards.filter(card => card.cloneGroupID === sourceCard.cloneGroupID && card.id !== sourceCard.id);
}

function scenarioFolderName(record) {
  return record.folderName ?? `scenario_${record.id}`;
}

function scenarioCardsIndexPath(workspacePath, folderName) {
  return path.join(workspacePath, folderName, 'cards_index.json');
}

function scenarioHistoryPath(workspacePath, folderName) {
  return path.join(workspacePath, folderName, 'history.json');
}

function scenarioLinkedCardsPath(workspacePath, folderName) {
  return path.join(workspacePath, folderName, 'linked_cards.json');
}

function scenarioCardTextPath(workspacePath, folderName, cardId) {
  return path.join(workspacePath, folderName, `card_${cardId}.txt`);
}

function cardMatchesQuery(card, queryTokens) {
  if (queryTokens.length === 0) {
    return true;
  }
  const haystack = normalizeSearchText(card.content);
  return queryTokens.every(token => haystack.includes(token));
}

function scenarioLaneRoot(scenario, categoryLabel) {
  const indexes = buildScenarioIndexes(scenario);
  const titleRoot = indexes.rootCards[0] ?? null;
  if (!titleRoot) {
    return null;
  }
  return (indexes.childrenByParent.get(titleRoot.id) ?? []).find(card => card.category === categoryLabel) ?? null;
}

function appendHistorySnapshot(scenario, reason) {
  const timestamp = new Date().toISOString();
  scenario.historyRecords.push({
    id: randomUUID(),
    timestamp,
    name: null,
    scenarioID: scenario.id,
    cardSnapshots: scenario.cards.map(makeCardSnapshot),
    isDelta: false,
    deletedCardIDs: [],
    isPromoted: true,
    promotionReason: reason,
    noteCardID: null,
    schemaVersion: CURRENT_SCHEMA_VERSION
  });
  scenario.timestamp = timestamp;
  scenario.changeCountSinceLastSnapshot = 0;
}

export class ScenarioWorkspaceStore {
  constructor({ workspacePath, scenarioId = null, scenarioTitle = null }) {
    this.workspacePath = path.resolve(workspacePath);
    this.scenarioId = scenarioId ? String(scenarioId) : null;
    this.scenarioTitle = scenarioTitle ? String(scenarioTitle) : null;
    this.writeTail = Promise.resolve();
  }

  async listScenarios() {
    const scenariosPath = path.join(this.workspacePath, 'scenarios.json');
    const records = await readJsonFile(scenariosPath, []);
    if (!Array.isArray(records)) {
      throw new Error('Invalid scenarios.json format');
    }
    return records
      .map(normalizeScenarioRecord)
      .sort(compareScenarios)
      .map(record => ({
        id: record.id,
        title: record.title,
        isTemplate: record.isTemplate,
        timestamp: record.timestamp,
        folderName: scenarioFolderName(record)
      }));
  }

  async loadWorkspace() {
    const scenariosPath = path.join(this.workspacePath, 'scenarios.json');
    const records = await readJsonFile(scenariosPath, []);
    if (!Array.isArray(records)) {
      throw new Error('Invalid scenarios.json format');
    }

    const scenarios = new Map();
    for (const rawRecord of records) {
      const record = normalizeScenarioRecord(rawRecord);
      const folderName = scenarioFolderName(record);
      const cardsRaw = await readJsonFile(scenarioCardsIndexPath(this.workspacePath, folderName), []);
      const historyRaw = await readJsonFile(scenarioHistoryPath(this.workspacePath, folderName), []);
      const linkedRaw = await readJsonFile(scenarioLinkedCardsPath(this.workspacePath, folderName), []);

      const normalizedCardRecords = Array.isArray(cardsRaw) ? cardsRaw : [];
      const cards = [];
      for (const rawCard of normalizedCardRecords) {
        const text = await readTextFile(
          scenarioCardTextPath(this.workspacePath, folderName, rawCard.id),
          ''
        );
        cards.push(normalizeCardRecord(rawCard, text));
      }

      const historyRecords = Array.isArray(historyRaw) ? historyRaw.map(normalizeHistoryRecord) : [];
      const linkedCardRecords = Array.isArray(linkedRaw) ? linkedRaw.map(normalizeLinkedCardRecord) : [];

      scenarios.set(record.id, {
        id: record.id,
        title: record.title,
        isTemplate: record.isTemplate,
        timestamp: record.timestamp,
        changeCountSinceLastSnapshot: record.changeCountSinceLastSnapshot,
        folderName,
        cards,
        historyRecords,
        linkedCardRecords
      });
    }

    const selectedScenario = this.resolveSelectedScenario(scenarios);
    return { scenarios, selectedScenario };
  }

  resolveSelectedScenario(scenarios) {
    if (this.scenarioId) {
      const found = scenarios.get(this.scenarioId);
      if (!found) {
        throw new Error(`Scenario not found for id ${this.scenarioId}`);
      }
      return found;
    }

    if (this.scenarioTitle) {
      const matches = Array.from(scenarios.values()).filter(
        scenario => scenario.title.trim() === this.scenarioTitle.trim()
      );
      if (matches.length === 0) {
        throw new Error(`Scenario not found for title ${this.scenarioTitle}`);
      }
      if (matches.length > 1) {
        throw new Error(`Multiple scenarios match title ${this.scenarioTitle}; use scenario id instead`);
      }
      return matches[0];
    }

    const nonTemplates = Array.from(scenarios.values()).filter(scenario => !scenario.isTemplate);
    if (nonTemplates.length === 1) {
      return nonTemplates[0];
    }
    if (scenarios.size === 1) {
      return Array.from(scenarios.values())[0];
    }
    throw new Error('Multiple scenarios exist; select one with --scenario-id or --scenario-title');
  }

  async saveWorkspace(workspace) {
    const scenariosPath = path.join(this.workspacePath, 'scenarios.json');
    const scenarioRecords = Array.from(workspace.scenarios.values())
      .map(scenario => ({
        id: scenario.id,
        title: scenario.title,
        isTemplate: scenario.isTemplate,
        timestamp: scenario.timestamp,
        changeCountSinceLastSnapshot: scenario.changeCountSinceLastSnapshot,
        folderName: scenario.folderName,
        schemaVersion: CURRENT_SCHEMA_VERSION
      }))
      .sort(compareScenarios);

    await ensureDirectory(this.workspacePath);
    await writeFileAtomic(scenariosPath, toStableJson(scenarioRecords));

    for (const scenario of workspace.scenarios.values()) {
      const folderPath = path.join(this.workspacePath, scenario.folderName);
      await ensureDirectory(folderPath);

      const cardRecords = scenario.cards.map(card => ({
        id: card.id,
        scenarioID: scenario.id,
        parentID: card.parentID ?? null,
        orderIndex: card.orderIndex,
        createdAt: card.createdAt,
        category: card.category ?? null,
        isFloating: Boolean(card.isFloating),
        isArchived: Boolean(card.isArchived),
        lastSelectedChildID: card.lastSelectedChildID ?? null,
        schemaVersion: CURRENT_SCHEMA_VERSION,
        colorHex: card.colorHex ?? null,
        cloneGroupID: card.cloneGroupID ?? null
      }));

      await writeFileAtomic(
        scenarioCardsIndexPath(this.workspacePath, scenario.folderName),
        toStableJson(cardRecords)
      );
      await writeFileAtomic(
        scenarioHistoryPath(this.workspacePath, scenario.folderName),
        toStableJson(scenario.historyRecords)
      );
      await writeFileAtomic(
        scenarioLinkedCardsPath(this.workspacePath, scenario.folderName),
        toStableJson(scenario.linkedCardRecords)
      );

      const validCardIds = new Set();
      for (const card of scenario.cards) {
        validCardIds.add(card.id);
        await writeFileAtomic(
          scenarioCardTextPath(this.workspacePath, scenario.folderName, card.id),
          normalizeLineEndings(card.content)
        );
      }

      const directoryEntries = await fs.readdir(folderPath);
      for (const entry of directoryEntries) {
        if (!entry.startsWith('card_') || !entry.endsWith('.txt')) {
          continue;
        }
        const id = entry.replace(/^card_/, '').replace(/\.txt$/, '');
        if (!validCardIds.has(id)) {
          await fs.rm(path.join(folderPath, entry), { force: true });
        }
      }
    }
  }

  enqueueMutation(mutate) {
    const run = this.writeTail.then(async () => {
      const workspace = await this.loadWorkspace();
      const result = await mutate(workspace, workspace.selectedScenario);
      if (result?.mutated) {
        await this.saveWorkspace(workspace);
      }
      return result;
    });
    this.writeTail = run.catch(() => {});
    return run;
  }

  ensureTitleRoot(scenario) {
    const indexes = buildScenarioIndexes(scenario);
    if (indexes.rootCards.length > 0) {
      return indexes.rootCards[0];
    }

    const rootCard = {
      id: randomUUID(),
      scenarioID: scenario.id,
      parentID: null,
      orderIndex: 0,
      createdAt: new Date().toISOString(),
      category: null,
      isFloating: false,
      isArchived: false,
      lastSelectedChildID: null,
      schemaVersion: CURRENT_SCHEMA_VERSION,
      colorHex: null,
      cloneGroupID: null,
      content: scenario.title || '제목 없음'
    };
    scenario.cards.push(rootCard);
    return rootCard;
  }

  ensureCategoryLane(scenario, categoryLabel) {
    const existing = scenarioLaneRoot(scenario, categoryLabel);
    if (existing) {
      return { laneRoot: existing, created: false };
    }

    const titleRoot = this.ensureTitleRoot(scenario);
    const indexes = buildScenarioIndexes(scenario);
    const siblings = indexes.childrenByParent.get(titleRoot.id) ?? [];
    const requestedRank = CATEGORY_RANK.get(categoryLabel) ?? Number.MAX_SAFE_INTEGER;

    let insertIndex = siblings.length;
    for (const sibling of siblings) {
      const siblingRank = CATEGORY_RANK.get(sibling.category) ?? Number.MAX_SAFE_INTEGER;
      if (siblingRank > requestedRank) {
        insertIndex = sibling.orderIndex;
        break;
      }
    }

    for (const sibling of siblings) {
      if (sibling.orderIndex >= insertIndex) {
        sibling.orderIndex += 1;
      }
    }

    const laneRoot = {
      id: categoryLabel === CATEGORY_LABELS.craft ? SHARED_CRAFT_ROOT_CARD_ID : randomUUID(),
      scenarioID: scenario.id,
      parentID: titleRoot.id,
      orderIndex: insertIndex,
      createdAt: new Date().toISOString(),
      category: categoryLabel,
      isFloating: false,
      isArchived: false,
      lastSelectedChildID: null,
      schemaVersion: CURRENT_SCHEMA_VERSION,
      colorHex: null,
      cloneGroupID: null,
      content: categoryLabel
    };

    scenario.cards.push(laneRoot);
    reindexChildren(scenario, titleRoot.id);
    return { laneRoot, created: true };
  }

  getScenarioOverviewPayload(scenario) {
    const indexes = buildScenarioIndexes(scenario);
    const titleRoot = indexes.rootCards[0] ?? null;
    const laneRoots = {};

    for (const categoryLabel of [CATEGORY_LABELS.plot, CATEGORY_LABELS.note, CATEGORY_LABELS.craft]) {
      const laneRoot = titleRoot
        ? (indexes.childrenByParent.get(titleRoot.id) ?? []).find(card => card.category === categoryLabel) ?? null
        : null;
      laneRoots[categoryLabel] = laneRoot
        ? {
            id: laneRoot.id,
            content: laneRoot.content,
            childCount: (indexes.childrenByParent.get(laneRoot.id) ?? []).length
          }
        : null;
    }

    const nonArchivedCards = scenario.cards.filter(card => !card.isArchived);
    const cardsByCategory = {};
    for (const categoryLabel of [CATEGORY_LABELS.plot, CATEGORY_LABELS.note, CATEGORY_LABELS.craft, CATEGORY_LABELS.uncategorized]) {
      cardsByCategory[categoryLabel] = nonArchivedCards.filter(card => (card.category ?? CATEGORY_LABELS.uncategorized) === categoryLabel).length;
    }

    return {
      workspacePath: this.workspacePath,
      scenarioId: scenario.id,
      scenarioTitle: scenario.title,
      isTemplate: scenario.isTemplate,
      timestamp: scenario.timestamp,
      titleRoot: titleRoot ? summarizeCardForList(titleRoot) : null,
      laneRoots,
      totalCards: scenario.cards.length,
      totalVisibleCards: nonArchivedCards.length,
      cardsByCategory,
      historySnapshotCount: scenario.historyRecords.length
    };
  }

  async getScenarioOverview() {
    const { selectedScenario } = await this.loadWorkspace();
    return this.getScenarioOverviewPayload(selectedScenario);
  }

  async getCardTree({ rootCardId = null, category = null, maxDepth = null, includeArchived = false } = {}) {
    const { selectedScenario } = await this.loadWorkspace();
    const indexes = buildScenarioIndexes(selectedScenario, includeArchived);

    let roots;
    if (rootCardId) {
      const root = indexes.cardById.get(String(rootCardId));
      if (!root) {
        throw new Error(`Card not found for id ${rootCardId}`);
      }
      roots = [root];
    } else if (category) {
      const categoryLabel = categoryLabelFromInput(category);
      const laneRoot = scenarioLaneRoot(selectedScenario, categoryLabel);
      roots = laneRoot ? [laneRoot] : [];
    } else {
      roots = indexes.rootCards;
    }

    return {
      scenarioId: selectedScenario.id,
      scenarioTitle: selectedScenario.title,
      rootCount: roots.length,
      tree: roots.map(card => serializeTreeNode(card, indexes, maxDepth))
    };
  }

  async getCard({ cardId, includeChildrenDepth = 1, includeArchived = false }) {
    const { selectedScenario } = await this.loadWorkspace();
    const indexes = buildScenarioIndexes(selectedScenario, includeArchived);
    const card = indexes.cardById.get(String(cardId));
    if (!card) {
      throw new Error(`Card not found for id ${cardId}`);
    }

    return {
      scenarioId: selectedScenario.id,
      scenarioTitle: selectedScenario.title,
      card: serializeTreeNode(card, indexes, includeChildrenDepth),
      path: buildCardPath(card, indexes)
    };
  }

  async searchCards({ query, category = null, limit = 20, includeArchived = false }) {
    const { selectedScenario } = await this.loadWorkspace();
    const indexes = buildScenarioIndexes(selectedScenario, includeArchived);
    const queryTokens = normalizeLineEndings(query)
      .split(/\s+/)
      .map(token => normalizeSearchText(token))
      .filter(Boolean);
    const categoryLabel = category ? categoryLabelFromInput(category) : null;

    const matches = selectedScenario.cards
      .filter(card => includeArchived || !card.isArchived)
      .filter(card => (categoryLabel ? card.category === categoryLabel : true))
      .filter(card => cardMatchesQuery(card, queryTokens))
      .sort(compareCards)
      .slice(0, Math.max(1, Math.min(Number(limit ?? 20), 200)))
      .map(card => ({
        ...summarizeCardForList(card),
        path: buildCardPath(card, indexes)
      }));

    return {
      scenarioId: selectedScenario.id,
      scenarioTitle: selectedScenario.title,
      query,
      category: categoryLabel,
      limit,
      matchCount: matches.length,
      matches
    };
  }

  async createCard({
    parentCardId = null,
    beforeCardId = null,
    afterCardId = null,
    content,
    category = null,
    confirmed = false
  }) {
    if (confirmed !== true) {
      throw new Error('create_card requires confirmed=true');
    }

    return this.enqueueMutation(async (workspace, selectedScenario) => {
      const normalizedContent = normalizeLineEndings(content).trim();
      if (!normalizedContent) {
        throw new Error('Card content must not be empty');
      }

      const indexes = buildScenarioIndexes(selectedScenario, true);
      let resolvedParentId = parentCardId ? String(parentCardId) : null;
      let targetOrderIndex = 0;

      if (beforeCardId && afterCardId) {
        throw new Error('Use either beforeCardId or afterCardId, not both');
      }

      if (beforeCardId || afterCardId) {
        const referenceCardId = beforeCardId ? String(beforeCardId) : String(afterCardId);
        const referenceCard = indexes.cardById.get(referenceCardId);
        if (!referenceCard) {
          throw new Error(`Reference card not found for id ${referenceCardId}`);
        }
        resolvedParentId = referenceCard.parentID ?? null;
        targetOrderIndex = beforeCardId ? referenceCard.orderIndex : referenceCard.orderIndex + 1;
      } else if (resolvedParentId) {
        const parentCard = indexes.cardById.get(resolvedParentId);
        if (!parentCard) {
          throw new Error(`Parent card not found for id ${resolvedParentId}`);
        }
        const siblings = selectedScenario.cards.filter(card => (card.parentID ?? null) === resolvedParentId);
        targetOrderIndex = siblings.length;
      } else {
        const rootCards = selectedScenario.cards.filter(card => card.parentID == null);
        targetOrderIndex = rootCards.length;
      }

      for (const sibling of selectedScenario.cards) {
        if ((sibling.parentID ?? null) === (resolvedParentId ?? null) && sibling.orderIndex >= targetOrderIndex) {
          sibling.orderIndex += 1;
        }
      }

      const parentCard = resolvedParentId ? indexes.cardById.get(resolvedParentId) ?? null : null;
      const categoryLabel = category ? categoryLabelFromInput(category) : parentCard?.category ?? null;
      const newCard = {
        id: randomUUID(),
        scenarioID: selectedScenario.id,
        parentID: resolvedParentId,
        orderIndex: targetOrderIndex,
        createdAt: new Date().toISOString(),
        category: categoryLabel,
        isFloating: false,
        isArchived: false,
        lastSelectedChildID: null,
        schemaVersion: CURRENT_SCHEMA_VERSION,
        colorHex: null,
        cloneGroupID: null,
        content: normalizedContent
      };

      selectedScenario.cards.push(newCard);
      reindexChildren(selectedScenario, resolvedParentId);
      appendHistorySnapshot(selectedScenario, 'mcp-create-card');

      return {
        mutated: true,
        scenarioId: selectedScenario.id,
        createdCard: summarizeCardForList(newCard)
      };
    });
  }

  async updateCard({ cardId, content, mode = 'replace', confirmed = false }) {
    if (confirmed !== true) {
      throw new Error('update_card requires confirmed=true');
    }

    return this.enqueueMutation(async (workspace, selectedScenario) => {
      const indexes = buildScenarioIndexes(selectedScenario, true);
      const card = indexes.cardById.get(String(cardId));
      if (!card) {
        throw new Error(`Card not found for id ${cardId}`);
      }

      const incoming = normalizeLineEndings(content).trim();
      if (!incoming) {
        throw new Error('Updated content must not be empty');
      }

      let nextContent;
      switch (mode) {
        case 'replace':
          nextContent = incoming;
          break;
        case 'append':
          nextContent = card.content.trim() ? `${card.content}\n\n${incoming}` : incoming;
          break;
        case 'prepend':
          nextContent = card.content.trim() ? `${incoming}\n\n${card.content}` : incoming;
          break;
        default:
          throw new Error(`Unsupported update mode: ${mode}`);
      }

      if (nextContent === card.content) {
        return {
          mutated: false,
          scenarioId: selectedScenario.id,
          updated: false,
          card: summarizeCardForList(card)
        };
      }

      card.content = nextContent;
      for (const peer of cloneGroupPeers(selectedScenario, card)) {
        peer.content = nextContent;
      }
      appendHistorySnapshot(selectedScenario, 'mcp-update-card');

      return {
        mutated: true,
        scenarioId: selectedScenario.id,
        updated: true,
        card: summarizeCardForList(card),
        clonePeerCount: cloneGroupPeers(selectedScenario, card).length
      };
    });
  }

  async deleteCard({ cardId, confirmed = false }) {
    if (confirmed !== true) {
      throw new Error('delete_card requires confirmed=true');
    }

    return this.enqueueMutation(async (workspace, selectedScenario) => {
      const indexes = buildScenarioIndexes(selectedScenario, true);
      const card = indexes.cardById.get(String(cardId));
      if (!card) {
        throw new Error(`Card not found for id ${cardId}`);
      }

      const titleRoot = indexes.rootCards[0] ?? null;
      if (titleRoot && titleRoot.id === card.id) {
        throw new Error('Deleting the primary title root card is not allowed');
      }

      const toRemove = collectDescendantIds(card.id, indexes);
      toRemove.add(card.id);

      selectedScenario.cards = selectedScenario.cards.filter(candidate => !toRemove.has(candidate.id));
      reindexChildren(selectedScenario, card.parentID ?? null);
      pruneLinkedCardRecords(selectedScenario);
      appendHistorySnapshot(selectedScenario, 'mcp-delete-card');

      return {
        mutated: true,
        scenarioId: selectedScenario.id,
        deletedCardId: card.id,
        deletedCardCount: toRemove.size
      };
    });
  }

  async saveDiscussionSummary({ items, dryRun = true, confirmed = false }) {
    if (!Array.isArray(items) || items.length === 0) {
      throw new Error('save_discussion_summary requires a non-empty items array');
    }

    return this.enqueueMutation(async (workspace, selectedScenario) => {
      const normalizedItems = items.map((item, index) => {
        const categoryLabel = categoryLabelFromInput(item.category);
        const content = normalizeSummaryText(item.content);
        return {
          index,
          category: categoryLabel,
          content
        };
      });

      const invalidItem = normalizedItems.find(item => !item.content);
      if (invalidItem) {
        throw new Error(`Item ${invalidItem.index + 1} is empty after normalization`);
      }

      const indexes = buildScenarioIndexes(selectedScenario, false);
      const titleRoot = indexes.rootCards[0] ?? null;
      const laneRootIds = new Set();
      if (titleRoot) {
        for (const lane of indexes.childrenByParent.get(titleRoot.id) ?? []) {
          if (lane.category && CATEGORY_RANK.has(lane.category)) {
            laneRootIds.add(lane.id);
          }
        }
      }

      const duplicateCandidates = selectedScenario.cards
        .filter(card => !card.isArchived)
        .filter(card => !laneRootIds.has(card.id))
        .filter(card => !(titleRoot && card.id === titleRoot.id))
        .map(card => ({
          source: 'existing',
          cardId: card.id,
          category: card.category ?? CATEGORY_LABELS.uncategorized,
          content: card.content
        }));

      const acceptedItems = [];
      const skippedItems = [];
      const previewLaneState = new Map();

      for (const item of normalizedItems) {
        const duplicate = findDuplicateMatch(item.content, [
          ...duplicateCandidates,
          ...acceptedItems.map(accepted => ({
            source: 'pending',
            cardId: null,
            category: accepted.category,
            content: accepted.content
          }))
        ]);

        if (duplicate) {
          skippedItems.push({
            index: item.index,
            category: item.category,
            content: item.content,
            reason: `duplicate-${duplicate.kind}`,
            matchedCardId: duplicate.cardId ?? null,
            matchedCategory: duplicate.category ?? null,
            matchedSource: duplicate.source,
            similarity: duplicate.score
          });
          continue;
        }

        const existingLaneRoot = scenarioLaneRoot(selectedScenario, item.category);
        const laneInfo = previewLaneState.get(item.category) ?? {
          category: item.category,
          laneRootId: existingLaneRoot?.id ?? null,
          laneAlreadyExists: Boolean(existingLaneRoot),
          willCreateLaneRoot: !existingLaneRoot
        };
        previewLaneState.set(item.category, laneInfo);
        acceptedItems.push(item);
      }

      const preview = {
        dryRun: Boolean(dryRun),
        scenarioId: selectedScenario.id,
        scenarioTitle: selectedScenario.title,
        acceptedCount: acceptedItems.length,
        skippedCount: skippedItems.length,
        lanes: Array.from(previewLaneState.values()),
        acceptedItems,
        skippedItems
      };

      if (dryRun) {
        return {
          mutated: false,
          ...preview
        };
      }

      if (confirmed !== true) {
        throw new Error('save_discussion_summary requires confirmed=true when dryRun=false');
      }

      if (acceptedItems.length === 0) {
        return {
          mutated: false,
          ...preview
        };
      }

      const createdCards = [];
      const createdLaneRoots = [];

      for (const item of acceptedItems) {
        const { laneRoot, created } = this.ensureCategoryLane(selectedScenario, item.category);
        if (created) {
          createdLaneRoots.push({
            category: item.category,
            laneRootId: laneRoot.id
          });
        }

        const refreshedIndexes = buildScenarioIndexes(selectedScenario, true);
        const currentLaneRoot = refreshedIndexes.cardById.get(laneRoot.id) ?? laneRoot;
        const children = refreshedIndexes.childrenByParent.get(currentLaneRoot.id) ?? [];
        const newCard = {
          id: randomUUID(),
          scenarioID: selectedScenario.id,
          parentID: currentLaneRoot.id,
          orderIndex: children.length,
          createdAt: new Date().toISOString(),
          category: item.category,
          isFloating: false,
          isArchived: false,
          lastSelectedChildID: null,
          schemaVersion: CURRENT_SCHEMA_VERSION,
          colorHex: null,
          cloneGroupID: null,
          content: item.content
        };
        selectedScenario.cards.push(newCard);
        reindexChildren(selectedScenario, currentLaneRoot.id);
        createdCards.push({
          ...summarizeCardForList(newCard),
          sourceIndex: item.index
        });
      }

      appendHistorySnapshot(selectedScenario, 'mcp-save-discussion-summary');

      return {
        mutated: true,
        ...preview,
        createdCount: createdCards.length,
        createdLaneRoots,
        createdCards
      };
    });
  }
}
