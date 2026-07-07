import { NextRequest, NextResponse } from "next/server";
import { CreateJobBodySchema } from "@/lib/types";
import {
  createJob,
  initJohnnyJobs,
  listJobs,
  estimateJobCost,
  DEFAULT_REPO_PATH,
} from "@/lib/jobs";
import { JobBudgetSchema } from "@11am/jobs";

export async function GET() {
  await initJohnnyJobs();
  const jobs = listJobs("johnny").sort(
    (a, b) => new Date(b.created_at).getTime() - new Date(a.created_at).getTime()
  );
  return NextResponse.json({ jobs });
}

export async function POST(request: NextRequest) {
  try {
    await initJohnnyJobs();
    const body = CreateJobBodySchema.parse(await request.json());

    const repo = body.repo
      ? {
          ...body.repo,
          path:
            body.repo.type === "local"
              ? body.repo.path ?? DEFAULT_REPO_PATH
              : body.repo.path,
          ref: body.repo.ref ?? "main",
        }
      : {
          type: "local" as const,
          path: DEFAULT_REPO_PATH,
          ref: "main",
        };

    const budget = JobBudgetSchema.parse({
      max_tokens: 100_000,
      max_time_ms: 30 * 60 * 1000,
      max_cost_usd: 2.0,
      ...body.budget,
    });

    const estimate = estimateJobCost(body.prompt, budget);

    const job = await createJob({
      consumer: "johnny",
      prompt: body.prompt,
      repo,
      budget,
    });

    return NextResponse.json({
      job,
      estimate,
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Job creation failed";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
