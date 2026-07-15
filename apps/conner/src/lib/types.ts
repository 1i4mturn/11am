import { z } from "zod";

export type WorkflowType =
  | "idea_validation"
  | "stress_test"
  | "gtm"
  | "growth"
  | "pricing"
  | "digest";

export type Cadence = "once" | "daily" | "weekly" | "monthly" | "custom";

export type Confidence = "high" | "medium" | "low";

/** Exact shape William depends on - source_agent lowercase per agent-summaries schema */
export const ConnerStrategySummarySchema = z.object({
  source_agent: z.literal("conner"),
  as_of: z.string(),
  positioning_update: z.string(),
  target_segment: z.string(),
  key_decisions: z.array(z.string()),
  confidence: z.enum(["high", "medium", "low"]),
});

export type ConnerStrategySummary = z.infer<typeof ConnerStrategySummarySchema>;

export const GeorgeNumbersSummarySchema = z.object({
  source_agent: z.string().optional(),
  as_of: z.string(),
  revenue: z.string(),
  margin_pct: z.number(),
  runway_months: z.number(),
  burn_rate: z.string(),
  flags: z.array(z.string()),
  confidence: z.enum(["high", "medium", "low"]),
});

export type GeorgeNumbersSummary = z.infer<typeof GeorgeNumbersSummarySchema>;

export interface IdeaValidationResult {
  workflow: "idea_validation";
  idea: string;
  verdict: "pursue" | "refine" | "park" | "kill";
  reasoning: string;
  market_assumptions: string[];
  risks: string[];
  offer: {
    headline: string;
    promise: string;
    audience: string;
    price_anchor: string;
    delivery: string;
  };
  next_steps: string[];
  confidence: Confidence;
  narrative: string;
}

export interface StressTestResult {
  workflow: "stress_test";
  idea_or_model: string;
  george_context: GeorgeNumbersSummary;
  used_mock_george: boolean;
  stress_points: string[];
  runway_impact: string;
  unit_economics_flags: string[];
  recommendation: string;
  confidence: Confidence;
  narrative: string;
}

export interface GtmResult {
  workflow: "gtm";
  launch_brief: string;
  channels: Array<{ channel: string; rationale: string; priority: "now" | "next" | "later" }>;
  timeline_phases: Array<{ phase: string; duration: string; actions: string[] }>;
  james_context_used: boolean;
  used_mock_james: boolean;
  confidence: Confidence;
  narrative: string;
}

export interface GrowthResult {
  workflow: "growth";
  strategy_summary: string;
  levers: Array<{ lever: string; impact: string; effort: string }>;
  experiments: string[];
  george_context_used: boolean;
  james_context_used: boolean;
  used_mock_george: boolean;
  used_mock_james: boolean;
  confidence: Confidence;
  narrative: string;
}

export interface PricingResult {
  workflow: "pricing";
  pricing_model: string;
  tiers_or_packages: Array<{ name: string; price: string; rationale: string }>;
  unit_economics_check: string;
  competitive_position: string;
  george_context: GeorgeNumbersSummary;
  james_research_summary: string;
  used_mock_george: boolean;
  used_mock_james: boolean;
  recommendation: string;
  confidence: Confidence;
  narrative: string;
}

export interface DigestResult {
  workflow: "digest";
  period_label: string;
  health_score: "strong" | "stable" | "caution" | "critical";
  highlights: string[];
  concerns: string[];
  cross_agent_synthesis: string;
  agents_available: string[];
  agents_missing: string[];
  recommended_actions: string[];
  narrative: string;
}

export interface JamesInvokeResult {
  from_agent: string;
  to_agent: string;
  summary: string;
  structured_result?: Record<string, unknown>;
  memory_ids_written: string[];
  follow_up_needed: boolean;
}

export interface ConnerHandoff {
  from_agent: "Conner";
  to_agent: string;
  request_type: string;
  summary: string;
  structured_result?: Record<string, unknown>;
  strategy_written?: boolean;
  memory_ids_written: string[];
}
