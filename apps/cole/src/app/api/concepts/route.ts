import { NextRequest, NextResponse } from "next/server";
import { z } from "zod";
import { generateContentConcepts } from "@/lib/video/engine";

const Schema = z.object({
  topic: z.string().min(1),
  platform: z.enum(["youtube", "reels", "tiktok", "general"]),
});

export async function POST(request: NextRequest) {
  try {
    const body = Schema.parse(await request.json());
    const result = await generateContentConcepts(body.topic, body.platform);
    return NextResponse.json({ result });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Concepts failed";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
