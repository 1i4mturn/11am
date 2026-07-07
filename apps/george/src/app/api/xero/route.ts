import { NextRequest, NextResponse } from "next/server";
import { getXeroAuthStatus, getXeroFinancials } from "@/lib/xero/client";

export async function GET() {
  try {
    const status = await getXeroAuthStatus();
    if (!status.connected) {
      return NextResponse.json({
        connected: false,
        authUrl: status.authUrl,
        message: process.env.XERO_CLIENT_ID
          ? "Connect Xero to read P&L and cash position"
          : "Set XERO_CLIENT_ID and XERO_CLIENT_SECRET in .env.local",
      });
    }
    const financials = await getXeroFinancials();
    return NextResponse.json({ connected: true, ...status, financials });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Xero read failed";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
