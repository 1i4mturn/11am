import { NextRequest, NextResponse } from "next/server";
import { z } from "zod";
import { runHandoff } from "@/lib/design/engine";

const WilliamHandoffSchema = z.object({
  copy: z.string(),
  platform: z.string(),
  format: z.string(),
  tone_notes: z.string(),
  visual_direction: z.string(),
});

const HandoffSchema = z.object({
  from_agent: z.string(),
  to_agent: z.string().optional(),
  task: z.string().min(1),
  context_ref: z.string().optional(),
  priority: z.enum(["normal", "urgent"]).default("normal"),
  request_type: z
    .enum([
      "brand_direction",
      "visual_brief",
      "token_review",
      "design_critique",
      "layout",
      "competitor_landscape",
      "color_typography",
      "general",
    ])
    .optional(),
  william_handoff: WilliamHandoffSchema.optional(),
});

export async function POST(request: NextRequest) {
  try {
    const body = HandoffSchema.parse(await request.json());
    const result = await runHandoff({
      from_agent: body.from_agent,
      task: body.task,
      request_type: body.request_type,
      william_handoff: body.william_handoff,
    });

    return NextResponse.json({
      from_agent: "Robert",
      to_agent: body.from_agent,
      request_type: body.request_type ?? "general",
      summary: result.summary,
      structured_result: result.structured_result,
      brand_system_written: true,
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
        task: "string",
        request_type:
          "brand_direction | visual_brief | token_review | design_critique | layout | competitor_landscape | general",
        william_handoff: "optional — same shape as William→Robert handoff",
      },
      response: {
        from_agent: "Robert",
        summary: "string",
        structured_result: "object",
        brand_system_written: "boolean",
        memory_ids_written: "string[]",
      },
    },
  });
}
