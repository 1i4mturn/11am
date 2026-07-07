import { NextResponse } from "next/server";
import { getAgentSummaryViaContext } from "@/lib/bolton/client";

const REPORT_AGENTS = ["george", "james", "conner"] as const;

export async function GET() {
  const reports = await Promise.all(
    REPORT_AGENTS.map(async (agentId) => {
      const pack = await getAgentSummaryViaContext(agentId);
      return {
        agent_id: agentId,
        context_pack: pack,
        available: !!pack,
      };
    })
  );

  return NextResponse.json({ reports, source: "bolton_context_pack" });
}
