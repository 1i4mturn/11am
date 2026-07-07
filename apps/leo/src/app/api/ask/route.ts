import { NextRequest, NextResponse } from "next/server";
import { z } from "zod";
import { askLeo } from "@/lib/agents/ask";

const AskSchema = z.object({
  query: z.string().min(1),
});

export async function POST(request: NextRequest) {
  try {
    const body = AskSchema.parse(await request.json());
    const result = await askLeo(body.query);
    return NextResponse.json(result);
  } catch (error) {
    const message = error instanceof Error ? error.message : "Ask failed";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
