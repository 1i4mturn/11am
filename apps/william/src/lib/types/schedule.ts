import { z } from "zod";
import { PlatformSchema } from "./voice-profile";

export const CadenceSchema = z.enum(["once", "daily", "weekly", "monthly", "custom"]);

export const ScheduleTaskSchema = z.object({
  prompt: z.string().min(1),
  platform: PlatformSchema.default("email"),
  cadence: CadenceSchema,
  custom_schedule: z.string().optional(),
  include_business_context: z.boolean().optional(),
});

export type Cadence = z.infer<typeof CadenceSchema>;
export type ScheduleTask = z.infer<typeof ScheduleTaskSchema>;
