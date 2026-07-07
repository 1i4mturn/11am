import { z } from "zod";

export const JobStatusSchema = z.enum([
  "queued",
  "running",
  "completed",
  "failed",
  "killed",
]);
export type JobStatus = z.infer<typeof JobStatusSchema>;

export const JobConsumerSchema = z.enum(["johnny", "leo", "cole"]);
export type JobConsumer = z.infer<typeof JobConsumerSchema>;

export const RepoScopeSchema = z.object({
  type: z.enum(["local", "github"]),
  path: z.string().optional(),
  owner: z.string().optional(),
  repo: z.string().optional(),
  ref: z.string().default("main"),
});
export type RepoScope = z.infer<typeof RepoScopeSchema>;

export const JobBudgetSchema = z.object({
  max_tokens: z.number().default(100_000),
  max_time_ms: z.number().default(30 * 60 * 1000),
  max_cost_usd: z.number().default(2.0),
});
export type JobBudget = z.infer<typeof JobBudgetSchema>;

export const JobCostSchema = z.object({
  input_tokens: z.number().default(0),
  output_tokens: z.number().default(0),
  estimated_usd: z.number().default(0),
  elapsed_ms: z.number().default(0),
});
export type JobCost = z.infer<typeof JobCostSchema>;

export const JobStepSchema = z.object({
  id: z.string(),
  label: z.string(),
  status: z.enum(["pending", "running", "done", "skipped", "failed"]),
  detail: z.string().optional(),
  started_at: z.string().optional(),
  finished_at: z.string().optional(),
});
export type JobStep = z.infer<typeof JobStepSchema>;

export const BuildJobSchema = z.object({
  id: z.string(),
  consumer: JobConsumerSchema,
  status: JobStatusSchema,
  prompt: z.string(),
  repo: RepoScopeSchema,
  budget: JobBudgetSchema,
  cost: JobCostSchema,
  progress: z.number(),
  stage: z.string(),
  steps: z.array(JobStepSchema),
  bolton_context: z.record(z.string(), z.unknown()).optional(),
  result: z.record(z.string(), z.unknown()).optional(),
  error: z.string().optional(),
  kill_requested: z.boolean(),
  created_at: z.string(),
  updated_at: z.string(),
  completed_at: z.string().optional(),
});
export type BuildJob = z.infer<typeof BuildJobSchema>;

export const CreateJobInputSchema = z.object({
  consumer: JobConsumerSchema.default("johnny"),
  prompt: z.string().min(1),
  repo: RepoScopeSchema,
  budget: JobBudgetSchema.partial().optional(),
});
export type CreateJobInput = z.infer<typeof CreateJobInputSchema>;

export interface JobEvent {
  type: "progress" | "stage" | "completed" | "failed" | "killed";
  job_id: string;
  progress?: number;
  stage?: string;
  status?: JobStatus;
  message?: string;
  result?: Record<string, unknown>;
}

export interface JobsConfig {
  dataDir: string;
  boltonApiUrl: string;
  anthropicApiKey: string;
  githubToken?: string;
  sandboxImage: string;
  pagespeedApiKey?: string;
  tokenPricePerMInput?: number;
  tokenPricePerMOutput?: number;
}
