import { NextRequest, NextResponse } from "next/server";
import { z } from "zod";
import { runResearch } from "@/lib/research/engine";

/** Separate-context handoff — returns ONLY summarised handoff, never full thread */
const HandoffSchema = z.object({
  from_agent: z.string(),
  to_agent: z.string().optional(),
  research_question: z.string().min(1),
  task: z.string().optional(),
  context_ref: z.string().optional(),
  priority: z.enum(["normal", "urgent"]).default("normal"),
  request_type: z
    .enum(["market", "technical", "cultural", "academic", "pricing", "general"])
    .optional(),
});

export async function POST(request: NextRequest) {
  try {
    const body = HandoffSchema.parse(await request.json());
    const question = body.research_question || body.task;
    if (!question) {
      return NextResponse.json({ error: "research_question required" }, { status: 400 });
    }

    const handoff = await runResearch({
      research_question: question,
      from_agent: body.from_agent,
      to_agent: body.to_agent ?? body.from_agent,
      context_ref: body.context_ref,
      priority: body.priority,
      request_type: body.request_type,
    });

    return NextResponse.json(handoff);
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
        research_question: "string",
        context_ref: "string (optional)",
        priority: "normal | urgent",
        request_type: "market | technical | cultural | academic | pricing | general",
      },
      response: {
        from_agent: "James",
        to_agent: "string",
        research_question: "string",
        key_findings: "string[]",
        what_this_means: "string",
        recommendation: "string",
        sources: "[{ title, url, credibility_score, notes? }]",
        saved_to_bolton: "boolean",
        memory_id: "string (optional)",
      },
      note: "Full research thread never returned — James runs in separate context.",
    },
  });
}
