import { NextRequest, NextResponse } from "next/server";
import { z } from "zod";
import { runColorTypographyRecommendation } from "@/lib/design/engine";

const Schema = z.object({ brief: z.string().min(1) });

export async function POST(request: NextRequest) {
  try {
    const body = Schema.parse(await request.json());
    const tokens = await runColorTypographyRecommendation(body.brief);
    return NextResponse.json({ tokens });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Token recommendation failed";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
