import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import * as z from 'zod/v4';
import { CATEGORY_LABELS, ScenarioWorkspaceStore } from './scenario-store.js';

function parseArgs(argv) {
  const options = {
    workspace: process.env.WTF_WORKSPACE_PATH ?? null,
    scenarioId: null,
    scenarioTitle: null,
    listScenarios: false,
    help: false
  };

  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    switch (arg) {
      case '--workspace':
        options.workspace = argv[index + 1] ?? null;
        index += 1;
        break;
      case '--scenario-id':
        options.scenarioId = argv[index + 1] ?? null;
        index += 1;
        break;
      case '--scenario-title':
        options.scenarioTitle = argv[index + 1] ?? null;
        index += 1;
        break;
      case '--list-scenarios':
        options.listScenarios = true;
        break;
      case '--help':
      case '-h':
        options.help = true;
        break;
      default:
        throw new Error(`Unknown argument: ${arg}`);
    }
  }

  if (options.scenarioId && options.scenarioTitle) {
    throw new Error('Use either --scenario-id or --scenario-title, not both');
  }

  return options;
}

function printHelp() {
  const lines = [
    'Usage:',
    '  node server.js --workspace /path/to/file.wtf --list-scenarios',
    '  node server.js --workspace /path/to/file.wtf --scenario-id <uuid>',
    '  node server.js --workspace /path/to/file.wtf --scenario-title "Title"',
    '',
    'Options:',
    '  --workspace        Path to a .wtf workspace package',
    '  --scenario-id      Lock the MCP server to one scenario id',
    '  --scenario-title   Lock the MCP server to one exact scenario title',
    '  --list-scenarios   Print scenarios in the workspace and exit'
  ];
  process.stdout.write(`${lines.join('\n')}\n`);
}

function jsonResult(payload) {
  return {
    content: [
      {
        type: 'text',
        text: JSON.stringify(payload, null, 2)
      }
    ]
  };
}

function jsonResource(uri, payload) {
  return {
    contents: [
      {
        uri,
        mimeType: 'application/json',
        text: JSON.stringify(payload, null, 2)
      }
    ]
  };
}

