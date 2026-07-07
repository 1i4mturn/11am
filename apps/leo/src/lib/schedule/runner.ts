import { promises as fs } from "fs";
import path from "path";
import { invokeAgent } from "@/lib/agents/invoke";
import { writeToBolton } from "@/lib/bolton/client";

/**
 * Scheduled-task runner — executes the schedule entries every agent's ask bar
 * writes to Bolton (tags: ["task", <agent>, "schedule", "cadence:<c>"]).
 *
 * Previously these entries were stored but nothing ran them. This runner:
 *  - polls Bolton for active task entries with a schedule tag
 *  - runs the ones that are due (once / daily / weekly / monthly)
 *  - routes each prompt back to the agent that created it via the shared
 *    agent-invocation contract, and writes the result to Bolton
 *  - tracks last-run times in a local JSON file so restarts don't re-fire
 *
 * Safety: max RUNS_PER_TICK executions per poll, per-run bounded by the
 * invocation contract's 90s timeout, disable entirely with
 * LEO_SCHEDULER_ENABLED=false. "custom" cadences are surfaced but never
 * auto-run (free-text schedules aren't parsed — deliberate).
 */

const BOLTON_BASE = process.env.BOLTON_API_URL ?? "http://localhost:3002";
const POLL_MS = 10 * 60 * 1000; // 10 minutes
const RUNS_PER_TICK = 3;

const CADENCE_INTERVAL_MS: Record<string, number> = {
  daily: 22 * 60 * 60 * 1000, // a little under 24h so drift doesn't skip a day
  weekly: 6.5 * 24 * 60 * 60 * 1000,
  monthly: 27 * 24 * 60 * 60 * 1000,
};

interface ScheduledTaskPayload {
  prompt: string;
  task_type?: string;
  cadence: string;
  custom_schedule?: string | null;
  assigned_to?: string;
  created_by?: string;
  created_at?: string;
}

interface SchedulerState {
  lastRun: Record<string, string>; // entry id → ISO timestamp
  completedOnce: string[]; // "once" entry ids already executed
}

const stateKey = Symbol.for("@11am/leo/scheduler");

function getRuntime(): { running: boolean; ticking: boolean } {
  const g = globalThis as Record<symbol, { running: boolean; ticking: boolean }>;
  if (!g[stateKey]) g[stateKey] = { running: false, ticking: false };
  return g[stateKey];
}

function stateFilePath(): string {
  return path.join(process.cwd(), ".data", "scheduler-state.json");
}

async function loadState(): Promise<SchedulerState> {
  try {
    const raw = await fs.readFile(stateFilePath(), "utf8");
    const parsed = JSON.parse(raw) as Partial<SchedulerState>;
    return { lastRun: parsed.lastRun ?? {}, completedOnce: parsed.completedOnce ?? [] };
  } catch {
    return { lastRun: {}, completedOnce: [] };
  }
}

async function saveState(state: SchedulerState): Promise<void> {
  await fs.mkdir(path.dirname(stateFilePath()), { recursive: true });
  await fs.writeFile(stateFilePath(), JSON.stringify(state, null, 2));
}

interface BoltonTaskEntry {
  id: string;
  title: string;
  tags?: string[];
  full_content?: string | null;
  fullContent?: string | null;
}

async function fetchScheduledTasks(): Promise<BoltonTaskEntry[]> {
  const res = await fetch(`${BOLTON_BASE}/api/memory?entry_type=task&status=active`, {
    cache: "no-store",
    signal: AbortSignal.timeout(5_000),
  });
  if (!res.ok) return [];
  const data = (await res.json()) as { entries?: BoltonTaskEntry[] };
  return (data.entries ?? []).filter((e) => (e.tags ?? []).includes("schedule"));
}

function parsePayload(entry: BoltonTaskEntry): ScheduledTaskPayload | null {
  const raw = entry.full_content ?? entry.fullContent;
  if (!raw) return null;
  try {
    const parsed = JSON.parse(raw) as ScheduledTaskPayload;
    return parsed.prompt && parsed.cadence ? parsed : null;
  } catch {
    return null;
  }
}

function isDue(entryId: string, cadence: string, state: SchedulerState): boolean {
  if (cadence === "custom") return false; // never auto-run free-text schedules
  if (cadence === "once") return !state.completedOnce.includes(entryId);
  const interval = CADENCE_INTERVAL_MS[cadence];
  if (!interval) return false;
  const last = state.lastRun[entryId];
  return !last || Date.now() - new Date(last).getTime() >= interval;
}

async function runTask(entry: BoltonTaskEntry, payload: ScheduledTaskPayload): Promise<void> {
  const targetAgent = (payload.created_by ?? "leo").toLowerCase();
  const response = await invokeAgent({
    from_agent: "leo",
    to_agent: targetAgent,
    task: payload.prompt,
    context_ref: `scheduled:${entry.id}`,
    priority: "normal",
    response_mode: "sync",
  });

  await writeToBolton({
    source_agent: "Leo",
    entry_type: "output",
    title: `Scheduled run (${payload.cadence}): ${payload.prompt.slice(0, 70)}`,
    summary: response.summary.slice(0, 500) || "Scheduled task executed.",
    full_content: JSON.stringify(
      { scheduled_entry_id: entry.id, target_agent: targetAgent, response },
      null,
      2
    ),
    tags: ["scheduled-run", targetAgent, `cadence:${payload.cadence}`],
    force: true,
  });
}

export async function runSchedulerTick(): Promise<{ ran: number; due: number }> {
  const runtime = getRuntime();
  if (runtime.ticking) return { ran: 0, due: 0 };
  runtime.ticking = true;

  try {
    const [entries, state] = await Promise.all([fetchScheduledTasks(), loadState()]);
    const due = entries
      .map((entry) => ({ entry, payload: parsePayload(entry) }))
      .filter((t): t is { entry: BoltonTaskEntry; payload: ScheduledTaskPayload } => !!t.payload)
      .filter(({ entry, payload }) => isDue(entry.id, payload.cadence, state));

    let ran = 0;
    for (const { entry, payload } of due.slice(0, RUNS_PER_TICK)) {
      try {
        await runTask(entry, payload);
      } catch {
        // A failed run still counts as attempted this interval — avoids
        // hammering a broken target agent every 10 minutes.
      }
      state.lastRun[entry.id] = new Date().toISOString();
      if (payload.cadence === "once") state.completedOnce.push(entry.id);
      ran += 1;
    }

    if (ran > 0) await saveState(state);
    return { ran, due: due.length };
  } catch {
    return { ran: 0, due: 0 };
  } finally {
    runtime.ticking = false;
  }
}

export function startScheduler(): void {
  if (process.env.LEO_SCHEDULER_ENABLED === "false" || process.env.VERCEL === "1") return;
  const runtime = getRuntime();
  if (runtime.running) return;
  runtime.running = true;

  setInterval(() => {
    void runSchedulerTick();
  }, POLL_MS);

  // First tick shortly after boot rather than immediately, so local dev
  // startup isn't racing Bolton coming up.
  setTimeout(() => {
    void runSchedulerTick();
  }, 30_000);
}
