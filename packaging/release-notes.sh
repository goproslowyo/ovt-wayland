#!/bin/bash
# Write the notes of a GitHub release from the files it carries.
#
#   packaging/release-notes.sh ASSETS_DIR > notes.md
#
# The environment names the release: VERSION (13.1.0), TAG, REPO (owner/name),
# SHA (the commit built), and IMAGE_SUFFIX as the workflow uses it. RPMS_RESULT,
# DEBS_RESULT and ARCH_RESULT are the results of the build jobs, so the notes
# can say what is missing. Images come from targets.json in the working
# directory.

set -euo pipefail
export LC_ALL=C

dir="$1"
: "${VERSION:?}" "${TAG:?}" "${REPO:?}" "${SHA:?}"
owner="${REPO%%/*}"
dl="https://github.com/$REPO/releases/download/$TAG"

has() { compgen -G "$dir/$1" > /dev/null; }
# link FILE [TEXT]
link() { printf '[%s](%s/%s)' "${2:-$1}" "$dl" "$1"; }

# ubuntu24.04 -> Ubuntu 24.04, debian.forky -> Debian testing (forky)
debian_name() {
    case "$1" in
        debian.sid) echo "Debian sid" ;;
        debian.forky) echo "Debian testing (forky)" ;;
        debian13) echo "Debian 13 (trixie)" ;;
        ubuntu*) echo "Ubuntu ${1#ubuntu}" ;;
        *) echo "$1" ;;
    esac
}

cat <<EOF
open-vm-tools $VERSION with copy and paste and drag and drop that work under
Wayland, built from [\`${SHA:0:7}\`](https://github.com/$REPO/commit/$SHA)
with the patches in [\`patches/\`](https://github.com/$REPO/tree/$SHA/patches).
Every file here is also listed in \`SHA256SUMS\` and carries a build
attestation, as the Verify section below explains.

EOF

missing=""
[ "${RPMS_RESULT:-success}" = success ] || missing+="- Some Fedora RPMs did not build in this run."$'\n'
[ "${DEBS_RESULT:-success}" = success ] || missing+="- Some Debian and Ubuntu packages did not build in this run."$'\n'
[ "${ARCH_RESULT:-success}" = success ] || missing+="- The Arch package did not build in this run."$'\n'
if [ -n "$missing" ]; then
    printf '## Missing from this release\n\n%s\n' "$missing"
fi

if has 'open-vm-tools-[0-9]*.fc*.x86_64.rpm'; then
    cat <<'EOF'
## Fedora

| Release | Packages | Source |
|---|---|---|
EOF
    for f in "$dir"/open-vm-tools-[0-9]*.fc*.x86_64.rpm; do
        f="$(basename "$f")"
        rel="$(sed -n 's/.*\.fc\([0-9]*\)\..*/\1/p' <<<"$f")"
        desk="open-vm-tools-desktop-${f#open-vm-tools-}"
        src="${f%.x86_64.rpm}.src.rpm"
        row="| Fedora $rel | $(link "$f" open-vm-tools)"
        [ -e "$dir/$desk" ] && row+=", $(link "$desk" open-vm-tools-desktop)"
        row+=" |"
        [ -e "$dir/$src" ] && row+=" $(link "$src" "source rpm") |" || row+=" |"
        echo "$row"
    done
    cat <<EOF

On Fedora Atomic, such as Silverblue or Kinoite:

\`\`\`bash
rel=\$(rpm -E %fedora)
curl -LO $dl/open-vm-tools-$VERSION-100.fc\$rel.clipway.x86_64.rpm
curl -LO $dl/open-vm-tools-desktop-$VERSION-100.fc\$rel.clipway.x86_64.rpm
rpm-ostree override replace ./open-vm-tools-*.rpm
systemctl reboot
\`\`\`

On Fedora Workstation and other dnf systems, download the same two files and
run \`sudo dnf install ./open-vm-tools-*.rpm\`, then log out and back in.

EOF
fi

if has 'open-vm-tools_*.deb'; then
    cat <<'EOF'
## Debian and Ubuntu

| Release | Packages |
|---|---|
EOF
    # Stable before testing before sid, then Ubuntu by release.
    debs=()
    while IFS= read -r f; do
        debs+=("$f")
    done < <(for f in "$dir"/open-vm-tools_*.deb; do
                 f="$(basename "$f")"
                 case "$f" in
                     *.debian13_*) k=0 ;;
                     *.debian.forky_*) k=1 ;;
                     *.debian.sid_*) k=2 ;;
                     *) k=3 ;;
                 esac
                 printf '%s %s\n' "$k" "$f"
             done | sort | cut -d' ' -f2)
    for f in "${debs[@]}"; do
        tag="$(sed -n 's/.*ovtwayland[0-9]*\.\(.*\)_[a-z0-9]*\.deb$/\1/p' <<<"$f")"
        desk="open-vm-tools-desktop_${f#open-vm-tools_}"
        row="| $(debian_name "$tag") | $(link "$f" open-vm-tools)"
        [ -e "$dir/$desk" ] && row+=", $(link "$desk" open-vm-tools-desktop)"
        echo "$row |"
    done
    cat <<'EOF'

Download both files for your release, install them with
`sudo apt install ./open-vm-tools_*.deb ./open-vm-tools-desktop_*.deb`, then
log out and back in. Remove `open-vm-tools-sdmp`, `-containerinfo` or
`-salt-minion` first if you have them. This release does not carry them.

EOF
fi

if has 'open-vm-tools-wayland-*.pkg.tar.zst'; then
    f="$(basename "$(compgen -G "$dir/open-vm-tools-wayland-*.pkg.tar.zst" | head -1)")"
    cat <<EOF
## Arch Linux

$(link "$f") replaces \`open-vm-tools\`.

\`\`\`bash
sudo pacman -U ./$f
sudo systemctl enable --now vmtoolsd.service vmware-vmblock-fuse.service
\`\`\`

EOF
fi

if [ -f targets.json ]; then
    echo "## Bootc images"
    echo
    echo "Signed images, rebuilt every Monday and on every change:"
    echo
    jq -r --arg o "$owner" --arg s "${IMAGE_SUFFIX:-}" '
        .images[] | "- `ghcr.io/\($o)/\(.image)\($s):latest`, based on `\(.base)`"
    ' targets.json
    cat <<EOF

Switch with \`sudo bootc switch ghcr.io/$owner/<image>:latest\` and reboot.

EOF
fi

cat <<EOF
## Verify

\`\`\`bash
sha256sum -c --ignore-missing SHA256SUMS
gh attestation verify <file> -R $REPO
gh attestation verify oci://ghcr.io/$owner/<image>:latest -R $REPO
\`\`\`

The attestation shows which workflow run and commit built a file. The images
are also signed with the key in
[\`cosign.pub\`](https://github.com/$REPO/blob/$SHA/cosign.pub).
EOF
