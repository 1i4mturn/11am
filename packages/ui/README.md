# @11am/ui

Shared design system for the **11am** agent suite - lives at `packages/ui` in the monorepo.

## Usage

Each app depends on `"@11am/ui": "*"` via npm workspaces.

```tsx
import "@11am/ui/styles.css"; // in globals.css
import { AppShell, PageHeader, Button, Card } from "@11am/ui";
```

Fonts ship with the package (`src/assets/fonts/`). Logos live in `src/assets/logos/` - copy into each app's `public/logos/`.
