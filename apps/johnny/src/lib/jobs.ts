import path from "path";
import {
  createJob,
  getJob,
  initJobStore,
  killJob,
  listJobs,
  setJobsConfig,
  startJobWorker,
  estimateJobCost,
  type JobsConfig,
} from "@11am/jobs";
import { DEFAULT_REPO_PATH, JOB_DATA_DIR, SANDBOX_IMAGE } from "@/lib/config";

let workerStop: (() => void) | null = null;

export function getJobsConfigFromEnv(): JobsConfig {
  const dataDir = path.isAbsolute(JOB_DATA_DIR)
    ? JOB_DATA_DIR
    : path.join(process.cwd(), JOB_DATA_DIR);

  return {
    dataDir,
    boltonApiUrl: process.env.BOLTON_API_URL ?? "http://localhost:3002",
    anthropicApiKey: process.env.ANTHROPIC_API_KEY ?? "",
    githubToken: process.env.GITHUB_TOKEN,
    sandboxImage: SANDBOX_IMAGE,
    pagespeedApiKey: process.env.PAGESPEED_API_KEY,
  };
}

export async function initJohnnyJobs(): Promise<void> {
  if (process.env.JOHNNY_JOBS_ENABLED === "false" || process.env.VERCEL === "1") {
    return;
  }
  const config = getJobsConfigFromEnv();
  setJobsConfig(config);
  await initJobStore(config.dataDir);
  if (!workerStop) {
    workerStop = startJobWorker(2500);
  }
}

export {
  createJob,
  getJob,
  killJob,
  listJobs,
  estimateJobCost,
  DEFAULT_REPO_PATH,
};
