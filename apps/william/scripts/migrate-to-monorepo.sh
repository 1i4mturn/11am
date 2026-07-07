#!/usr/bin/env bash
set -euo pipefail

ROOT="$HOME/Projects/11am"
UI_SRC="$HOME/Projects/liamos-william/packages/11am-ui"

mkdir -p "$ROOT/apps" "$ROOT/packages"

# Copy canonical UI package (with fonts + latest components)
rm -rf "$ROOT/packages/ui"
cp -R "$UI_SRC" "$ROOT/packages/ui"

# Remove vendored copies from apps before move
for app in liamos-william liamos-marc liamos-bolton; do
  rm -rf "$HOME/Projects/$app/packages"
  rm -rf "$HOME/Projects/$app/.next"
done

# Move apps into monorepo (skip if already moved)
move_if_needed() {
  local src="$1" dest="$2"
  if [ -d "$src" ] && [ ! -d "$dest" ]; then
    mv "$src" "$dest"
    echo "Moved $src → $dest"
  fi
}

move_if_needed "$HOME/Projects/liamos-william" "$ROOT/apps/william"
move_if_needed "$HOME/Projects/liamos-marc" "$ROOT/apps/marc"
move_if_needed "$HOME/Projects/liamos-bolton" "$ROOT/apps/bolton"

# Retire standalone UI repo
if [ -d "$HOME/Projects/11am-ui" ]; then
  rm -rf "$HOME/Projects/11am-ui"
  echo "Removed standalone ~/Projects/11am-ui (now packages/ui)"
fi

# Move setup guide
if [ -f "$HOME/Projects/11AM.md" ] && [ ! -f "$ROOT/README.md" ]; then
  mv "$HOME/Projects/11AM.md" "$ROOT/README.md"
fi

echo "Monorepo structure ready at $ROOT"
