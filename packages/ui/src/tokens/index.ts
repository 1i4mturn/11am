/** 11am design tokens — from Robert's locked visual decisions */

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
  wordmarkSrc: "/logos/agent_logo_11am_from_png_smoothed.svg",
} as const;
