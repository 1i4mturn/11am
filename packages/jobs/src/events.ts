import { EventEmitter } from "events";
import type { JobEvent } from "./types";

const globalKey = Symbol.for("@11am/jobs/events");

function getEmitter(): EventEmitter {
  const g = globalThis as Record<symbol, EventEmitter>;
  if (!g[globalKey]) {
    g[globalKey] = new EventEmitter();
    g[globalKey].setMaxListeners(100);
  }
  return g[globalKey];
}

export function emitJobEvent(event: JobEvent): void {
  getEmitter().emit("job", event);
  getEmitter().emit(`job:${event.job_id}`, event);
}

export function onJobEvent(
  jobId: string | "*",
  listener: (event: JobEvent) => void
): () => void {
  const emitter = getEmitter();
  const channel = jobId === "*" ? "job" : `job:${jobId}`;
  emitter.on(channel, listener);
  return () => emitter.off(channel, listener);
}
