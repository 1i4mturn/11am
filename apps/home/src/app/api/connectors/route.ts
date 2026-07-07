import { NextResponse } from "next/server";
import { loadConnectorStatuses } from "@/lib/connectors";

export const dynamic = "force-dynamic";

export async function GET() {
  const connectors = await loadConnectorStatuses();
  return NextResponse.json({ connectors });
}
