import { NextRequest, NextResponse } from "next/server";
import { z } from "zod";
import { explainFinancialTerm } from "@/lib/finance/tax";

const Schema = z.object({ term: z.string().min(1) });

export async function POST(request: NextRequest) {
  try {
    const body = Schema.parse(await request.json());
    const explanation = await explainFinancialTerm(body.term);
    return NextResponse.json({ explanation });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Explain failed";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
