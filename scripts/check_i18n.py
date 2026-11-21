#!/usr/bin/env python3
"""Uygulamadaki her t('Türkçe', 'English') metninin l10n.dart'ta tüm dillerde çevirisi var mı denetler."""
import re, sys, pathlib
root = pathlib.Path(__file__).resolve().parent.parent / 'lib'
def parse_literal(src, i):
    """Dart string literal(s) starting at src[i] (adjacent literals concatenated). Returns (value, raw, end, interpolated)."""
    val, raw, interp = '', '', False
    while True:
        while i < len(src) and src[i] in ' \n\t': i += 1
        rawflag = False
        if src[i] == 'r' and src[i+1] in '\'"':
            rawflag = True; i += 1
        if i >= len(src) or src[i] not in '\'"': break
        q = src[i]; j = i + 1; out = ''
        while src[j] != q:
            c = src[j]
            if c == '\\' and not rawflag:
                n = src[j+1]
                out += {'n': '\n', 't': '\t', '\\': '\\', "'": "'", '"': '"', '$': '$'}.get(n, n); j += 2; continue
            if c == '$' and not rawflag:
                interp = True
            out += c; j += 1
        raw += src[i:j+1]; val += out; i = j + 1
    return val, raw, i, interp

found = []
for f in sorted(root.rglob('*.dart')):
    src = f.read_text()
    for m in re.finditer(r'(?<![A-Za-z0-9_.])t\(', src):
        i = m.end()
        try:
            tr, rtr, i, i1 = parse_literal(src, i)
            while src[i] in ' \n\t': i += 1
            if src[i] != ',': continue
            en, ren, i, i2 = parse_literal(src, i + 1)
        except IndexError:
            continue
        if not ren: continue
        found.append({'file': str(f.relative_to(root)), 'tr': tr, 'en': en, 'interp': i1 or i2, 'raw_en': ren})

l10n = (root / 'l10n.dart').read_text()
langs = re.findall(r"^  '(\w\w)': \{", l10n, re.M)
blocks = re.split(r"^  '\w\w': \{", l10n, flags=re.M)[1:]
def keys_of(block):
    out = set()
    for m in re.finditer(r"^    '((?:[^'\\]|\\.)*)': ", block, re.M):
        out.add(m.group(1).replace("\\'", "'").replace('\\$', '$').replace('\\n', '\n').replace('\\\\', '\\'))
    return out
table = dict(zip(langs, map(keys_of, blocks)))
bad = 0
for x in found:
    if x['interp']:
        print(f"HATA {x['file']}: metin içinde değişken var, {{0}} yer tutucusu kullan: {x['raw_en'][:80]}"); bad += 1
        continue
    for L in langs:
        if L == 'tr': continue
        if x['en'] not in table[L]:
            print(f"EKSİK [{L}] {x['file']}: {x['en'][:80]}"); bad += 1
print(f"{len(found)} metin, {len(langs)} dil tablosu: " + ("sorun yok" if bad == 0 else f"{bad} sorun"))
sys.exit(1 if bad else 0)
