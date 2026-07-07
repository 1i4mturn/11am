import { z } from "zod";

export const CadenceSchema = z.enum([
  "once",
  "daily",
  "weekly",
  "monthly",
  "custom",
]);
export type Cadence = z.infer<typeof CadenceSchema>;

export const ReviewInputSchema = z.object({
  prompt: z.string().min(1),
  diff: z.string().optional(),
  repo_path: z.string().optional(),
  github: z
    .object({
      owner: z.string(),
      repo: z.string(),
      base: z.string().default("main"),
      head: z.string(),
    })
    .optional(),
});
export type ReviewInput = z.infer<typeof ReviewInputSchema>;

export interface ReviewResult {
  summary: string;
  findings: Array<{
    severity: "high" | "medium" | "low";
    file?: string;
    message: string;
  }>;
  suggestions: string[];
  architecture_notes: string;
  raw?: string;
}

export const CreateJobBodySchema = z.object({
  prompt: z.string().min(1),
  repo: z
    .object({
      type: z.enum(["local", "github"]),
      path: z.string().optional(),
      owner: z.string().optional(),
      repo: z.string().optional(),
      ref: z.string().optional(),
    })
    .optional(),
  budget: z
    .object({
      max_tokens: z.number().optional(),
      max_time_ms: z.number().optional(),
      max_cost_usd: z.number().optional(),
    })
    .optional(),
});
