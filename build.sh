#!/usr/bin/env bash
set -euo pipefail
tag=$1 name=$2 host=$3
shift 3
root=$PWD
dist=$root/dist
work=$root/build/$name
cache=$root/deps/$host
mkdir -p "$dist"

rm -rf "$work"
git -c advice.detachedHead=false clone -q --depth 1 --branch "$tag" https://github.com/fwup-home/fwup "$work"
if [ -d "$cache" ]; then
    mkdir -p "$work/build/$host"
    cp -R "$cache" "$work/build/$host/deps"
fi

mkdir -p "$work/bin"
printf '#!/bin/sh\nexec %s "$@"\n' "$*" > "$work/bin/$host-gcc"
chmod +x "$work/bin/$host-gcc"
export PATH=$work/bin:$PATH

cd "$work"
./autogen.sh
CROSS_COMPILE=$host scripts/build_deps.sh
rm -rf "$cache"
mkdir -p "$root/deps"
cp -R "$work/build/$host/deps" "$cache"
deps=$work/build/$host/deps/usr/lib/pkgconfig
PKG_CONFIG_PATH=$deps PKG_CONFIG_LIBDIR=$deps ./configure --host="$host" --enable-shared=no

case $host in
    *-darwin)
        make -j"$(sysctl -n hw.ncpu)"
        exe=src/fwup
        strip "$exe"
        # Stripping breaks the ad-hoc signature Apple Silicon refuses to run without.
        codesign -f -s - "$exe"
        ;;
    *)
        make -j"$(nproc)" LDFLAGS=-s
        exe=src/fwup
        [[ $host == *-mingw32 ]] && exe=src/fwup.exe
        ;;
esac
out=$dist/fwup-$name${exe#src/fwup}
cp "$exe" "$out"

case $(uname -sm) in
    "Linux x86_64") native=linux-amd64 ;;
    "Darwin arm64") native=macos-arm64 ;;
    *) native= ;;
esac
if [ "$name" = "$native" ]; then
    [ "$("$out" --version)" = "${tag#v}" ] || { echo "build: $out does not report ${tag#v}" >&2; exit 1; }
fi

zig=$(dirname "$(command -v zig 2>/dev/null || echo .)")
{
    for f in LICENSE src/3rdparty/*/LICEN[CS]E* build/"$host"/deps/*/LICENSE build/"$host"/deps/*/COPYING; do
        printf '\n==> %s <==\n\n' "$f"
        cat "$f"
    done
    case $host in
        *-linux-musl) runtime=("$zig/LICENSE" "$zig/lib/libc/musl/COPYRIGHT") ;;
        *-mingw32) runtime=("$zig/LICENSE" "$zig/lib/libc/mingw/COPYING") ;;
        *) runtime=() ;;
    esac
    for f in ${runtime[@]+"${runtime[@]}"}; do
        printf '\n==> zig/%s <==\n\n' "${f#"$zig"/}"
        cat "$f"
    done
} > "$dist/fwup-$name-LICENSES.txt"
