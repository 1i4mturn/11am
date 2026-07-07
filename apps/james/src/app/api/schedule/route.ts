import { NextRequest, NextResponse } from "next/server";
import { z } from "zod";
import { writeToBolton } from "@/lib/bolton/client";

const CadenceSchema = z.enum(["once", "daily", "weekly", "monthly", "custom"]);

const ScheduleSchema = z.object({
  prompt: z.string().min(1),
  cadence: CadenceSchema,
  custom_schedule: z.string().optional(),
  task_type: z.enum(["research", "market_scan", "pricing_check", "general"]).default("research"),
});

export async function POST(request: NextRequest) {
  try {
    const body = ScheduleSchema.parse(await request.json());
    const cadenceLabel =
      body.cadence === "custom" && body.custom_schedule
        ? body.custom_schedule
        : body.cadence;

    await writeToBolton({
      source_agent: "James",
      entry_type: "task",
      title: `Scheduled research: ${body.prompt.slice(0, 60)}${body.prompt.length > 60 ? "…" : ""}`,
      summary: `${cadenceLabel} · ${body.task_type} · ${body.prompt.slice(0, 200)}`,
      full_content: JSON.stringify(
        {
          prompt: body.prompt,
          task_type: body.task_type,
          cadence: body.cadence,
          custom_schedule: body.custom_schedule ?? null,
          assigned_to: "leo",
          created_by: "james",
          created_at: new Date().toISOString(),
        },
        null,
        2
      ),
      tags: ["task", "james", "schedule", `cadence:${body.cadence}`, "leo-calendar"],
      force: true,
    });

    return NextResponse.json({
      success: true,
      message: `Scheduled for Leo's calendar (${cadenceLabel})`,
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Schedule failed";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
