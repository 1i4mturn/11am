import { NextRequest, NextResponse } from "next/server";
import { getOAuth2Client, saveCalendarTokens } from "@/lib/google/calendar";

export async function GET(request: NextRequest) {
  const code = request.nextUrl.searchParams.get("code");
  const error = request.nextUrl.searchParams.get("error");

  if (error) {
    return NextResponse.redirect(new URL("/?calendar=error", request.url));
  }

  if (!code) {
    return NextResponse.json({ error: "No authorization code" }, { status: 400 });
  }

  try {
    const oauth2Client = getOAuth2Client();
    const { tokens } = await oauth2Client.getToken(code);
    await saveCalendarTokens("default", tokens);
    return NextResponse.redirect(new URL("/?calendar=connected", request.url));
  } catch {
    return NextResponse.redirect(new URL("/?calendar=error", request.url));
  }
}
