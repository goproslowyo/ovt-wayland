#!/bin/sh
# Install the built .debs in a fresh container of the target and check them.
#
#   builders/debian-deb/install-test.sh <base image> <directory with .debs>
#
# for example
#
#   builders/debian-deb/install-test.sh ubuntu:24.04 out/ubuntu-24.04/debs
#
# It first installs the target's own open-vm-tools and open-vm-tools-desktop,
# then installs the built ones over them the way the README says, so apt has
# to resolve the dependencies from the target's archive and treat the files
# as an upgrade. It then checks the installed version, that vmtoolsd links,
# and that the dndcp plugin links libwayland-client. Nothing here runs a desktop
# session.

set -eu

base="${1:?usage: $0 <base image> <deb directory>}"
debs="$(cd "${2:?usage: $0 <base image> <deb directory>}" && pwd)"
engine="${ENGINE:-podman}"

"$engine" run --rm -v "$debs:/debs:ro,Z" "docker.io/library/$base" sh -euc '
    export DEBIAN_FRONTEND=noninteractive
    # archive.ubuntu.com sometimes answers with 413. Retry as build.sh does.
    apt_retry() {
        n=1
        until apt-get "$@"; do
            [ "$n" -lt 5 ] || exit 1
            sleep $((n * 20))
            n=$((n + 1))
        done
    }
    apt_retry update -qq
    apt_retry install -y -qq --no-install-recommends \
        open-vm-tools open-vm-tools-desktop > /dev/null
    echo "--- stock"
    dpkg-query -W -f "\${Package} \${Version}\n" open-vm-tools open-vm-tools-desktop
    apt_retry install -y --no-install-recommends \
        /debs/open-vm-tools_*.deb /debs/open-vm-tools-desktop_*.deb
    echo "--- installed"
    dpkg-query -W -f "\${Package} \${Version}\n" open-vm-tools open-vm-tools-desktop \
        | tee /tmp/installed
    test "$(grep -c " 2:13\.1\.0-100ovtwayland" /tmp/installed)" = 2
    # vmtoolsd exits before reading its options outside a VMware VM, so
    # check that it links instead of running it.
    echo "--- ldd vmtoolsd"
    ldd /usr/bin/vmtoolsd | tee /tmp/ldd
    if grep -q "not found" /tmp/ldd; then exit 1; fi
    so="$(dpkg -L open-vm-tools-desktop | grep "/plugins/vmusr/libdndcp.so$")"
    echo "--- ldd $so"
    ldd "$so" | tee /tmp/ldd
    if grep -q "not found" /tmp/ldd; then exit 1; fi
    grep -q "libwayland-client\.so" /tmp/ldd
    grep -q "libgtk-4\.so" /tmp/ldd
    echo "install test passed"
'
