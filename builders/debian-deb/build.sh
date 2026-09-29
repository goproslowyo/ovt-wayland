#!/bin/sh
# Build steps for builders/debian-deb/Containerfile, one per subcommand:
#
#   fetch    download and verify the upstream tarball and Debian's packaging
#   prepare  assemble the source tree and apply the packaging changes
#   build    run dpkg-buildpackage and copy the .debs to /debs
#   check    look for the patched log strings in the built libdndcp.so
#   apt      run apt-get with the given arguments, retrying on failure
#
# The Containerfile sets OVT_VERSION, OVT_BUILD, OVT_SHA256,
# DEBIAN_PKG_VERSION, DEBIAN_SNAPSHOT, DEBIAN_TAR_SHA256, PKG_REV and
# DISTRO_TAG. Work happens in the current directory.

set -eu

: "${OVT_VERSION:?}" "${OVT_BUILD:?}" "${OVT_SHA256:?}"
: "${DEBIAN_PKG_VERSION:?}" "${DEBIAN_SNAPSHOT:?}" "${DEBIAN_TAR_SHA256:?}"
: "${PKG_REV:=1}" "${DISTRO_TAG:=}"

src="open-vm-tools-${OVT_VERSION}"
upstream_tar="open-vm-tools-${OVT_VERSION}-${OVT_BUILD}.tar.gz"
debian_tar="open-vm-tools_${DEBIAN_PKG_VERSION}.debian.tar.xz"

# Download $2 from the first URL in $3... that serves a file with SHA-256 $1.
fetch_verified() {
    sum="$1"; out="$2"; shift 2
    for url in "$@"; do
        echo "fetching $url"
        if curl -fsSL --retry 3 -o "$out.part" "$url" \
            && echo "$sum  $out.part" | sha256sum -c --quiet -; then
            mv "$out.part" "$out"
            return 0
        fi
        echo "WARNING: $url failed or did not match $sum" >&2
        rm -f "$out.part"
    done
    echo "ERROR: no source for $out matched the pinned checksum." >&2
    exit 1
}

distro_tag() {
    if [ -n "$DISTRO_TAG" ]; then
        echo "$DISTRO_TAG"
        return
    fi
    . /etc/os-release
    if [ -n "${VERSION_ID:-}" ]; then
        echo "${ID}${VERSION_ID}"
    else
        echo "${ID}.${VERSION_CODENAME}"
    fi
}

do_fetch() {
    fetch_verified "$OVT_SHA256" "$upstream_tar" \
        "https://github.com/vmware/open-vm-tools/releases/download/stable-${OVT_VERSION}/${upstream_tar}"
    fetch_verified "$DEBIAN_TAR_SHA256" "$debian_tar" \
        "https://snapshot.debian.org/archive/debian/${DEBIAN_SNAPSHOT}/pool/main/o/open-vm-tools/${debian_tar}" \
        "https://deb.debian.org/debian/pool/main/o/open-vm-tools/${debian_tar}"
}

