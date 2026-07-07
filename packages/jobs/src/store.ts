import { mkdir, readFile, readdir, writeFile } from "fs/promises";
import path from "path";
import { BuildJobSchema, type BuildJob } from "./types";

const storeKey = Symbol.for("@11am/jobs/store");

interface JobStoreState {
  dataDir: string;
  jobs: Map<string, BuildJob>;
  loaded: boolean;
}

function getState(): JobStoreState {
  const g = globalThis as Record<symbol, JobStoreState>;
  if (!g[storeKey]) {
    g[storeKey] = { dataDir: "", jobs: new Map(), loaded: false };
  }
  return g[storeKey];
}

export async function initJobStore(dataDir: string): Promise<void> {
  const state = getState();
  state.dataDir = dataDir;
  await mkdir(dataDir, { recursive: true });
  if (!state.loaded) {
    await loadFromDisk();
    state.loaded = true;
  }
}

async function loadFromDisk(): Promise<void> {
  const state = getState();
  if (!state.dataDir) return;
  try {
    const files = await readdir(state.dataDir);
    for (const file of files) {
      if (!file.endsWith(".json")) continue;
      const raw = await readFile(path.join(state.dataDir, file), "utf-8");
      const parsed = BuildJobSchema.safeParse(JSON.parse(raw));
      if (parsed.success) state.jobs.set(parsed.data.id, parsed.data);
    }
  } catch {
    // empty store
  }
}

async function persist(job: BuildJob): Promise<void> {
  const state = getState();
  if (!state.dataDir) return;
  await writeFile(
    path.join(state.dataDir, `${job.id}.json`),
    JSON.stringify(job, null, 2),
    "utf-8"
  );
}

export function getJob(id: string): BuildJob | undefined {
  return getState().jobs.get(id);
}

export function listJobs(consumer?: string): BuildJob[] {
  const jobs = [...getState().jobs.values()];
  return consumer ? jobs.filter((j) => j.consumer === consumer) : jobs;
}

export async function saveJob(job: BuildJob): Promise<BuildJob> {
  const updated = { ...job, updated_at: new Date().toISOString() };
  getState().jobs.set(updated.id, updated);
  await persist(updated);
  return updated;
}

export async function updateJob(
  id: string,
  patch: Partial<BuildJob>
): Promise<BuildJob | undefined> {
  const existing = getJob(id);
  if (!existing) return undefined;
  return saveJob({ ...existing, ...patch });
}
