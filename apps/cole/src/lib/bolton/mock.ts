import type { BrandSystemDoc } from "@/lib/types";

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
    { id: "monogram-dark", description: "Inverted monogram on dark ask bars" },
    { id: "wordmark-light", description: "Black wordmark on warm white" },
  ],
  spacing_tokens: {
    page_padding: "1.5rem",
    section_gap: "2.5rem",
    card_padding: "1.25rem",
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
    { type: "do", rule: "Warm editorial pacing — not frantic cuts" },
    { type: "dont", rule: "No stock-photo energy or corporate motion graphics" },
  ],
};
