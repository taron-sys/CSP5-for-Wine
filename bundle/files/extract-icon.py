#!/usr/bin/env python3
"""extract-icon.py — program icon of a Windows EXE as PNG (several sizes).

Usage:    extract-icon.py EXE ICONDIR NAME

Writes ICONDIR/<N>x<N>/apps/NAME.png (hicolor layout) and prints the sizes written.
Needed for the menu entries (install.sh): Wine only creates its own icons when it
processes a shortcut itself — and the names are hashes and often missing. Standard
library only (icoutils/wrestool are not commonly installed).

The main icon is, like on Windows, the icon group with the smallest ID.
Entries are 32-bit BMP (DIB with alpha) or PNG.
"""
import os, struct, sys, zlib

SIZES = (16, 32, 48, 64, 96, 128, 256)


def pe_resources(d):
    pe = struct.unpack_from('<I', d, 0x3c)[0]
    if d[pe:pe + 4] != b'PE\0\0':
        raise ValueError('not a PE file')
    nsec = struct.unpack_from('<H', d, pe + 6)[0]
    osz = struct.unpack_from('<H', d, pe + 20)[0]
    opt = pe + 24
    magic = struct.unpack_from('<H', d, opt)[0]
    dd = opt + (112 if magic == 0x20b else 96)
    rva, size = struct.unpack_from('<II', d, dd + 16)    # IMAGE_DIRECTORY_ENTRY_RESOURCE
    if not rva:
        raise ValueError('no resources')
    secs = []
    so = opt + osz
    for i in range(nsec):
        _, vs, va, rs, ro = struct.unpack_from('<8sIIII', d, so + i * 40)
        secs.append((va, max(vs, rs), ro))

    def off(r):
        for va, ln, ro in secs:
            if va <= r < va + ln:
                return r - va + ro
        raise ValueError('RVA out of range')

    base = off(rva)

    def entries(o):
        nn, ni = struct.unpack_from('<HH', d, o + 12)
        return [struct.unpack_from('<II', d, o + 16 + i * 8) for i in range(nn + ni)]

    def ids(x):                      # {numeric ID: reference} of a directory
        o = base + (x & 0x7fffffff)
        return {n: y for n, y in entries(o) if not n & 0x80000000}

    def leaf(x):
        o = base + (x & 0x7fffffff)
        if x & 0x80000000:           # subdirectory -> first language
            return leaf(entries(o)[0][1])
        rv, sz = struct.unpack_from('<II', d, o)
        fo = off(rv)
        return d[fo:fo + sz]

    top = {n: y for n, y in entries(base) if not n & 0x80000000}
    return top, ids, leaf


def png_chunk(t, b):
    return struct.pack('>I', len(b)) + t + b + struct.pack('>I', zlib.crc32(t + b) & 0xffffffff)


def dib_to_png(dib):
    hs, w, h2, planes, bpp = struct.unpack_from('<IiiHH', dib, 0)
    h = h2 // 2                      # height includes the AND mask
    if bpp not in (24, 32) or w <= 0 or h <= 0:
        return None
    px = dib[hs:]
    stride = ((w * bpp + 31) // 32) * 4
    maskstride = ((w + 31) // 32) * 4
    maskoff = stride * h
    rows = []
    for y in range(h - 1, -1, -1):   # bottom-up -> top-down
        row = bytearray(b'\0')       # PNG-Filter 0
        line = px[y * stride:(y + 1) * stride]
        for x in range(w):
            if bpp == 32:
                b, g, r, a = line[x * 4:x * 4 + 4]
            else:
                b, g, r = line[x * 3:x * 3 + 3]
                m = px[maskoff + y * maskstride + x // 8] if maskoff < len(px) else 0
                a = 0 if (m >> (7 - x % 8)) & 1 else 255
            row += bytes((r, g, b, a))
        rows.append(bytes(row))
    ihdr = struct.pack('>IIBBBBB', w, h, 8, 6, 0, 0, 0)
    return (b'\x89PNG\r\n\x1a\n' + png_chunk(b'IHDR', ihdr)
            + png_chunk(b'IDAT', zlib.compress(b''.join(rows), 9)) + png_chunk(b'IEND', b''))


def main(argv):
    if len(argv) != 4:
        print(__doc__)
        return 2
    exe, icondir, name = argv[1:]
    d = open(exe, 'rb').read()
    top, ids, leaf = pe_resources(d)
    groups = ids(top[14])            # RT_GROUP_ICON
    icons = ids(top[3])              # RT_ICON
    grp = leaf(groups[min(groups)])
    count = struct.unpack_from('<H', grp, 4)[0]
    best = {}
    for i in range(count):
        w, h, _, _, _, bpp, _, iid = struct.unpack_from('<BBBBHHIH', grp, 6 + i * 14)
        w = w or 256
        if w not in SIZES or iid not in icons:
            continue
        data = leaf(icons[iid])
        png = data if data[:8] == b'\x89PNG\r\n\x1a\n' else dib_to_png(data)
        if png:
            best[w] = png
    for w, png in sorted(best.items()):
        out = os.path.join(icondir, f'{w}x{w}', 'apps')
        os.makedirs(out, exist_ok=True)
        with open(os.path.join(out, name + '.png'), 'wb') as f:
            f.write(png)
    print(' '.join(str(w) for w in sorted(best)))
    return 0 if best else 1


if __name__ == '__main__':
    try:
        sys.exit(main(sys.argv))
    except Exception as e:                      # never abort the installer

        print(f'extract-icon: {e}', file=sys.stderr)
        sys.exit(1)
