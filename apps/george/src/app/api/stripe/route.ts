import { NextRequest, NextResponse } from "next/server";
import { z } from "zod";
import { getStripeMetrics, getStripeKey, saveStripeKey } from "@/lib/stripe/client";

export async function GET() {
  const key = await getStripeKey();
  if (!key) {
    return NextResponse.json({
      configured: false,
      message: "Set STRIPE_RESTRICTED_KEY in .env.local or POST a key",
    });
  }
  try {
    const metrics = await getStripeMetrics();
    return NextResponse.json({ configured: true, metrics });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Stripe read failed";
    return NextResponse.json({ configured: true, error: message }, { status: 500 });
  }
}

const KeySchema = z.object({ key: z.string().min(10) });

export async function POST(request: NextRequest) {
  try {
    const body = KeySchema.parse(await request.json());
    await saveStripeKey(body.key);
    const metrics = await getStripeMetrics();
    return NextResponse.json({ success: true, metrics });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Stripe setup failed";
    return NextResponse.json({ error: message }, { status: 400 });
  }
}
