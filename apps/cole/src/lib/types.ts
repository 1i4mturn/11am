import { z } from "zod";

export type Cadence = "once" | "daily" | "weekly" | "monthly" | "custom";

export type WorkflowType =
  | "script"
  | "concepts"
  | "storyboard"
  | "transcribe"
  | "convert"
  | "motion_template";

export type Platform = "youtube" | "reels" | "tiktok" | "general";

export const MotionTokensSchema = z.object({
  timing: z.record(z.string(), z.string()),
  easing: z.record(z.string(), z.string()),
  logo_safe_area: z.string(),
});

export const BrandSystemDocSchema = z.object({
  source_agent: z.literal("Robert"),
  version: z.string(),
  color_tokens: z.record(z.string(), z.string()),
  type_scale: z.record(z.string(), z.string()),
  logo_variants: z.array(
    z.object({
      id: z.string(),
      description: z.string(),
      usage: z.string().optional(),
    })
  ),
  spacing_tokens: z.record(z.string(), z.string()),
  motion_tokens: MotionTokensSchema,
  do_dont_rules: z.array(
    z.object({
      type: z.enum(["do", "dont"]),
      rule: z.string(),
    })
  ),
});

export type BrandSystemDoc = z.infer<typeof BrandSystemDocSchema>;

export interface BrandContext {
  doc: BrandSystemDoc;
  from_mock: boolean;
  motion_tokens_ready: boolean;
}

export interface ScriptPackageResult {
  workflow: "script";
  brief: string;
  platform: Platform;
  script: string;
  shot_list: Array<{ shot: number; description: string; duration: string; notes: string }>;
  voiceover: string;
  editing_direction: string;
  motion_notes: string;
}

export interface ContentConceptResult {
  workflow: "concepts";
  platform: Platform;
  hook: string;
  structure: Array<{ beat: string; duration: string; purpose: string }>;
  cta: string;
  caption_draft: string;
}

export interface StoryboardResult {
  workflow: "storyboard";
  title: string;
  frames: Array<{
    frame: number;
    visual: string;
    audio: string;
    duration: string;
    transition: string;
  }>;
  spec_only: true;
}

export interface TranscriptionResult {
  text: string;
  segments: Array<{ start: number; end: number; text: string }>;
  srt: string;
  vtt: string;
}

export interface ConvertResult {
  input_format: string;
  output_format: string;
  output_path: string;
  download_url: string;
}

export interface MotionTemplateResult {
  template_id: string;
  css_variables: Record<string, string>;
  motion_spec: {
    timing: Record<string, string>;
    easing: Record<string, string>;
    logo_safe_area: string;
  };
  preview_html: string;
}
