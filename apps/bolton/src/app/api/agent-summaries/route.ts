import { NextRequest, NextResponse } from "next/server";
import { z } from "zod";
import { getLatestAgentSummary, writeAgentSummary } from "@/lib/summaries";
import { resolveUserId } from "@/lib/config";

export async function GET(request: NextRequest) {
  const userId = resolveUserId(request.headers.get("x-user-id"));
  const agentId = request.nextUrl.searchParams.get("agent_id");
  if (!agentId) {
    return NextResponse.json({ error: "Missing agent_id" }, { status: 400 });
  }
  const row = await getLatestAgentSummary(agentId, userId);
  if (!row) return NextResponse.json({ error: "Not found" }, { status: 404 });
  return NextResponse.json({ summary: row });
}

const WriteSchema = z.object({
  agent_id: z.string(),
  summary: z.record(z.string(), z.unknown()),
  session_note: z.string().optional(),
  memory_entry_id: z.string().uuid().optional(),
});

export async function POST(request: NextRequest) {
  const userId = resolveUserId(request.headers.get("x-user-id"));
  const body = WriteSchema.parse(await request.json());
  const row = await writeAgentSummary(
    body.agent_id,
    body.summary,
    userId,
    body.session_note,
    body.memory_entry_id
  );
  return NextResponse.json({ success: true, id: row.id });
}
