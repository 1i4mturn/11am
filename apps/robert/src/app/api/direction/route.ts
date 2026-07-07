import { NextRequest, NextResponse } from "next/server";
import { z } from "zod";
import { runBrandDirection } from "@/lib/design/engine";

const Schema = z.object({ query: z.string().min(1) });

export async function POST(request: NextRequest) {
  try {
    const body = Schema.parse(await request.json());
    const result = await runBrandDirection(body.query);
    return NextResponse.json({ result });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Direction failed";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
