import Anthropic from "@anthropic-ai/sdk";
import type { Message } from "@anthropic-ai/sdk/resources/messages/messages";
import { RESEARCH_SYSTEM_SUFFIX, parseResearchJson } from "@/lib/research/template";
import { checkPriorResearch } from "@/lib/research/memory";
import {
  SOURCE_ROUTING,
  classifyRequestType,
  isDeepResearch,
  searchMaxUses,
} from "@/lib/research/routing";
import { shouldSaveToBolton } from "@/lib/research/save-heuristic";
import { writeToBolton } from "@/lib/bolton/client";
import type { JamesHandoff, ResearchBrief, ResearchSource, RequestType } from "@/lib/types";
import { briefToMarkdown } from "@/lib/research/template";

const MODEL = "claude-sonnet-4-20250514";

const JAMES_SYSTEM = `You are James, the research agent for LiamOS/11am. You ground every answer in web evidence with citations.
You run in a separate context — callers receive only a summarised handoff, never your full thread.
${RESEARCH_SYSTEM_SUFFIX}`;

function extractSourcesFromResponse(response: Message): ResearchSource[] {
  const sources: ResearchSource[] = [];
  const seen = new Set<string>();

  for (const block of response.content) {
    if (block.type === "text" && "citations" in block && Array.isArray(block.citations)) {
      for (const cite of block.citations) {
        if (cite.type !== "web_search_result_location") continue;
        const url = cite.url ?? "";
        if (!url || seen.has(url)) continue;
        seen.add(url);
        sources.push({
          title: cite.title ?? url,
          url,
          credibility_score: 3,
          notes: cite.cited_text?.slice(0, 120),
        });
      }
    }
    if (block.type === "web_search_tool_result" && Array.isArray(block.content)) {
      for (const result of block.content) {
        if (result.type !== "web_search_result") continue;
        const url = result.url ?? "";
        if (!url || seen.has(url)) continue;
        seen.add(url);
        sources.push({
          title: result.title ?? url,
          url,
          credibility_score: 3,
          notes: result.page_age ? `Page age: ${result.page_age}` : undefined,
        });
      }
    }
  }
  return sources;
}

function extractText(response: Message): string {
  return response.content
    .filter((b) => b.type === "text")
    .map((b) => (b.type === "text" ? b.text : ""))
    .join("\n");
}

export interface RunResearchInput {
  research_question: string;
  to_agent?: string;
  from_agent?: string;
  context_ref?: string;
  priority?: "normal" | "urgent";
  request_type?: RequestType;
}

export async function runResearch(input: RunResearchInput): Promise<JamesHandoff> {
  const apiKey = process.env.ANTHROPIC_API_KEY;
  if (!apiKey) throw new Error("ANTHROPIC_API_KEY not set");

  const to_agent = input.to_agent ?? input.from_agent ?? "Liam";
  const request_type = classifyRequestType(input.research_question, input.request_type);
  const routing = SOURCE_ROUTING[request_type];
  const depth = isDeepResearch(input.research_question, input.priority) ? "deep" : "standard";
  const maxUses = searchMaxUses(depth);

  const prior = await checkPriorResearch(input.research_question);

  const priorBlock =
    prior.length > 0
      ? `\n\nPrior James research on this topic (reuse where still valid, note gaps):\n${prior
          .map((p) => `- [${p.title}] ${p.summary}`)
          .join("\n")}`
      : "";

  const userPrompt = `Research question: ${input.research_question}
Request type: ${routing.label} — ${routing.search_guidance}
Preferred sources: ${routing.preferred_sources}
Depth: ${depth} (use up to ${maxUses} web searches if needed)
${input.context_ref ? `Context ref: ${input.context_ref}` : ""}${priorBlock}

Search the web. Follow the locked output template. Include credibility scores per source.`;

  const client = new Anthropic({ apiKey });

  const toolConfig: {
    type: "web_search_20250305";
    name: "web_search";
    max_uses: number;
    allowed_callers: ["direct"];
    allowed_domains?: string[];
    user_location?: {
      type: "approximate";
      city: string;
      region: string;
      country: string;
      timezone: string;
    };
  } = {
    type: "web_search_20250305",
    name: "web_search",
    max_uses: maxUses,
    allowed_callers: ["direct"],
    user_location: {
      type: "approximate",
      city: "Sydney",
      region: "New South Wales",
      country: "AU",
      timezone: "Australia/Sydney",
    },
  };

  if (routing.allowed_domains?.length) {
    toolConfig.allowed_domains = routing.allowed_domains;
  }

  const response = await client.messages.create({
    model: MODEL,
    max_tokens: depth === "deep" ? 8000 : 5000,
    system: JAMES_SYSTEM,
    messages: [{ role: "user", content: userPrompt }],
    tools: [toolConfig],
  });

  const rawText = extractText(response);
  let brief: ResearchBrief | null = parseResearchJson(rawText);

  const citationSources = extractSourcesFromResponse(response);

  if (!brief) {
    brief = {
      research_question: input.research_question,
      key_findings: [rawText.slice(0, 500)],
      what_this_means: "See key findings.",
      recommendation: "Review findings and decide next step.",
      sources: citationSources,
    };
  } else if (brief.sources.length === 0 && citationSources.length > 0) {
    brief.sources = citationSources;
  }

  const save = shouldSaveToBolton({
    research_question: input.research_question,
    key_findings: brief.key_findings,
    request_type,
    context_ref: input.context_ref,
  });

  let memory_id: string | undefined;
  if (save) {
    const write = await writeToBolton({
      source_agent: "James",
      entry_type: "research",
      title: brief.research_question.slice(0, 100),
      summary: brief.key_findings.join(" ").slice(0, 500),
      full_content: briefToMarkdown(brief),
      tags: ["research", "james", request_type, `depth:${depth}`],
      force: true,
    });
    memory_id = write?.id;
  }

  const searchUses =
    (response.usage as { server_tool_use?: { web_search_requests?: number } })?.server_tool_use
      ?.web_search_requests ?? undefined;

  return {
    from_agent: "James",
    to_agent,
    ...brief,
    saved_to_bolton: save,
    memory_id,
    prior_research_used: prior.length ? prior : undefined,
    request_type,
    depth,
    search_uses: searchUses,
  };
}
