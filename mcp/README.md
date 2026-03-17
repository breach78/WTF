# WA Scenario MCP

This MCP server locks itself to one scenario inside one `.wtf` workspace.

## Install

```bash
cd /Users/three/app_build/wa/mcp
npm install
```

## Pick a scenario

List scenarios in a workspace:

```bash
node server.js --workspace /absolute/path/to/workspace.wtf --list-scenarios
```

Start the MCP server for one scenario:

```bash
node server.js --workspace /absolute/path/to/workspace.wtf --scenario-id <SCENARIO_UUID>
```

You can also select by exact title:

```bash
node server.js --workspace /absolute/path/to/workspace.wtf --scenario-title "Scenario Title"
```

## Exposed resources

- `scenario://current/overview`
- `scenario://current/tree`

## Exposed tools

- `scenario_overview`
- `get_card_tree`
- `get_card`
- `search_cards`
- `create_card`
- `update_card`
- `delete_card`
- `save_discussion_summary`

## Write safety

- `create_card`, `update_card`, and `delete_card` require `confirmed: true`.
- `save_discussion_summary` is designed for `dryRun: true` first, then `dryRun: false` with `confirmed: true`.
- `save_discussion_summary` removes likely duplicates before writing.
- Every write appends one full history snapshot to `history.json`.

## Discussion summary flow

1. Codex classifies the discussion into one or more categories.
2. Codex calls `save_discussion_summary` with `dryRun: true`.
3. You confirm the preview.
4. Codex calls `save_discussion_summary` again with `dryRun: false` and `confirmed: true`.

Each accepted summary item is written as a new child card under the matching category lane.

## Important caveat

This server is scoped to one scenario and does not intentionally write to other scenarios.

The macOS app itself already has shared `작법` synchronization logic across scenarios inside the same `.wtf` workspace. If you later open the workspace in the app, that app behavior may still affect `작법` cards across scenarios.
