import { onJobEvent } from "@11am/jobs";
import { getJob, initJohnnyJobs } from "@/lib/jobs";

export const dynamic = "force-dynamic";

export async function GET(
  _request: Request,
  { params }: { params: Promise<{ id: string }> }
) {
  await initJohnnyJobs();
  const { id } = await params;

  const stream = new ReadableStream({
    start(controller) {
      const encoder = new TextEncoder();

      const send = (data: unknown) => {
        controller.enqueue(encoder.encode(`data: ${JSON.stringify(data)}\n\n`));
      };

      const job = getJob(id);
      if (job) {
        send({ type: "snapshot", job });
      }

      const unsubscribe = onJobEvent(id, (event) => {
        send(event);
        if (
          event.type === "completed" ||
          event.type === "failed" ||
          event.type === "killed"
        ) {
          unsubscribe();
          controller.close();
        }
      });

      const heartbeat = setInterval(() => {
        controller.enqueue(encoder.encode(": heartbeat\n\n"));
      }, 15_000);

      const poll = setInterval(() => {
        const current = getJob(id);
        if (current) send({ type: "snapshot", job: current });
        if (
          current &&
          (current.status === "completed" ||
            current.status === "failed" ||
            current.status === "killed")
        ) {
          clearInterval(poll);
          clearInterval(heartbeat);
          unsubscribe();
          controller.close();
        }
      }, 3000);
    },
  });

  return new Response(stream, {
    headers: {
      "Content-Type": "text/event-stream",
      "Cache-Control": "no-cache",
      Connection: "keep-alive",
    },
  });
}
