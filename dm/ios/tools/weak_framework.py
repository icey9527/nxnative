"""Turn a required framework into a weak one in a linked Mach-O executable.

    weak_framework.py <executable> <framework name> [...]

Why: MetalFX is iOS 16+, but the host imports its header (and clang's module
autolink emits a required LC_LOAD_DYLIB whatever the link flags say). On an
iOS 15 device dyld then aborts before main ("Library not loaded:
/System/Library/Frameworks/MetalFX.framework/MetalFX"). The code already
tests the feature at run time; only the load command has to be weak.
"""
import struct
import sys

LC_LOAD_DYLIB = 0xC
LC_LOAD_WEAK_DYLIB = 0x8000001F


def patch(path, names):
    with open(path, 'r+b') as f:
        head = f.read(32)
        if len(head) < 32:
            raise SystemExit(f'{path}: too short for a Mach-O header')
        magic = struct.unpack_from('<I', head, 0)[0]
        if magic != 0xFEEDFACF:
            raise SystemExit(f'{path}: not a thin 64-bit Mach-O (magic {magic:#x})')
        ncmds = struct.unpack_from('<I', head, 16)[0]
        f.seek(32)
        off = 32
        changed = []
        for _ in range(ncmds):
            f.seek(off)
            cmd, size = struct.unpack('<II', f.read(8))
            if size < 8:
                raise SystemExit(f'{path}: bad load command size at {off:#x}')
            if cmd in (LC_LOAD_DYLIB, LC_LOAD_WEAK_DYLIB):
                f.seek(off + 8)
                name_off = struct.unpack('<I', f.read(4))[0]
                f.seek(off + name_off)
                raw = f.read(size - name_off).split(b'\0', 1)[0].decode('utf-8', 'replace')
                if any(n in raw for n in names) and cmd == LC_LOAD_DYLIB:
                    f.seek(off)
                    f.write(struct.pack('<I', LC_LOAD_WEAK_DYLIB))
                    changed.append(raw)
            off += size
    for c in changed:
        print(f'weak: {c}')
    if not changed:
        print('weak: nothing to change (already weak or not linked)')
    return changed


if __name__ == '__main__':
    if len(sys.argv) < 3:
        raise SystemExit('usage: weak_framework.py <executable> <framework name> [...]')
    patch(sys.argv[1], sys.argv[2:])
