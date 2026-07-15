import { z } from "zod";

export type Cadence = "once" | "daily" | "weekly" | "monthly" | "custom";

export type WorkflowType =
  | "brand_direction"
  | "color_typography"
  | "moodboard"
  | "logo_concepts"
  | "brand_audit"
  | "competitor_landscape"
  | "handoff";

export type HandoffTarget = "johnny" | "cole";

/** Exact shape William sends - must stay in sync */
export interface WilliamRobertHandoff {
  copy: string;
  platform: string;
  format: string;
  tone_notes: string;
  visual_direction: string;
}

export const MotionTokensSchema = z.object({
  timing: z.record(z.string(), z.string()),
  easing: z.record(z.string(), z.string()),
  logo_safe_area: z.string(),
});

export const DoDontRuleSchema = z.object({
  type: z.enum(["do", "dont"]),
  rule: z.string(),
});

export const LogoVariantSchema = z.object({
  id: z.string(),
  description: z.string(),
  usage: z.string().optional(),
  concept_image_url: z.string().optional(),
});

/** Living brand-system doc - exact Bolton schema (Cole depends on motion_tokens) */
export const BrandSystemDocSchema = z.object({
  source_agent: z.literal("Robert"),
  version: z.string(),
  color_tokens: z.record(z.string(), z.string()),
  type_scale: z.record(z.string(), z.string()),
  logo_variants: z.array(LogoVariantSchema),
  spacing_tokens: z.record(z.string(), z.string()),
  motion_tokens: MotionTokensSchema,
  do_dont_rules: z.array(DoDontRuleSchema),
});

export type BrandSystemDoc = z.infer<typeof BrandSystemDocSchema>;

export const TokenRecommendationSchema = z.object({
  color_tokens: z.record(z.string(), z.string()),
  type_scale: z.record(z.string(), z.string()),
  spacing_tokens: z.record(z.string(), z.string()),
  rationale: z.record(z.string(), z.string()).optional(),
});

export type TokenRecommendation = z.infer<typeof TokenRecommendationSchema>;

export const ImplementationBriefSchema = z.object({
  source_agent: z.literal("Robert"),
  target_agent: z.enum(["johnny", "cole"]),
  as_of: z.string(),
  project: z.string(),
  objective: z.string(),
  color_tokens: z.record(z.string(), z.string()),
  type_scale: z.record(z.string(), z.string()),
  spacing_tokens: z.record(z.string(), z.string()),
  motion_tokens: MotionTokensSchema,
  layout_direction: z.string(),
  component_notes: z.array(z.string()),
  motion_direction: z.string().optional(),
  assets: z.array(
    z.object({
      type: z.string(),
      url: z.string().optional(),
      notes: z.string(),
    })
  ),
  do_dont_rules: z.array(z.string()),
  acceptance_criteria: z.array(z.string()),
});

export type ImplementationBrief = z.infer<typeof ImplementationBriefSchema>;

export interface BrandDirectionResult {
  workflow: "brand_direction";
  advice: string;
  conner_context_used: boolean;
  used_mock_conner: boolean;
  recommended_updates: string[];
  confidence: "high" | "medium" | "low";
}

export interface MoodboardResult {
  workflow: "moodboard";
  prompt: string;
  images: Array<{ url: string; revised_prompt?: string }>;
  images_remaining: number;
}

export interface LogoConceptResult {
  workflow: "logo_concepts";
  direction: string;
  concepts: Array<{
    id: string;
    description: string;
    image_url?: string;
    notes: string;
  }>;
  disclaimer: string;
}

export interface BrandAuditResult {
  workflow: "brand_audit";
  asset_filename: string;
  inconsistencies: Array<{
    area: string;
    expected: string;
    observed: string;
    severity: "high" | "medium" | "low";
  }>;
  passes: string[];
  overall_verdict: "on_brand" | "needs_revision" | "off_brand";
  summary: string;
}

export interface CompetitorLandscapeResult {
  workflow: "competitor_landscape";
  james_context_used: boolean;
  used_mock_james: boolean;
  visual_trends: string[];
  competitor_patterns: Array<{ name: string; visual_notes: string }>;
  differentiation_opportunities: string[];
  recommendation: string;
}

export interface RobertHandoffResponse {
  from_agent: "Robert";
  to_agent: string;
  request_type: string;
  summary: string;
  structured_result?: Record<string, unknown>;
  brand_system_written?: boolean;
  memory_ids_written: string[];
}
