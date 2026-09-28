#!/bin/bash
# Build the open-vm-tools-wayland Arch package in a container.
#
#   podman run --rm -v "$PWD":/src:ro,z -v "$PWD/out":/out:z \
#       docker.io/library/archlinux:latest /src/packaging/arch/build.sh /out
#
# Run from the repository root. It installs base-devel, builds as an
# unprivileged user with makepkg, checks the plugin for one log string per
# patch group, installs the package to prove it resolves, and copies
# open-vm-tools-wayland-<epoch>:<version>-x86_64.pkg.tar.zst to the output
# directory. The debug package is left out.

set -euo pipefail
export LC_ALL=C

[ "$#" -eq 1 ] || { echo "usage: $0 OUTDIR" >&2; exit 2; }
out="$1"
mkdir -p "$out"
here="$(cd "$(dirname "$0")" && pwd)"

pacman -Syu --noconfirm --needed base-devel git sudo

id builder >/dev/null 2>&1 || useradd -m builder
echo 'builder ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/builder
work="$(mktemp -d)"
chown builder "$work"

sudo -u builder "$here/prepare.sh" "$work/pkg"
(
    cd "$work/pkg"
    sudo -u builder env BUILDDIR="$work/build" PKGDEST="$work/pkgs" \
        makepkg --syncdeps --noconfirm
)

set -- "$work"/pkgs/open-vm-tools-wayland-[0-9]*.pkg.tar.zst
test "$#" -eq 1 || { echo "ERROR: expected one package, got $#: $*" >&2; exit 1; }
pkg="$1"

# The patched sources are the only place these strings come from, so a
# package that lost a patch fails here.
so=usr/lib/open-vm-tools/plugins/vmusr/libdndcp.so
tmp="$(mktemp -d)"
bsdtar -xf "$pkg" -C "$tmp" "$so"
# Save the strings once. With pipefail, strings | grep -q fails when grep
# exits early and strings gets SIGPIPE.
strings "$tmp/$so" > "$tmp/strings"
for s in 'unsafe fileItem' 'no XDG_CURRENT_DESKTOP' 'drag entering, telling the host' \
         'using ext-data-control-v1' 'wl-copy is not installed' \
         'paste observed, requesting files' 'native drag source ready' \
         'Mutter bridges XDND' 'native drop target shown on' 'PruneStagingDirectories'; do
    grep -qF "$s" "$tmp/strings" || { echo "ERROR: plugin lacks '$s'" >&2; exit 1; }
done
rm -rf "$tmp"
echo "patched dndcp verified"

pacman -U --noconfirm "$pkg"
pacman -Q open-vm-tools-wayland
# vmtoolsd exits before reading its options outside a VMware VM, so check
# that it and the plugin link instead of running them.
for f in /usr/bin/vmtoolsd /usr/lib/open-vm-tools/plugins/vmusr/libdndcp.so; do
    if ldd "$f" | grep "not found"; then exit 1; fi
done

cp "$pkg" "$out/"
ls -l "$out"
