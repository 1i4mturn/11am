import { NextRequest, NextResponse } from "next/server";
import { z } from "zod";
import { generateMeetingPrep } from "@/lib/plan/meeting";

const PrepSchema = z.object({
  eventId: z.string().min(1),
});

export async function POST(request: NextRequest) {
  try {
    const body = PrepSchema.parse(await request.json());
    const result = await generateMeetingPrep(body.eventId);
    return NextResponse.json(result);
  } catch (error) {
    const message = error instanceof Error ? error.message : "Meeting prep failed";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}

export async function GET(request: NextRequest) {
  const eventId = request.nextUrl.searchParams.get("eventId");
  if (!eventId) {
    return NextResponse.json({
      endpoint: "POST /api/meeting-prep",
      body: { eventId: "google-calendar-event-id" },
    });
  }

  try {
    const result = await generateMeetingPrep(eventId);
    return NextResponse.json(result);
  } catch (error) {
    const message = error instanceof Error ? error.message : "Meeting prep failed";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
