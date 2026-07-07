import { z } from "zod";

export const PlatformSchema = z.enum([
  "email",
  "linkedin",
  "blog",
  "slack",
  "announcement",
  "other",
]);
export type Platform = z.infer<typeof PlatformSchema>;

export const VoiceProfileSchema = z.object({
  tone_adjectives: z.array(z.string()),
  sentence_rhythm: z.string(),
  vocabulary_preferences: z.array(z.string()),
  avoid_phrases: z.array(z.string()),
  platform_rules: z.record(z.string(), z.string()),
  argument_style: z.string(),
});
export type VoiceProfile = z.infer<typeof VoiceProfileSchema>;

export const RobertHandoffSchema = z.object({
  copy: z.string(),
  platform: z.string(),
  format: z.string(),
  tone_notes: z.string(),
  visual_direction: z.string(),
});
export type RobertHandoff = z.infer<typeof RobertHandoffSchema>;

export const BoltonAgentSummarySchema = z.object({
  agent_id: z.enum(["george", "conner"]),
  summary: z.record(z.string(), z.unknown()),
  session_note: z.string().optional(),
});
export type BoltonAgentSummary = z.infer<typeof BoltonAgentSummarySchema>;
