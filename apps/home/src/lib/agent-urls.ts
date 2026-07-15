import type { AgentId } from "@/data/agents";

/** Local dev defaults - one port per agent */
const LOCAL_APP_URLS: Record<AgentId, string> = {
  william: "http://localhost:3000",
  marc: "http://localhost:3001",
  bolton: "http://localhost:3002",
  james: "http://localhost:3003",
  george: "http://localhost:3004",
  conner: "http://localhost:3005",
  leo: "http://localhost:3006",
  robert: "http://localhost:3007",
  harris: "http://localhost:3008",
  cole: "http://localhost:3009",
  johnny: "http://localhost:3011",
};

/**
 * Agent app URL for sidebar / monogram links.
 * Set NEXT_PUBLIC_*_APP_URL on home (Vercel) when trialing the full suite in the cloud.
 */
export function getAgentAppUrl(id: AgentId): string {
  const fromEnv: Partial<Record<AgentId, string | undefined>> = {
    william: process.env.NEXT_PUBLIC_WILLIAM_APP_URL,
    marc: process.env.NEXT_PUBLIC_MARC_APP_URL,
    bolton: process.env.NEXT_PUBLIC_BOLTON_APP_URL,
    james: process.env.NEXT_PUBLIC_JAMES_APP_URL,
    george: process.env.NEXT_PUBLIC_GEORGE_APP_URL,
    conner: process.env.NEXT_PUBLIC_CONNER_APP_URL,
    leo: process.env.NEXT_PUBLIC_LEO_APP_URL,
    robert: process.env.NEXT_PUBLIC_ROBERT_APP_URL,
    harris: process.env.NEXT_PUBLIC_HARRIS_APP_URL,
    cole: process.env.NEXT_PUBLIC_COLE_APP_URL,
    johnny: process.env.NEXT_PUBLIC_JOHNNY_APP_URL,
  };

  return fromEnv[id] ?? LOCAL_APP_URLS[id];
}

/** Server-side API base URLs (home → agent backends) */
export const AGENT_API_URLS = {
  marc: process.env.MARC_API_URL ?? LOCAL_APP_URLS.marc,
  william: process.env.WILLIAM_API_URL ?? LOCAL_APP_URLS.william,
  leo: process.env.LEO_API_URL ?? LOCAL_APP_URLS.leo,
  george: process.env.GEORGE_API_URL ?? LOCAL_APP_URLS.george,
  bolton: process.env.BOLTON_API_URL ?? LOCAL_APP_URLS.bolton,
  james: process.env.JAMES_API_URL ?? LOCAL_APP_URLS.james,
  conner: process.env.CONNER_API_URL ?? LOCAL_APP_URLS.conner,
  robert: process.env.ROBERT_API_URL ?? LOCAL_APP_URLS.robert,
  harris: process.env.HARRIS_API_URL ?? LOCAL_APP_URLS.harris,
  cole: process.env.COLE_API_URL ?? LOCAL_APP_URLS.cole,
  johnny: process.env.JOHNNY_API_URL ?? LOCAL_APP_URLS.johnny,
} as const;
