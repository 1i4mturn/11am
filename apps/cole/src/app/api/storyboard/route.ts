import { NextRequest, NextResponse } from "next/server";
import { z } from "zod";
import { generateStoryboard } from "@/lib/video/engine";

const Schema = z.object({ title: z.string().min(1) });

export async function POST(request: NextRequest) {
  try {
    const body = Schema.parse(await request.json());
    const result = await generateStoryboard(body.title);
    return NextResponse.json({ result });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Storyboard failed";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
