import { askRobert, askRobertWithVision, extractJson } from "@/lib/claude";
import {
  getBrandSystemFromBolton,
  getConnerContext,
  getJamesVisualResearch,
  persistBrandSystem,
  writeImplementationBrief,
} from "@/lib/bolton/client";
import { MOCK_BRAND_SYSTEM } from "@/lib/bolton/mock";
import { generateImage, getImagesRemaining } from "@/lib/images/openai";
import type {
  BrandAuditResult,
  BrandDirectionResult,
  BrandSystemDoc,
  CompetitorLandscapeResult,
  ImplementationBrief,
  LogoConceptResult,
  MoodboardResult,
  TokenRecommendation,
  WilliamRobertHandoff,
} from "@/lib/types";
import {
  BrandSystemDocSchema,
  ImplementationBriefSchema,
  TokenRecommendationSchema,
} from "@/lib/types";

const BRAND_DIRECTION_PROMPT = `Give brand direction advice grounded in Conner's commercial context.
Respond with JSON ONLY:
{
  "advice": "string — 2-4 paragraphs of direction",
  "recommended_updates": ["string — specific brand-system updates to consider"],
  "confidence": "high" | "medium" | "low"
}`;

const TOKEN_RECOMMENDATION_PROMPT = `Recommend colour and typography as structured tokens ONLY — no prose paragraphs.
Use the living brand-system as baseline. Output JSON ONLY:
{
  "color_tokens": { "token_name": "#hex or css value" },
  "type_scale": { "token_name": "size / line-height / letter-spacing" },
  "spacing_tokens": { "token_name": "value" },
  "rationale": { "token_name": "brief why" }
}`;

const BRAND_SYSTEM_UPDATE_PROMPT = `Update or create the living brand-system doc.
Output JSON ONLY with this EXACT shape:
{
  "source_agent": "Robert",
  "version": "YYYY.MM.DD-description",
  "color_tokens": {},
  "type_scale": {},
  "logo_variants": [{ "id": "string", "description": "string", "usage": "string" }],
  "spacing_tokens": {},
  "motion_tokens": {
    "timing": { "fast": "150ms", "base": "250ms", "slow": "400ms", "logo_reveal": "600ms" },
    "easing": { "default": "cubic-bezier(...)", "enter": "...", "exit": "..." },
    "logo_safe_area": "string"
  },
  "do_dont_rules": [{ "type": "do" | "dont", "rule": "string" }]
}
motion_tokens are REQUIRED — Cole's pipeline depends on them.`;

const LOGO_DIRECTION_PROMPT = `Provide logo direction and concept descriptions ONLY — not production SVG.
Output JSON ONLY:
{
  "direction": "string — overall logo direction",
  "concepts": [
    { "id": "string", "description": "string", "notes": "string", "image_prompt": "string for image gen" }
  ]
}`;

const AUDIT_PROMPT = `Audit this asset against the brand-system tokens. Flag inconsistencies.
Output JSON ONLY:
{
  "inconsistencies": [{ "area": "string", "expected": "string", "observed": "string", "severity": "high"|"medium"|"low" }],
  "passes": ["string — what is on-brand"],
  "overall_verdict": "on_brand" | "needs_revision" | "off_brand",
  "summary": "string"
}`;

const COMPETITOR_LANDSCAPE_PROMPT = `Interpret James's research as a competitor visual landscape analysis.
Output JSON ONLY:
{
  "visual_trends": ["string"],
  "competitor_patterns": [{ "name": "string", "visual_notes": "string" }],
  "differentiation_opportunities": ["string"],
  "recommendation": "string"
}`;

const IMPLEMENTATION_BRIEF_PROMPT = `Produce a structured design brief for implementation — NO code.
Output JSON ONLY:
{
  "source_agent": "Robert",
  "target_agent": "johnny" | "cole",
  "as_of": "YYYY-MM-DD",
  "project": "string",
  "objective": "string",
  "color_tokens": {},
  "type_scale": {},
  "spacing_tokens": {},
  "motion_tokens": { "timing": {}, "easing": {}, "logo_safe_area": "string" },
  "layout_direction": "string",
  "component_notes": ["string"],
  "motion_direction": "string (required if target is cole)",
  "assets": [{ "type": "string", "url": "string optional", "notes": "string" }],
  "do_dont_rules": ["string"],
  "acceptance_criteria": ["string"]
}`;

