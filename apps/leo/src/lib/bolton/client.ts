import type {
  BoltonMemoryEntry,
  BoltonTask,
  ContextPack,
  TaskFields,
} from "@/lib/types";
import { parseTaskFields, taskToFullContent } from "@/lib/types";

const BOLTON_BASE = process.env.BOLTON_API_URL ?? "http://localhost:3002";

async function boltonFetch(path: string, init?: RequestInit) {
  const res = await fetch(`${BOLTON_BASE}${path}`, {
    ...init,
    headers: { "Content-Type": "application/json", ...init?.headers },
  });
  return res;
}

export async function writeToBolton(candidate: {
  source_agent: string;
  entry_type: string;
  title: string;
  summary: string;
  full_content?: string;
  tags?: string[];
  importance_score?: number;
  cadence?: TaskFields["cadence"];
  custom_schedule?: string;
  force?: boolean;
}): Promise<{ saved?: boolean; id?: string; action?: string } | null> {
  try {
    const res = await boltonFetch("/api/memory", {
      method: "POST",
      body: JSON.stringify({ ...candidate, force: candidate.force ?? true }),
    });
    if (res.ok) {
      const data = await res.json();
      const id = data.id ?? data.entry?.id;
      return { ...data, id };
    }
  } catch {
    // Bolton may be offline during dev
  }
  return null;
}

export async function getBoltonContext(
  task: string,
  requestingAgent = "Leo"
): Promise<{ context_pack: ContextPack } | null> {
  try {
    const res = await boltonFetch("/api/context", {
      method: "POST",
      body: JSON.stringify({ requesting_agent: requestingAgent, task }),
    });
    if (res.ok) return res.json();
  } catch {
    // fallback
  }
  return null;
}

export async function listBoltonMemory(params: {
  entry_type?: string;
  source_agent?: string;
  status?: string;
}): Promise<BoltonMemoryEntry[]> {
  const qs = new URLSearchParams();
  if (params.entry_type) qs.set("entry_type", params.entry_type);
  if (params.source_agent) qs.set("source_agent", params.source_agent);
  if (params.status) qs.set("status", params.status);

  try {
    const res = await boltonFetch(`/api/memory?${qs.toString()}`);
    if (!res.ok) return [];
    const data = (await res.json()) as { entries: BoltonMemoryEntry[] };
    return data.entries ?? [];
  } catch {
    return [];
  }
}

export async function listBoltonTasks(): Promise<BoltonTask[]> {
  const entries = await listBoltonMemory({ entry_type: "task", status: "active" });
  return entries.map((entry) => {
    const raw = entry as unknown as Record<string, unknown>;
    const normalized: BoltonMemoryEntry = {
      id: String(raw.id ?? entry.id),
      source_agent: String(raw.source_agent ?? entry.source_agent ?? ""),
      entry_type: String(raw.entry_type ?? entry.entry_type ?? "task"),
      title: String(raw.title ?? entry.title ?? ""),
      summary: String(raw.summary ?? entry.summary ?? ""),
      full_content: (raw.full_content as string | null | undefined) ?? entry.full_content,
      tags: (raw.tags as string[]) ?? entry.tags,
      status: String(raw.status ?? entry.status ?? "active"),
      cadence: (raw.cadence as string | null) ?? entry.cadence,
      custom_schedule: (raw.custom_schedule as string | null) ?? entry.custom_schedule,
      created_at: String(raw.created_at ?? entry.created_at ?? ""),
    };
    return {
      ...normalized,
      task: parseTaskFields(normalized),
    };
  });
}

export async function updateBoltonMemory(
  id: string,
  patch: {
    title?: string;
    summary?: string;
    full_content?: string;
    tags?: string[];
    status?: string;
  }
): Promise<boolean> {
  try {
    const res = await boltonFetch("/api/memory", {
      method: "PATCH",
      body: JSON.stringify({ id, ...patch }),
    });
    return res.ok;
  } catch {
    return false;
  }
}

export async function createBoltonTask(input: {
  title: string;
  summary: string;
  source_agent?: string;
  task: TaskFields;
  tags?: string[];
}): Promise<{ id?: string } | null> {
  const result = await writeToBolton({
    source_agent: input.source_agent ?? "Leo",
    entry_type: "task",
    title: input.title,
    summary: input.summary,
    full_content: taskToFullContent(input.task),
    tags: [
      ...(input.tags ?? []),
      `status:${input.task.status}`,
      `priority:${input.task.priority}`,
    ],
    cadence: input.task.cadence,
    custom_schedule: input.task.custom_schedule ?? undefined,
    force: true,
  });
  return result?.id ? { id: result.id } : null;
}

export async function updateBoltonTask(
  entry: BoltonTask,
  patch: Partial<TaskFields> & { title?: string; summary?: string }
): Promise<boolean> {
  const task = { ...entry.task, ...patch };
  return updateBoltonMemory(entry.id, {
    title: patch.title ?? entry.title,
    summary: patch.summary ?? entry.summary,
    full_content: taskToFullContent(task),
    tags: [
      ...(entry.tags ?? []).filter(
        (t) => !t.startsWith("status:") && !t.startsWith("priority:")
      ),
      `status:${task.status}`,
      `priority:${task.priority}`,
    ],
  });
}

export async function archiveBoltonTask(id: string): Promise<boolean> {
  try {
    const res = await boltonFetch(`/api/memory?id=${id}&confirmed=true`, {
      method: "DELETE",
    });
    return res.ok;
  } catch {
    return false;
  }
}

export async function getAgentSummaryViaContext(
  agentId: string
): Promise<ContextPack | null> {
  const taskMap: Record<string, string> = {
    george: "Latest George finance summary — revenue, runway, burn rate, flags",
    james: "Latest James research summary — competitive landscape and key findings",
    conner: "Latest Conner strategy summary — positioning, decisions, target segment",
  };
  const task = taskMap[agentId.toLowerCase()];
  if (!task) return null;
  const pack = await getBoltonContext(task, "Leo");
  return pack?.context_pack ?? null;
}
