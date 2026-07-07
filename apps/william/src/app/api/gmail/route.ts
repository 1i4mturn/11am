import { NextRequest, NextResponse } from "next/server";
import { fetchSentEmails, getGmailAuthStatus } from "@/lib/ingestion/gmail";
import { getUser } from "@/lib/tiers";
import { isPro } from "@/lib/config";
import { ingestCorpus } from "@/lib/ingestion";

export async function GET() {
  const user = await getUser();
  if (!isPro(user.tier)) {
    return NextResponse.json({ error: "Gmail requires Pro tier" }, { status: 403 });
  }

  if (!process.env.GOOGLE_CLIENT_ID) {
    return NextResponse.json({
      connected: false,
      needsReauth: false,
      authUrl: null,
      message: "Gmail OAuth not configured. Set GOOGLE_CLIENT_ID and GOOGLE_CLIENT_SECRET.",
    });
  }

  const status = await getGmailAuthStatus("default");
  return NextResponse.json({
    ...status,
    message: status.needsReauth
      ? "Gmail Testing mode refresh expires every 7 days — reconnect to keep syncing."
      : undefined,
  });
}

export async function POST(request: NextRequest) {
  const user = await getUser();
  if (!isPro(user.tier)) {
    return NextResponse.json({ error: "Gmail requires Pro tier" }, { status: 403 });
  }

  try {
    const emails = await fetchSentEmails("default", 50);
    const corpus = emails
      .map((e) => `Subject: ${e.subject}\n\n${e.body}`)
      .join("\n\n---\n\n");

    if (corpus.length < 100) {
      return NextResponse.json({ error: "Not enough sent emails found" }, { status: 400 });
    }

    const result = await ingestCorpus(corpus, "gmail", "default", {
      emailCount: String(emails.length),
    });

    return NextResponse.json({
      success: true,
      emailsIngested: emails.length,
      chunksAdded: result.chunksAdded,
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Gmail sync failed";
    const needsReauth = message.toLowerCase().includes("invalid_grant") || message.includes("not connected");
    return NextResponse.json(
      { error: message, needsReauth },
      { status: needsReauth ? 401 : 500 }
    );
  }
}
