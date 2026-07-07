export type AgentId =
  | "leo"
  | "johnny"
  | "marc"
  | "william"
  | "robert"
  | "conner"
  | "george"
  | "james"
  | "harris"
  | "cole"
  | "bolton";

export interface AgentEntry {
  id: AgentId;
  name: string;
  role: string;
  tagline: string;
  copy: string;
  meta: string;
  logo: string;
  href?: string;
  live?: boolean;
}

export const AGENTS: AgentEntry[] = [
  {
    id: "leo",
    name: "leo",
    role: "operations",
    tagline: "Chief of staff — routes work across the suite.",
    copy: "Leo is the main entry point into LiamOS: calm, practical and strategic, he turns messy requests into priorities, routes work to the right specialist and keeps projects moving without making the whole thing feel corporate.",
    meta: "Use Leo when a task spans multiple domains, needs sequencing, or needs to be translated into a clear operating plan.",
    logo: "/logos/leo_le.svg",
    href: "http://localhost:3006",
    live: true,
  },
  {
    id: "johnny",
    name: "johnny",
    role: "build",
    tagline: "Builder — concept to execution.",
    copy: "Johnny is the build brain of the system: practical, technical and implementation-led, he takes direction from the other agents and turns it into something usable.",
    meta: "Use Johnny for front-end experiments, app logic, automations, integrations, workflow builds, technical structure and anything that needs to move from concept into execution.",
    logo: "/logos/johnny_jo.svg",
    href: "http://localhost:3011",
    live: true,
  },
  {
    id: "marc",
    name: "marc",
    role: "communications",
    tagline: "Inbox intelligence — triage, not another email client.",
    copy: "Marc handles the inbox: relationship context, triage logic, reply drafts and the prioritisation layer that makes email feel manageable rather than overwhelming.",
    meta: "Use Marc for inbox triage, reply drafting, sender memory and communication prioritisation.",
    logo: "/logos/marc_mc.svg",
    href: "http://localhost:3001",
    live: true,
  },
  {
    id: "william",
    name: "william",
    role: "voice",
    tagline: "Writer — copy-ready drafts in your voice.",
    copy: "William produces copy-ready drafts — warm, clear, authentically you. He learns your voice from your writing, applies it consistently and flags when something drifts.",
    meta: "Use William for emails, posts, announcements, long-form drafts, and anything that needs to sound like you, not like AI.",
    logo: "/logos/william_wm.svg",
    href: "http://localhost:3000",
    live: true,
  },
  {
    id: "robert",
    name: "robert",
    role: "design",
    tagline: "Visual direction — taste and intention.",
    copy: "Robert sets the visual direction: colour, type, layout, motion, and the aesthetic decisions that make the system feel considered rather than assembled.",
    meta: "Use Robert for brand decisions, UI direction, design critique, visual references and anything where taste and intention matter.",
    logo: "/logos/robert_rt.svg",
    href: "http://localhost:3007",
    live: true,
  },
  {
    id: "conner",
    name: "conner",
    role: "growth",
    tagline: "Commercial direction — what is worth building.",
    copy: "Conner sets the commercial direction: offers, positioning, business experiments, value creation and the strategic layer that decides what is worth building in the first place.",
    meta: "Use Conner for monetisation, product angles, market logic, pitch structure and deciding which ideas should become real.",
    logo: "/logos/conner_cr.svg",
    href: "http://localhost:3005",
    live: true,
  },
  {
    id: "george",
    name: "george",
    role: "finance",
    tagline: "Numbers, models and grounded decisions.",
    copy: "George handles numbers, models and decision support: calm finance logic, forecasting, comparisons, reconciliations and the spreadsheet thinking that makes a choice feel grounded.",
    meta: "Use George for budgets, pricing, forecasts, cash flow, operational modelling and commercial comparisons.",
    logo: "/logos/george_ge.svg",
    href: "http://localhost:3004",
  },
  {
    id: "james",
    name: "james",
    role: "research",
    tagline: "Landscape scans and source-backed synthesis.",
    copy: "James researches, compares and synthesises: he turns scattered sources, product references, competitor notes and open questions into a clear point of view.",
    meta: "Use James when the system needs a landscape scan, structured options, source-backed recommendations or a briefing before a decision.",
    logo: "/logos/james_jm.svg",
    href: "http://localhost:3003",
  },
  {
    id: "harris",
    name: "harris",
    role: "learning",
    tagline: "Study paths and skill-building without homework vibes.",
    copy: "Harris manages learning: study paths, practice structure, skills, progress and the slow compound work of getting sharper without turning everything into homework.",
    meta: "Use Harris for language learning, courses, reading plans, study systems, practice routines and progress tracking.",
    logo: "/logos/harris_hr.svg",
    href: "http://localhost:3008",
    live: true,
  },
  {
    id: "cole",
    name: "cole",
    role: "motion",
    tagline: "Video, film and moving-image direction.",
    copy: "Cole owns the moving-image layer: video references, sequencing, story, edits, reels, visual rhythm and the cinematic instincts of the system.",
    meta: "Use Cole for video concepts, shot lists, edit direction, reference gathering and the bridge between static brand and moving image.",
    logo: "/logos/cole_co.svg",
    href: "http://localhost:3009",
    live: true,
  },
  {
    id: "bolton",
    name: "bolton",
    role: "memory",
    tagline: "Institutional memory — tidy, inspectable, source-backed.",
    copy: "Bolton stores and retrieves: decisions, voice data, business context, relationships and the institutional memory that keeps the system coherent across sessions.",
    meta: "Use Bolton to log decisions, query context, surface relevant history and ensure the system remembers what matters.",
    logo: "/logos/bolton_bn.svg",
    href: "http://localhost:3002",
    live: true,
  },
];

export const LIVE_AGENTS = AGENTS.filter((a) => a.live);
