import { mkdir, readFile, writeFile } from "fs/promises";
import path from "path";
import type { LearningHub, LearningPlan } from "@/lib/types";
import { LearningHubSchema } from "@/lib/types";
import {
  loadLearningHubFromBolton,
  saveLearningHubToBolton,
} from "@/lib/bolton/client";

const LOCAL_HUB_PATH = path.join(process.cwd(), ".data", "learning-hub.json");

function emptyHub(): LearningHub {
  return {
    version: 1,
    updated_at: new Date().toISOString(),
    plans: [],
    french_srs: [],
  };
}

async function readLocalHub(): Promise<LearningHub | null> {
  try {
    const raw = await readFile(LOCAL_HUB_PATH, "utf-8");
    const parsed = LearningHubSchema.safeParse(JSON.parse(raw));
    return parsed.success ? parsed.data : null;
  } catch {
    return null;
  }
}

async function writeLocalHub(hub: LearningHub): Promise<void> {
  await mkdir(path.dirname(LOCAL_HUB_PATH), { recursive: true });
  await writeFile(LOCAL_HUB_PATH, JSON.stringify(hub, null, 2), "utf-8");
}

/** Learning Hub — primary store (Bolton reference entry + local fallback) */
export async function getLearningHub(): Promise<LearningHub> {
  const bolton = await loadLearningHubFromBolton();
  if (bolton.hub) return bolton.hub;

  const local = await readLocalHub();
  if (local) return local;

  return emptyHub();
}

export async function saveLearningHub(hub: LearningHub): Promise<LearningHub> {
  const updated: LearningHub = {
    ...hub,
    updated_at: new Date().toISOString(),
  };

  await writeLocalHub(updated);

  const saved = await saveLearningHubToBolton(updated, updated.bolton_entry_id);
  if (saved?.id) updated.bolton_entry_id = saved.id;

  await writeLocalHub(updated);
  return updated;
}

export async function addPlanToHub(plan: LearningPlan): Promise<LearningHub> {
  const hub = await getLearningHub();
  const existing = hub.plans.findIndex((p) => p.id === plan.id);
  if (existing >= 0) hub.plans[existing] = plan;
  else hub.plans.unshift(plan);
  return saveLearningHub(hub);
}

export async function updatePlanProgress(
  planId: string,
  patch: Partial<LearningPlan["progress"]>
): Promise<LearningHub> {
  const hub = await getLearningHub();
  const plan = hub.plans.find((p) => p.id === planId);
  if (!plan) throw new Error("Plan not found");

  plan.progress = {
    ...plan.progress,
    ...patch,
    sessions_completed:
      patch.sessions_completed ?? plan.progress.sessions_completed + 1,
    updated_at: new Date().toISOString(),
  };
  plan.updated_at = new Date().toISOString();
  return saveLearningHub(hub);
}

export function newPlanId(): string {
  return `plan_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`;
}

export function defaultProgress(): LearningPlan["progress"] {
  return {
    status: "active",
    percent_self_reported: 0,
    sessions_completed: 0,
    milestones_completed: [],
    updated_at: new Date().toISOString(),
  };
}
