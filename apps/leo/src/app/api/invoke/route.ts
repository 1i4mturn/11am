import { NextRequest, NextResponse } from "next/server";
import { z } from "zod";
import { invokeAgent } from "@/lib/agents/invoke";

const InvokeSchema = z.object({
  from_agent: z.string(),
  to_agent: z.string(),
  task: z.string().min(1),
  context_ref: z.string().optional(),
  priority: z.enum(["normal", "urgent"]).default("normal"),
  response_mode: z.enum(["sync", "async"]).default("sync"),
});

export async function POST(request: NextRequest) {
  try {
    const body = InvokeSchema.parse(await request.json());

    if (body.response_mode === "async") {
      return NextResponse.json(
        { error: "v1 supports synchronous routing only" },
        { status: 400 }
      );
    }

    const response = await invokeAgent(body);
    return NextResponse.json(response);
  } catch (error) {
    const message = error instanceof Error ? error.message : "Invoke failed";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}

export async function GET() {
  return NextResponse.json({
    contract: {
      request: {
        from_agent: "string",
        to_agent: "string",
        task: "string",
        context_ref: "string (optional)",
        priority: "normal | urgent",
        response_mode: "sync | async (v1: sync only)",
      },
      response: {
        from_agent: "string",
        to_agent: "string",
        summary: "string",
        structured_result: "object (optional)",
        memory_ids_written: "string[]",
        follow_up_needed: "boolean",
      },
    },
  });
}
