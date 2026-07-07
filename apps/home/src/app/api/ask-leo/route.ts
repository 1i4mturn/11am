import { NextRequest, NextResponse } from "next/server";
import { LEO_API_URL } from "@/lib/config";

export async function POST(request: NextRequest) {
  try {
    const body = await request.json();
    const res = await fetch(`${LEO_API_URL}/api/ask`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ query: body.query }),
      cache: "no-store",
    });
    const data = await res.json();
    if (!res.ok) {
      return NextResponse.json({ error: data.error ?? "Leo unavailable" }, { status: res.status });
    }
    return NextResponse.json(data);
  } catch (error) {
    const message = error instanceof Error ? error.message : "Ask Leo failed";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
