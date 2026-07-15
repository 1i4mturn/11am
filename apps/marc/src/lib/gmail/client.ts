import { google } from "googleapis";
import { eq } from "drizzle-orm";
import { db } from "@/lib/db";
import { users } from "@/lib/db/schema";

export const GMAIL_SCOPES = [
  "https://www.googleapis.com/auth/gmail.readonly",
  "https://www.googleapis.com/auth/gmail.modify",
  "https://www.googleapis.com/auth/gmail.labels",
];

export function getOAuth2Client() {
  return new google.auth.OAuth2(
    process.env.GOOGLE_CLIENT_ID,
    process.env.GOOGLE_CLIENT_SECRET,
    process.env.GOOGLE_REDIRECT_URI ?? "http://localhost:3001/api/gmail/callback"
  );
}

export function getAuthUrl(): string {
  return getOAuth2Client().generateAuthUrl({
    access_type: "offline",
    scope: GMAIL_SCOPES,
    prompt: "consent",
  });
}

export async function saveGmailTokens(
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
      gmailAccessToken: tokens.access_token ?? null,
      gmailTokenExpiry: tokens.expiry_date ? new Date(tokens.expiry_date) : null,
      updatedAt: new Date(),
      ...(tokens.refresh_token ? { gmailRefreshToken: tokens.refresh_token } : {}),
    })
    .where(eq(users.id, userId));
}

/** Gmail OAuth Testing mode - refresh tokens expire after ~7 days */
const GMAIL_TESTING_REFRESH_DAYS = 7;

export async function getGmailAuthStatus(userId = "default") {
  const [user] = await db.select().from(users).where(eq(users.id, userId)).limit(1);
  const connected = !!user?.gmailRefreshToken;

  let needsReauth = false;
  let daysUntilExpiry: number | null = null;

  if (connected && user?.updatedAt) {
    const elapsedDays =
      (Date.now() - new Date(user.updatedAt).getTime()) / (1000 * 60 * 60 * 24);
    daysUntilExpiry = Math.max(0, Math.ceil(GMAIL_TESTING_REFRESH_DAYS - elapsedDays));
    needsReauth = elapsedDays >= GMAIL_TESTING_REFRESH_DAYS - 1;
  }

  return {
    connected,
    needsReauth,
    daysUntilExpiry,
    authUrl: !connected || needsReauth ? getAuthUrl() : null,
  };
}

export async function getGmailClient(userId = "default") {
  const [user] = await db.select().from(users).where(eq(users.id, userId)).limit(1);
  if (!user?.gmailRefreshToken) throw new Error("Gmail not connected");

  const oauth2Client = getOAuth2Client();
  oauth2Client.setCredentials({
    access_token: user.gmailAccessToken,
    refresh_token: user.gmailRefreshToken,
    expiry_date: user.gmailTokenExpiry?.getTime(),
  });

  oauth2Client.on("tokens", async (tokens) => {
    await saveGmailTokens(userId, tokens);
  });

  return google.gmail({ version: "v1", auth: oauth2Client });
}

export function parseEmailAddress(raw: string): { name: string; email: string } {
  const match = raw.match(/^(?:"?([^"]*)"?\s)?<?([^>]+@[^>]+)>?$/);
  if (match) {
    return { name: (match[1] ?? "").trim(), email: match[2].trim().toLowerCase() };
  }
  return { name: "", email: raw.trim().toLowerCase() };
}

export function extractBody(payload: {
  body?: { data?: string | null };
  parts?: Array<{
    mimeType?: string | null;
    body?: { data?: string | null };
    parts?: Array<{ mimeType?: string | null; body?: { data?: string | null } }>;
  }>;
}): string {
  if (payload.body?.data) {
    return Buffer.from(payload.body.data, "base64url").toString("utf-8");
  }

  const parts = payload.parts ?? [];
  for (const part of parts) {
    if (part.mimeType === "text/plain" && part.body?.data) {
      return Buffer.from(part.body.data, "base64url").toString("utf-8");
    }
  }
  for (const part of parts) {
    if (part.mimeType === "text/html" && part.body?.data) {
      const html = Buffer.from(part.body.data, "base64url").toString("utf-8");
      return html.replace(/<[^>]+>/g, " ").replace(/\s+/g, " ").trim();
    }
    if (part.parts) {
      const nested = extractBody({ parts: part.parts });
      if (nested) return nested;
    }
  }
  return "";
}

export function extractListUnsubscribe(headers: Array<{ name?: string | null; value?: string | null }>) {
  const header = headers.find((h) => h.name?.toLowerCase() === "list-unsubscribe");
  return header?.value ?? null;
}