async function run() {
  const options = parseArgs(process.argv.slice(2));

  if (options.help) {
    printHelp();
    return;
  }

  if (!options.workspace) {
    throw new Error('--workspace is required');
  }

  const store = new ScenarioWorkspaceStore({
    workspacePath: options.workspace,
    scenarioId: options.scenarioId,
    scenarioTitle: options.scenarioTitle
  });

  if (options.listScenarios) {
    const scenarios = await store.listScenarios();
    process.stdout.write(`${JSON.stringify(scenarios, null, 2)}\n`);
    return;
  }

  const server = new McpServer({
    name: 'wa-scenario-mcp',
    version: '0.1.0'
  });

  server.registerResource(
    'scenario-overview',
    'scenario://current/overview',
    {
      title: 'Scenario Overview',
      description: 'Current scenario metadata, lane roots, and counts',
      mimeType: 'application/json'
    },
    async () => jsonResource('scenario://current/overview', await store.getScenarioOverview())
  );

  server.registerResource(
    'scenario-tree',
    'scenario://current/tree',
    {
      title: 'Scenario Tree',
      description: 'Full current scenario card tree',
      mimeType: 'application/json'
    },
    async () => jsonResource('scenario://current/tree', await store.getCardTree({}))
  );

  server.registerTool(
    'scenario_overview',
    {
      description: 'Read the locked scenario overview, including lane root ids and card counts.',
      annotations: {
        readOnlyHint: true,
        openWorldHint: false
      }
    },
    async () => jsonResult(await store.getScenarioOverview())
  );

  server.registerTool(
    'get_card_tree',
    {
      description: 'Read a card tree for the whole scenario, one category lane, or a specific root card.',
      annotations: {
        readOnlyHint: true,
        openWorldHint: false
      },
      inputSchema: {
        rootCardId: z.string().optional().describe('Specific root card id to inspect'),
        category: z
          .enum([CATEGORY_LABELS.plot, CATEGORY_LABELS.note, CATEGORY_LABELS.craft, 'plot', 'note', 'craft'])
          .optional()
          .describe('Optional category lane to inspect'),
        maxDepth: z.number().int().min(0).max(20).optional().describe('Optional max child depth'),
        includeArchived: z.boolean().optional().describe('Include archived cards')
      }
    },
    async args => jsonResult(await store.getCardTree(args))
  );

  server.registerTool(
    'get_card',
    {
      description: 'Read one card with its path and optional child tree.',
      annotations: {
        readOnlyHint: true,
        openWorldHint: false
      },
      inputSchema: {
        cardId: z.string().describe('Card id'),
        includeChildrenDepth: z.number().int().min(0).max(12).optional().describe('Child depth to include'),
        includeArchived: z.boolean().optional().describe('Include archived cards')
      }
    },
    async args => jsonResult(await store.getCard(args))
  );

  server.registerTool(
    'search_cards',
    {
      description: 'Search the locked scenario card contents.',
      annotations: {
        readOnlyHint: true,
        openWorldHint: false
      },
      inputSchema: {
        query: z.string().describe('Search query'),
        category: z
          .enum([CATEGORY_LABELS.plot, CATEGORY_LABELS.note, CATEGORY_LABELS.craft, 'plot', 'note', 'craft'])
          .optional()
          .describe('Optional category filter'),
        limit: z.number().int().min(1).max(200).optional().describe('Maximum results'),
        includeArchived: z.boolean().optional().describe('Include archived cards')
      }
    },
    async args => jsonResult(await store.searchCards(args))
  );

  server.registerTool(
    'create_card',
    {
      description: 'Create a new card. Requires explicit confirmation from the user first.',
      inputSchema: {
        parentCardId: z.string().optional().describe('Parent card id for the new card'),
        beforeCardId: z.string().optional().describe('Insert before this sibling card id'),
        afterCardId: z.string().optional().describe('Insert after this sibling card id'),
        content: z.string().describe('Card body text'),
        category: z
          .enum([CATEGORY_LABELS.plot, CATEGORY_LABELS.note, CATEGORY_LABELS.craft, 'plot', 'note', 'craft'])
          .optional()
          .describe('Optional category override'),
        confirmed: z.literal(true).describe('Must be true after user confirmation')
      }
    },
    async args => jsonResult(await store.createCard(args))
  );

  server.registerTool(
    'update_card',
    {
      description: 'Update one card body. Requires explicit confirmation from the user first.',
      inputSchema: {
        cardId: z.string().describe('Card id'),
        content: z.string().describe('New text to apply'),
        mode: z.enum(['replace', 'append', 'prepend']).optional().describe('How to combine the text'),
        confirmed: z.literal(true).describe('Must be true after user confirmation')
      }
    },
    async args => jsonResult(await store.updateCard(args))
  );

  server.registerTool(
    'delete_card',
    {
      description: 'Delete one card and its descendants. Requires explicit confirmation from the user first.',
      inputSchema: {
        cardId: z.string().describe('Card id'),
        confirmed: z.literal(true).describe('Must be true after user confirmation')
      }
    },
    async args => jsonResult(await store.deleteCard(args))
  );

  server.registerTool(
    'save_discussion_summary',
    {
      description:
        'Preview or save concise discussion summaries as new child cards under category lanes with duplicate filtering.',
      inputSchema: {
        items: z
          .array(
            z.object({
              category: z.enum([
                CATEGORY_LABELS.plot,
                CATEGORY_LABELS.note,
                CATEGORY_LABELS.craft,
                'plot',
                'note',
                'craft'
              ]),
              content: z.string().describe('Concise declarative summary sentence')
            })
          )
          .min(1)
          .describe('Categorized summary items'),
        dryRun: z.boolean().optional().describe('Preview only when true'),
        confirmed: z.boolean().optional().describe('Must be true when dryRun=false')
      }
    },
    async args => jsonResult(await store.saveDiscussionSummary(args))
  );

  const transport = new StdioServerTransport();
  await server.connect(transport);
}

run().catch(error => {
  process.stderr.write(`wa-scenario-mcp error: ${error.message}\n`);
  process.exit(1);
});
