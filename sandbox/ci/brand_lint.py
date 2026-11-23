#!/usr/bin/env python3
"""Brand v2 lint for the interface code: fails on colour, grey, faded text, shouted labels, system symbols, system fonts
and literal corner radii (docs/mac/11-brand-v2-alignment.md, phase 5).

Content isn't interface: what people make (designs, decks, photos, video, PDFs as printed) keeps its own colours, so those
engines are left out. A line that must break a rule says why with `// brand-lint: allow <reason>`.
"""
import os, re, sys

ROOT = os.path.join(os.path.dirname(__file__), '..', 'ElevenAm')
# Engines that draw people's content, not 11am's interface.
CONTENT = ('Features/Canvas/', 'Media/', 'Features/Files/ImageKit.swift', 'Features/Files/FileBrowser.swift',
           'Features/PDF/PDFEngine.swift', 'Features/Documents/DocRender.swift', 'Features/Documents/DocxWriter.swift',
           'Features/Documents/DocumentKit.swift', 'Features/Photo/', 'Features/Video/VideoRender', 'Features/Video/VideoKit',
           'Features/Sheets/Grid', 'Features/Mail/', 'Features/Money/LedgerKit.swift', 'Features/Build/TerminalKit.swift')
ICON_FILES = ('Design/Icons.swift',)
HUES = r'(red|green|blue|orange|yellow|purple|pink|teal|mint|indigo|cyan|brown|gray|grey)'

RULES = [
    ('system symbol', r'Image\(systemName:', 'draw it as a line icon: Icon("name"), or Image.brand("name") in menus', ICON_FILES),
    ('system symbol label', r'systemImage:\s*"', 'use Label { Text(...) } icon: { Icon("name") }', ICON_FILES + ('Design/Components.swift',)),
    ('system font', r'\.font\(\.system\(', 'use BrandFont or .brand(size:)', ()),
    ('literal colour', r'\bColor\(red:|NSColor\((calibrated|srgb|device)?[rR]ed:', 'the brand has two colours: use BrandTokens or theme.ink/paper', ('Design/BrandTokens.swift',)),
    ('hue', r'(?<![\w.])(Color|NSColor)?\.(system)?' + HUES + r'\b(?!:)(?!Component)', 'no hue in the interface: use ink, fill, weight or position', ()),
    ('accent colour', r'\.accentColor|NSColor\.controlAccentColor', 'no accent colour: use ink', ()),
    ('tint', r'\.tint\((?!theme\.ink|BrandTokens\.ink|ink\b)', 'tint with ink only', ()),
    ('faded text', r'\.foreground(Style|Color)\([^)\n]*\.opacity\(', 'text stays at full strength: go under vellum to recede', ()),
    ('shouted label', r'Text\([^)\n]*\.uppercased\(\)', 'labels are lowercase Courier; everything else sentence case', ()),
    ('corner radius', r'cornerRadius:\s*[1-9]', 'corners come from BrandTokens (square, row 8, notice 12, drop 36)', ('Design/BrandTokens.swift',)),
    ('focus ring removed', r'focusEffectDisabled|focusRingType\s*=\s*\.none', 'focus rings are never removed', ()),
]

# Text on each surface it sits on: (name, text, surface) as sRGB 0-255, with the surface already composited.
INK, PAPER = (10, 10, 10), (255, 255, 255)
def over(top, alpha, below): return tuple(round(t * alpha + b * (1 - alpha)) for t, b in zip(top, below))
PAIRS = [
    ('ink on paper', INK, PAPER),
    ('paper on ink', PAPER, INK),
    ('ink on a note over ink', INK, over(PAPER, 0.82, INK)),
    ('ink on a note over paper', INK, over(PAPER, 0.82, PAPER)),
    ('paper on sheet-ink over ink', PAPER, over(PAPER, 0.12, INK)),
    ('paper on sheet-ink over the drop', PAPER, over(PAPER, 0.12, (0, 0, 0))),
    ('ink on the drop\'s white notices', INK, PAPER),
]

def luminance(rgb):
    def channel(c):
        c = c / 255
        return c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4
    r, g, b = (channel(c) for c in rgb)
    return 0.2126 * r + 0.7152 * g + 0.0722 * b

def contrast(a, b):
    la, lb = sorted((luminance(a), luminance(b)), reverse=True)
    return (la + 0.05) / (lb + 0.05)

def lint():
    problems = []
    for dirpath, _, files in os.walk(ROOT):
        for name in files:
            if not name.endswith('.swift'): continue
            path = os.path.join(dirpath, name)
            rel = os.path.relpath(path, ROOT)
            if rel.startswith(CONTENT) or any(rel.startswith(c) for c in CONTENT): continue
            for number, line in enumerate(open(path, encoding='utf-8'), 1):
                code = line.split('//')[0] if '"' not in line.split('//')[0][-1:] else line
                if 'brand-lint: allow' in line: continue
                stripped = line.strip()
                if stripped.startswith('//') or stripped.startswith('///'): continue
                for rule, pattern, advice, allowed in RULES:
                    if rel in allowed: continue
                    if re.search(pattern, code):
                        problems.append(f'{rel}:{number}: {rule}: {advice}\n    {stripped[:140]}')
    return problems

if __name__ == '__main__':
    problems = lint()
    for name, text, surface in PAIRS:
        ratio = contrast(text, surface)
        print(f'contrast {name}: {ratio:.1f}:1')
        if ratio < 4.5: problems.append(f'contrast: {name} is {ratio:.1f}:1, under 4.5:1')
    for problem in problems: print(problem)
    print(f'brand lint: {len(problems)} problem{"s" if len(problems) != 1 else ""}')
    sys.exit(1 if problems else 0)
