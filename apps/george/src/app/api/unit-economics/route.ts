import { NextRequest, NextResponse } from "next/server";
import { z } from "zod";
import { runUnitEconomics } from "@/lib/finance/engine";

const Schema = z.object({
  cac: z.number().optional(),
  ltv: z.number().optional(),
  arpu: z.number().optional(),
  gross_margin_pct: z.number().optional(),
  monthly_churn_pct: z.number().optional(),
  payback_months: z.number().optional(),
  customers: z.number().optional(),
  notes: z.string().optional(),
});

export async function POST(request: NextRequest) {
  try {
    const body = Schema.parse(await request.json());
    const result = await runUnitEconomics(body);
    return NextResponse.json(result);
  } catch (error) {
    const message = error instanceof Error ? error.message : "Analysis failed";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
