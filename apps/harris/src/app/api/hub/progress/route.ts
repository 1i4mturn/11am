import { NextRequest, NextResponse } from "next/server";
import { z } from "zod";
import { updatePlanProgress } from "@/lib/hub/store";

const Schema = z.object({
  plan_id: z.string(),
  percent_self_reported: z.number().min(0).max(100).optional(),
  status: z.enum(["active", "paused", "completed"]).optional(),
  last_session_note: z.string().optional(),
  sessions_completed: z.number().int().min(0).optional(),
  milestones_completed: z.array(z.string()).optional(),
});

export async function PATCH(request: NextRequest) {
  try {
    const body = Schema.parse(await request.json());
    const { plan_id, ...patch } = body;
    const hub = await updatePlanProgress(plan_id, patch);
    return NextResponse.json({ hub });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Progress update failed";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
