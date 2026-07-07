import { NextRequest, NextResponse } from "next/server";
import { z } from "zod";
import { runGtmPlanning } from "@/lib/strategy/engine";

const GtmSchema = z.object({
  brief: z.string().min(1),
});

export async function POST(request: NextRequest) {
  try {
    const body = GtmSchema.parse(await request.json());
    const result = await runGtmPlanning(body.brief);
    return NextResponse.json({ result });
  } catch (error) {
    const message = error instanceof Error ? error.message : "GTM planning failed";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
