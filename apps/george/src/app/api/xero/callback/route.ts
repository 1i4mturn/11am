import { NextRequest, NextResponse } from "next/server";
import { exchangeXeroCode } from "@/lib/xero/client";

export async function GET(request: NextRequest) {
  const code = request.nextUrl.searchParams.get("code");
  const error = request.nextUrl.searchParams.get("error");

  if (error) {
    return NextResponse.redirect(new URL("/integrations?xero=error", request.url));
  }

  if (!code) {
    return NextResponse.json({ error: "No authorization code" }, { status: 400 });
  }

  try {
    await exchangeXeroCode(code);
    return NextResponse.redirect(new URL("/integrations?xero=connected", request.url));
  } catch {
    return NextResponse.redirect(new URL("/integrations?xero=error", request.url));
  }
}
