#!/usr/bin/env bash
# Build locally what CI builds, from targets.json.
#
#   ./build.sh rpms 45          RPMs for Fedora 45, into out/fc45/rpms
#   ./build.sh image bazzite    the RPMs for that image's release, then the image
#
# Set SIGNED_REPO to embed a signature policy for your own repository. Run
# with sudo to build into the root image store, which bootc switch reads.
set -euo pipefail
cd "$(dirname "$0")"

die() { echo "build.sh: $*" >&2; exit 1; }

build_rpms() {
    local rel="$1"
    jq -e --argjson r "$rel" '.rpms[] | select(.fedora_release == $r)' \
        targets.json >/dev/null || die "Fedora $rel is not in targets.json"
    rm -rf "out/fc$rel"
    podman build -f builders/fedora-rpm/Containerfile \
        --build-arg FEDORA_RELEASE="$rel" -o "out/fc$rel" .
    ls -1 "out/fc$rel/rpms"
}

build_image() {
    local name="$1" t rel base cf image tag args=()
    t="$(jq -ce --arg n "$name" '.images[] | select(.name == $n)' targets.json)" ||
        die "no image named $name in targets.json"
    rel="$(jq -r .fedora_release <<<"$t")"
    base="$(jq -r .base <<<"$t")"
    cf="$(jq -r .containerfile <<<"$t")"
    image="$(jq -r .image <<<"$t")"
    # Always rebuild. Reusing an old out/ would put stale RPMs in the image,
    # and the layer cache makes an unchanged rebuild quick.
    build_rpms "$rel"
    if [ -n "${SIGNED_REPO:-}" ]; then
        args+=(--build-arg "SIGNED_REPO=$SIGNED_REPO")
    fi
    for tag in $(jq -r '.tags[]' <<<"$t"); do
        args+=(-t "localhost/$image:$tag")
    done
    podman build -f "$cf" --build-arg BASE_IMAGE="$base" \
        --build-context rpms="out/fc$rel/rpms" "${args[@]}" .
}

case "${1:-}" in
    rpms)  [ $# -eq 2 ] || die "usage: $0 rpms <fedora release>"; build_rpms "$2" ;;
    image) [ $# -eq 2 ] || die "usage: $0 image <name>"; build_image "$2" ;;
    *)     die "usage: $0 rpms <fedora release> | image <name>" ;;
esac
