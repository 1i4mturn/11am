import { askHarris, extractJson } from "@/lib/claude";
import { getSkillGapSignals } from "@/lib/bolton/client";
import {
  addPlanToHub,
  defaultProgress,
  getLearningHub,
  newPlanId,
  saveLearningHub,
} from "@/lib/hub/store";
import type {
  ExercisesResult,
  ExplainResult,
  FrenchSrsCard,
  GapPlanResult,
  LearningPlan,
  PlanGenerationResult,
  RoadmapResult,
  SkillGapSignal,
} from "@/lib/types";
import { PlanContentSchema } from "@/lib/types";

const PLAN_PROMPT = `Generate a learning plan. Output JSON ONLY:
{
  "overview": "string",
  "phases": [{ "name": "string", "duration": "string", "goals": ["string"], "resources": ["string"] }],
  "weekly_rhythm": "string optional"
}
Then markdown narrative starting with "## Your plan".`;

const ROADMAP_PROMPT = `Generate a skill roadmap. Output JSON ONLY:
{
  "roadmap": "string - markdown roadmap",
  "milestones": ["string"]
}
Then brief narrative.`;

const EXERCISES_PROMPT = `Generate practice exercises. Output JSON ONLY:
{
  "exercises": [{ "title": "string", "content": "string - the actual exercise" }]
}`;

const EXPLAIN_PROMPT = `Explain a concept clearly for self-directed learning. Output JSON ONLY:
{
  "explanation": "string - clear explanation",
  "practice_prompt": "string - one thing to try right now"
}`;

const FRENCH_PROMPT = `Help with French learning (lightweight personal feature). Be accurate on grammar.
Provide explanation + 2-3 practice items. Output JSON:
{
  "explanation": "string",
  "practice_items": ["string"]
}`;

