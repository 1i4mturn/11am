import { NextRequest, NextResponse } from "next/server";
import { z } from "zod";
import { saveMemoryEntry } from "@/lib/memory";
import { resolveUserId } from "@/lib/config";
import { CadenceSchema } from "@/lib/types";

/**
 * Schedule action for the Ask Bolton bar - same cross-cutting pattern as the
 * other agents, except Bolton writes the task entry to its own store directly.
 */
const ScheduleSchema = z.object({
  prompt: z.string().min(1),
  cadence: CadenceSchema,
  custom_schedule: z.string().optional(),
  task_type: z.string().default("memory_review"),
});

export async function POST(request: NextRequest) {
  try {
    const userId = resolveUserId(request.headers.get("x-user-id"));
    const body = ScheduleSchema.parse(await request.json());
    const cadenceLabel =
      body.cadence === "custom" && body.custom_schedule ? body.custom_schedule : body.cadence;

    const taskPayload = {
      prompt: body.prompt,
      task_type: body.task_type,
      cadence: body.cadence,
      custom_schedule: body.custom_schedule ?? null,
      assigned_to: "leo",
      created_by: "bolton",
      created_at: new Date().toISOString(),
    };

    await saveMemoryEntry(
      {
        source_agent: "Bolton",
        entry_type: "task",
        title: `Scheduled memory task: ${body.prompt.slice(0, 60)}${body.prompt.length > 60 ? "…" : ""}`,
        summary: `${cadenceLabel} · ${body.task_type} · ${body.prompt.slice(0, 200)}`,
        full_content: JSON.stringify(taskPayload, null, 2),
        tags: ["task", "bolton", "schedule", `cadence:${body.cadence}`, "leo-calendar"],
        cadence: body.cadence,
        custom_schedule: body.custom_schedule,
        importance_score: 0.7,
      },
      userId,
      true
    );

    return NextResponse.json({
      success: true,
      task: taskPayload,
      message: `Scheduled for Leo's calendar (${cadenceLabel})`,
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Schedule failed";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
