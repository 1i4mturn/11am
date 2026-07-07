import { NextResponse } from "next/server";
import { getLearningHub } from "@/lib/hub/store";

export async function GET() {
  try {
    const hub = await getLearningHub();
    return NextResponse.json({ hub });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Hub load failed";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
