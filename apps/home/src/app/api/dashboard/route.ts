import { NextResponse } from "next/server";
import { loadDashboardData } from "@/lib/dashboard-data";

export const dynamic = "force-dynamic";

export async function GET() {
  try {
    const data = await loadDashboardData();
    return NextResponse.json(data);
  } catch (error) {
    const message = error instanceof Error ? error.message : "Dashboard load failed";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
