#!/bin/bash
# Put everything makepkg needs for open-vm-tools-wayland in one directory.
#
#   packaging/arch/prepare.sh OUTDIR
#
# Copies the PKGBUILD, the files it takes from Arch's and Fedora's packages
# and every patch in patches/ into OUTDIR. It fails if the PKGBUILD's
# _patches list differs from patches/.

set -euo pipefail
export LC_ALL=C

[ "$#" -eq 1 ] || { echo "usage: $0 OUTDIR" >&2; exit 2; }
here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/../.." && pwd)"
mkdir -p "$1"
out="$(cd "$1" && pwd)"

want="$(cd "$repo/patches" && ls -1 -- *.patch)"
have="$(sed -n '/^_patches=(/,/^)/p' "$here/PKGBUILD" | grep -oE "[0-9]{4}-[A-Za-z0-9._-]+\.patch")"
if [ "$want" != "$have" ]; then
    echo "ERROR: _patches in PKGBUILD does not match patches/" >&2
    diff <(echo "$have") <(echo "$want") >&2 || true
    exit 1
fi

cp "$here/PKGBUILD" "$here/vmtoolsd.pam" "$here/vmtoolsd.service" \
   "$here/vmware-vmblock-fuse.service" "$here/open-vm-tools-gcc16.patch" \
   "$here/open-vm-tools-sigc++3.patch" "$repo"/patches/*.patch "$out/"
