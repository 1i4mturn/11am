import { NextRequest, NextResponse } from "next/server";
import { getLatestAgentSummaries } from "@/lib/bolton";
import { getUser } from "@/lib/tiers";

export async function GET() {
  const userId = "default";
  const user = await getUser(userId);

  if (user.tier !== "pro") {
    return NextResponse.json(
      { error: "Cross-agent context requires Pro tier" },
      { status: 403 }
    );
  }

  const summaries = await getLatestAgentSummaries(userId);

  return NextResponse.json({
    george: summaries.george
      ? {
          summary: summaries.george.summary,
          sessionNote: summaries.george.sessionNote,
          updatedAt: summaries.george.createdAt,
        }
      : null,
    conner: summaries.conner
      ? {
          summary: summaries.conner.summary,
          sessionNote: summaries.conner.sessionNote,
          updatedAt: summaries.conner.createdAt,
        }
      : null,
  });
}

export async function POST(request: NextRequest) {
  const userId = "default";
  const body = await request.json();
  const { saveAgentSummary } = await import("@/lib/bolton");

  const agentId = body.agentId as "george" | "conner";
  if (!["george", "conner"].includes(agentId)) {
    return NextResponse.json({ error: "Invalid agent" }, { status: 400 });
  }

  await saveAgentSummary(agentId, body.summary, body.sessionNote, userId);
  return NextResponse.json({ success: true });
}