function splitNarrative(text: string): { json: Record<string, unknown> | null; narrative: string } {
  const json = extractJson<Record<string, unknown>>(text);
  const narrativeMatch = text.match(/##[\s\S]*/);
  return { json, narrative: narrativeMatch?.[0] ?? text };
}

export async function generateLearningPlan(
  skill: string,
  context?: string
): Promise<PlanGenerationResult> {
  const raw = await askHarris(
    PLAN_PROMPT,
    `Skill to learn:\n${skill}${context ? `\n\nContext:\n${context}` : ""}`,
    5000
  );
  const { json, narrative } = splitNarrative(raw);
  const planContent = PlanContentSchema.safeParse(json);

  const plan: LearningPlan = {
    id: newPlanId(),
    skill,
    created_at: new Date().toISOString(),
    updated_at: new Date().toISOString(),
    source: "manual",
    plan: planContent.success
      ? planContent.data
      : { overview: narrative.slice(0, 500), phases: [] },
    exercises: [],
    progress: defaultProgress(),
  };

  const hub = await addPlanToHub(plan);
  const saved = hub.plans.find((p) => p.id === plan.id) ?? plan;

  return { plan: saved, narrative };
}

export async function generateRoadmap(skill: string): Promise<RoadmapResult> {
  const raw = await askHarris(ROADMAP_PROMPT, `Skill:\n${skill}`, 4000);
  const json = extractJson<{ roadmap?: string; milestones?: string[] }>(raw);

  const roadmap = json?.roadmap ?? raw;
  const milestones = json?.milestones ?? [];

  const hub = await getLearningHub();
  const plan = hub.plans.find((p) => p.skill.toLowerCase() === skill.toLowerCase());
  if (plan) {
    plan.roadmap = roadmap;
    plan.updated_at = new Date().toISOString();
    await addPlanToHub(plan);
  }

  return { skill, roadmap, milestones };
}

export async function generateExercises(skill: string, focus?: string): Promise<ExercisesResult> {
  const raw = await askHarris(
    EXERCISES_PROMPT,
    `Skill: ${skill}\nFocus: ${focus ?? "general practice"}\nGenerate 3-5 exercises.`,
    4000
  );
  const json = extractJson<{ exercises?: Array<{ title: string; content: string }> }>(raw);
  const exercises = json?.exercises ?? [];

  const hub = await getLearningHub();
  const plan = hub.plans.find((p) => p.skill.toLowerCase() === skill.toLowerCase());
  if (plan) {
    plan.exercises = exercises.map((e, i) => ({
      id: `ex_${i}`,
      title: e.title,
      content: e.content,
      completed: false,
    }));
    plan.updated_at = new Date().toISOString();
    await addPlanToHub(plan);
  }

  return { skill, exercises };
}

export async function explainConcept(concept: string): Promise<ExplainResult> {
  const raw = await askHarris(EXPLAIN_PROMPT, `Concept:\n${concept}`, 3000);
  const json = extractJson<{ explanation?: string; practice_prompt?: string }>(raw);

  return {
    concept,
    explanation: json?.explanation ?? raw,
    practice_prompt: json?.practice_prompt ?? "Try applying this in a small practice session.",
  };
}

export async function generateGapPlan(gap?: SkillGapSignal): Promise<GapPlanResult> {
  const { gaps, from_mock } = await getSkillGapSignals();
  const signal = gap ?? gaps[0];
  if (!signal) throw new Error("No skill-gap signals available");

  const raw = await askHarris(
    PLAN_PROMPT,
    `Build a learning plan for this REAL skill gap from ${signal.source_agent}:\n\nSkill gap: ${signal.skill_gap}\nEvidence: ${signal.evidence}\nPriority: ${signal.priority}\n\nAnchor everything to the evidence - not a generic curriculum.`,
    5000
  );
  const { json, narrative } = splitNarrative(raw);
  const planContent = PlanContentSchema.safeParse(json);

  const plan: LearningPlan = {
    id: newPlanId(),
    skill: signal.skill_gap,
    created_at: new Date().toISOString(),
    updated_at: new Date().toISOString(),
    source: "skill_gap",
    skill_gap_ref: `${signal.source_agent}:${signal.skill_gap.slice(0, 40)}`,
    plan: planContent.success
      ? planContent.data
      : { overview: `Gap-driven plan: ${signal.skill_gap}`, phases: [] },
    exercises: [],
    progress: defaultProgress(),
  };

  await addPlanToHub(plan);

  return { skill_gap: signal, from_mock, plan, narrative };
}

export async function frenchHelp(query: string): Promise<{
  explanation: string;
  practice_items: string[];
}> {
  const raw = await askHarris(FRENCH_PROMPT, query, 3000);
  const json = extractJson<{ explanation?: string; practice_items?: string[] }>(raw);
  return {
    explanation: json?.explanation ?? raw,
    practice_items: json?.practice_items ?? [],
  };
}

export async function addFrenchSrsCard(front: string, back: string): Promise<FrenchSrsCard> {
  const hub = await getLearningHub();
  const card: FrenchSrsCard = {
    id: `fr_${Date.now()}`,
    front,
    back,
    next_review: new Date().toISOString().slice(0, 10),
    interval_days: 1,
    ease: 2.5,
  };
  hub.french_srs.push(card);
  await saveLearningHub(hub);
  return card;
}

export async function reviewFrenchCard(
  cardId: string,
  quality: "again" | "hard" | "good" | "easy"
): Promise<FrenchSrsCard | null> {
  const hub = await getLearningHub();
  const card = hub.french_srs.find((c) => c.id === cardId);
  if (!card) return null;

  const intervals = { again: 1, hard: 2, good: 4, easy: 7 };
  card.interval_days = intervals[quality];
  const next = new Date();
  next.setDate(next.getDate() + card.interval_days);
  card.next_review = next.toISOString().slice(0, 10);
  if (quality === "easy") card.ease = Math.min(card.ease + 0.1, 3);
  if (quality === "again") card.ease = Math.max(card.ease - 0.2, 1.3);

  await saveLearningHub(hub);
  return card;
}

export async function runHandoff(input: {
  from_agent: string;
  task: string;
}): Promise<{ summary: string; memory_ids_written: string[] }> {
  const result = await generateLearningPlan(input.task, `Requested by ${input.from_agent}`);
  return {
    summary: result.plan.plan.overview.slice(0, 500),
    memory_ids_written: [],
  };
}