function bumpVersion(): string {
  const d = new Date();
  return `${d.getFullYear()}.${String(d.getMonth() + 1).padStart(2, "0")}.${String(d.getDate()).padStart(2, "0")}`;
}

export async function runBrandDirection(query: string): Promise<BrandDirectionResult> {
  const conner = await getConnerContext();
  const { doc: brand } = await getBrandSystemFromBolton();

  const raw = await askRobert(
    BRAND_DIRECTION_PROMPT,
    `Brand direction question:\n${query}\n\nConner commercial context:\n${JSON.stringify(conner.data, null, 2)}\n\nCurrent brand system:\n${JSON.stringify(brand, null, 2)}`,
    5000
  );
  const json = extractJson<{
    advice?: string;
    recommended_updates?: string[];
    confidence?: BrandDirectionResult["confidence"];
  }>(raw);

  return {
    workflow: "brand_direction",
    advice: json?.advice ?? raw,
    conner_context_used: true,
    used_mock_conner: conner.from_mock,
    recommended_updates: json?.recommended_updates ?? [],
    confidence: json?.confidence ?? "medium",
  };
}

export async function runColorTypographyRecommendation(
  brief: string
): Promise<TokenRecommendation> {
  const { doc: brand } = await getBrandSystemFromBolton();
  const raw = await askRobert(
    TOKEN_RECOMMENDATION_PROMPT,
    `Brief:\n${brief}\n\nCurrent brand system:\n${JSON.stringify(brand, null, 2)}`,
    3000
  );
  const json = extractJson<TokenRecommendation>(raw);
  const parsed = TokenRecommendationSchema.safeParse(json);
  if (parsed.success) return parsed.data;

  return {
    color_tokens: brand.color_tokens,
    type_scale: brand.type_scale,
    spacing_tokens: brand.spacing_tokens,
    rationale: { fallback: "Could not parse — returned current tokens" },
  };
}

export async function buildBrandSystemDoc(
  updateBrief: string,
  base?: BrandSystemDoc
): Promise<BrandSystemDoc> {
  const current = base ?? (await getBrandSystemFromBolton()).doc;
  const raw = await askRobert(
    BRAND_SYSTEM_UPDATE_PROMPT,
    `Update brief:\n${updateBrief}\n\nCurrent doc:\n${JSON.stringify(current, null, 2)}`,
    4000
  );
  const json = extractJson<BrandSystemDoc>(raw);
  const parsed = BrandSystemDocSchema.safeParse({
    ...json,
    source_agent: "Robert",
    version: json?.version ?? `${bumpVersion()}-update`,
  });
  if (parsed.success) return parsed.data;
  return { ...MOCK_BRAND_SYSTEM, version: `${bumpVersion()}-fallback` };
}

export async function updateBrandSystem(
  updateBrief: string
): Promise<{ doc: BrandSystemDoc; memory_ids_written: string[] }> {
  const doc = await buildBrandSystemDoc(updateBrief);
  const memory_ids_written = await persistBrandSystem(doc);
  return { doc, memory_ids_written };
}

export async function runMoodboard(
  prompt: string,
  sessionId: string,
  count = 2
): Promise<MoodboardResult> {
  const { doc: brand } = await getBrandSystemFromBolton();
  const capped = Math.min(count, getImagesRemaining(sessionId));
  if (capped <= 0) {
    throw new Error("Session image cap reached");
  }

  const enrichedPrompt = await askRobert(
    "Rewrite the user's moodboard request as a single DALL-E image prompt. Reference brand colours and tone. Output ONLY the prompt text, no JSON.",
    `Request: ${prompt}\nBrand colours: ${JSON.stringify(brand.color_tokens)}`,
    500
  );

  const images: MoodboardResult["images"] = [];
  for (let i = 0; i < capped; i++) {
    const variant =
      capped > 1
        ? `${enrichedPrompt.trim()} — variation ${i + 1}, editorial moodboard reference`
        : enrichedPrompt.trim();
    const img = await generateImage(variant, sessionId);
    images.push(img);
  }

  return {
    workflow: "moodboard",
    prompt: enrichedPrompt.trim(),
    images,
    images_remaining: getImagesRemaining(sessionId),
  };
}

