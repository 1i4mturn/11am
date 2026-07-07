import { z } from "zod";

export const CadenceSchema = z.enum(["once", "daily", "weekly", "monthly", "custom"]);

export const ScheduleTaskSchema = z.object({
  prompt: z.string().min(1),
  cadence: CadenceSchema,
  custom_schedule: z.string().optional(),
  task_type: z.enum(["inbox_review", "briefing", "search", "general"]).default("general"),
});

export type Cadence = z.infer<typeof CadenceSchema>;
export type ScheduleTask = z.infer<typeof ScheduleTaskSchema>;
