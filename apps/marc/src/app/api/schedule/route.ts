import { NextRequest, NextResponse } from "next/server";
import { ScheduleTaskSchema } from "@/lib/types/schedule";
import { writeToBolton } from "@/lib/bolton/client";

export async function POST(request: NextRequest) {
  try {
    const body = ScheduleTaskSchema.parse(await request.json());
    const cadenceLabel =
      body.cadence === "custom" && body.custom_schedule
        ? body.custom_schedule
        : body.cadence;

    const taskPayload = {
      prompt: body.prompt,
      task_type: body.task_type,
      cadence: body.cadence,
      custom_schedule: body.custom_schedule ?? null,
      assigned_to: "leo",
      created_by: "marc",
      created_at: new Date().toISOString(),
    };

    await writeToBolton({
      source_agent: "Marc",
      entry_type: "task",
      title: `Scheduled inbox task: ${body.prompt.slice(0, 60)}${body.prompt.length > 60 ? "…" : ""}`,
      summary: `${cadenceLabel} · ${body.task_type} · ${body.prompt.slice(0, 200)}`,
      full_content: JSON.stringify(taskPayload, null, 2),
      tags: ["task", "marc", "schedule", `cadence:${body.cadence}`, "leo-calendar"],
      cadence: body.cadence,
      custom_schedule: body.custom_schedule,
      importance_score: 0.7,
      force: true,
    });

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
