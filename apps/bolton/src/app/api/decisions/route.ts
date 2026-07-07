import { NextRequest, NextResponse } from "next/server";
import { z } from "zod";
import { logDecision, listDecisions } from "@/lib/decisions";

export async function GET() {
  const decisions = await listDecisions();
  return NextResponse.json({ decisions });
}

const DecisionSchema = z.object({
  decision: z.string().min(1),
  context: z.string().optional(),
  rationale: z.string().optional(),
  alternatives_considered: z.array(z.string()).optional(),
  source_agent: z.string(),
  decision_type: z.string().optional(),
});

export async function POST(request: NextRequest) {
  const body = DecisionSchema.parse(await request.json());
  const dec = await logDecision({
    decision: body.decision,
    context: body.context,
    rationale: body.rationale,
    alternativesConsidered: body.alternatives_considered,
    sourceAgent: body.source_agent,
    decisionType: body.decision_type,
  });
  return NextResponse.json({ decision: dec });
}
