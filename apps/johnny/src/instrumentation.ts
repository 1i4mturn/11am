export async function register() {
  if (process.env.NEXT_RUNTIME === "nodejs") {
    const { initJohnnyJobs } = await import("@/lib/jobs");
    await initJohnnyJobs();
  }
}
