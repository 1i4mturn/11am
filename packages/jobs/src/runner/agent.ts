import Anthropic from "@anthropic-ai/sdk";
import { addTokenUsage, isBudgetExceeded } from "../budget";
import {
  listWorkspaceDir,
  readWorkspaceFile,
  runInSandbox,
} from "../sandbox";
import type { BoltonContextPack } from "../bolton";
import { boltonContextBlock } from "../bolton";
import type { BuildJob, JobCost, JobsConfig } from "../types";

const MODEL = process.env.ANTHROPIC_MODEL ?? "claude-sonnet-4-20250514";

export interface AgentRunResult {
  output: string;
  cost: JobCost;
  notes: Record<string, string>;
}

export async function runAgenticBuild(
  config: JobsConfig,
  job: BuildJob,
  workspacePath: string,
  boltonPack: BoltonContextPack,
  onProgress: (stage: string, progress: number) => void,
  shouldKill: () => boolean,
  startedAt: number
): Promise<AgentRunResult> {
  const client = new Anthropic({ apiKey: config.anthropicApiKey });
  let cost = { ...job.cost };
  const notes: Record<string, string> = {};

  const system = `You are Johnny, the build agent for LiamOS/11am.
Execute technical tasks inside a read-only sandboxed workspace.
Use tools to inspect files and run checks. Produce:
1. Pre-production code cleaning recommendations
2. Documentation outline for changed areas
3. Technical architecture notes aligned with Bolton context
4. Test file suggestions (describe test cases; do not write to disk)

Bolton context:
${boltonContextBlock(boltonPack)}

Respond concisely. When done, summarize findings in plain text.`;

  const tools: Anthropic.Tool[] = [
    {
      name: "read_file",
      description: "Read a file from the workspace (max 100KB)",
      input_schema: {
        type: "object",
        properties: { path: { type: "string" } },
        required: ["path"],
      },
    },
    {
      name: "list_directory",
      description: "List files in a workspace directory",
      input_schema: {
        type: "object",
        properties: { path: { type: "string" } },
        required: ["path"],
      },
    },
    {
      name: "run_sandbox_command",
      description: "Run a read-only shell command in the isolated container (e.g. grep, find, cat)",
      input_schema: {
        type: "object",
        properties: {
          command: { type: "string", description: "Shell command to run" },
        },
        required: ["command"],
      },
    },
  ];

  const messages: Anthropic.MessageParam[] = [
    {
      role: "user",
      content: `Build task: ${job.prompt}\n\nRepo workspace is mounted at /workspace. Begin analysis.`,
    },
  ];

  let finalText = "";
  const maxTurns = 12;

  for (let turn = 0; turn < maxTurns; turn++) {
    if (shouldKill()) break;

    const budgetCheck = isBudgetExceeded(cost, job.budget, startedAt);
    if (budgetCheck.exceeded) break;

    onProgress(`agent turn ${turn + 1}`, 50 + turn * 3);

    const response = await client.messages.create({
      model: MODEL,
      max_tokens: 4096,
      system,
      tools,
      messages,
    });

    cost = addTokenUsage(
      cost,
      response.usage.input_tokens,
      response.usage.output_tokens,
      config.tokenPricePerMInput,
      config.tokenPricePerMOutput
    );
    cost = { ...cost, elapsed_ms: Date.now() - startedAt };

    const toolUses = response.content.filter((b) => b.type === "tool_use");
    const textBlocks = response.content.filter((b) => b.type === "text");
    if (textBlocks.length) {
      finalText = textBlocks.map((b) => (b.type === "text" ? b.text : "")).join("\n");
    }

    messages.push({ role: "assistant", content: response.content });

    if (toolUses.length === 0 || response.stop_reason === "end_turn") {
      break;
    }

    const toolResults: Anthropic.ToolResultBlockParam[] = [];
    for (const toolUse of toolUses) {
      if (toolUse.type !== "tool_use") continue;
      const input = toolUse.input as Record<string, string>;
      let result = "";

      try {
        if (toolUse.name === "read_file") {
          result = await readWorkspaceFile(workspacePath, input.path);
        } else if (toolUse.name === "list_directory") {
          const entries = await listWorkspaceDir(workspacePath, input.path || ".");
          result = entries.join("\n");
        } else if (toolUse.name === "run_sandbox_command") {
          const cmd = input.command?.slice(0, 500) ?? "ls";
          const sandboxResult = await runInSandbox(
            config.sandboxImage,
            workspacePath,
            ["sh", "-c", cmd]
          );
          result = `${sandboxResult.stdout}\n${sandboxResult.stderr}`.slice(0, 20_000);
          notes[`cmd:${turn}`] = cmd;
        } else {
          result = "Unknown tool";
        }
      } catch (e) {
        result = `Error: ${e instanceof Error ? e.message : String(e)}`;
      }

      toolResults.push({
        type: "tool_result",
        tool_use_id: toolUse.id,
        content: result.slice(0, 30_000),
      });
    }

    messages.push({ role: "user", content: toolResults });
  }

  return { output: finalText, cost, notes };
}

export async function generateTests(
  config: JobsConfig,
  prompt: string,
  context: string,
  cost: JobCost,
  budget: BuildJob["budget"],
  startedAt: number
): Promise<{ tests: string; cost: JobCost }> {
  const client = new Anthropic({ apiKey: config.anthropicApiKey });
  const budgetCheck = isBudgetExceeded(cost, budget, startedAt);
  if (budgetCheck.exceeded) return { tests: "Skipped - budget exceeded", cost };

  const response = await client.messages.create({
    model: MODEL,
    max_tokens: 3000,
    system:
      "You are Johnny. Generate test cases and example test code for the described code. Output JSON with { suites: [{ name, cases: [{ name, description, example_code }] }] }.",
    messages: [
      {
        role: "user",
        content: `Task: ${prompt}\n\nContext:\n${context.slice(0, 40_000)}`,
      },
    ],
  });

  const text =
    response.content.find((b) => b.type === "text")?.type === "text"
      ? (response.content.find((b) => b.type === "text") as { text: string }).text
      : "";

  const updated = addTokenUsage(
    cost,
    response.usage.input_tokens,
    response.usage.output_tokens,
    config.tokenPricePerMInput,
    config.tokenPricePerMOutput
  );

  return { tests: text, cost: updated };
}
