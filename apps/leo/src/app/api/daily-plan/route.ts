import { NextResponse } from "next/server";
import { generateDailyPlan } from "@/lib/plan/daily";

export async function POST() {
  try {
    const result = await generateDailyPlan();
    return NextResponse.json(result);
  } catch (error) {
    const message = error instanceof Error ? error.message : "Daily plan failed";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}

export async function GET() {
  return NextResponse.json({
    endpoint: "POST /api/daily-plan",
    description: "Synthesize today's plan from calendar + Bolton tasks",
  });
}
