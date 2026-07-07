import { NextRequest, NextResponse } from "next/server";
import { z } from "zod";
import { runStressTest } from "@/lib/strategy/engine";

const StressTestSchema = z.object({
  idea_or_model: z.string().min(1),
});

export async function POST(request: NextRequest) {
  try {
    const body = StressTestSchema.parse(await request.json());
    const result = await runStressTest(body.idea_or_model);
    return NextResponse.json({ result });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Stress test failed";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
