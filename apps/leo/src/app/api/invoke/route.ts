import { NextRequest, NextResponse } from "next/server";
import { z } from "zod";
import { invokeAgent, invokeAgentsParallel } from "@/lib/agents/invoke";

const InvokeSchema = z.object({
  from_agent: z.string(),
  to_agent: z.string().optional(),
  to_agents: z.array(z.string()).min(1).max(5).optional(),
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
        { error: "async routing not supported — use sync (single or parallel)" },
        { status: 400 }
      );
    }

    // Parallel fan-out: brief several agents at once with the same task.
    if (body.to_agents?.length) {
      const responses = await invokeAgentsParallel(
        {
          from_agent: body.from_agent,
          task: body.task,
          context_ref: body.context_ref,
          priority: body.priority,
          response_mode: "sync",
        },
        body.to_agents
      );
      return NextResponse.json({ parallel: true, responses });
    }

    if (!body.to_agent) {
      return NextResponse.json(
        { error: "Provide to_agent (single) or to_agents (parallel fan-out)" },
        { status: 400 }
      );
    }

    const response = await invokeAgent({
      from_agent: body.from_agent,
      to_agent: body.to_agent,
      task: body.task,
      context_ref: body.context_ref,
      priority: body.priority,
      response_mode: "sync",
    });
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
        to_agent: "string (single invocation)",
        to_agents: "string[] (parallel fan-out, max 5, optional)",
        task: "string",
        context_ref: "string (optional)",
        priority: "normal | urgent",
        response_mode: "sync (async not supported)",
      },
      response: {
        from_agent: "string",
        to_agent: "string",
        summary: "string",
        structured_result: "object (optional)",
        memory_ids_written: "string[]",
        follow_up_needed: "boolean",
      },
      parallel_response: {
        parallel: true,
        responses: "AgentInvokeResponse[] (order matches to_agents)",
      },
    },
  });
}
