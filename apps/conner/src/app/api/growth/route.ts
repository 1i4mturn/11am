import { NextRequest, NextResponse } from "next/server";
import { z } from "zod";
import { runGrowthStrategy } from "@/lib/strategy/engine";

const GrowthSchema = z.object({
  focus: z.string().min(1),
});

export async function POST(request: NextRequest) {
  try {
    const body = GrowthSchema.parse(await request.json());
    const result = await runGrowthStrategy(body.focus);
    return NextResponse.json({ result });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Growth strategy failed";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
