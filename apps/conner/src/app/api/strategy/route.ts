import { NextRequest, NextResponse } from "next/server";
import { z } from "zod";
import { getLatestAgentSummary } from "@/lib/bolton/client";
import { writeLatestStrategy } from "@/lib/strategy/engine";

const WriteStrategySchema = z.object({
  session_summary: z.string().min(1),
});

export async function POST(request: NextRequest) {
  try {
    const body = WriteStrategySchema.parse(await request.json());
    const { summary, memory_ids_written } = await writeLatestStrategy(body.session_summary);
    return NextResponse.json({ summary, memory_ids_written });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Strategy write failed";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}

export async function GET() {
  try {
    const raw = await getLatestAgentSummary("conner");
    if (!raw) {
      return NextResponse.json({ error: "No strategy summary found" }, { status: 404 });
    }
    return NextResponse.json({ summary: raw });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Fetch failed";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
