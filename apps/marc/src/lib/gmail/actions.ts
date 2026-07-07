import { db } from "@/lib/db";
import { actionLog } from "@/lib/db/schema";
import { getGmailClient } from "./client";

/** All Gmail mutations require explicit user confirmation */
export async function archiveMessages(
  messageIds: string[],
  userId = "default",
  confirmed = false
) {
  if (!confirmed) throw new Error("User confirmation required");

  const gmail = await getGmailClient(userId);
  for (const id of messageIds) {
    await gmail.users.messages.modify({
      userId: "me",
      id,
      requestBody: { removeLabelIds: ["INBOX"] },
    });
  }

  await db.insert(actionLog).values({
    userId,
    actionType: "archive",
    targetIds: messageIds,
    payload: { count: messageIds.length },
  });
}

export async function applyLabel(
  messageIds: string[],
  labelName: string,
  userId = "default",
  confirmed = false
) {
  if (!confirmed) throw new Error("User confirmation required");

  const gmail = await getGmailClient(userId);
  const labels = await gmail.users.labels.list({ userId: "me" });
  let labelId = labels.data.labels?.find((l) => l.name === labelName)?.id;

  if (!labelId) {
    const created = await gmail.users.labels.create({
      userId: "me",
      requestBody: { name: labelName, labelListVisibility: "labelShow", messageListVisibility: "show" },
    });
    labelId = created.data.id!;
  }

  for (const id of messageIds) {
    await gmail.users.messages.modify({
      userId: "me",
      id,
      requestBody: { addLabelIds: [labelId] },
    });
  }

  await db.insert(actionLog).values({
    userId,
    actionType: "apply_label",
    targetIds: messageIds,
    payload: { labelName, labelId },
  });

  return labelId;
}

export async function createDraftReply(
  threadId: string,
  to: string,
  subject: string,
  body: string,
  userId = "default",
  confirmed = false
) {
  if (!confirmed) throw new Error("User confirmation required");

  const gmail = await getGmailClient(userId);
  const encoded = Buffer.from(
    `To: ${to}\r\nSubject: ${subject.startsWith("Re:") ? subject : `Re: ${subject}`}\r\nContent-Type: text/plain; charset=utf-8\r\n\r\n${body}`
  )
    .toString("base64")
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/, "");

  const draft = await gmail.users.drafts.create({
    userId: "me",
    requestBody: {
      message: { raw: encoded, threadId },
    },
  });

  await db.insert(actionLog).values({
    userId,
    actionType: "create_draft",
    targetIds: [threadId],
    payload: { draftId: draft.data.id, to, subject },
  });

  return draft.data;
}

export async function sendReply(
  threadId: string,
  to: string,
  subject: string,
  body: string,
  userId = "default",
  confirmed = false
) {
  if (!confirmed) throw new Error("User confirmation required");

  const gmail = await getGmailClient(userId);
  const encoded = Buffer.from(
    `To: ${to}\r\nSubject: ${subject.startsWith("Re:") ? subject : `Re: ${subject}`}\r\nContent-Type: text/plain; charset=utf-8\r\n\r\n${body}`
  )
    .toString("base64")
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/, "");

  const sent = await gmail.users.messages.send({
    userId: "me",
    requestBody: { raw: encoded, threadId },
  });

  await db.insert(actionLog).values({
    userId,
    actionType: "send_reply",
    targetIds: [threadId],
    payload: { messageId: sent.data.id, to, subject },
  });

  return sent.data;
}

export async function markRead(
  messageIds: string[],
  userId = "default",
  confirmed = false
) {
  if (!confirmed) throw new Error("User confirmation required");

  const gmail = await getGmailClient(userId);
  for (const id of messageIds) {
    await gmail.users.messages.modify({
      userId: "me",
      id,
      requestBody: { removeLabelIds: ["UNREAD"] },
    });
  }

  await db.insert(actionLog).values({
    userId,
    actionType: "mark_read",
    targetIds: messageIds,
  });
}
