import { NextResponse } from "next/server";
import { loadDashboardData, type DashboardPayload } from "@/lib/dashboard-data";

export const dynamic = "force-dynamic";

/**
 * Short in-memory cache. The dashboard polls every 60s and each load fans out
 * to Marc, Leo, and Bolton - caching for 45s dedupes bursts (multiple tabs,
 * manual refreshes) without the UI ever being more than one poll stale.
 */
const CACHE_TTL_MS = 45_000;
const cacheKey = Symbol.for("@11am/home/dashboard-cache");

type CacheSlot = { at: number; data: DashboardPayload } | undefined;

function getCache(): CacheSlot {
  return (globalThis as Record<symbol, CacheSlot>)[cacheKey];
}

function setCache(data: DashboardPayload): void {
  (globalThis as Record<symbol, CacheSlot>)[cacheKey] = { at: Date.now(), data };
}

export async function GET() {
  try {
    const cached = getCache();
    if (cached && Date.now() - cached.at < CACHE_TTL_MS) {
      return NextResponse.json(cached.data);
    }

    const data = await loadDashboardData();
    setCache(data);
    return NextResponse.json(data);
  } catch (error) {
    const message = error instanceof Error ? error.message : "Dashboard load failed";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
