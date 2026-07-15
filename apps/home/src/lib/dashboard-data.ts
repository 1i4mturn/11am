import type { AgentId } from "@/data/agents";
import type {
  ActivityEntry,
  BuildStatus,
  GlanceCard,
  GlanceRow,
} from "@/data/dashboard";
import { AGENT_BUILD_STATUS } from "@/data/dashboard";
import { BOLTON_API_URL, LEO_API_URL, MARC_API_URL } from "@/lib/config";

interface MarcTriageItem {
  sender: string;
  subject: string;
  why_it_matters: string;
  priority: "high" | "medium" | "low";
}

interface CalendarEvent {
  summary: string;
  start: string;
  end: string;
}

interface BoltonEntry {
  id: string;
  source_agent: string;
  title: string;
  summary: string;
  tags?: string[];
  entry_type: string;
  created_at?: string;
  createdAt?: string;
}

function entryCreatedAt(e: BoltonEntry): string | undefined {
  const v = e.created_at ?? e.createdAt;
  return v && v.length > 0 ? v : undefined;
}

function normalizeEntry(e: Record<string, unknown>): BoltonEntry {
  return {
    id: String(e.id ?? ""),
    source_agent: String(e.source_agent ?? e.sourceAgent ?? ""),
    title: String(e.title ?? ""),
    summary: String(e.summary ?? ""),
    tags: (e.tags as string[]) ?? [],
    entry_type: String(e.entry_type ?? e.entryType ?? ""),
    created_at: String(e.created_at ?? e.createdAt ?? ""),
  };
}

interface BoltonDecision {
  id: string;
  sourceAgent: string;
  decision: string;
  context?: string;
  createdAt: string;
}

function agentIdFromSource(source: string): AgentId {
  const key = source.toLowerCase().replace(/\s+/g, "");
  const map: Record<string, AgentId> = {
    leo: "leo",
    marc: "marc",
    william: "william",
    bolton: "bolton",
    johnny: "johnny",
    robert: "robert",
    james: "james",
    george: "george",
    conner: "conner",
    harris: "harris",
    cole: "cole",
  };
  return map[key] ?? "bolton";
}

function relativeTime(iso: string): string {
  const diff = Date.now() - new Date(iso).getTime();
  const mins = Math.floor(diff / 60_000);
  if (mins < 1) return "just now";
  if (mins < 60) return `${mins} min ago`;
  const hours = Math.floor(mins / 60);
  if (hours < 24) return `${hours} hour${hours === 1 ? "" : "s"} ago`;
  const days = Math.floor(hours / 24);
  return `${days} day${days === 1 ? "" : "s"} ago`;
}

function formatEventTime(iso: string): string {
  const d = new Date(iso);
  return d.toLocaleTimeString("en-AU", { hour: "numeric", minute: "2-digit", hour12: true }).toLowerCase();
}

async function fetchInboxGlance(): Promise<GlanceCard> {
  const rows: GlanceRow[] = [];
  try {
    const res = await fetch(`${MARC_API_URL}/api/triage`, {
      method: "POST",
      cache: "no-store",
      signal: AbortSignal.timeout(3_500),
    });
    if (res.ok) {
      const data = await res.json();
      const items = (data.items ?? []) as MarcTriageItem[];
      const top = items
        .filter((i) => i.priority === "high")
        .slice(0, 2);
      for (const item of top) {
        const who = item.sender.split(" ")[0] || item.sender;
        rows.push({
          who,
          text: item.why_it_matters || item.subject,
          tag: "urgent",
        });
      }
      const rest = items.length - top.length;
      if (rest > 0) {
        rows.push({
          text: `${rest} other email${rest === 1 ? "" : "s"} triaged, nothing else needs you`,
        });
      }
    }
  } catch {
    // offline
  }

  if (rows.length === 0) {
    rows.push({ text: "marc offline - start marc on :3001 to load inbox triage" });
  }

  return { kicker: "inbox, from marc", agentId: "marc", rows };
}

