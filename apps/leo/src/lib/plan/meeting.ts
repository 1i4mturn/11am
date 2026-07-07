import { getBoltonContext } from "@/lib/bolton/client";
import { synthesizeWithClaude } from "@/lib/claude";
import { getCalendarEvent } from "@/lib/google/calendar";

export async function generateMeetingPrep(eventId: string): Promise<{
  brief: string;
  eventTitle: string;
}> {
  const event = await getCalendarEvent(eventId);
  if (!event) throw new Error("Event not found");

  const contextTask = `Meeting prep for "${event.summary}" on ${event.start}. Attendees: ${event.attendees?.join(", ") ?? "unknown"}. Related decisions, projects, and recent memory.`;
  const pack = await getBoltonContext(contextTask, "Leo");

  const system = `You are Leo preparing a meeting brief for Liam. Include: purpose, attendees context, talking points, open decisions, and suggested prep actions. Markdown format.`;

  const userPrompt = `Calendar event:
${JSON.stringify(event, null, 2)}

Bolton context:
${pack?.context_pack ? JSON.stringify(pack.context_pack, null, 2) : "No Bolton context available."}

Generate a meeting prep brief.`;

  const brief = await synthesizeWithClaude(system, userPrompt);
  return { brief, eventTitle: event.summary };
}
