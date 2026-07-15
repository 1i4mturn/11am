import { db } from "@/lib/db";
import { actionLog } from "@/lib/db/schema";

const BATCH_SIZE = 20;
const BATCH_DELAY_MS = 500;

function parseUnsubscribeUrl(listUnsubscribe: string): string | null {
  const httpsMatch = listUnsubscribe.match(/<(https?:[^>]+)>/i);
  if (httpsMatch) return httpsMatch[1];

  const bareUrl = listUnsubscribe.match(/https?:\/\/[^\s>,]+/i);
  return bareUrl?.[0] ?? null;
}

async function sleep(ms: number) {
  await new Promise((resolve) => setTimeout(resolve, ms));
}

/** Execute list-unsubscribe via HTTPS One-Click (RFC 8058) when available */
export async function executeUnsubscribe(
  listUnsubscribe: string,
  messageId: string,
  userId = "default",
  confirmed = false
): Promise<{ success: boolean; method: string; message?: string }> {
  if (!confirmed) throw new Error("User confirmation required");

  const url = parseUnsubscribeUrl(listUnsubscribe);
  if (!url) {
    return {
      success: false,
      method: "mailto",
      message: "No HTTPS unsubscribe URL - use mailto link manually",
    };
  }

  try {
    const res = await fetch(url, {
      method: "POST",
      headers: {
        "List-Unsubscribe": "One-Click",
        "Content-Type": "application/x-www-form-urlencoded",
      },
      body: "List-Unsubscribe=One-Click",
    });

    await db.insert(actionLog).values({
      userId,
      actionType: "unsubscribe",
      targetIds: [messageId],
      payload: { url, status: res.status },
    });

    return {
      success: res.ok || res.status === 204,
      method: "https",
      message: res.ok ? "Unsubscribe request sent" : `HTTP ${res.status}`,
    };
  } catch (error) {
    return {
      success: false,
      method: "https",
      message: error instanceof Error ? error.message : "Unsubscribe failed",
    };
  }
}

export async function batchUnsubscribe(
  items: Array<{ messageId: string; listUnsubscribe: string }>,
  userId = "default",
  confirmed = false
): Promise<Array<{ messageId: string; success: boolean; message?: string }>> {
  if (!confirmed) throw new Error("User confirmation required");

  const results: Array<{ messageId: string; success: boolean; message?: string }> = [];

  for (let i = 0; i < items.length; i++) {
    const item = items[i];
    const result = await executeUnsubscribe(
      item.listUnsubscribe,
      item.messageId,
      userId,
      true
    );
    results.push({
      messageId: item.messageId,
      success: result.success,
      message: result.message,
    });

    if ((i + 1) % BATCH_SIZE === 0 && i + 1 < items.length) {
      await sleep(BATCH_DELAY_MS);
    }
  }

  return results;
}
