import { listBoltonMemory, writeToBolton } from "@/lib/bolton/client";
import { synthesizeWithClaude } from "@/lib/claude";

export async function generateOpsSummary(period: "weekly" | "monthly"): Promise<{
  summary: string;
  memory_ids_written: string[];
}> {
  const entries = await listBoltonMemory({ status: "active" });
  const days = period === "weekly" ? 7 : 30;
  const cutoff = Date.now() - days * 24 * 60 * 60 * 1000;

  const recent = entries.filter((e) => {
    if (!e.created_at) return true;
    return new Date(e.created_at).getTime() >= cutoff;
  });

  const system = `You are Leo producing a ${period} operations summary for Liam across all 11am agents.
Cover: key decisions, completed tasks, open items, cross-agent themes, and recommended focus for next ${period === "weekly" ? "week" : "month"}.
Markdown format.`;

  const userPrompt = `Period: last ${days} days
Bolton entries (${recent.length}):
${JSON.stringify(
  recent.map((e) => ({
    agent: e.source_agent,
    type: e.entry_type,
    title: e.title,
    summary: e.summary,
    created_at: e.created_at,
  })),
  null,
  2
)}`;

  const summary = await synthesizeWithClaude(system, userPrompt, 6000);

  const write = await writeToBolton({
    source_agent: "Leo",
    entry_type: "other",
    title: `${period === "weekly" ? "Weekly" : "Monthly"} ops summary - ${new Date().toISOString().slice(0, 10)}`,
    summary: summary.slice(0, 500),
    full_content: summary,
    tags: ["ops_summary", period],
    force: true,
  });

  return {
    summary,
    memory_ids_written: write?.id ? [write.id] : [],
  };
}
