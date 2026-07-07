import { NextRequest, NextResponse } from "next/server";

const inboxKey = Symbol.for("@11am/jobs/push-inbox");

function getInbox(): Array<{ job_id: string; status: string; summary?: string; at: string }> {
  const g = globalThis as Record<symbol, Array<{ job_id: string; status: string; summary?: string; at: string }>>;
  if (!g[inboxKey]) g[inboxKey] = [];
  return g[inboxKey];
}

export async function POST(request: NextRequest) {
  const body = await request.json();
  const entry = {
    job_id: String(body.job_id ?? ""),
    status: String(body.status ?? ""),
    summary: body.summary ? String(body.summary) : undefined,
    at: new Date().toISOString(),
  };
  getInbox().unshift(entry);
  if (getInbox().length > 50) getInbox().pop();
  return NextResponse.json({ received: true });
}

export async function GET() {
  return NextResponse.json({ messages: getInbox().slice(0, 20) });
}
