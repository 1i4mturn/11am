import { askCole, extractJson } from "@/lib/claude";
import { brandContextBlock, getBrandContext } from "@/lib/bolton/client";
import type {
  ContentConceptResult,
  Platform,
  ScriptPackageResult,
  StoryboardResult,
} from "@/lib/types";

const SCRIPT_PROMPT = `Create a full video production package grounded in Robert's brand-system (especially motion_tokens).
Output JSON ONLY:
{
  "script": "string — spoken script or A-roll outline",
  "shot_list": [{ "shot": 1, "description": "string", "duration": "string", "notes": "string" }],
  "voiceover": "string — voiceover copy if applicable",
  "editing_direction": "string — pacing, cuts, b-roll notes",
  "motion_notes": "string — transitions using motion_tokens timing/easing"
}`;

const CONCEPTS_PROMPT = `Create a platform-native content concept structure.
Output JSON ONLY:
{
  "hook": "string",
  "structure": [{ "beat": "string", "duration": "string", "purpose": "string" }],
  "cta": "string",
  "caption_draft": "string"
}`;

const STORYBOARD_PROMPT = `Create a TEXT-ONLY storyboard spec (no rendered video).
Use motion_tokens for transition notes.
Output JSON ONLY:
{
  "title": "string",
  "frames": [{ "frame": 1, "visual": "string", "audio": "string", "duration": "string", "transition": "string" }]
}`;

export async function generateScriptPackage(
  brief: string,
  platform: Platform = "general"
): Promise<ScriptPackageResult> {
  const brand = await getBrandContext();
  if (!brand.motion_tokens_ready) {
    throw new Error("Robert brand-system motion_tokens not ready — load Robert app first");
  }

  const raw = await askCole(
    SCRIPT_PROMPT,
    `Brief:\n${brief}\nPlatform: ${platform}\n\nBrand context:\n${brandContextBlock(brand)}`
  );
  const json = extractJson<{
    script?: string;
    shot_list?: ScriptPackageResult["shot_list"];
    voiceover?: string;
    editing_direction?: string;
    motion_notes?: string;
  }>(raw);

  return {
    workflow: "script",
    brief,
    platform,
    script: json?.script ?? raw,
    shot_list: json?.shot_list ?? [],
    voiceover: json?.voiceover ?? "",
    editing_direction: json?.editing_direction ?? "",
    motion_notes: json?.motion_notes ?? "",
  };
}

export async function generateContentConcepts(
  topic: string,
  platform: Platform
): Promise<ContentConceptResult> {
  const brand = await getBrandContext();
  const raw = await askCole(
    CONCEPTS_PROMPT,
    `Topic:\n${topic}\nPlatform: ${platform}\n\nBrand context:\n${brandContextBlock(brand)}`
  );
  const json = extractJson<{
    hook?: string;
    structure?: ContentConceptResult["structure"];
    cta?: string;
    caption_draft?: string;
  }>(raw);

  return {
    workflow: "concepts",
    platform,
    hook: json?.hook ?? "",
    structure: json?.structure ?? [],
    cta: json?.cta ?? "",
    caption_draft: json?.caption_draft ?? "",
  };
}

export async function generateStoryboard(title: string): Promise<StoryboardResult> {
  const brand = await getBrandContext();
  if (!brand.motion_tokens_ready) {
    throw new Error("Robert brand-system motion_tokens not ready");
  }

  const raw = await askCole(
    STORYBOARD_PROMPT,
    `Storyboard for:\n${title}\n\nBrand context:\n${brandContextBlock(brand)}`
  );
  const json = extractJson<{
    title?: string;
    frames?: StoryboardResult["frames"];
  }>(raw);

  return {
    workflow: "storyboard",
    title: json?.title ?? title,
    frames: json?.frames ?? [],
    spec_only: true,
  };
}

export async function runHandoff(input: {
  from_agent: string;
  task: string;
}): Promise<{ summary: string }> {
  const result = await generateScriptPackage(input.task);
  return { summary: result.script.slice(0, 500) };
}
