import { NextRequest, NextResponse } from "next/server";
import { getGmailAuthStatus } from "@/lib/gmail/client";
import { syncInbox, getIndexedMessageCount } from "@/lib/gmail/sync";
import { getUser } from "@/lib/tiers";

export async function GET() {
  const user = await getUser();
  const count = user.gmailRefreshToken ? await getIndexedMessageCount() : 0;

  if (!process.env.GOOGLE_CLIENT_ID) {
    return NextResponse.json({
      connected: false,
      needsReauth: false,
      authUrl: null,
      message: "Set GOOGLE_CLIENT_ID and GOOGLE_CLIENT_SECRET in .env.local",
      indexedCount: count,
      lastSyncAt: user.lastSyncAt,
    });
  }

  const status = await getGmailAuthStatus("default");
  return NextResponse.json({
    ...status,
    indexedCount: count,
    lastSyncAt: user.lastSyncAt,
    tier: user.tier,
    message: status.needsReauth
      ? "Gmail Testing mode refresh expires every 7 days - reconnect to keep syncing."
      : undefined,
  });
}

export async function POST() {
  try {
    const user = await getUser();
    if (!user.gmailRefreshToken) {
      return NextResponse.json({ error: "Gmail not connected" }, { status: 400 });
    }

    const result = await syncInbox();
    return NextResponse.json({ success: true, ...result });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Sync failed";
    const needsReauth =
      message.toLowerCase().includes("invalid_grant") || message.includes("not connected");
    return NextResponse.json({ error: message, needsReauth }, { status: needsReauth ? 401 : 500 });
  }
}
