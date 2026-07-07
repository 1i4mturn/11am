import { emitJobEvent } from "./events";
import { notifyJobComplete } from "./push";
import { getJob, initJobStore, listJobs, saveJob, updateJob } from "./store";
import { isBudgetExceeded, estimateJobCost } from "./budget";
import { fetchBoltonContext } from "./bolton";
import {
  ensureSandboxImage,
  prepareWorkspace,
} from "./sandbox";
import { runDependencyAudit } from "./checks/audit";
import { runSeoReview } from "./checks/seo";
import { runAgenticBuild, generateTests } from "./runner/agent";
import type {
  BuildJob,
  CreateJobInput,
  JobStep,
  JobsConfig,
} from "./types";
import { CreateJobInputSchema, JobBudgetSchema } from "./types";

const workerKey = Symbol.for("@11am/jobs/worker");
const configKey = Symbol.for("@11am/jobs/config");

function getWorkerState(): { running: boolean; processing: boolean } {
  const g = globalThis as Record<symbol, { running: boolean; processing: boolean }>;
  if (!g[workerKey]) g[workerKey] = { running: false, processing: false };
  return g[workerKey];
}

export function setJobsConfig(config: JobsConfig): void {
  (globalThis as Record<symbol, JobsConfig>)[configKey] = config;
}

export function getJobsConfig(): JobsConfig | undefined {
  return (globalThis as Record<symbol, JobsConfig>)[configKey];
}

function defaultSteps(): JobStep[] {
  return [
    { id: "bolton", label: "Bolton context", status: "pending" },
    { id: "workspace", label: "Prepare workspace", status: "pending" },
    { id: "audit", label: "Dependency audit", status: "pending" },
    { id: "seo", label: "SEO review", status: "pending" },
    { id: "agent", label: "Agentic build analysis", status: "pending" },
    { id: "tests", label: "Test generation", status: "pending" },
    { id: "review", label: "Final review", status: "pending" },
  ];
}

function patchStep(steps: JobStep[], id: string, patch: Partial<JobStep>): JobStep[] {
  return steps.map((s) => (s.id === id ? { ...s, ...patch } : s));
}

export async function createJob(input: CreateJobInput): Promise<BuildJob> {
  const parsed = CreateJobInputSchema.parse(input);
  const config = getJobsConfig();
  if (!config) throw new Error("Jobs config not initialized");

  await initJobStore(config.dataDir);

  const budget = JobBudgetSchema.parse({
    max_tokens: 100_000,
    max_time_ms: 30 * 60 * 1000,
    max_cost_usd: 2.0,
    ...parsed.budget,
  });

  const estimate = estimateJobCost(parsed.prompt, budget);

  const job: BuildJob = {
    id: crypto.randomUUID(),
    consumer: parsed.consumer,
    status: "queued",
    prompt: parsed.prompt,
    repo: parsed.repo,
    budget,
    cost: {
      input_tokens: 0,
      output_tokens: 0,
      estimated_usd: estimate.estimated_usd,
      elapsed_ms: 0,
    },
    progress: 0,
    stage: "queued",
    steps: defaultSteps(),
    kill_requested: false,
    created_at: new Date().toISOString(),
    updated_at: new Date().toISOString(),
  };

  await saveJob(job);
  emitJobEvent({ type: "progress", job_id: job.id, progress: 0, stage: "queued" });
  return job;
}

export async function killJob(id: string): Promise<BuildJob | undefined> {
  const job = getJob(id);
  if (!job || job.status === "completed" || job.status === "failed" || job.status === "killed") {
    return job;
  }
  const updated = await updateJob(id, { kill_requested: true, stage: "kill requested" });
  return updated;
}

async function setProgress(job: BuildJob, stage: string, progress: number): Promise<BuildJob> {
  const updated = await saveJob({ ...job, stage, progress, status: "running" });
  emitJobEvent({
    type: "progress",
    job_id: updated.id,
    progress,
    stage,
    status: "running",
  });
  return updated;
}

