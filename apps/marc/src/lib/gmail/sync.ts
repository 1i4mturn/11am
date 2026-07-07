import { eq, sql } from "drizzle-orm";
import { db } from "@/lib/db";
import { emailMessages, users } from "@/lib/db/schema";
import {
  getGmailClient,
  extractBody,
  parseEmailAddress,
  extractListUnsubscribe,
} from "./client";
import { embedText } from "@/lib/search/embeddings";
import { getUser } from "@/lib/tiers";
import { isPro } from "@/lib/config";

export interface SyncResult {
  synced: number;
  newMessages: number;
}

export async function syncInbox(userId = "default", maxResults = 100): Promise<SyncResult> {
  const gmail = await getGmailClient(userId);
  const user = await getUser(userId);
  const pro = isPro(user.tier);
  const indexFullContent = user.fullContentIndexing || pro;

  const listResponse = await gmail.users.messages.list({
    userId: "me",
    maxResults,
    q: "in:inbox OR in:sent",
  });

  const messages = listResponse.data.messages ?? [];
  let newMessages = 0;

  for (const msg of messages) {
    if (!msg.id) continue;

    const existing = await db
      .select({ id: emailMessages.id })
      .from(emailMessages)
      .where(
        sql`${emailMessages.userId} = ${userId} AND ${emailMessages.messageId} = ${msg.id}`
      )
      .limit(1);

    if (existing.length) continue;

    const detail = await gmail.users.messages.get({
      userId: "me",
      id: msg.id,
      format: "full",
    });

    const headers = detail.data.payload?.headers ?? [];
    const from = headers.find((h) => h.name === "From")?.value ?? "";
    const to = headers.find((h) => h.name === "To")?.value ?? "";
    const subject = headers.find((h) => h.name === "Subject")?.value ?? "";
    const dateStr = headers.find((h) => h.name === "Date")?.value ?? "";
    const { name, email } = parseEmailAddress(from);
    const body = extractBody(detail.data.payload ?? {});
    const listUnsub = extractListUnsubscribe(headers);
    const labels = detail.data.labelIds ?? [];
    const snippet = detail.data.snippet ?? "";
    const isUnread = labels.includes("UNREAD");

    let embedding: number[] | null = null;
    if (indexFullContent && body) {
      const embedContent = `Subject: ${subject}\nFrom: ${from}\n${body.slice(0, 4000)}`;
      embedding = await embedText(embedContent);
    }

    const embeddingStr = embedding ? `[${embedding.join(",")}]` : null;

    if (embeddingStr) {
      await db.execute(sql`
        INSERT INTO email_messages (
          user_id, message_id, thread_id, sender_email, sender_name,
          recipients, subject, snippet, body, labels, received_at,
          is_unread, has_unsubscribe, list_unsubscribe, embedding
        ) VALUES (
          ${userId}, ${msg.id}, ${detail.data.threadId ?? msg.id},
          ${email}, ${name || null}, ${JSON.stringify(to.split(",").map((s) => s.trim()))}::jsonb,
          ${subject}, ${snippet}, ${body.slice(0, 50000)}, ${JSON.stringify(labels)}::jsonb,
          ${dateStr ? new Date(dateStr).toISOString() : new Date().toISOString()}::timestamp,
          ${isUnread}, ${!!listUnsub}, ${listUnsub}, ${embeddingStr}::vector
        )
        ON CONFLICT (user_id, message_id) DO NOTHING
      `);
    } else {
      await db.execute(sql`
        INSERT INTO email_messages (
          user_id, message_id, thread_id, sender_email, sender_name,
          recipients, subject, snippet, body, labels, received_at,
          is_unread, has_unsubscribe, list_unsubscribe
        ) VALUES (
          ${userId}, ${msg.id}, ${detail.data.threadId ?? msg.id},
          ${email}, ${name || null}, ${JSON.stringify(to.split(",").map((s) => s.trim()))}::jsonb,
          ${subject}, ${snippet}, ${body.slice(0, 50000)}, ${JSON.stringify(labels)}::jsonb,
          ${dateStr ? new Date(dateStr).toISOString() : new Date().toISOString()}::timestamp,
          ${isUnread}, ${!!listUnsub}, ${listUnsub}
        )
        ON CONFLICT (user_id, message_id) DO NOTHING
      `);
    }

    newMessages++;
  }

  await db
    .update(users)
    .set({ lastSyncAt: new Date(), updatedAt: new Date() })
    .where(eq(users.id, userId));

  return { synced: messages.length, newMessages };
}

export async function getIndexedMessageCount(userId = "default") {
  const [row] = await db
    .select({ count: sql<number>`count(*)::int` })
    .from(emailMessages)
    .where(eq(emailMessages.userId, userId));
  return row?.count ?? 0;
}

export async function getRecentMessages(userId = "default", limit = 50) {
  return db
    .select()
    .from(emailMessages)
    .where(eq(emailMessages.userId, userId))
    .orderBy(sql`${emailMessages.receivedAt} DESC`)
    .limit(limit);
}

export async function getMessageById(messageId: string, userId = "default") {
  const [msg] = await db
    .select()
    .from(emailMessages)
    .where(
      sql`${emailMessages.userId} = ${userId} AND ${emailMessages.messageId} = ${messageId}`
    )
    .limit(1);
  return msg ?? null;
}

export async function getThreadMessages(threadId: string, userId = "default") {
  return db
    .select()
    .from(emailMessages)
    .where(
      sql`${emailMessages.userId} = ${userId} AND ${emailMessages.threadId} = ${threadId}`
    )
    .orderBy(emailMessages.receivedAt);
}