export async function runLogoConcepts(
  direction: string,
  sessionId: string
): Promise<LogoConceptResult> {
  const { doc: brand } = await getBrandSystemFromBolton();
  const raw = await askRobert(
    LOGO_DIRECTION_PROMPT,
    `Logo direction request:\n${direction}\n\nBrand system:\n${JSON.stringify(brand, null, 2)}`,
    3000
  );
  const json = extractJson<{
    direction?: string;
    concepts?: Array<{
      id: string;
      description: string;
      notes: string;
      image_prompt?: string;
    }>;
  }>(raw);

  const concepts: LogoConceptResult["concepts"] = [];
  const conceptList = json?.concepts ?? [];

  for (const c of conceptList.slice(0, 2)) {
    let image_url: string | undefined;
    if (getImagesRemaining(sessionId) > 0 && c.image_prompt) {
      try {
        const img = await generateImage(
          `${c.image_prompt} — logo concept sketch only, not final vector, monochrome friendly`,
          sessionId,
          { size: "1024x1024" }
        );
        image_url = img.url;
      } catch {
        // concept text still valuable without image
      }
    }
    concepts.push({
      id: c.id,
      description: c.description,
      notes: c.notes,
      image_url,
    });
  }

  return {
    workflow: "logo_concepts",
    direction: json?.direction ?? direction,
    concepts,
    disclaimer:
      "Direction and concept images only — production-ready vector logos are a human/Later step.",
  };
}

export async function runBrandAudit(
  imageBase64: string,
  mediaType: "image/jpeg" | "image/png" | "image/gif" | "image/webp",
  filename: string
): Promise<BrandAuditResult> {
  const { doc: brand } = await getBrandSystemFromBolton();
  const raw = await askRobertWithVision(
    AUDIT_PROMPT,
    `Audit this asset (${filename}) against the brand system:\n${JSON.stringify(brand, null, 2)}`,
    imageBase64,
    mediaType,
    4000
  );
  const json = extractJson<{
    inconsistencies?: BrandAuditResult["inconsistencies"];
    passes?: string[];
    overall_verdict?: BrandAuditResult["overall_verdict"];
    summary?: string;
  }>(raw);

  return {
    workflow: "brand_audit",
    asset_filename: filename,
    inconsistencies: json?.inconsistencies ?? [],
    passes: json?.passes ?? [],
    overall_verdict: json?.overall_verdict ?? "needs_revision",
    summary: json?.summary ?? raw.slice(0, 500),
  };
}

export async function runCompetitorLandscape(
  focus?: string
): Promise<CompetitorLandscapeResult> {
  const james = await getJamesVisualResearch();
  const { doc: brand } = await getBrandSystemFromBolton();

  const raw = await askRobert(
    COMPETITOR_LANDSCAPE_PROMPT,
    `Focus: ${focus ?? "General visual landscape"}\n\nJames research:\n${JSON.stringify(james.data, null, 2)}\n\nOur brand system:\n${JSON.stringify(brand.color_tokens, null, 2)}`,
    5000
  );
  const json = extractJson<{
    visual_trends?: string[];
    competitor_patterns?: CompetitorLandscapeResult["competitor_patterns"];
    differentiation_opportunities?: string[];
    recommendation?: string;
  }>(raw);

  return {
    workflow: "competitor_landscape",
    james_context_used: true,
    used_mock_james: james.from_mock,
    visual_trends: json?.visual_trends ?? [],
    competitor_patterns: json?.competitor_patterns ?? [],
    differentiation_opportunities: json?.differentiation_opportunities ?? [],
    recommendation: json?.recommendation ?? "",
  };
}

