import { NextRequest, NextResponse } from "next/server";
import { z } from "zod";
import { invokeJamesResearch } from "@/lib/strategy/engine";

const InvokeJamesSchema = z.object({
  task: z.string().min(1),
  priority: z.enum(["normal", "urgent"]).default("normal"),
});

/** Issue a research request to James via Leo's shared agent-invocation contract */
export async function POST(request: NextRequest) {
  try {
    const body = InvokeJamesSchema.parse(await request.json());
    const result = await invokeJamesResearch(body.task, body.priority);
    return NextResponse.json({ result });
  } catch (error) {
    const message = error instanceof Error ? error.message : "James invoke failed";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}

export async function GET() {
  return NextResponse.json({
    contract: {
      endpoint: "POST /api/invoke-james",
      routes_via: "Leo /api/invoke",
      request: {
        task: "string — research question for James",
        priority: "normal | urgent",
      },
      response: {
        from_agent: "james",
        to_agent: "conner",
        summary: "string",
        structured_result: "object (optional)",
        memory_ids_written: "string[]",
        follow_up_needed: "boolean",
      },
    },
  });
}
