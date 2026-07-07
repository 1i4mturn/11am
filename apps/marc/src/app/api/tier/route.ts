import { NextRequest, NextResponse } from "next/server";
import { z } from "zod";
import { getUser, setUserTier, tierFeatures } from "@/lib/tiers";

export async function GET() {
  const user = await getUser();
  return NextResponse.json({
    tier: user.tier,
    actionsThisMonth: user.actionsThisMonth,
    features: tierFeatures(user.tier),
    fullContentIndexing: user.fullContentIndexing,
  });
}

const TierSchema = z.object({
  tier: z.enum(["free", "pro"]),
});

export async function POST(request: NextRequest) {
  const body = TierSchema.parse(await request.json());
  await setUserTier(body.tier);
  return NextResponse.json({ tier: body.tier, features: tierFeatures(body.tier) });
}
