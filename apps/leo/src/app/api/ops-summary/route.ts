import { NextRequest, NextResponse } from "next/server";
import { z } from "zod";
import { generateOpsSummary } from "@/lib/plan/ops";

const OpsSchema = z.object({
  period: z.enum(["weekly", "monthly"]).default("weekly"),
});

export async function POST(request: NextRequest) {
  try {
    const body = OpsSchema.parse(
      request.headers.get("content-type")?.includes("json")
        ? await request.json()
        : { period: request.nextUrl.searchParams.get("period") ?? "weekly" }
    );
    const result = await generateOpsSummary(body.period);
    return NextResponse.json(result);
  } catch (error) {
    const message = error instanceof Error ? error.message : "Ops summary failed";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}

export async function GET(request: NextRequest) {
  const period = request.nextUrl.searchParams.get("period") === "monthly" ? "monthly" : "weekly";
  try {
    const result = await generateOpsSummary(period);
    return NextResponse.json(result);
  } catch (error) {
    const message = error instanceof Error ? error.message : "Ops summary failed";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
