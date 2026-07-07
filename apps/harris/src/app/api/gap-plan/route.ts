import { NextResponse } from "next/server";
import { generateGapPlan } from "@/lib/learning/engine";

export async function POST() {
  try {
    const result = await generateGapPlan();
    return NextResponse.json({ result });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Gap plan failed";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
