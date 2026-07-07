"use client";

import { Badge, Button, Card, PageHeader } from "@11am/ui";
import Link from "next/link";
import { Suspense, useCallback, useEffect, useState } from "react";
import { useSearchParams } from "next/navigation";

interface CalendarStatus {
  connected: boolean;
  needsReauth?: boolean;
  daysUntilExpiry?: number | null;
  authUrl: string | null;
  message?: string;
}

function HomeContent() {
  const searchParams = useSearchParams();
  const [calendar, setCalendar] = useState<CalendarStatus | null>(null);
  const [taskCount, setTaskCount] = useState(0);
  const [notice, setNotice] = useState("");
  const [error, setError] = useState("");

  const load = useCallback(async () => {
    const [calRes, taskRes] = await Promise.all([
      fetch("/api/calendar"),
      fetch("/api/tasks"),
    ]);
    setCalendar(await calRes.json());
    const tasks = await taskRes.json();
    setTaskCount((tasks.tasks ?? []).filter((t: { task: { status: string } }) =>
      !["done", "cancelled"].includes(t.task.status)
    ).length);
  }, []);

  useEffect(() => {
    load();
  }, [load]);

  useEffect(() => {
    const c = searchParams.get("calendar");
    if (c === "connected") setNotice("Google Calendar connected.");
    if (c === "error") setError("Calendar connection failed.");
  }, [searchParams]);

  return (
    <div className="am-section space-y-8">
      <PageHeader
        title="Chief of staff"
        description="Calendar, tasks, routing, and daily planning — single-user debug build."
      />

      {notice && <p className="am-copy text-sm">{notice}</p>}
      {error && <p className="am-copy am-error text-sm">{error}</p>}

      <div className="grid gap-4 md:grid-cols-2">
        <Card padding="md">
          <p className="am-label mb-2">Google Calendar</p>
          {calendar?.connected ? (
            <div className="space-y-2">
              <Badge tone={calendar.needsReauth ? "low" : "high"}>
                {calendar.needsReauth ? "Re-auth needed" : "Connected"}
              </Badge>
              {calendar.daysUntilExpiry != null && (
                <p className="am-copy text-sm">
                  Testing mode token: ~{calendar.daysUntilExpiry} days left
                </p>
              )}
              {calendar.needsReauth && calendar.authUrl && (
                <a href={calendar.authUrl} className="am-btn am-btn-secondary px-3 py-1.5 am-label inline-block">
                  Reconnect Calendar
                </a>
              )}
            </div>
          ) : (
            <div className="space-y-2">
              <p className="am-copy text-sm">Not connected</p>
              {calendar?.authUrl && (
                <a href={calendar.authUrl} className="am-btn am-btn-primary px-3 py-1.5 am-label inline-block">
                  Connect Calendar
                </a>
              )}
            </div>
          )}
          {calendar?.message && (
            <p className="am-copy mt-2 text-sm text-[var(--am-muted)]">{calendar.message}</p>
          )}
        </Card>

        <Card padding="md">
          <p className="am-label mb-2">Bolton tasks</p>
          <p className="am-title text-2xl">{taskCount}</p>
          <p className="am-copy text-sm">Active tasks in shared memory</p>
          <Link href="/tasks" className="am-btn am-btn-ghost px-3 py-1.5 am-label mt-3 inline-block">
            View tasks
          </Link>
        </Card>
      </div>

      <Card padding="md">
        <p className="am-label mb-4">Quick actions</p>
        <div className="flex flex-wrap gap-2">
          <Link href="/plan" className="am-btn am-btn-primary px-3 py-1.5 am-label">
            Generate daily plan
          </Link>
          <Link href="/calendar" className="am-btn am-btn-secondary px-3 py-1.5 am-label">
            Calendar
          </Link>
          <Link href="/reports" className="am-btn am-btn-secondary px-3 py-1.5 am-label">
            Agent reports
          </Link>
          <Link href="/invoke" className="am-btn am-btn-secondary px-3 py-1.5 am-label">
            Route to agent
          </Link>
        </div>
      </Card>
    </div>
  );
}

export default function HomePage() {
  return (
    <Suspense>
      <HomeContent />
    </Suspense>
  );
}
