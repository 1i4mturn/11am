import { google } from "googleapis";
import { eq } from "drizzle-orm";
import { db } from "@/lib/db";
import { users } from "@/lib/db/schema";
import type { CalendarEvent } from "@/lib/types";

export const CALENDAR_SCOPES = [
  "https://www.googleapis.com/auth/calendar.readonly",
  "https://www.googleapis.com/auth/calendar.events",
];

const TESTING_REFRESH_DAYS = 7;

export function getOAuth2Client() {
  return new google.auth.OAuth2(
    process.env.GOOGLE_CLIENT_ID,
    process.env.GOOGLE_CLIENT_SECRET,
    process.env.GOOGLE_REDIRECT_URI ?? "http://localhost:3006/api/calendar/callback"
  );
}

export function getAuthUrl(): string {
  return getOAuth2Client().generateAuthUrl({
    access_type: "offline",
    scope: CALENDAR_SCOPES,
    prompt: "consent",
  });
}

export async function saveCalendarTokens(
  userId: string,
  tokens: {
    access_token?: string | null;
    refresh_token?: string | null;
    expiry_date?: number | null;
  }
) {
  await db
    .update(users)
    .set({
      calendarAccessToken: tokens.access_token ?? null,
      calendarTokenExpiry: tokens.expiry_date ? new Date(tokens.expiry_date) : null,
      calendarConnectedAt: new Date(),
      updatedAt: new Date(),
      ...(tokens.refresh_token ? { calendarRefreshToken: tokens.refresh_token } : {}),
    })
    .where(eq(users.id, userId));
}

export async function getCalendarAuthStatus(userId = "default") {
  const [user] = await db.select().from(users).where(eq(users.id, userId)).limit(1);
  const connected = !!user?.calendarRefreshToken;

  let needsReauth = false;
  let daysUntilExpiry: number | null = null;
  const anchor = user?.calendarConnectedAt ?? user?.updatedAt;

  if (connected && anchor) {
    const elapsedDays = (Date.now() - new Date(anchor).getTime()) / (1000 * 60 * 60 * 24);
    daysUntilExpiry = Math.max(0, Math.ceil(TESTING_REFRESH_DAYS - elapsedDays));
    needsReauth = elapsedDays >= TESTING_REFRESH_DAYS - 1;
  }

  return {
    connected,
    needsReauth,
    daysUntilExpiry,
    authUrl: !connected || needsReauth ? getAuthUrl() : null,
  };
}

export async function getCalendarClient(userId = "default") {
  const [user] = await db.select().from(users).where(eq(users.id, userId)).limit(1);
  if (!user?.calendarRefreshToken) throw new Error("Calendar not connected");

  const oauth2Client = getOAuth2Client();
  oauth2Client.setCredentials({
    access_token: user.calendarAccessToken,
    refresh_token: user.calendarRefreshToken,
    expiry_date: user.calendarTokenExpiry?.getTime(),
  });

  oauth2Client.on("tokens", async (tokens) => {
    await saveCalendarTokens(userId, tokens);
  });

  return google.calendar({ version: "v3", auth: oauth2Client });
}

function mapEvent(
  item: {
    id?: string | null;
    summary?: string | null;
    description?: string | null;
    location?: string | null;
    htmlLink?: string | null;
    start?: { dateTime?: string | null; date?: string | null };
    end?: { dateTime?: string | null; date?: string | null };
    attendees?: Array<{ email?: string | null }> | null;
  } | null
): CalendarEvent | null {
  if (!item?.id) return null;
  const start = item.start?.dateTime ?? item.start?.date;
  const end = item.end?.dateTime ?? item.end?.date;
  if (!start || !end) return null;

  return {
    id: item.id,
    summary: item.summary ?? "(No title)",
    description: item.description ?? undefined,
    location: item.location ?? undefined,
    start,
    end,
    htmlLink: item.htmlLink ?? undefined,
    attendees: item.attendees?.map((a) => a.email ?? "").filter(Boolean),
  };
}

export async function listCalendarEvents(
  userId = "default",
  timeMin?: string,
  timeMax?: string
): Promise<CalendarEvent[]> {
  const calendar = await getCalendarClient(userId);
  const now = new Date();
  const min = timeMin ?? now.toISOString();
  const max =
    timeMax ?? new Date(now.getTime() + 14 * 24 * 60 * 60 * 1000).toISOString();

  const res = await calendar.events.list({
    calendarId: "primary",
    timeMin: min,
    timeMax: max,
    singleEvents: true,
    orderBy: "startTime",
    maxResults: 50,
  });

  return (res.data.items ?? [])
    .map(mapEvent)
    .filter((e): e is CalendarEvent => e !== null);
}

export async function getCalendarEvent(
  eventId: string,
  userId = "default"
): Promise<CalendarEvent | null> {
  const calendar = await getCalendarClient(userId);
  const res = await calendar.events.get({ calendarId: "primary", eventId });
  return mapEvent(res.data);
}

export async function createCalendarEvent(
  input: {
    summary: string;
    description?: string;
    location?: string;
    start: string;
    end: string;
  },
  userId = "default"
): Promise<CalendarEvent> {
  const calendar = await getCalendarClient(userId);
  const isAllDay = !input.start.includes("T");

  const res = await calendar.events.insert({
    calendarId: "primary",
    requestBody: {
      summary: input.summary,
      description: input.description,
      location: input.location,
      start: isAllDay ? { date: input.start.slice(0, 10) } : { dateTime: input.start },
      end: isAllDay ? { date: input.end.slice(0, 10) } : { dateTime: input.end },
    },
  });

  const event = mapEvent(res.data);
  if (!event) throw new Error("Failed to create event");
  return event;
}

export async function updateCalendarEvent(
  eventId: string,
  input: Partial<{
    summary: string;
    description: string;
    location: string;
    start: string;
    end: string;
  }>,
  userId = "default"
): Promise<CalendarEvent> {
  const calendar = await getCalendarClient(userId);
  const existing = await calendar.events.get({ calendarId: "primary", eventId });

  const start = input.start ?? existing.data.start?.dateTime ?? existing.data.start?.date;
  const end = input.end ?? existing.data.end?.dateTime ?? existing.data.end?.date;
  const isAllDay = start && !start.includes("T");

  const res = await calendar.events.patch({
    calendarId: "primary",
    eventId,
    requestBody: {
      summary: input.summary ?? existing.data.summary ?? undefined,
      description: input.description ?? existing.data.description ?? undefined,
      location: input.location ?? existing.data.location ?? undefined,
      ...(start && end
        ? {
            start: isAllDay ? { date: start.slice(0, 10) } : { dateTime: start },
            end: isAllDay ? { date: end.slice(0, 10) } : { dateTime: end },
          }
        : {}),
    },
  });

  const event = mapEvent(res.data);
  if (!event) throw new Error("Failed to update event");
  return event;
}

export async function deleteCalendarEvent(eventId: string, userId = "default") {
  const calendar = await getCalendarClient(userId);
  await calendar.events.delete({ calendarId: "primary", eventId });
}

export function todayRange(): { timeMin: string; timeMax: string } {
  const start = new Date();
  start.setHours(0, 0, 0, 0);
  const end = new Date(start);
  end.setDate(end.getDate() + 1);
  return { timeMin: start.toISOString(), timeMax: end.toISOString() };
}
