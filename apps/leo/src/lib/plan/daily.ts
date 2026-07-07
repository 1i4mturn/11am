import { listBoltonTasks } from "@/lib/bolton/client";
import { synthesizeWithClaude } from "@/lib/claude";
import { listCalendarEvents, todayRange } from "@/lib/google/calendar";
import type { BoltonTask, CalendarEvent } from "@/lib/types";

export async function generateDailyPlan(): Promise<{
  plan: string;
  events: CalendarEvent[];
  tasks: BoltonTask[];
}> {
  const { timeMin, timeMax } = todayRange();
  let events: CalendarEvent[] = [];
  try {
    events = await listCalendarEvents("default", timeMin, timeMax);
  } catch {
    events = [];
  }

  const tasks = await listBoltonTasks();
  const activeTasks = tasks.filter((t) => t.task.status !== "done" && t.task.status !== "cancelled");

  const system = `You are Leo, chief of staff for Liam. Synthesize a practical daily plan from calendar events and Bolton task entries.
Format as markdown with sections: ## Focus, ## Schedule, ## Tasks, ## Notes.
Be concise and actionable. No fluff.`;

  const userPrompt = `Today's date: ${new Date().toISOString().slice(0, 10)}

Calendar events:
${events.length ? JSON.stringify(events, null, 2) : "No events (calendar may be disconnected)."}

Active tasks from Bolton:
${activeTasks.length ? JSON.stringify(activeTasks.map((t) => ({ title: t.title, summary: t.summary, ...t.task })), null, 2) : "No active tasks."}

Create Liam's daily plan.`;

  const plan = await synthesizeWithClaude(system, userPrompt);
  return { plan, events, tasks: activeTasks };
}
