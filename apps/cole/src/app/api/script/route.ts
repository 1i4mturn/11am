import { NextRequest, NextResponse } from "next/server";
import { z } from "zod";
import { generateScriptPackage } from "@/lib/video/engine";

const Schema = z.object({
  brief: z.string().min(1),
  platform: z.enum(["youtube", "reels", "tiktok", "general"]).default("general"),
});

export async function POST(request: NextRequest) {
  try {
    const body = Schema.parse(await request.json());
    const result = await generateScriptPackage(body.brief, body.platform);
    return NextResponse.json({ result });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Script failed";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
