import { NextRequest, NextResponse } from "next/server";
import {
  getCalendarAuthStatus,
  listCalendarEvents,
  createCalendarEvent,
  updateCalendarEvent,
  deleteCalendarEvent,
} from "@/lib/google/calendar";
import { z } from "zod";

export async function GET(request: NextRequest) {
  if (!process.env.GOOGLE_CLIENT_ID) {
    return NextResponse.json({
      connected: false,
      needsReauth: false,
      authUrl: null,
      message: "Set GOOGLE_CLIENT_ID and GOOGLE_CLIENT_SECRET in .env.local",
      events: [],
    });
  }

  const status = await getCalendarAuthStatus("default");
  const timeMin = request.nextUrl.searchParams.get("timeMin") ?? undefined;
  const timeMax = request.nextUrl.searchParams.get("timeMax") ?? undefined;

  let events: Awaited<ReturnType<typeof listCalendarEvents>> = [];
  if (status.connected && !status.needsReauth) {
    try {
      events = await listCalendarEvents("default", timeMin, timeMax);
    } catch (error) {
      const message = error instanceof Error ? error.message : "Calendar fetch failed";
      const needsReauth =
        message.toLowerCase().includes("invalid_grant") || message.includes("not connected");
      return NextResponse.json({
        ...status,
        events: [],
        error: message,
        needsReauth,
        authUrl: needsReauth ? status.authUrl ?? (await getCalendarAuthStatus()).authUrl : status.authUrl,
        message: needsReauth
          ? "Google Calendar Testing mode refresh expires every 7 days - reconnect to keep access."
          : undefined,
      });
    }
  }

  return NextResponse.json({
    ...status,
    events,
    message: status.needsReauth
      ? "Google Calendar Testing mode refresh expires every 7 days - reconnect to keep access."
      : undefined,
  });
}

const CreateSchema = z.object({
  summary: z.string().min(1),
  description: z.string().optional(),
  location: z.string().optional(),
  start: z.string(),
  end: z.string(),
});

const UpdateSchema = CreateSchema.partial().extend({
  eventId: z.string(),
});

export async function POST(request: NextRequest) {
  try {
    const body = CreateSchema.parse(await request.json());
    const event = await createCalendarEvent(body);
    return NextResponse.json({ event });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Create failed";
    return NextResponse.json({ error: message }, { status: 400 });
  }
}

export async function PATCH(request: NextRequest) {
  try {
    const body = UpdateSchema.parse(await request.json());
    const { eventId, ...patch } = body;
    const event = await updateCalendarEvent(eventId, patch);
    return NextResponse.json({ event });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Update failed";
    return NextResponse.json({ error: message }, { status: 400 });
  }
}

export async function DELETE(request: NextRequest) {
  const eventId = request.nextUrl.searchParams.get("eventId");
  if (!eventId) {
    return NextResponse.json({ error: "Missing eventId" }, { status: 400 });
  }
  try {
    await deleteCalendarEvent(eventId);
    return NextResponse.json({ success: true });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Delete failed";
    return NextResponse.json({ error: message }, { status: 400 });
  }
}
