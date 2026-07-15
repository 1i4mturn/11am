import { NextResponse } from "next/server";
import { buildLatestNumbersSummary } from "@/lib/finance/engine";
import { writeLatestNumbers, writeToBolton } from "@/lib/bolton/client";
import { getStripeMetrics, getStripeKey } from "@/lib/stripe/client";
import { getXeroFinancials, getXeroAuthStatus } from "@/lib/xero/client";

export async function POST() {
  try {
    const context: Record<string, unknown> = {};

    if (await getStripeKey()) {
      try {
        context.stripe = await getStripeMetrics();
      } catch {
        context.stripe_error = "Stripe read failed";
      }
    }

    const xeroStatus = await getXeroAuthStatus();
    if (xeroStatus.connected) {
      try {
        context.xero = await getXeroFinancials();
      } catch {
        context.xero_error = "Xero read failed";
      }
    }

    const summary = await buildLatestNumbersSummary(context);
    await writeLatestNumbers(summary);

    await writeToBolton({
      source_agent: "George",
      entry_type: "research",
      title: `Latest numbers - ${summary.as_of}`,
      summary: `${summary.revenue} · ${summary.runway_months}mo runway · burn ${summary.burn_rate}`,
      full_content: JSON.stringify(summary, null, 2),
      tags: ["george", "latest_numbers", "finance"],
      force: true,
    });

    return NextResponse.json({ summary });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Summary failed";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}

export async function GET() {
  try {
    const res = await fetch(
      `${process.env.BOLTON_API_URL ?? "http://localhost:3002"}/api/agent-summaries?agent_id=george`
    );
    if (res.ok) {
      const data = await res.json();
      return NextResponse.json(data);
    }
    return NextResponse.json({ error: "No summary found" }, { status: 404 });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Fetch failed";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
