import { NextRequest, NextResponse } from "next/server";
import { getOAuth2Client, saveGmailTokens } from "@/lib/gmail/client";

export async function GET(request: NextRequest) {
  const code = request.nextUrl.searchParams.get("code");
  const error = request.nextUrl.searchParams.get("error");

  if (error) {
    return NextResponse.redirect(new URL("/?gmail=error", request.url));
  }

  if (!code) {
    return NextResponse.json({ error: "No authorization code" }, { status: 400 });
  }

  try {
    const oauth2Client = getOAuth2Client();
    const { tokens } = await oauth2Client.getToken(code);
    await saveGmailTokens("default", tokens);
    return NextResponse.redirect(new URL("/?gmail=connected", request.url));
  } catch {
    return NextResponse.redirect(new URL("/?gmail=error", request.url));
  }
}