export async function createImplementationBrief(input: {
  target: "johnny" | "cole";
  project: string;
  objective: string;
  william_handoff?: WilliamRobertHandoff;
}): Promise<{ brief: ImplementationBrief; memory_id?: string }> {
  const { doc: brand } = await getBrandSystemFromBolton();
  const raw = await askRobert(
    IMPLEMENTATION_BRIEF_PROMPT,
    `Target: ${input.target}\nProject: ${input.project}\nObjective: ${input.objective}\n\nBrand system:\n${JSON.stringify(brand, null, 2)}${
      input.william_handoff
        ? `\n\nWilliam handoff:\n${JSON.stringify(input.william_handoff, null, 2)}`
        : ""
    }`,
    5000
  );
  const json = extractJson<ImplementationBrief>(raw);
  const parsed = ImplementationBriefSchema.safeParse({
    ...json,
    source_agent: "Robert",
    target_agent: input.target,
    as_of: json?.as_of ?? new Date().toISOString().slice(0, 10),
    project: input.project,
    objective: input.objective,
    color_tokens: json?.color_tokens ?? brand.color_tokens,
    type_scale: json?.type_scale ?? brand.type_scale,
    spacing_tokens: json?.spacing_tokens ?? brand.spacing_tokens,
    motion_tokens: json?.motion_tokens ?? brand.motion_tokens,
  });

  const brief = parsed.success
    ? parsed.data
    : ({
        source_agent: "Robert" as const,
        target_agent: input.target,
        as_of: new Date().toISOString().slice(0, 10),
        project: input.project,
        objective: input.objective,
        color_tokens: brand.color_tokens,
        type_scale: brand.type_scale,
        spacing_tokens: brand.spacing_tokens,
        motion_tokens: brand.motion_tokens,
        layout_direction: raw.slice(0, 500),
        component_notes: [],
        motion_direction: input.target === "cole" ? "See brand motion_tokens" : undefined,
        assets: [],
        do_dont_rules: brand.do_dont_rules.map((r) => r.rule),
        acceptance_criteria: ["Matches brand-system tokens", "No off-palette colours"],
      } satisfies ImplementationBrief);

  const write = await writeImplementationBrief(brief as unknown as Record<string, unknown>);
  return { brief, memory_id: write?.id };
}

export async function runHandoff(input: {
  from_agent: string;
  task: string;
  request_type?: string;
  william_handoff?: WilliamRobertHandoff;
}): Promise<{
  summary: string;
  structured_result?: Record<string, unknown>;
  memory_ids_written: string[];
}> {
  const type = input.request_type ?? "general";
  let result: Record<string, unknown>;
  let summary: string;
  const memory_ids_written: string[] = [];

  switch (type) {
    case "brand_direction":
    case "visual_brief": {
      const r = await runBrandDirection(input.task);
      result = r as unknown as Record<string, unknown>;
      summary = r.advice.slice(0, 500);
      break;
    }
    case "token_review":
    case "color_typography": {
      const tokens = await runColorTypographyRecommendation(input.task);
      result = tokens as unknown as Record<string, unknown>;
      summary = `Token recommendation: ${Object.keys(tokens.color_tokens).length} colours, ${Object.keys(tokens.type_scale).length} type tokens`;
      break;
    }
    case "design_critique":
    case "layout": {
      const r = await runBrandDirection(`Design critique: ${input.task}`);
      result = r as unknown as Record<string, unknown>;
      summary = r.advice.slice(0, 500);
      break;
    }
    case "competitor_landscape": {
      const r = await runCompetitorLandscape(input.task);
      result = r as unknown as Record<string, unknown>;
      summary = r.recommendation;
      break;
    }
    default: {
      const r = await runBrandDirection(input.task);
      result = r as unknown as Record<string, unknown>;
      summary = r.advice.slice(0, 500);
    }
  }

  const brandUpdate = await updateBrandSystem(
    `Handoff from ${input.from_agent} (${type}): ${input.task}\n\n${summary}`
  );
  memory_ids_written.push(...brandUpdate.memory_ids_written);

  if (input.william_handoff) {
    const brief = await createImplementationBrief({
      target: "johnny",
      project: input.william_handoff.platform,
      objective: `Visual implementation for ${input.william_handoff.format}`,
      william_handoff: input.william_handoff,
    });
    if (brief.memory_id) memory_ids_written.push(brief.memory_id);
    result = { ...result, implementation_brief: brief.brief };
  }

  return { summary, structured_result: result, memory_ids_written };
}
