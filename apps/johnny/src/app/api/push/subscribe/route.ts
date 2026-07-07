import { NextRequest, NextResponse } from "next/server";
import { z } from "zod";
import { registerPushSubscription } from "@11am/jobs";

const SubscribeSchema = z.object({
  job_id: z.string().optional(),
  endpoint: z.string().url(),
});

export async function POST(request: NextRequest) {
  try {
    const body = SubscribeSchema.parse(await request.json());
    const id = registerPushSubscription({
      id: crypto.randomUUID(),
      job_id: body.job_id,
      endpoint: body.endpoint,
    });
    return NextResponse.json({ subscription_id: id });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Subscribe failed";
    return NextResponse.json({ error: message }, { status: 400 });
  }
}
