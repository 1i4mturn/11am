import { getBrandContext } from "@/lib/bolton/client";
import type { MotionTemplateResult } from "@/lib/types";

const TEMPLATES: Record<
  string,
  { label: string; description: string }
> = {
  "title-reveal": {
    label: "Title reveal",
    description: "Warm editorial title card with logo safe area",
  },
  "lower-third": {
    label: "Lower third",
    description: "Name/title lower third with brand typography",
  },
  "end-card": {
    label: "End card",
    description: "Simple CTA end card with monogram",
  },
};

export function listMotionTemplates() {
  return Object.entries(TEMPLATES).map(([id, t]) => ({ id, ...t }));
}

/** Basic tier — apply Robert's tokens to a simple HTML/CSS template spec */
export async function renderMotionTemplate(
  templateId: string
): Promise<MotionTemplateResult> {
  const brand = await getBrandContext();
  if (!brand.motion_tokens_ready) {
    throw new Error("motion_tokens required — confirm Robert brand-system is in Bolton");
  }

  const template = TEMPLATES[templateId];
  if (!template) throw new Error(`Unknown template: ${templateId}`);

  const { color_tokens, type_scale, motion_tokens } = brand.doc;

  const css_variables: Record<string, string> = {
    "--cole-bg": color_tokens.background ?? "#faf9f7",
    "--cole-fg": color_tokens.foreground ?? "#161616",
    "--cole-muted": color_tokens.muted ?? "#6b6560",
    "--cole-font": type_scale.font_family ?? "sans-serif",
    "--cole-duration-fast": motion_tokens.timing.fast,
    "--cole-duration-base": motion_tokens.timing.base,
    "--cole-duration-slow": motion_tokens.timing.slow,
    "--cole-ease-default": motion_tokens.easing.default,
    "--cole-ease-enter": motion_tokens.easing.enter,
    "--cole-logo-safe": motion_tokens.logo_safe_area,
  };

  const preview_html = `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8"/>
<style>
:root {
${Object.entries(css_variables)
  .map(([k, v]) => `  ${k}: ${v};`)
  .join("\n")}
}
body { margin:0; background:var(--cole-bg); color:var(--cole-fg); font-family:var(--cole-font); }
.card {
  min-height:100vh; display:flex; align-items:center; justify-content:center; flex-direction:column;
  padding:2rem; box-sizing:border-box;
}
.title {
  font-size:2rem; letter-spacing:-0.02em;
  animation: reveal var(--cole-duration-slow) var(--cole-ease-enter) both;
}
.sub { color:var(--cole-muted); margin-top:1rem; animation: fade var(--cole-duration-base) var(--cole-ease-default) 0.2s both; }
@keyframes reveal { from { opacity:0; transform:translateY(12px); } to { opacity:1; transform:none; } }
@keyframes fade { from { opacity:0; } to { opacity:1; } }
.safe-note { position:absolute; bottom:1rem; font-size:0.75rem; color:var(--cole-muted); }
</style>
</head>
<body>
<div class="card">
  <div class="title">${template.label}</div>
  <div class="sub">${template.description}</div>
  <div class="safe-note">logo safe area: ${motion_tokens.logo_safe_area}</div>
</div>
</body>
</html>`;

  return {
    template_id: templateId,
    css_variables,
    motion_spec: motion_tokens,
    preview_html,
  };
}
