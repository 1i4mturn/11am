/** 11am design tokens - from Robert's locked visual decisions */

export const colors = {
  paper: "#faf9f7",
  panel: "#edeeef",
  background: "#edeeef",
  backgroundWarm: "#faf9f7",
  foreground: "#161616",
  graphite: "#2f2f2f",
  muted: "#6b6560",
  border: "rgba(0,0,0,0.05)",
  surface: "rgba(255,255,255,0.6)",
  surfaceHi: "rgba(255,255,255,0.75)",
  surfaceDk: "rgba(22,22,22,0.9)",
  accentLight: "rgba(255,255,255,0.6)",
} as const;

export type AgentId =
  | "william"
  | "marc"
  | "bolton"
  | "leo"
  | "johnny"
  | "robert"
  | "conner"
  | "george"
  | "james"
  | "harris"
  | "cole";

export interface AgentConfig {
  id: AgentId;
  name: string;
  monogram: string;
  role: string;
  logoFile: string;
}

export const agents: Record<AgentId, AgentConfig> = {
  william: { id: "william", name: "William", monogram: "wm", role: "writing & brand voice", logoFile: "william_wm.svg" },
  marc: { id: "marc", name: "Marc", monogram: "mc", role: "inbox & communication", logoFile: "marc_mc.svg" },
  bolton: { id: "bolton", name: "Bolton", monogram: "bn", role: "memory & archive", logoFile: "bolton_bn.svg" },
  leo: { id: "leo", name: "Leo", monogram: "le", role: "chief of staff", logoFile: "leo_le.svg" },
  johnny: { id: "johnny", name: "Johnny", monogram: "jo", role: "build & technical", logoFile: "johnny_jo.svg" },
  robert: { id: "robert", name: "Robert", monogram: "rt", role: "design", logoFile: "robert_rt.svg" },
  conner: { id: "conner", name: "Conner", monogram: "cr", role: "business building", logoFile: "conner_cr.svg" },
  george: { id: "george", name: "George", monogram: "ge", role: "finance", logoFile: "george_ge.svg" },
  james: { id: "james", name: "James", monogram: "jm", role: "research", logoFile: "james_jm.svg" },
  harris: { id: "harris", name: "Harris", monogram: "hr", role: "learning", logoFile: "harris_hr.svg" },
  cole: { id: "cole", name: "Cole", monogram: "co", role: "video & film", logoFile: "cole_co.svg" },
};

export const brand = {
  name: "11am",
  suiteLabel: "11am agent suite",
  fontFamily: "'Alte Haas Grotesk', 'Helvetica Neue', Helvetica, Arial, sans-serif",
} as const;

export const suite = {
  homeUrl: process.env.NEXT_PUBLIC_HOME_URL ?? "http://localhost:3010",
  wordmarkSrc: "/logos/11am_wordmark.svg",
} as const;

/** Fixed rail order - identical on every agent page */
export const agentRoster: AgentId[] = [
  "marc",
  "william",
  "bolton",
  "leo",
  "johnny",
  "robert",
  "james",
  "george",
  "conner",
  "harris",
  "cole",
];

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

/** Agent app URL for rail tiles - set NEXT_PUBLIC_*_APP_URL in production */
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
