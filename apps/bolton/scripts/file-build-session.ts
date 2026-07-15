/**
 * File the 11am build session (Jul 6 2026) to Bolton Postgres + Notion.
 *
 * Usage (from apps/bolton):
 *   npx tsx scripts/file-build-session.ts
 *
 * Notion env (optional but required for Notion sync):
 *   NOTION_API_KEY
 *   NOTION_11AM_PROJECT_PAGE_ID     - append build log section
 *   NOTION_MEMORY_DATABASE_ID       - sync memory bank rows
 *   NOTION_DECISION_LOG_DATABASE_ID - sync decisions (Title + Summary props)
 */
import postgres from "postgres";
import { logDecision } from "../src/lib/decisions";
import { saveMemoryEntry } from "../src/lib/memory";
import {
  appendBuildSessionToNotion,
  createNotionDatabaseRow,
  syncEntryToNotion,
  getNotionStatus,
} from "../src/lib/notion";

const BUILD_SESSION_MEMORIES = [
  {
    source_agent: "Johnny",
    entry_type: "project" as const,
    title: "11am v1 debug builds - test-ready (Jul 6 2026)",
    summary:
      "William, Marc, and Bolton v1 single-user debug builds complete per acceptance criteria. Monorepo at ~/Projects/11am, ports 3000/3001/3002, shared Postgres pgvector on 5435.",
    tags: ["11am", "build-session", "v1"],
    importance_score: 0.95,
  },
  {
    source_agent: "William",
    entry_type: "output" as const,
    title: "William - streaming + Ask bar + schedule",
    summary:
      "SSE /api/generate/stream, dark Ask William bar with Schedule→Bolton tasks, George/Conner typed schemas, Gmail 7-day reauth, SINGLE_USER_DEBUG bypasses tier gates.",
    tags: ["william", "build-session"],
    importance_score: 0.85,
  },
  {
    source_agent: "Marc",
    entry_type: "output" as const,
    title: "Marc - inbox v1 gaps closed",
    summary:
      "Ask Marc bar, bulk unsubscribe with confirmation, rule confirm/apply, triage persistence, William handoff UI, Gmail scopes trimmed to readonly/modify/labels, 7-day reauth.",
    tags: ["marc", "build-session"],
    importance_score: 0.85,
  },
  {
    source_agent: "Bolton",
    entry_type: "output" as const,
    title: "Bolton - capture engine + Notion scaffold",
    summary:
      "Supersede/link capture actions, archive-only DELETE, task cadence columns, structured context pack, entity POST API, hybrid search citations, 22 seed memories.",
    tags: ["bolton", "build-session"],
    importance_score: 0.9,
  },
  {
    source_agent: "Conner",
    entry_type: "decision" as const,
    title: "Single-user debug env vars default on",
    summary:
      "WILLIAM_SINGLE_USER, MARC_SINGLE_USER, BOLTON_SINGLE_USER default on for Liam-only testing. Set to false to re-enable tier gates before second user.",
    tags: ["decision", "11am"],
    importance_score: 0.8,
  },
  {
    source_agent: "Bolton",
    entry_type: "reference" as const,
    title: "Bolton soft-delete policy",
    summary:
      "Memory entries are never hard-deleted. DELETE archives. Supersede links old→new entry. Notion mirror archives on supersede.",
    tags: ["bolton", "policy"],
    importance_score: 0.85,
  },
  {
    source_agent: "Robert",
    entry_type: "reference" as const,
    title: "Dark ask bar pattern (@11am/ui)",
    summary:
      "am-ask-bar with inverted monogram (wm/mc). Schedule action writes Bolton entry_type task with cadence for Leo calendar.",
    tags: ["design", "shared"],
    importance_score: 0.75,
  },
  {
    source_agent: "Marc",
    entry_type: "decision" as const,
    title: "Gmail OAuth Testing mode - no CASA yet",
    summary:
      "Google Cloud app stays in Testing with Liam as sole test user. Refresh tokens expire every 7 days. No send/compose scope until sending is needed.",
    tags: ["marc", "gmail", "security"],
    importance_score: 0.85,
  },
];

