import { NextRequest, NextResponse } from "next/server";
import { z } from "zod";
import { runResearch } from "@/lib/research/engine";

const ResearchSchema = z.object({
  research_question: z.string().min(1),
  request_type: z
    .enum(["market", "technical", "cultural", "academic", "pricing", "general"])
    .optional(),
  context_ref: z.string().optional(),
  priority: z.enum(["normal", "urgent"]).optional(),
});

export async function POST(request: NextRequest) {
  try {
    const body = ResearchSchema.parse(await request.json());
    const handoff = await runResearch({
      research_question: body.research_question,
      to_agent: "Liam",
      from_agent: "Liam",
      context_ref: body.context_ref,
      priority: body.priority,
      request_type: body.request_type,
    });
    return NextResponse.json({ handoff });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Research failed";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
