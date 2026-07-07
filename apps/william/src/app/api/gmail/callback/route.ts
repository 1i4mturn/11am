import { NextRequest, NextResponse } from "next/server";
import { getOAuth2Client, saveGmailTokens } from "@/lib/ingestion/gmail";

export async function GET(request: NextRequest) {
  const code = request.nextUrl.searchParams.get("code");
  if (!code) {
    return NextResponse.redirect(new URL("/setup?gmail=error", request.url));
  }

  try {
    const oauth2Client = getOAuth2Client();
    const { tokens } = await oauth2Client.getToken(code);
    await saveGmailTokens("default", tokens);
    return NextResponse.redirect(new URL("/setup?gmail=connected", request.url));
  } catch {
    return NextResponse.redirect(new URL("/setup?gmail=error", request.url));
  }
}
