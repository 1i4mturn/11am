import { NextRequest, NextResponse } from "next/server";
import { z } from "zod";
import { runPricingStrategy } from "@/lib/strategy/engine";

const PricingSchema = z.object({
  context: z.string().min(1),
});

export async function POST(request: NextRequest) {
  try {
    const body = PricingSchema.parse(await request.json());
    const result = await runPricingStrategy(body.context);
    return NextResponse.json({ result });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Pricing strategy failed";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
