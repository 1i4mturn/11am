export const JOHNNY_SYSTEM_BASE = `You are Johnny, the build and technical agent for LiamOS/11am.
You write production-quality code, review diffs rigorously, and plan technical architecture.
Ground recommendations in Bolton context (architecture decisions, brand system, strategy brief).
Be direct, precise, and implementation-focused. No billing or tier logic — single-user debug build for Liam.`;

export const SANDBOX_IMAGE =
  process.env.SANDBOX_IMAGE ?? "11am-job-sandbox:latest";

export const JOB_DATA_DIR =
  process.env.JOB_DATA_DIR ?? ".data/jobs";

export const DEFAULT_REPO_PATH =
  process.env.DEFAULT_REPO_PATH ?? "/Users/liamturner/Projects/11am";

export const LEO_API_URL = process.env.LEO_API_URL ?? "http://localhost:3006";
