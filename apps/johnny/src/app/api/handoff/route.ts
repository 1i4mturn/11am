import { NextRequest, NextResponse } from "next/server";
import { z } from "zod";
import { runHandoff } from "@/lib/review";

const HandoffSchema = z.object({
  from_agent: z.string(),
  task: z.string().min(1),
  priority: z.enum(["normal", "urgent"]).default("normal"),
});

export async function POST(request: NextRequest) {
  try {
    const body = HandoffSchema.parse(await request.json());
    const result = await runHandoff(body);
    return NextResponse.json({
      from_agent: "Johnny",
      to_agent: body.from_agent,
      summary: result.summary,
      memory_ids_written: [],
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Handoff failed";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}

export async function GET() {
  return NextResponse.json({
    contract: {
      request: { from_agent: "string", task: "string" },
      response: { from_agent: "Johnny", summary: "string" },
    },
  });
}