const BUILD_DECISIONS = [
  {
    decision: "Single-user debug env vars default on for all 11am agents",
    context: "William, Marc, Bolton v1 build session Jul 6 2026",
    rationale: "Unblocks local testing without tier gates for Liam-only debug builds",
    sourceAgent: "Conner",
    decisionType: "dev",
  },
  {
    decision: "Bolton DELETE archives only - never hard delete",
    context: "Bolton memory integrity policy",
    rationale: "Preserves audit trail; supersede/link model replaces silent deletion",
    sourceAgent: "Bolton",
    decisionType: "data",
  },
  {
    decision: "entry_type task + cadence as first-class Bolton columns",
    context: "Cross-agent Schedule UI from William and Marc ask bars",
    rationale: "Leo calendar scheduling requires queryable cadence, not JSON-only",
    sourceAgent: "Conner",
    decisionType: "architecture",
  },
];

async function main() {
  console.log("Notion status:", await getNotionStatus());

  const connectionString =
    process.env.DATABASE_URL ?? "postgresql://elevenam:elevenam@localhost:5435/elevenam";

  try {
    const sql = postgres(connectionString, { max: 1 });
    await sql`SELECT 1`;
    await sql.end();
  } catch {
    console.warn("Postgres unavailable - skipping Bolton DB writes (start Docker + npm run db)");
  }

  console.log("\n── Filing to Bolton Postgres ──");
  for (const mem of BUILD_SESSION_MEMORIES) {
    const result = await saveMemoryEntry(mem, "default", true);
    const entryId =
      "id" in result && result.id
        ? String(result.id)
        : result.entry && typeof result.entry === "object" && "id" in result.entry
          ? String(result.entry.id)
          : null;
    console.log(
      `  memory: ${mem.title.slice(0, 50)} → ${result.action}${entryId ? ` (${entryId})` : ""}`
    );
    if (entryId) {
      const notion = await syncEntryToNotion(entryId, mem);
      if (notion.synced) console.log(`    notion memory: ${notion.action} ${notion.notion_page_id}`);
      else if (notion.reason) console.log(`    notion memory: skipped (${notion.reason})`);
    }
  }

  for (const dec of BUILD_DECISIONS) {
    const saved = await logDecision(dec, "default");
    console.log(`  decision: ${dec.decision.slice(0, 50)} → ${saved.id}`);

    const decisionDb = process.env.NOTION_DECISION_LOG_DATABASE_ID;
    if (decisionDb) {
      const notion = await createNotionDatabaseRow(decisionDb, {
        Title: { title: [{ text: { content: dec.decision.slice(0, 200) } }] },
        Summary: {
          rich_text: [{ text: { content: `${dec.context}. ${dec.rationale}`.slice(0, 2000) } }],
        },
        Agent: { select: { name: dec.sourceAgent } },
      });
      if (notion.synced) console.log(`    notion decision: ${notion.notion_page_id}`);
    }
  }

  console.log("\n── Filing to Notion project page ──");
  const append = await appendBuildSessionToNotion("Build session - 6 Jul 2026 (11am v1 debug)", [
    {
      heading: "Overview",
      bullets: [
        "Monorepo ~/Projects/11am - William :3000, Marc :3001, Bolton :3002, Postgres :5435",
        "Acceptance: William, Marc, Bolton v1 debug builds test-ready",
        "Debug: *_SINGLE_USER env vars default on; set false to re-enable tier gates",
      ],
    },
    {
      heading: "William",
      bullets: [
        "SSE streaming /api/generate/stream",
        "Ask William bar + Schedule → Bolton tasks",
        "George/Conner typed Zod schemas + migrate seed",
        "Gmail Testing mode 7-day reauth prompt",
      ],
    },
    {
      heading: "Marc",
      bullets: [
        "Ask Marc bar + Schedule → Bolton tasks",
        "Triage persists to DB; suggested_reply + William handoff",
        "Bulk unsubscribe (HTTPS, confirmed, protected keywords)",
        "Rule builder confirm & apply; Gmail scopes trimmed",
      ],
    },
    {
      heading: "Bolton",
      bullets: [
        "Capture: supersede/link; DELETE = archive only",
        "Task cadence columns; structured context pack",
        "POST /api/entities; hybrid search with [Bolton:id] citations",
        "Notion sync on save; conflict_review flag on scan",
      ],
    },
  ]);

  if (append.synced) {
    console.log(`  appended to project page: ${append.notion_page_id}`);
  } else {
    console.log(`  project page: skipped (${append.reason})`);
  }

  console.log("\nDone.");
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