async function executeJob(jobId: string): Promise<void> {
  const config = getJobsConfig();
  if (!config) throw new Error("Jobs config not initialized");

  let job = getJob(jobId);
  if (!job) return;

  const startedAt = Date.now();
  let cleanup: (() => Promise<void>) | undefined;

  try {
    job = await saveJob({ ...job, status: "running", stage: "starting", progress: 5 });
    await ensureSandboxImage(config.sandboxImage);

    // Bolton context
    job = await setProgress(job, "fetching Bolton context", 10);
    job = await saveJob({
      ...job,
      steps: patchStep(job.steps, "bolton", {
        status: "running",
        started_at: new Date().toISOString(),
      }),
    });
    const boltonPack = await fetchBoltonContext(config, job.prompt);
    job = await saveJob({
      ...job,
      bolton_context: boltonPack as unknown as Record<string, unknown>,
      steps: patchStep(job.steps, "bolton", {
        status: "done",
        finished_at: new Date().toISOString(),
        detail: `${boltonPack.raw_entries.length} entries`,
      }),
    });

    if (job.kill_requested) throw new Error("Killed by user");

    // Workspace
    job = await setProgress(job, "preparing workspace", 18);
    job = await saveJob({
      ...job,
      steps: patchStep(job.steps, "workspace", {
        status: "running",
        started_at: new Date().toISOString(),
      }),
    });
    const ws = await prepareWorkspace(job.repo, config.githubToken);
    cleanup = ws.cleanup;
    job = await saveJob({
      ...job,
      steps: patchStep(job.steps, "workspace", {
        status: "done",
        finished_at: new Date().toISOString(),
        detail: ws.workspacePath,
      }),
    });

    if (job.kill_requested) throw new Error("Killed by user");

    // Audit
    job = await setProgress(job, "dependency audit", 28);
    job = await saveJob({
      ...job,
      steps: patchStep(job.steps, "audit", {
        status: "running",
        started_at: new Date().toISOString(),
      }),
    });
    const audit = await runDependencyAudit(config.sandboxImage, ws.workspacePath);
    job = await saveJob({
      ...job,
      steps: patchStep(job.steps, "audit", {
        status: "done",
        finished_at: new Date().toISOString(),
        detail: audit.summary,
      }),
    });

    if (job.kill_requested) throw new Error("Killed by user");

    // SEO
    job = await setProgress(job, "SEO review", 38);
    job = await saveJob({
      ...job,
      steps: patchStep(job.steps, "seo", {
        status: "running",
        started_at: new Date().toISOString(),
      }),
    });
    const seo = await runSeoReview(
      config.sandboxImage,
      ws.workspacePath,
      undefined,
      config.pagespeedApiKey
    );
    job = await saveJob({
      ...job,
      steps: patchStep(job.steps, "seo", {
        status: "done",
        finished_at: new Date().toISOString(),
        detail: seo.summary,
      }),
    });

    if (job.kill_requested) throw new Error("Killed by user");

    const shouldKill = () => {
      const current = getJob(jobId);
      return !!current?.kill_requested;
    };

    // Agentic build
    job = await setProgress(job, "agentic analysis", 50);
    job = await saveJob({
      ...job,
      steps: patchStep(job.steps, "agent", {
        status: "running",
        started_at: new Date().toISOString(),
      }),
    });
    const agentResult = await runAgenticBuild(
      config,
      job,
      ws.workspacePath,
      boltonPack,
      (stage, progress) => {
        void setProgress(job!, stage, progress);
      },
      shouldKill,
      startedAt
    );
    job = await saveJob({
      ...job,
      cost: { ...agentResult.cost, elapsed_ms: Date.now() - startedAt },
      steps: patchStep(job.steps, "agent", {
        status: "done",
        finished_at: new Date().toISOString(),
      }),
    });

    const budgetCheck = isBudgetExceeded(job.cost, job.budget, startedAt);
    if (budgetCheck.exceeded || job.kill_requested) {
      throw new Error(budgetCheck.reason ?? "Killed by user");
    }

    // Tests
    job = await setProgress(job, "test generation", 78);
    job = await saveJob({
      ...job,
      steps: patchStep(job.steps, "tests", {
        status: "running",
        started_at: new Date().toISOString(),
      }),
    });
    const testResult = await generateTests(
      config,
      job.prompt,
      agentResult.output,
      job.cost,
      job.budget,
      startedAt
    );
    job = await saveJob({
      ...job,
      cost: { ...testResult.cost, elapsed_ms: Date.now() - startedAt },
      steps: patchStep(job.steps, "tests", {
        status: "done",
        finished_at: new Date().toISOString(),
      }),
    });

    // Final
    job = await setProgress(job, "finalizing", 95);
    const result = {
      summary: agentResult.output.slice(0, 2000) || "Build job completed",
      bolton_entries: boltonPack.raw_entries.length,
      dependency_audit: audit.summary,
      seo: seo.summary,
      tests: testResult.tests.slice(0, 10_000),
      agent_notes: agentResult.notes,
      cost: job.cost,
      budget: job.budget,
    };

    job = await saveJob({
      ...job,
      status: "completed",
      progress: 100,
      stage: "completed",
      completed_at: new Date().toISOString(),
      result,
      steps: patchStep(job.steps, "review", {
        status: "done",
        finished_at: new Date().toISOString(),
      }),
      cost: { ...job.cost, elapsed_ms: Date.now() - startedAt },
    });

    await notifyJobComplete(job);
  } catch (error) {
    const message = error instanceof Error ? error.message : "Job failed";
    const isKilled = message.includes("Killed") || job?.kill_requested;
    job = await saveJob({
      ...job!,
      status: isKilled ? "killed" : "failed",
      error: message,
      stage: isKilled ? "killed" : "failed",
      completed_at: new Date().toISOString(),
      cost: { ...job!.cost, elapsed_ms: Date.now() - startedAt },
    });
    await notifyJobComplete(job);
  } finally {
    await cleanup?.();
  }
}

async function processQueue(): Promise<void> {
  const state = getWorkerState();
  if (state.processing) return;
  state.processing = true;

  try {
    const queued = listJobs().filter((j) => j.status === "queued");
    for (const job of queued) {
      const current = getJob(job.id);
      if (current?.status !== "queued") continue;
      await executeJob(job.id);
    }
  } finally {
    state.processing = false;
  }
}

export function startJobWorker(pollMs = 3000): () => void {
  const state = getWorkerState();
  if (state.running) return () => {};
  state.running = true;

  const interval = setInterval(() => {
    void processQueue();
  }, pollMs);

  void processQueue();

  return () => {
    clearInterval(interval);
    state.running = false;
  };
}

export { getJob, listJobs, initJobStore, estimateJobCost };