do_prepare() {
    export LC_ALL=C

    # Debian's orig tarball is a snapshot of the upstream git repository, with
    # the sources in open-vm-tools/, and debian/rules builds from there. The
    # release tarball holds only that directory, so unpack it into place.
    rm -rf "$src"
    mkdir -p "$src/open-vm-tools"
    tar -xzf "$upstream_tar" -C "$src/open-vm-tools" --strip-components=1
    tar -xJf "$debian_tar" -C "$src"
    test -f "$src/open-vm-tools/configure.ac"
    test -f "$src/debian/rules"

    got="$(sed -n 's|^TOOLS_VERSION="\(.*\)"$|\1|p' "$src/open-vm-tools/configure.ac")"
    if [ "$got" != "$OVT_VERSION" ]; then
        echo "ERROR: tarball is open-vm-tools $got, expected $OVT_VERSION." >&2
        exit 1
    fi

    cd "$src"

    # Patches this builder carries for Debian's packaging, in the quilt
    # format Debian uses. They apply after Debian's own and before ours.
    mkdir -p debian/patches/ovt-debian
    for f in /debian-patches/*.patch; do
        test -e "$f" || break
        b="$(basename "$f")"
        cp "$f" "debian/patches/ovt-debian/$b"
        echo "ovt-debian/$b" >> debian/patches/series
    done

    # Our patches come from git format-patch inside open-vm-tools/, so their
    # paths lack the open-vm-tools/ prefix that quilt needs here. Rewrite the
    # file headers only, and add each patch to the end of debian/patches/series
    # so that it applies after Debian's own.
    mkdir -p debian/patches/ovt-wayland
    n=0
    for f in /patches/*.patch; do
        test -e "$f" || break
        b="$(basename "$f")"
        if ! printf '%s' "$b" | grep -qE '^[0-9]{4}-[A-Za-z0-9._-]+\.patch$'; then
            echo "ERROR: refusing patch filename: $b" >&2
            echo "Patch filenames must match NNNN-<name>.patch with <name> in [A-Za-z0-9._-]." >&2
            exit 1
        fi
        awk -v p=open-vm-tools/ '
            /^diff --git a\/.* b\// {
                sub(/^diff --git a\//, "diff --git a/" p)
                sub(/ b\//, " b/" p)
                hdr = 1
                print
                next
            }
            hdr && /^--- a\// { sub(/^--- a\//, "--- a/" p) }
            hdr && /^\+\+\+ b\// { sub(/^\+\+\+ b\//, "+++ b/" p) }
            /^@@ / { hdr = 0 }
            { print }
        ' "$f" > "debian/patches/ovt-wayland/$b"
        echo "ovt-wayland/$b" >> debian/patches/series
        n=$((n + 1))
    done
    test "$n" -gt 0

    # Apply the whole series now so that a patch that does not apply fails
    # here. dpkg-source applies quilt patches without fuzz.
    dpkg-source --before-build .

    # Build the desktop plugin against GTK4 with the Wayland backend, as the
    # Fedora package does. --with-wayland makes configure fail rather than
    # build the plugin without it. Debian's 13.0.10 packaging uses GTK3.
    sed -i 's|^\([[:space:]]*\)--with-gtk3[[:space:]]*\\$|\1--with-gtk4 \\\n\1--with-wayland \\|' debian/rules
    grep -q -- '--with-gtk4 \\$' debian/rules
    grep -q -- '--with-wayland \\$' debian/rules
    if grep -q -- '--with-gtk3' debian/rules; then exit 1; fi

    # The release tarball has no ReleaseNotes.md. It is in the git repository
    # that Debian's orig tarball comes from.
    sed -i 's|^\(\tdh_installchangelogs\) ReleaseNotes.md$|\1|' debian/rules
    if grep -q 'ReleaseNotes.md' debian/rules; then exit 1; fi

    sed -i 's|libgtkmm-3.0-dev, libgtk-3-dev,|libgtkmm-4.0-dev, libgtk-4-dev,\n libwayland-dev, wayland-protocols (>= 1.39),|' debian/control
    grep -q '^ libwayland-dev, wayland-protocols (>= 1.39),$' debian/control
    if grep -q 'gtk-3\|gtkmm-3' debian/control; then exit 1; fi

    # Debian's epoch is 2. A 0 revision sorts below a Debian or Ubuntu upload
    # of the same upstream version, and 13.1.0 sorts above the 13.0.10 they
    # ship today.
    . /etc/os-release
    tag="$(distro_tag)"
    version="2:${OVT_VERSION}-100ovtwayland${PKG_REV}~${tag}"
    dist="${VERSION_CODENAME:-unstable}"
    {
        echo "open-vm-tools (${version}) ${dist}; urgency=medium"
        echo
        echo "  * New upstream release ${OVT_VERSION}, built with Debian's"
        echo "    ${DEBIAN_PKG_VERSION} packaging."
        echo "  * Add the ovt-wayland dndcp patches for copy and paste and drag"
        echo "    and drop in Wayland sessions."
        echo "  * Build the desktop plugin against GTK4 with --with-wayland."
        echo
        echo " -- ovt-wayland <68455785+goproslowyo@users.noreply.github.com>  $(date -R -u -d "@${SOURCE_DATE_EPOCH:-$(date +%s)}")"
        echo
        cat debian/changelog
    } > debian/changelog.new
    mv debian/changelog.new debian/changelog
    dpkg-parsechangelog -S Version
    test "$(dpkg-parsechangelog -S Version)" = "$version"
}

do_build() {
    cd "$src"
    DEB_BUILD_OPTIONS="parallel=$(nproc) ${DEB_BUILD_OPTIONS:-}" \
        dpkg-buildpackage -b -us -uc
    cd ..
    mkdir -p /debs
    for f in ./*.deb; do
        case "$f" in *-dbgsym_*) continue ;; esac
        cp "$f" /debs/
    done
    ls -l /debs
    test -n "$(ls /debs/open-vm-tools_*.deb)"
    test -n "$(ls /debs/open-vm-tools-desktop_*.deb)"
}

# Only the patched sources contain these log strings, so a build that lost a
# patch fails here instead of shipping a stock binary. There is one per patch,
# in patch order, except 0201, which adds only configure and build rules. Keep
# the list in step with the Fedora builder's.
do_check() {
    d="$(mktemp -d)"
    dpkg-deb -x /debs/open-vm-tools-desktop_*.deb "$d"
    so="$(find "$d" -path '*/plugins/vmusr/libdndcp.so')"
    test -f "$so"
    strings "$so" > "$d/strings"
    fail=0
    while IFS= read -r s; do
        if ! grep -qF -- "$s" "$d/strings"; then
            echo "ERROR: libdndcp.so lacks: $s" >&2
            fail=1
        fi
    done <<'EOF'
unsafe fileItem
no XDG_CURRENT_DESKTOP
no X display, uinput disabled
drag entering, telling the host
using ext-data-control-v1
host clip offers
the guest still offers this host clip
clipboard text too large
reading the selection only after it changes
skipping non-file uri
paste observed, requesting files
managed after
native drag source ready
drag started from serial
formats natively
from the %s, was
placeholders under
never agreed
Mutter bridges XDND
outlived the drop
native drop target shown on
onto the native drop target
PruneStagingDirectories
EOF
    test "$fail" = 0
    objdump -p "$so" | grep -q 'NEEDED.*libwayland-client\.so'
    objdump -p "$so" | grep -q 'NEEDED.*libgtk-4\.so'
    rm -rf "$d"
    echo "patched dndcp verified"
}

# archive.ubuntu.com sometimes answers a burst of downloads with 413, and
# apt does not retry that. Packages already fetched stay in the cache, so a
# second run gets only the rest.
do_apt() {
    n=1
    until apt-get "$@"; do
        if [ "$n" -ge 5 ]; then
            echo "ERROR: apt-get $* failed $n times." >&2
            exit 1
        fi
        echo "apt-get failed, retrying in $((n * 20)) s" >&2
        sleep $((n * 20))
        n=$((n + 1))
    done
}

case "${1:-}" in
    apt) shift; do_apt "$@" ;;
    fetch) do_fetch ;;
    prepare) do_prepare ;;
    build) do_build ;;
    check) do_check ;;
    *) echo "usage: $0 fetch|prepare|build|check|apt <args>" >&2; exit 2 ;;
esac
