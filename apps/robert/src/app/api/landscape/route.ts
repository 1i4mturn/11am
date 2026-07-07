import { NextRequest, NextResponse } from "next/server";
import { z } from "zod";
import { runCompetitorLandscape } from "@/lib/design/engine";

const Schema = z.object({
  focus: z.string().optional(),
});

export async function POST(request: NextRequest) {
  try {
    const body = Schema.parse(await request.json().catch(() => ({})));
    const result = await runCompetitorLandscape(body.focus);
    return NextResponse.json({ result });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Landscape analysis failed";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
