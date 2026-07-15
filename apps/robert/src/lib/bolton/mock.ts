import type { BrandSystemDoc } from "@/lib/types";

/** Default living brand system seeded from @11am/ui tokens - used when Bolton has no doc yet */
export const MOCK_BRAND_SYSTEM: BrandSystemDoc = {
  source_agent: "Robert",
  version: "2026.07.06-mock",
  color_tokens: {
    background: "#faf9f7",
    foreground: "#161616",
    graphite: "#2f2f2f",
    surface: "#ffffff",
    border: "#e8e4dc",
    muted: "#6b6560",
    accent_light: "#f0efed",
    ask_bar: "#161616",
    ask_bar_text: "#faf9f7",
  },
  type_scale: {
    font_family:
      "'Alte Haas Grotesk', 'Helvetica Neue', Helvetica, Arial, sans-serif",
    display: "2.25rem / 1.1 / -0.02em",
    heading: "1.5rem / 1.2 / -0.01em",
    body: "0.9375rem / 1.6",
    label: "0.6875rem / 1.4 / 0.12em uppercase",
    monogram: "0.875rem / 1 / 0.2em lowercase",
  },
  logo_variants: [
    {
      id: "monogram-dark",
      description: "Inverted monogram on dark ask bars",
      usage: "Primary interaction surfaces",
    },
    {
      id: "wordmark-light",
      description: "Black wordmark on warm white",
      usage: "App shell headers",
    },
  ],
  spacing_tokens: {
    page_padding: "1.5rem",
    section_gap: "2.5rem",
    card_padding: "1.25rem",
    ask_bar_height: "3.5rem",
    grid_gutter: "1rem",
  },
  motion_tokens: {
    timing: {
      fast: "150ms",
      base: "250ms",
      slow: "400ms",
      logo_reveal: "600ms",
    },
    easing: {
      default: "cubic-bezier(0.4, 0, 0.2, 1)",
      enter: "cubic-bezier(0, 0, 0.2, 1)",
      exit: "cubic-bezier(0.4, 0, 1, 1)",
    },
    logo_safe_area: "1.25× monogram bounding box on all sides",
  },
  do_dont_rules: [
    { type: "do", rule: "Use warm off-white backgrounds - editorial, not sterile" },
    { type: "do", rule: "Dark inverted ask bars with lowercase monogram" },
    { type: "dont", rule: "No stock-photo energy or corporate blue gradients" },
    { type: "dont", rule: "No invented palettes outside the living brand-system doc" },
  ],
};

export const MOCK_CONNER_STRATEGY = {
  positioning_update:
    "11am as a calm multi-agent operating layer for solo operators (mock)",
  target_segment: "Solo founders running multiple business functions without hiring",
  key_decisions: ["Ship agent depth before horizontal marketing"],
  confidence: "medium",
};

export const MOCK_JAMES_VISUAL_RESEARCH = {
  topic: "Competitor visual landscape - AI productivity tools (mock)",
  key_findings: [
    "Linear-style minimal UI dominates B2B SaaS",
    "Warm neutrals differentiate from cold blue-grey defaults",
    "Agent products trend toward dark sidebars + light content",
  ],
  competitors: [
    { name: "Notion AI", visual_notes: "Neutral, dense, low-contrast icons" },
    { name: "Linear", visual_notes: "Purple accent, tight spacing, dark mode native" },
    { name: "Raycast", visual_notes: "Dark chrome, monospace accents, high polish" },
  ],
};
