import { readFileSync, existsSync } from "fs";
import { resolve } from "path";
import { appendBuildSessionToNotion } from "../src/lib/notion";

const envPath = resolve(__dirname, "../.env.local");
if (existsSync(envPath)) {
  for (const line of readFileSync(envPath, "utf8").split("\n")) {
    const m = line.match(/^([A-Z_]+)=(.*)$/);
    if (m && !process.env[m[1]]) process.env[m[1]] = m[2];
  }
}

const SESSIONS = [
  {
    title: "Leo - Chief of Staff (apps/leo, port 3006)",
    sections: [
      {
        heading: "Overview",
        bullets: [
          "Single-user debug build for Liam - no billing/tier logic",
          "Routing agent: calendar, tasks, daily plan, agent invocation, reporting",
          "All cross-agent data via Bolton memory + context-pack - no duplicate storage",
        ],
      },
      {
        heading: "Features shipped",
        bullets: [
          "Google Calendar OAuth (Testing mode, 7-day re-auth prompt)",
          "Calendar CRUD + meeting prep brief (Bolton context-pack)",
          "Daily plan: Claude synthesis of calendar + Bolton task entries",
          "Tasks as Bolton memory entries (entry_type: task, cadence field)",
          "Agent-invocation contract v1 (sync) - POST /api/invoke",
          "Reporting dashboard: George/James/Conner via Bolton context-pack",
          "Weekly/monthly ops summary over Bolton entries",
          "Ask bar pattern deferred - Leo uses nav pages; schedule via tasks API",
        ],
      },
      {
        heading: "Agent-invocation contract",
        bullets: [
          "request: { from_agent, to_agent, task, context_ref?, priority, response_mode }",
          "response: { from_agent, to_agent, summary, structured_result?, memory_ids_written, follow_up_needed }",
          "James routed to JAMES_API_URL/api/handoff (separate context)",
        ],
      },
      {
        heading: "Run",
        bullets: [
          "npm run dev:leo → http://localhost:3006",
          "GOOGLE_CLIENT_ID/SECRET, redirect http://localhost:3006/api/calendar/callback",
          "npm run db:migrate for calendar_* columns on users table",
        ],
      },
    ],
  },
  {
    title: "George - Finance Agent (apps/george, port 3004)",
    sections: [
      {
        heading: "Overview",
        bullets: [
          "Finance agent - conversational modelling, unit economics, integrations",
          "Full models in george_financial_models (Postgres) - NOT Bolton",
          "Latest numbers summary to bolton_agent_summaries (exact schema other agents depend on)",
        ],
      },
      {
        heading: "Features shipped",
        bullets: [
          "Conversational P&L, runway, cash flow, break-even (Claude)",
          "Unit economics: CAC, LTV, margin, payback",
          "Custom calculator generator → Supabase storage + Bolton memory link",
          "Plain-English financial term explanations",
          "Stripe restricted key: MRR, revenue, churn",
          "Xero uncertified OAuth: P&L + bank summary",
          "Spreadsheet .xlsx import (server-side text parse)",
          "Tax-awareness flags + persistent UI disclaimer",
          "Dark Ask George bar + Schedule → Bolton task → Leo calendar",
        ],
      },
      {
        heading: "Latest numbers schema (Bolton)",
        bullets: [
          "{ source_agent: 'George', as_of, revenue, margin_pct, runway_months, burn_rate, flags[], confidence }",
          "POST /api/agent-summaries in Bolton",
          "Publish via George Integrations → Publish latest numbers",
        ],
      },
      {
        heading: "Run",
        bullets: [
          "npm run dev:george → http://localhost:3004",
          "SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY for calculator artifacts",
          "STRIPE_RESTRICTED_KEY, XERO_CLIENT_ID/SECRET",
        ],
      },
    ],
  },
  {
    title: "James - Research Agent (apps/james, port 3003)",
    sections: [
      {
        heading: "Overview",
        bullets: [
          "Research agent referenced by every other agent - cheapest to stand up (no OAuth)",
          "Anthropic native web_search_20250305 with citations",
          "Runs in separate context - returns handoff only, never full thread",
        ],
      },
      {
        heading: "Locked output template",
        bullets: [
          "Research question → Key findings → What this means → Recommendation → Sources",
          "Source credibility scored 1-5 inline (Claude-judged)",
        ],
      },
      {
        heading: "Features shipped",
        bullets: [
          "Web search + citation-backed research end to end",
          "Handoff API: POST /api/handoff - JamesHandoff shape",
          "Save-vs-return heuristic (codified rules in save-heuristic.ts)",
          "Research memory check before new work (Bolton search + prior James entries)",
          "Source-type routing: market / technical / cultural / academic / pricing",
          "Deep synthesis: up to 12 searches for comparative/landscape questions",
          "Dark Ask James bar + Schedule → Bolton task → Leo calendar",
          "Leo invoke routes to JAMES_API_URL/api/handoff",
        ],
      },
      {
        heading: "Handoff shape",
        bullets: [
          "{ from_agent: 'James', to_agent, research_question, key_findings[], what_this_means, recommendation, sources[], saved_to_bolton, memory_id? }",
        ],
      },
      {
        heading: "Run",
        bullets: [
          "npm run dev:james → http://localhost:3003",
          "ANTHROPIC_API_KEY + web search enabled in Anthropic Console",
          "Leo: JAMES_API_URL=http://localhost:3003",
        ],
      },
    ],
  },
  {
    title: "Monorepo wiring (July 6, 2026)",
    sections: [
      {
        heading: "Ports",
        bullets: [
          "William 3000 · Marc 3001 · Bolton 3002 · James 3003 · George 3004 · Leo 3006 · Home 3010",
        ],
      },
      {
        heading: "Bolton additions",
        bullets: [
          "POST/GET /api/agent-summaries",
          "george_financial_models, george_calculators tables",
          "calendar_*, stripe_*, xero_* columns on users",
          "cadence + custom_schedule on memory_entries (tasks for Leo calendar)",
        ],
      },
      {
        heading: "Brand guidelines (Robert, July 6)",
        bullets: [
          "Dark ask bar with inverted monogram on each agent",
          "Schedule action beside ask → Bolton task entry with cadence → Leo calendar",
          "Visual identity per agent TBD - plain packages/ui for now",
        ],
      },
    ],
  },
];

async function main() {
  for (const session of SESSIONS) {
    const result = await appendBuildSessionToNotion(session.title, session.sections);
    if (result.synced) {
      console.log(`✓ Filed: ${session.title}`);
    } else {
      console.error(`✗ ${session.title}: ${result.reason}`);
      process.exitCode = 1;
    }
  }
  console.log("\nDone - check NOTION_11AM_PROJECT_PAGE_ID in Notion.");
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
