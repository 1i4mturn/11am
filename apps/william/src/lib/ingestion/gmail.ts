import { google } from "googleapis";
import { eq } from "drizzle-orm";
import { db } from "@/lib/db";
import { users } from "@/lib/db/schema";

const GMAIL_SCOPES = ["https://www.googleapis.com/auth/gmail.readonly"];

export function getOAuth2Client() {
  return new google.auth.OAuth2(
    process.env.GOOGLE_CLIENT_ID,
    process.env.GOOGLE_CLIENT_SECRET,
    process.env.GOOGLE_REDIRECT_URI ?? "http://localhost:3000/api/gmail/callback"
  );
}

export function getAuthUrl(): string {
  const oauth2Client = getOAuth2Client();
  return oauth2Client.generateAuthUrl({
    access_type: "offline",
    scope: GMAIL_SCOPES,
    prompt: "consent",
  });
}

export async function saveGmailTokens(
  userId: string,
  tokens: { access_token?: string | null; refresh_token?: string | null; expiry_date?: number | null }
): Promise<void> {
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
    const elapsedMs = Date.now() - new Date(user.updatedAt).getTime();
    const elapsedDays = elapsedMs / (1000 * 60 * 60 * 24);
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
  if (!user?.gmailRefreshToken) {
    throw new Error("Gmail not connected");
  }

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

export async function fetchSentEmails(
  userId = "default",
  maxResults = 50
): Promise<Array<{ subject: string; body: string; date: string }>> {
  const gmail = await getGmailClient(userId);

  const listResponse = await gmail.users.messages.list({
    userId: "me",
    labelIds: ["SENT"],
    maxResults,
  });

  const messages = listResponse.data.messages ?? [];
  const emails: Array<{ subject: string; body: string; date: string }> = [];

  for (const msg of messages.slice(0, maxResults)) {
    if (!msg.id) continue;

    const detail = await gmail.users.messages.get({
      userId: "me",
      id: msg.id,
      format: "full",
    });

    const headers = detail.data.payload?.headers ?? [];
    const subject = headers.find((h) => h.name === "Subject")?.value ?? "";
    const date = headers.find((h) => h.name === "Date")?.value ?? "";

    let body = "";
    const payload = detail.data.payload;

    if (payload?.body?.data) {
      body = Buffer.from(payload.body.data, "base64url").toString("utf-8");
    } else if (payload?.parts) {
      const textPart = payload.parts.find(
        (p) => p.mimeType === "text/plain" || p.mimeType === "text/html"
      );
      if (textPart?.body?.data) {
        body = Buffer.from(textPart.body.data, "base64url").toString("utf-8");
        body = body.replace(/<[^>]+>/g, " ").replace(/\s+/g, " ").trim();
      }
    }

    if (body.trim()) {
      emails.push({ subject, body: body.trim(), date });
    }
  }

  return emails;
}
