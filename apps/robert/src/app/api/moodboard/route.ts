import { NextRequest, NextResponse } from "next/server";
import { z } from "zod";
import { runMoodboard } from "@/lib/design/engine";

const Schema = z.object({
  prompt: z.string().min(1),
  session_id: z.string().min(1),
  count: z.number().int().min(1).max(4).default(2),
});

export async function POST(request: NextRequest) {
  try {
    const body = Schema.parse(await request.json());
    const result = await runMoodboard(body.prompt, body.session_id, body.count);
    return NextResponse.json({ result });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Moodboard failed";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