async function fetchCalendarGlance(): Promise<GlanceCard> {
  const rows: GlanceRow[] = [];
  let eventCount = 0;

  try {
    const now = new Date();
    const end = new Date(now);
    end.setDate(end.getDate() + 2);
    const calRes = await fetch(
      `${LEO_API_URL}/api/calendar?timeMin=${now.toISOString()}&timeMax=${end.toISOString()}`,
      { cache: "no-store", signal: AbortSignal.timeout(3_500) }
    );
    if (calRes.ok) {
      const data = await calRes.json();
      const events = (data.events ?? []) as CalendarEvent[];
      eventCount = events.length;
      for (const ev of events.slice(0, 2)) {
        rows.push({
          who: formatEventTime(ev.start),
          text: ev.summary,
          tag: new Date(ev.start).toDateString() === now.toDateString() ? "info" : undefined,
        });
      }
    }
  } catch {
    // offline
  }

  try {
    const taskRes = await fetch(`${BOLTON_API_URL}/api/memory?entry_type=task&status=active`, {
      cache: "no-store",
      signal: AbortSignal.timeout(3_500),
    });
    if (taskRes.ok) {
      const data = await taskRes.json();
      const tasks = (data.entries ?? []).map((e: Record<string, unknown>) => normalizeEntry(e));
      for (const t of tasks.slice(0, 1)) {
        rows.push({
          who: t.source_agent.toLowerCase(),
          text: t.title,
        });
      }
    }
  } catch {
    // offline
  }

  if (eventCount <= 1) {
    rows.push({ text: "Tomorrow looks light - good window to plan the next sprint" });
  } else if (rows.length === 0) {
    rows.push({ text: "leo calendar offline - connect on :3006" });
  }

  return { kicker: "calendar, from leo", agentId: "leo", rows };
}

async function fetchWipGlance(): Promise<GlanceCard> {
  const rows: GlanceRow[] = [];
  const sources = ["William", "Bolton", "Johnny"];

  try {
    const res = await fetch(`${BOLTON_API_URL}/api/memory?status=active`, { cache: "no-store", signal: AbortSignal.timeout(3_500) });
    if (res.ok) {
      const data = await res.json();
      const entries = (data.entries ?? []).map((e: Record<string, unknown>) => normalizeEntry(e));
      const wip = entries.filter((e: BoltonEntry) => {
        if (!sources.some((s) => e.source_agent?.toLowerCase() === s.toLowerCase())) return false;
        const tags = e.tags ?? [];
        const ready =
          tags.includes("ready") ||
          /ready|draft|shipped|review/i.test(e.summary) ||
          /ready|draft|shipped|review/i.test(e.title);
        return ready;
      });

      for (const e of wip.slice(0, 3)) {
        rows.push({
          who: e.source_agent.toLowerCase(),
          text: e.title,
          tag: (e.tags ?? []).includes("ready") ? "ready" : undefined,
        });
      }
    }
  } catch {
    // offline
  }

  if (rows.length === 0) {
    rows.push({ text: "no ready deliverables in bolton - tag entries ready when complete" });
  }

  return { kicker: "work in progress", agentId: "johnny", rows };
}

async function fetchActivity(): Promise<ActivityEntry[]> {
  const combined: Array<{ agentId: AgentId; time: string; text: string; at: number }> = [];

  try {
    const [memRes, decRes] = await Promise.all([
      fetch(`${BOLTON_API_URL}/api/memory?status=active`, { cache: "no-store", signal: AbortSignal.timeout(3_500) }),
      fetch(`${BOLTON_API_URL}/api/decisions`, { cache: "no-store", signal: AbortSignal.timeout(3_500) }),
    ]);

    if (memRes.ok) {
      const data = await memRes.json();
      const entries = (data.entries ?? []).map((e: Record<string, unknown>) => normalizeEntry(e));
      for (const e of entries) {
        const created = entryCreatedAt(e);
        if (!created) continue;
        combined.push({
          agentId: agentIdFromSource(e.source_agent),
          time: relativeTime(created),
          text: e.summary || e.title,
          at: new Date(created).getTime(),
        });
      }
    }

    if (decRes.ok) {
      const data = await decRes.json();
      for (const raw of data.decisions ?? []) {
        const d = raw as Record<string, unknown>;
        const source = String(d.sourceAgent ?? d.source_agent ?? "");
        const created = String(d.createdAt ?? d.created_at ?? "");
        const decision = String(d.decision ?? "");
        const context = d.context ? String(d.context) : "";
        if (!created) continue;
        combined.push({
          agentId: agentIdFromSource(source),
          time: relativeTime(created),
          text: decision + (context ? ` - ${context}` : ""),
          at: new Date(created).getTime(),
        });
      }
    }
  } catch {
    // offline
  }

  return combined
    .sort((a, b) => b.at - a.at)
    .slice(0, 8)
    .map(({ agentId, time, text }) => ({ agentId, time, text }));
}

export interface DashboardPayload {
  glance: GlanceCard[];
  activity: ActivityEntry[];
  roster: Array<{ agentId: AgentId; build_status: BuildStatus }>;
}

export async function loadDashboardData(): Promise<DashboardPayload> {
  const [inbox, calendar, wip, activity] = await Promise.all([
    fetchInboxGlance(),
    fetchCalendarGlance(),
    fetchWipGlance(),
    fetchActivity(),
  ]);

  return {
    glance: [inbox, calendar, wip],
    activity,
    roster: AGENT_BUILD_STATUS.map(({ agentId, build_status }) => ({
      agentId,
      build_status,
    })),
  };
}
