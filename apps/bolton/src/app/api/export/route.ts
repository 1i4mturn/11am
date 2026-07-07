import { NextResponse } from "next/server";
import { exportAllMemory } from "@/lib/memory";

export async function GET() {
  const data = await exportAllMemory();
  return NextResponse.json(data, {
    headers: {
      "Content-Disposition": `attachment; filename="bolton-memory-export-${Date.now()}.json"`,
    },
  });
}
