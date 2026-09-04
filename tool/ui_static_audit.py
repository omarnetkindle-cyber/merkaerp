#!/usr/bin/env python3
"""Static UI consistency audit for MerkaERP.

This is intentionally conservative: it catches regressions that can be verified
without a Flutter runtime. It does not replace widget/golden/accessibility tests.
"""
from __future__ import annotations
from pathlib import Path
import re, sys

ROOT = Path(__file__).resolve().parents[1]
LIB = ROOT / 'lib'
DARTS = sorted(LIB.rglob('*.dart'))
PAGES = sorted([p for p in DARTS if p.name.endswith(('page.dart', 'screen.dart'))])
issues: list[str] = []

# 1. Retired legacy corporate teal must not return.
for p in PAGES:
    text = p.read_text('utf-8', errors='ignore')
    if '0xFF006D77' in text or '#006D77' in text:
        issues.append(f'legacy teal: {p.relative_to(ROOT)}')

# 2. Large fixed dialogs/panels were a source of clipping on small screens.
large_dim = re.compile(r'\b(?:width\s*:\s*(?:7\d\d|8\d\d|9\d\d|[1-9]\d{3,})|height\s*:\s*(?:6\d\d|7\d\d|8\d\d|9\d\d|[1-9]\d{3,}))')
for p in PAGES:
    text = p.read_text('utf-8', errors='ignore')
    if large_dim.search(text):
        issues.append(f'large fixed dimension: {p.relative_to(ROOT)}')

# 3. Every IconButton exposed from a page must explain itself to novice users.
# This parser uses balanced parentheses so nested widgets do not create false positives.
def blocks(text: str, token: str):
    start = 0
    while True:
        i = text.find(token, start)
        if i < 0: return
        j = text.find('(', i + len(token))
        if j < 0: return
        depth = 0
        in_str = None
        escaped = False
        k = j
        while k < len(text):
            ch = text[k]
            if in_str:
                if escaped: escaped = False
                elif ch == '\\': escaped = True
                elif ch == in_str: in_str = None
            else:
                if ch in "'\"": in_str = ch
                elif ch == '(': depth += 1
                elif ch == ')':
                    depth -= 1
                    if depth == 0:
                        yield i, k + 1, text[i:k+1]
                        start = k + 1
                        break
            k += 1
        else:
            return

for p in PAGES:
    text = p.read_text('utf-8', errors='ignore')
    for i, _, block in blocks(text, 'IconButton'):
        if 'tooltip:' not in block:
            line = text.count('\n', 0, i) + 1
            issues.append(f'IconButton without tooltip: {p.relative_to(ROOT)}:{line}')

# 4. Long top tab sets must be horizontally scrollable.
for p in PAGES:
    text = p.read_text('utf-8', errors='ignore')
    for i, _, block in blocks(text, 'TabBar'):
        tab_count = len(re.findall(r'\bTab\s*\(', block))
        if tab_count >= 4 and 'isScrollable: true' not in block:
            line = text.count('\n', 0, i) + 1
            issues.append(f'TabBar with {tab_count} tabs not scrollable: {p.relative_to(ROOT)}:{line}')

# 5. Decorative hues outside the corporate/semantic family should not creep back
# anywhere in visible/shared UI code. blueGrey is allowed only for the explicit
# Go-Live "No aplica" state.
legacy_hues = re.compile(r'Colors\.(purple|teal|cyan|indigo|brown|pink|deepPurple|blue|blueGrey)\b')
for p in DARTS:
    text = p.read_text('utf-8', errors='ignore')
    for m in legacy_hues.finditer(text):
        if p.as_posix().endswith('core/go_live/go_live_page.dart') and m.group(1) == 'blueGrey':
            continue
        line = text.count('\n', 0, m.start()) + 1
        issues.append(f'non-brand decorative hue {m.group(0)}: {p.relative_to(ROOT)}:{line}')

# 6. Brand colors are centralized. Raw RGB literals are allowed only in the two
# token/theme sources that define the palette itself.
raw_color = re.compile(r'Color\(0xFF[0-9A-Fa-f]{6}\)')
raw_allow = {
    (LIB / 'ui' / 'merka_theme_tokens.dart').resolve(),
    (LIB / 'core' / 'theme' / 'app_theme.dart').resolve(),
}
for p in DARTS:
    if p.resolve() in raw_allow:
        continue
    text = p.read_text('utf-8', errors='ignore')
    for m in raw_color.finditer(text):
        line = text.count('\n', 0, m.start()) + 1
        issues.append(f'raw color outside theme tokens: {p.relative_to(ROOT)}:{line} {m.group(0)}')

print(f'UI static audit: {len(PAGES)} Page/Screen files + {len(DARTS)} Dart files palette-scanned.')
if issues:
    print(f'FAILED: {len(issues)} issue(s)')
    for issue in issues:
        print(f'- {issue}')
    sys.exit(1)
print('PASS: no audited UI consistency regressions found.')
print('Scope: full-lib palette + Page/Screen clipping, novice tooltips, long TabBars and retired decorative hues.')
print('Reminder: this does not replace Flutter widget/golden/accessibility testing on a real toolchain.')
