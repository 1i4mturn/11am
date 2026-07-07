import { z } from "zod";

export const EntryTypeSchema = z.enum([
  "decision",
  "preference",
  "project",
  "person",
  "research",
  "voice",
  "sender_memory",
  "reference",
  "output",
  "task",
]);

export const MemoryStatusSchema = z.enum([
  "active",
  "archived",
  "superseded",
  "conflict_review",
]);

export const ConfidenceSchema = z.enum(["high", "medium", "low"]);

export type EntryType = z.infer<typeof EntryTypeSchema>;
export type MemoryStatus = z.infer<typeof MemoryStatusSchema>;

export interface MemoryEntry {
  id: string;
  user_id: string;
  source_agent: string;
  entry_type: EntryType;
  title: string;
  summary: string;
  full_content?: string | null;
  tags: string[];
  related_entities: string[];
  related_entries: string[];
  importance_score: number;
  confidence: "high" | "medium" | "low";
  status: MemoryStatus;
  superseded_by_id?: string | null;
  created_at: Date;
  last_accessed_at: Date;
}

export interface Entity {
  id: string;
  entity_type: string;
  name: string;
  aliases: string[];
  summary: string;
  importance_level: string;
}

export interface Decision {
  id: string;
  decision: string;
  context: string;
  rationale: string;
  alternatives_considered: string[];
  source_agent: string;
  status: string;
  date: Date;
}

export const CadenceSchema = z.enum(["once", "daily", "weekly", "monthly", "custom"]);

export interface ContextMemoryRef {
  id: string;
  title: string;
  summary: string;
  entry_type: EntryType;
  source_agent: string;
}

export interface ContextEntityRef {
  id: string;
  name: string;
  entity_type: string;
  summary: string;
}

export interface ContextPack {
  requesting_agent: string;
  task: string;
  relevant_memory: ContextMemoryRef[];
  relevant_entities: ContextEntityRef[];
  active_decisions: string[];
  warnings: string[];
}

export interface CaptureCandidate {
  source_agent: string;
  entry_type: EntryType;
  title: string;
  summary: string;
  full_content?: string;
  tags?: string[];
  related_entities?: string[];
  related_entries?: string[];
  importance_score?: number;
  confidence?: "high" | "medium" | "low";
  cadence?: z.infer<typeof CadenceSchema>;
  custom_schedule?: string;
}

export type CaptureAction =
  | "save"
  | "update"
  | "supersede"
  | "link"
  | "skip"
  | "ask_user";
