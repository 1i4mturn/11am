import { NextRequest, NextResponse } from "next/server";
import { z } from "zod";
import { runHandoff } from "@/lib/strategy/engine";

const HandoffSchema = z.object({
  from_agent: z.string(),
  to_agent: z.string().optional(),
  task: z.string().min(1),
  context_ref: z.string().optional(),
  priority: z.enum(["normal", "urgent"]).default("normal"),
  request_type: z
    .enum(["positioning", "offer", "gtm", "experiment", "pricing", "idea_validation", "growth", "general"])
    .optional(),
});

export async function POST(request: NextRequest) {
  try {
    const body = HandoffSchema.parse(await request.json());
    const result = await runHandoff({
      from_agent: body.from_agent,
      task: body.task,
      request_type: body.request_type,
      context_ref: body.context_ref,
      priority: body.priority,
    });

    return NextResponse.json({
      from_agent: "Conner",
      to_agent: body.from_agent,
      request_type: body.request_type ?? "general",
      summary: result.summary,
      structured_result: result.structured_result,
      strategy_written: true,
      memory_ids_written: result.memory_ids_written,
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Handoff failed";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}

export async function GET() {
  return NextResponse.json({
    contract: {
      request: {
        from_agent: "string",
        to_agent: "string (optional)",
        task: "string",
        context_ref: "string (optional)",
        priority: "normal | urgent",
        request_type:
          "positioning | offer | gtm | experiment | pricing | idea_validation | growth | general",
      },
      response: {
        from_agent: "Conner",
        to_agent: "string",
        summary: "string",
        structured_result: "object (optional)",
        strategy_written: "boolean",
        memory_ids_written: "string[]",
      },
    },
  });
}
