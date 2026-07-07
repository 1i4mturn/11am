import { NextRequest, NextResponse } from "next/server";
import { z } from "zod";
import {
  listBoltonTasks,
  createBoltonTask,
  updateBoltonTask,
  archiveBoltonTask,
} from "@/lib/bolton/client";
import type { TaskCadence, TaskPriority, TaskStatus } from "@/lib/types";

export async function GET() {
  const tasks = await listBoltonTasks();
  return NextResponse.json({ tasks });
}

const CreateTaskSchema = z.object({
  title: z.string().min(1),
  summary: z.string().min(10),
  source_agent: z.string().optional(),
  status: z.enum(["pending", "in_progress", "done", "cancelled"]).optional(),
  due_date: z.string().nullable().optional(),
  priority: z.enum(["low", "normal", "high", "urgent"]).optional(),
  cadence: z.enum(["once", "daily", "weekly", "monthly", "custom"]).optional(),
  custom_schedule: z.string().nullable().optional(),
  tags: z.array(z.string()).optional(),
});

const UpdateTaskSchema = z.object({
  id: z.string().uuid(),
  title: z.string().optional(),
  summary: z.string().optional(),
  status: z.enum(["pending", "in_progress", "done", "cancelled"]).optional(),
  due_date: z.string().nullable().optional(),
  priority: z.enum(["low", "normal", "high", "urgent"]).optional(),
  cadence: z.enum(["once", "daily", "weekly", "monthly", "custom"]).optional(),
  custom_schedule: z.string().nullable().optional(),
});

export async function POST(request: NextRequest) {
  const body = CreateTaskSchema.parse(await request.json());
  const result = await createBoltonTask({
    title: body.title,
    summary: body.summary,
    source_agent: body.source_agent,
    tags: body.tags,
    task: {
      status: (body.status ?? "pending") as TaskStatus,
      due_date: body.due_date ?? null,
      priority: (body.priority ?? "normal") as TaskPriority,
      cadence: (body.cadence ?? "once") as TaskCadence,
      custom_schedule: body.custom_schedule ?? null,
    },
  });

  if (!result?.id) {
    return NextResponse.json({ error: "Failed to create task in Bolton" }, { status: 500 });
  }
  return NextResponse.json({ id: result.id });
}

export async function PATCH(request: NextRequest) {
  const body = UpdateTaskSchema.parse(await request.json());
  const tasks = await listBoltonTasks();
  const entry = tasks.find((t) => t.id === body.id);
  if (!entry) {
    return NextResponse.json({ error: "Task not found" }, { status: 404 });
  }

  const ok = await updateBoltonTask(entry, body);
  if (!ok) {
    return NextResponse.json({ error: "Failed to update task" }, { status: 500 });
  }
  return NextResponse.json({ success: true });
}

export async function DELETE(request: NextRequest) {
  const id = request.nextUrl.searchParams.get("id");
  if (!id) {
    return NextResponse.json({ error: "Missing id" }, { status: 400 });
  }
  const ok = await archiveBoltonTask(id);
  if (!ok) {
    return NextResponse.json({ error: "Failed to archive task" }, { status: 500 });
  }
  return NextResponse.json({ success: true });
}
