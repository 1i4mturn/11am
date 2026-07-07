import { z } from "zod";

export const TriageClassificationSchema = z.enum([
  "needs_reply",
  "needs_action",
  "waiting_on_other",
  "fyi",
  "archive",
  "newsletter",
  "finance",
  "system",
  "executive",
  "sensitive",
]);

export type TriageClassification = z.infer<typeof TriageClassificationSchema>;

export const PrioritySchema = z.enum(["high", "medium", "low"]);
export type Priority = z.infer<typeof PrioritySchema>;

export const RelationshipTypeSchema = z.enum([
  "executive",
  "client",
  "franchisee",
  "supplier",
  "finance",
  "friend",
  "unknown",
]);

export type RelationshipType = z.infer<typeof RelationshipTypeSchema>;

export interface InboxReviewItem {
  message_id: string;
  thread_id: string;
  sender: string;
  sender_email: string;
  subject: string;
  why_it_matters: string;
  priority: Priority;
  classification: TriageClassification;
  suggested_action: string;
  suggested_reply?: string;
  handoff_agent?: string;
}

export interface ReplyBrief {
  sender: string;
  relationship_type: string;
  thread_summary: string;
  desired_outcome: string;
  sensitivity_level: "normal" | "sensitive" | "urgent" | "reputation-relevant";
  tone_instruction: string;
  draft_reply: string;
  use_william?: boolean;
}

export interface SearchResult {
  message_id: string;
  thread_id: string;
  sender: string;
  subject: string;
  date: string;
  why_matched: string;
  thread_summary: string;
  suggested_action: string;
}

export interface InboxRule {
  rule_name: string;
  trigger: string;
  conditions: string[];
  actions: string[];
  exceptions: string[];
  created_by: string;
  status: "active" | "paused" | "pending";
}

export interface BoltonMemoryUpdate {
  memory_type: "sender_profile" | "decision" | "inbox_rule" | "recurring_pattern";
  source_thread: string;
  summary: string;
  confidence: "high" | "medium" | "low";
  expiry_or_review_date?: string;
}

export interface VoiceProfile {
  tone_adjectives: string[];
  sentence_rhythm: string;
  vocabulary_preferences: string[];
  avoid_phrases: string[];
  platform_rules: Record<string, string>;
  argument_style: string;
}
