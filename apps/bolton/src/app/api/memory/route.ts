import { NextRequest, NextResponse } from "next/server";
import { z } from "zod";
import {
  saveMemoryEntry,
  listMemoryEntries,
  getMemoryEntry,
  updateMemoryEntry,
  archiveMemoryEntry,
} from "@/lib/memory";
import { getUser, canSaveMemory } from "@/lib/tiers";
import { resolveUserId } from "@/lib/config";
import { EntryTypeSchema, CadenceSchema } from "@/lib/types";
import { archiveNotionPageByTitle } from "@/lib/notion";

/** Agent read/write API — POST /api/memory from any 11am agent app */

export async function GET(request: NextRequest) {
  const userId = resolveUserId(request.headers.get("x-user-id"));
  const status = request.nextUrl.searchParams.get("status") ?? undefined;
  const sourceAgent = request.nextUrl.searchParams.get("source_agent") ?? undefined;
  const entryType = request.nextUrl.searchParams.get("entry_type") ?? undefined;
  const id = request.nextUrl.searchParams.get("id");

  if (id) {
    const entry = await getMemoryEntry(id, userId);
    if (!entry) return NextResponse.json({ error: "Not found" }, { status: 404 });
    return NextResponse.json({ entry });
  }

  const entries = await listMemoryEntries(userId, { status, sourceAgent, entryType });
  return NextResponse.json({ entries });
}

const CaptureSchema = z.object({
  source_agent: z.string(),
  entry_type: EntryTypeSchema,
  title: z.string().min(1),
  summary: z.string().min(10),
  full_content: z.string().optional(),
  tags: z.array(z.string()).optional(),
  related_entities: z.array(z.string()).optional(),
  related_entries: z.array(z.string()).optional(),
  importance_score: z.number().optional(),
  confidence: z.enum(["high", "medium", "low"]).optional(),
  cadence: CadenceSchema.optional(),
  custom_schedule: z.string().optional(),
  force: z.boolean().optional(),
});

export async function POST(request: NextRequest) {
  const userId = resolveUserId(request.headers.get("x-user-id"));
  const user = await getUser(userId);
  const body = CaptureSchema.parse(await request.json());

  const existing = await listMemoryEntries(userId, { status: "active" }, 100);
  const rows = existing as unknown as Array<unknown>;
  const gate = await canSaveMemory(userId, rows.length);
  if (!gate.allowed && !body.force) {
    return NextResponse.json({ error: gate.reason }, { status: 429 });
  }

  if (user.tier === "free" && body.source_agent !== "Bolton" && !body.force) {
    return NextResponse.json(
      { error: "Cross-agent memory capture requires Pro tier" },
      { status: 403 }
    );
  }

  const result = await saveMemoryEntry(body, userId, body.force);
  return NextResponse.json(result);
}

const UpdateSchema = z.object({
  id: z.string().uuid(),
  title: z.string().optional(),
  summary: z.string().optional(),
  full_content: z.string().optional(),
  tags: z.array(z.string()).optional(),
  status: z.enum(["active", "archived", "superseded", "conflict_review"]).optional(),
});

export async function PATCH(request: NextRequest) {
  const userId = resolveUserId(request.headers.get("x-user-id"));
  const body = UpdateSchema.parse(await request.json());

  if (body.status === "archived" || body.status === "superseded") {
    const entry = await getMemoryEntry(body.id, userId);
    if (entry?.title) {
      archiveNotionPageByTitle(entry.title).catch(() => {});
    }
  }

  await updateMemoryEntry(body.id, body, userId);
  return NextResponse.json({ success: true });
}

/** Archive only — Bolton never hard-deletes memory */
export async function DELETE(request: NextRequest) {
  const userId = resolveUserId(request.headers.get("x-user-id"));
  const id = request.nextUrl.searchParams.get("id");
  if (!id) return NextResponse.json({ error: "Missing id" }, { status: 400 });
  if (!request.nextUrl.searchParams.get("confirmed")) {
    return NextResponse.json({ error: "Confirmation required" }, { status: 400 });
  }

  const entry = await getMemoryEntry(id, userId);
  if (entry?.title) {
    archiveNotionPageByTitle(entry.title).catch(() => {});
  }

  await archiveMemoryEntry(id, userId);
  return NextResponse.json({ success: true, action: "archived" });
}

export async function OPTIONS() {
  return NextResponse.json({
    endpoints: ["GET /api/memory", "POST /api/memory", "PATCH /api/memory", "DELETE /api/memory (archives)"],
  });
}
