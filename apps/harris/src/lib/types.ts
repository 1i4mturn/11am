import { z } from "zod";

export type Cadence = "once" | "daily" | "weekly" | "monthly" | "custom";

export type WorkflowType =
  | "plan"
  | "roadmap"
  | "exercises"
  | "explain"
  | "gap_plan"
  | "french";

export type PlanStatus = "active" | "paused" | "completed";

/** Skill-gap signal — written by James or any agent */
export const SkillGapSignalSchema = z.object({
  source_agent: z.string(),
  skill_gap: z.string(),
  evidence: z.string(),
  suggested_for: z.literal("Harris"),
  priority: z.enum(["high", "medium", "low"]),
});

export type SkillGapSignal = z.infer<typeof SkillGapSignalSchema>;

export const PlanPhaseSchema = z.object({
  name: z.string(),
  duration: z.string(),
  goals: z.array(z.string()),
  resources: z.array(z.string()).default([]),
});

export const PlanContentSchema = z.object({
  overview: z.string(),
  phases: z.array(PlanPhaseSchema),
  weekly_rhythm: z.string().optional(),
});

export const ProgressSchema = z.object({
  status: z.enum(["active", "paused", "completed"]),
  percent_self_reported: z.number().min(0).max(100),
  last_session_note: z.string().optional(),
  sessions_completed: z.number().int().min(0),
  milestones_completed: z.array(z.string()),
  updated_at: z.string(),
});

export const ExerciseSchema = z.object({
  id: z.string(),
  title: z.string(),
  content: z.string(),
  completed: z.boolean().default(false),
});

export const LearningPlanSchema = z.object({
  id: z.string(),
  skill: z.string(),
  created_at: z.string(),
  updated_at: z.string(),
  source: z.enum(["manual", "skill_gap", "french"]),
  skill_gap_ref: z.string().optional(),
  plan: PlanContentSchema,
  roadmap: z.string().optional(),
  exercises: z.array(ExerciseSchema).default([]),
  progress: ProgressSchema,
});

export type LearningPlan = z.infer<typeof LearningPlanSchema>;

export const FrenchSrsCardSchema = z.object({
  id: z.string(),
  front: z.string(),
  back: z.string(),
  next_review: z.string(),
  interval_days: z.number(),
  ease: z.number().default(2.5),
});

export type FrenchSrsCard = z.infer<typeof FrenchSrsCardSchema>;

/** Primary Learning Hub store — full plan detail lives here, not duplicated in Bolton */
export const LearningHubSchema = z.object({
  version: z.literal(1),
  updated_at: z.string(),
  bolton_entry_id: z.string().optional(),
  plans: z.array(LearningPlanSchema),
  french_srs: z.array(FrenchSrsCardSchema).default([]),
});

export type LearningHub = z.infer<typeof LearningHubSchema>;

export interface PlanGenerationResult {
  plan: LearningPlan;
  narrative: string;
}

export interface RoadmapResult {
  skill: string;
  roadmap: string;
  milestones: string[];
}

export interface ExercisesResult {
  skill: string;
  exercises: Array<{ title: string; content: string }>;
}

export interface ExplainResult {
  concept: string;
  explanation: string;
  practice_prompt: string;
}

export interface GapPlanResult {
  skill_gap: SkillGapSignal;
  from_mock: boolean;
  plan: LearningPlan;
  narrative: string;
}

export interface HarrisHandoffResponse {
  from_agent: "Harris";
  to_agent: string;
  summary: string;
  memory_ids_written: string[];
}
