import { NextRequest, NextResponse } from "next/server";
import { z } from "zod";
import {
  createHandoff,
  buildLeoHandoff,
  buildConnerHandoff,
  buildGeorgeHandoff,
  buildJamesHandoff,
  buildInboxReviewArtifact,
  type HandoffAgent,
} from "@/lib/handoffs";
import { getUser } from "@/lib/tiers";
import { isPro } from "@/lib/config";

const HandoffSchema = z.object({
  targetAgent: z.enum(["william", "leo", "conner", "george", "james", "bolton"]),
  sourceMessageId: z.string().optional(),
  item: z.record(z.string(), z.unknown()),
});

export async function POST(request: NextRequest) {
  const user = await getUser();
  if (!isPro(user.tier)) {
    return NextResponse.json({ error: "Cross-agent handoffs require Pro tier" }, { status: 403 });
  }

  const body = HandoffSchema.parse(await request.json());
  const artifact = buildArtifact(body.targetAgent, body.item);

  const handoff = await createHandoff(
    body.targetAgent as HandoffAgent,
    artifact,
    body.sourceMessageId
  );

  return NextResponse.json({ handoff });
}

function buildArtifact(agent: string, item: Record<string, unknown>) {
  switch (agent) {
    case "leo":
      return buildLeoHandoff(item as Parameters<typeof buildLeoHandoff>[0]);
    case "conner":
      return buildConnerHandoff(item as Parameters<typeof buildConnerHandoff>[0]);
    case "george":
      return buildGeorgeHandoff(item as Parameters<typeof buildGeorgeHandoff>[0]);
    case "james":
      return buildJamesHandoff(item as Parameters<typeof buildJamesHandoff>[0]);
    case "bolton":
      return {
        memory_type: item.memory_type ?? "decision",
        source_thread: item.thread_id ?? item.source_thread,
        summary: item.summary ?? item.why_it_matters,
        confidence: item.confidence ?? "medium",
      };
    default:
      return buildInboxReviewArtifact(item);
  }
}

export async function GET() {
  const { listHandoffs } = await import("@/lib/handoffs");
  const handoffs = await listHandoffs();
  return NextResponse.json({ handoffs });
}
