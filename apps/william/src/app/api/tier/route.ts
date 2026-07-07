import { NextRequest, NextResponse } from "next/server";
import { setUserTier, getUser } from "@/lib/tiers";

export async function GET() {
  const user = await getUser();
  return NextResponse.json({
    tier: user.tier,
    generationsThisMonth: user.generationsThisMonth,
  });
}

export async function POST(request: NextRequest) {
  const body = await request.json();
  const tier = body.tier as "free" | "pro";

  if (!["free", "pro"].includes(tier)) {
    return NextResponse.json({ error: "Invalid tier" }, { status: 400 });
  }

  await setUserTier(tier);
  return NextResponse.json({ success: true, tier });
}
