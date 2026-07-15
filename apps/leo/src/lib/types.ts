export type TaskCadence = "once" | "daily" | "weekly" | "monthly" | "custom";
export type TaskStatus = "pending" | "in_progress" | "done" | "cancelled";
export type TaskPriority = "low" | "normal" | "high" | "urgent";

export interface TaskFields {
  status: TaskStatus;
  due_date?: string | null;
  priority: TaskPriority;
  cadence: TaskCadence;
  custom_schedule?: string | null;
}

export interface BoltonMemoryEntry {
  id: string;
  source_agent: string;
  entry_type: string;
  title: string;
  summary: string;
  full_content?: string | null;
  tags?: string[];
  status: string;
  cadence?: string | null;
  custom_schedule?: string | null;
  created_at?: string;
}

export interface BoltonTask extends BoltonMemoryEntry {
  task: TaskFields;
}

export type AgentInvokePriority = "normal" | "urgent";
export type AgentResponseMode = "sync" | "async";

/** Shared routing interface - every agent in the suite uses this contract */
export interface AgentInvokeRequest {
  from_agent: string;
  to_agent: string;
  task: string;
  context_ref?: string;
  priority: AgentInvokePriority;
  response_mode: AgentResponseMode;
}

export interface AgentInvokeResponse {
  from_agent: string;
  to_agent: string;
  summary: string;
  structured_result?: Record<string, unknown>;
  memory_ids_written: string[];
  follow_up_needed: boolean;
}

export interface CalendarEvent {
  id: string;
  summary: string;
  description?: string;
  location?: string;
  start: string;
  end: string;
  htmlLink?: string;
  attendees?: string[];
}

export interface ContextPack {
  requesting_agent: string;
  task: string;
  relevant_memory: Array<{
    id: string;
    title: string;
    summary: string;
    entry_type: string;
    source_agent: string;
  }>;
  relevant_entities: Array<{
    id: string;
    name: string;
    entity_type: string;
    summary: string;
  }>;
  active_decisions: string[];
  warnings: string[];
}

export function parseTaskFields(entry: BoltonMemoryEntry): TaskFields {
  const defaults: TaskFields = {
    status: "pending",
    priority: "normal",
    cadence: (entry.cadence as TaskCadence) ?? "once",
    custom_schedule: entry.custom_schedule ?? null,
  };

  if (entry.full_content) {
    try {
      const parsed = JSON.parse(entry.full_content) as Partial<TaskFields>;
      return {
        status: parsed.status ?? defaults.status,
        due_date: parsed.due_date ?? null,
        priority: parsed.priority ?? defaults.priority,
        cadence: parsed.cadence ?? defaults.cadence,
        custom_schedule: parsed.custom_schedule ?? defaults.custom_schedule,
      };
    } catch {
      // fall through
    }
  }

  const tagStatus = entry.tags?.find((t) => t.startsWith("status:"));
  if (tagStatus) defaults.status = tagStatus.replace("status:", "") as TaskStatus;

  const tagPriority = entry.tags?.find((t) => t.startsWith("priority:"));
  if (tagPriority) defaults.priority = tagPriority.replace("priority:", "") as TaskPriority;

  return defaults;
}

export function taskToFullContent(fields: TaskFields): string {
  return JSON.stringify(fields);
}
