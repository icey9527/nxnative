#!/bin/bash
# Xcode target phase: copy the active game's resources into the app before CodeSign.
# Paths come from build_ipa.sh, not from a per-game rule or a phone-visible Mac path.
set -eu
[ "${DM_COPY_GAME_RESOURCES:-YES}" != NO ] || exit 0
die() { echo "[RED] $*" >&2; exit 1; }
[ "${PLATFORM_NAME:-}" = iphoneos ] || die 'This game needs a physical iPhone or iPad; choose a device, not a simulator.'
[ -f "${SRCROOT:?}/Gen/resources.env" ] || die 'Missing game resource paths; run build_ipa_from_nsp.py --prepare-xcode first.'
source "$SRCROOT/Gen/resources.env"
APP="${TARGET_BUILD_DIR:?}/${UNLOCALIZED_RESOURCES_FOLDER_PATH:?}"
case "$APP" in /*.app) ;; *) die "Unexpected app resource destination: $APP";; esac
# Validate every source before copying or removing anything (the external drive may be disconnected).
resource_dm=$(python3 -c 'import pathlib,sys; print(pathlib.Path(sys.argv[1]).resolve().parents[2])' "$0")
[ "${DM_NO_ROMFS_CHECK:-0}" = 1 ] || python3 "$resource_dm/tools/romfs.py" "$DM_RESOURCE_ROMFS" "$DM_RESOURCE_MARKER" || die "Game files unavailable: $DM_RESOURCE_ROMFS/$DM_RESOURCE_MARKER"   # DM_NO_ROMFS_CHECK=1: DM_COPY_ROMFS=NO builds made without the image
[ -d "$DM_RESOURCE_SHADERS" ] || die "Shader libraries unavailable: $DM_RESOURCE_SHADERS"
[ -z "$DM_RESOURCE_AOC" ] || [ -d "$DM_RESOURCE_AOC" ] || die "Add-on content unavailable: $DM_RESOURCE_AOC"
DM_RESOURCE_PSO=${DM_RESOURCE_PSO:-}   # (a project prepared before the pipeline archive has none)
[ -z "$DM_RESOURCE_PSO" ] || [ -f "$DM_RESOURCE_PSO/prebuilt.tsv" ] || die "Pipeline archive unavailable: $DM_RESOURCE_PSO"
echo 'Copy game resources (the first build copies the complete game; later builds sync changes)'
# A first copy into an empty place is an APFS clone (cp -c, clonefile): the game's files take no more disk space until either side changes, where rsync wrote all of them again
# (BotW's app is 16.5 GB; a full copy filled a Mac that had 13 GB free). cp falls back to a plain copy on a volume without clones. Later builds sync with rsync as before
sync_dir() {   # source folder, destination folder
    if [ ! -d "$2" ] || [ -z "$(ls -A "$2" 2>/dev/null)" ]; then mkdir -p "$2"; /bin/cp -cRp -- "$1/." "$2/" || die "copy $1 to $2"
    else /usr/bin/rsync -a --delete -- "$1/" "$2/" || die "sync $1 to $2"; fi
}
sync_romfs() {   # the RomFS (an image file or a folder), the app folder it goes in
    if [ -f "$1" ]; then
        if [ -f "$2/romfs.img" ]; then /usr/bin/rsync -a -- "$1" "$2/romfs.img"; else /bin/cp -cp -- "$1" "$2/romfs.img" || die "copy $1"; fi
        rm -rf "$2/romfs"; rm -f "$2/romfs.id"
    else
        sync_dir "$1" "$2/romfs"
        rm -f "$2/romfs.img" "$2/romfs.id"
    fi
}
if [ -n "$DM_RESOURCE_PROGRAMS" ]; then
    # A game of several programs (build_ipa.sh PROGRAMS_TSV): each program's RomFS, offline pages and nn::jit image in p<index>/, its shader libraries in msl/p<index>/, as the IPA has them (main.m)
    rm -rf "$APP/romfs" "$APP/romfs.img" "$APP/romfs.id" "$APP/html" "$APP/jit"   # one program's, from a project prepared for one program
    keep=' '
    while IFS=$'\t' read -r pn romfs marker shaders msldir; do
        mkdir -p "$APP/p$pn" "$APP/msl/p$pn/$msldir"
        sync_romfs "$romfs" "$APP/p$pn"
        sync_dir "$shaders" "$APP/msl/p$pn/$msldir"
        for old in "$APP/msl/p$pn/"*; do [ "$old" = "$APP/msl/p$pn/$msldir" ] || rm -rf "$old"; done
        beside_romfs "$romfs" "$APP/p$pn"
        keep="$keep p$pn "
    done < <(prog_rows)
    for old in "$APP"/p[0-9]* "$APP/msl/"*; do [ -e "$old" ] || continue; case "$keep" in *" $(basename "$old") "*) ;; *) rm -rf "$old";; esac; done
else
mkdir -p "$APP/msl/$DM_RESOURCE_MSLDIR"
# DM_COPY_ROMFS=NO: the game files stay out of the app (main.m takes Documents/romfs first, copied there once): a reinstall then sends the code and shaders, not the whole game
if [ "${DM_COPY_ROMFS:-YES}" = NO ]; then
    rm -rf "$APP/romfs" "$APP/romfs.img" "$APP/romfs.id"
    # the image's identity (dm/host/romfs_identity.h): main.m uses only a Documents/romfs.img that matches it; a RomFS folder has none yet (push_romfs.sh packs it), so no identity is written for it
    if [ -f "$DM_RESOURCE_ROMFS" ]; then
        python3 -I "$resource_dm/tools/romfs_image.py" --identity "$DM_RESOURCE_ROMFS" "${DM_RESOURCE_TITLE:-}" "${DM_RESOURCE_VERSION:-}" "${DM_RESOURCE_BUILD:-}" > "$APP/romfs.id" || die "identity of $DM_RESOURCE_ROMFS"
    fi
else sync_romfs "$DM_RESOURCE_ROMFS" "$APP"; fi
sync_dir "$DM_RESOURCE_SHADERS" "$APP/msl/$DM_RESOURCE_MSLDIR"
for old in "$APP/msl/"*; do
    [ "$old" = "$APP/msl/$DM_RESOURCE_MSLDIR" ] || rm -rf "$old"
done
beside_romfs "$DM_RESOURCE_ROMFS" "$APP"
for old in "$APP"/p[0-9]*; do [ -d "$old" ] && rm -rf "$old"; done   # the programs of a project prepared for several
fi
if [ -n "$DM_RESOURCE_AOC" ]; then
    sync_dir "$DM_RESOURCE_AOC" "$APP/aoc"
else
    rm -rf "$APP/aoc"
fi
# The pipeline archive made offline (the shader pairs' bases, build_ipa.sh): the app hands <App>/pso to the host as DM_PSO_BUNDLE
if [ -n "$DM_RESOURCE_PSO" ]; then
    sync_dir "$DM_RESOURCE_PSO" "$APP/pso"
else
    rm -rf "$APP/pso"
fi
