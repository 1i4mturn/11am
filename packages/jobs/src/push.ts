import { emitJobEvent } from "./events";
import type { BuildJob } from "./types";

const subsKey = Symbol.for("@11am/jobs/push-subs");

interface PushSubscription {
  id: string;
  job_id?: string;
  endpoint: string;
  created_at: string;
}

function getSubs(): Map<string, PushSubscription> {
  const g = globalThis as Record<symbol, Map<string, PushSubscription>>;
  if (!g[subsKey]) g[subsKey] = new Map();
  return g[subsKey];
}

export function registerPushSubscription(sub: Omit<PushSubscription, "created_at">): string {
  const id = sub.id || crypto.randomUUID();
  getSubs().set(id, { ...sub, id, created_at: new Date().toISOString() });
  return id;
}

export function listPushSubscriptions(jobId?: string): PushSubscription[] {
  return [...getSubs().values()].filter((s) => !jobId || s.job_id === jobId);
}

export async function notifyJobComplete(job: BuildJob): Promise<void> {
  emitJobEvent({
    type: job.status === "killed" ? "killed" : job.status === "failed" ? "failed" : "completed",
    job_id: job.id,
    progress: job.progress,
    stage: job.stage,
    status: job.status,
    result: job.result,
    message: job.error ?? `Job ${job.status}`,
  });

  const subs = listPushSubscriptions(job.id);
  for (const sub of subs) {
    try {
      await fetch(sub.endpoint, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          job_id: job.id,
          status: job.status,
          summary: job.result?.summary ?? job.stage,
        }),
      });
    } catch {
      // non-blocking
    }
  }
}
