# @11am/ui

Shared design system for the **11am** agent suite.

Based on Robert's locked visual decisions (Notion Design Direction Hub):
- Background `#ffffff` / `#faf9f7` — papery, editorial
- Typography: Alte Haas Grotesk (add `@font-face` when TTF files available)
- Graphite copy `#2f2f2f`, zero garish colour on chrome
- Agent monograms: wm, mc, bn, etc.
- Subtle grain overlay

## Usage in Next.js apps

```bash
npm install file:../11am-ui
```

```tsx
// app/layout.tsx
import "@11am/ui/styles.css";
import { AppShell } from "@11am/ui";

export default function Layout({ children }) {
  return (
    <AppShell
      agent="william"
      logoSrc="/logos/william_wm.svg"
      nav={[{ href: "/", label: "Write" }, { href: "/setup", label: "Voice setup" }]}
    >
      {children}
    </AppShell>
  );
}
```

Copy agent logos from `11am-ui/src/assets/logos/` into each app's `public/logos/`.
