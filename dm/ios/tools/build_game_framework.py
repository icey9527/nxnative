#!/usr/bin/env python3
"""Build a TonTon Route C code framework from already rewritten modules.

Inspired by NX2Apple patches 0045–0051 (MIT). This adapter preserves this
fork's signed __TEXT layout and shader chain, rather than relabelling newer
upstream output. Game assets and saves stay outside the framework.
"""
import argparse
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[3]
TOOLS = Path(__file__).resolve().parent


def build(args):
    title = args.game.upper()
    if not re.fullmatch(r'[0-9A-F]{16}', title):
        raise ValueError('game must be a 16-digit title ID')
    if not re.fullmatch(r'[0-9]+(?:\.[0-9]+){0,2}', args.min_os):
        raise ValueError('min-os must be a numeric OS version')
    if not args.modules or any(not re.fullmatch(r'[A-Za-z0-9]+', m) for m in args.modules):
        raise ValueError('module names must contain only ASCII letters and digits')
    if len(args.modules) != len(set(args.modules)):
        raise ValueError('duplicate modules')
    patched = args.patched.resolve(strict=True)
    nro = patched / 'nro.tsv'
    if nro.exists() and any(l.strip() and not l.startswith(('#', 'refused\t')) for l in nro.read_text().splitlines()):
        raise ValueError('packed NRO frameworks require a matching NRO loader, not yet supported')
    for module in args.modules:
        for suffix in ['patched.bin', 'fixups.tsv', 'gates.tsv', 'obs.tsv', 'cuts.tsv']:
            if not (patched / f'{module}.{suffix}').is_file():
                raise ValueError(f'missing module input {module}.{suffix}')
    chain = re.search(r'^#define DMSH_CHAIN "([0-9a-f]+)"',
                      (ROOT / 'dm/gfx/nvn/dmsh_chain.h').read_text(), re.M).group(1)
    name = f'DmGame{title}.framework'
    out = args.output.resolve()
    if out.exists():
        raise ValueError(f'output already exists: {out}, retained for inspection')
    out.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='tonton-game-framework-', dir=out.parent) as temp:
        work = Path(temp)
        fw = work / name
        (fw / 'dm').mkdir(parents=True)
        asm = work / 'embed.S'
        flags = subprocess.check_output([sys.executable, str(TOOLS / 'gen_embed.py'),
                                         str(patched), str(asm), *args.modules], text=True).split()
        marker = work / 'marker.c'
        marker.write_text('__attribute__((visibility("default"),used)) const unsigned char dm_game_image_marker = 1;\n')
        sdk = subprocess.check_output(['xcrun', '--sdk', 'iphoneos', '--show-sdk-path'], text=True).strip()
        subprocess.run(['xcrun', '--sdk', 'iphoneos', 'clang', '-target',
                        f'arm64-apple-ios{args.min_os}', '-isysroot', sdk, '-dynamiclib',
                        '-fvisibility=hidden', '-Wl,-install_name,@rpath/' + name + '/DmGame',
                        *flags, str(marker), str(asm), '-o', str(fw / 'DmGame')], check=True)
        subprocess.run([sys.executable, str(TOOLS / 'set_text_maxprot.py'), str(fw / 'DmGame')], check=True)
        for module in args.modules:
            for suffix in ['fixups.tsv', 'gates.tsv', 'obs.tsv', 'cuts.tsv']:
                shutil.copyfile(patched / f'{module}.{suffix}', fw / 'dm' / f'{module}.{suffix}')
        manifest = dict(schema=1, title_id=title, name=args.name or title,
                        display_version=args.display_version, package_version=args.package_version,
                        modules=args.modules, nro_count=0, chain='b-' + chain, loader='FR',
                        framework=name, framework_executable='DmGame', image_marker='dm_game_image_marker',
                        min_os=args.min_os, tonton_host_abi='tonton-signed-text-v1')
        (fw / 'game.manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n')
        (fw / 'Info.plist').write_bytes(plistlib.dumps(dict(CFBundleExecutable='DmGame',
            CFBundleIdentifier='com.tonytan.game.' + title.lower(), CFBundlePackageType='FMWK',
            CFBundleVersion='1', CFBundleShortVersionString='1.0', MinimumOSVersion=args.min_os)))
        # Ad-hoc is a staging signature. The complete app installer must sign
        # nested code with the same device-valid identity as the containing app.
        subprocess.run(['codesign', '--force', '--sign', '-', str(fw)], check=True)
        subprocess.run(['codesign', '--verify', '--strict', str(fw)], check=True)
        os.rename(fw, out)
    return manifest


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--game', required=True)
    ap.add_argument('--patched', type=Path, required=True)
    ap.add_argument('--output', type=Path, required=True)
    ap.add_argument('--modules', nargs='+', required=True)
    ap.add_argument('--name')
    ap.add_argument('--min-os', default='16.1')
    ap.add_argument('--display-version', default='')
    ap.add_argument('--package-version', default='')
    args = ap.parse_args()
    try:
        print(json.dumps(build(args), ensure_ascii=False, indent=2))
    except (ValueError, OSError, subprocess.CalledProcessError) as e:
        ap.exit(1, f'{e}\n')


if __name__ == '__main__':
    main()
