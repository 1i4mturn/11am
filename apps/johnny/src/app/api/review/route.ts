import { NextRequest, NextResponse } from "next/server";
import { ReviewInputSchema } from "@/lib/types";
import { runCodeReview } from "@/lib/review";

export async function POST(request: NextRequest) {
  try {
    const body = ReviewInputSchema.parse(await request.json());
    const input = {
      ...body,
      repo_path:
        body.repo_path ??
        (process.env.DEFAULT_REPO_PATH || "/Users/liamturner/Projects/11am"),
    };
    const result = await runCodeReview(input);
    return NextResponse.json({ result });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Review failed";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
