import { NextRequest, NextResponse } from "next/server";
import { z } from "zod";
import { runLogoConcepts } from "@/lib/design/engine";

const Schema = z.object({
  direction: z.string().min(1),
  session_id: z.string().min(1),
});

export async function POST(request: NextRequest) {
  try {
    const body = Schema.parse(await request.json());
    const result = await runLogoConcepts(body.direction, body.session_id);
    return NextResponse.json({ result });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Logo concepts failed";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
