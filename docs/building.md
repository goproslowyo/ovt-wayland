# Building

## Images and packages

Each build produces these. [`targets.json`](../targets.json) lists them, and
CI builds from it.

| Target | Built from | Where |
|---|---|---|
| Bazzite image | `ghcr.io/ublue-os/bazzite:stable`, Fedora 44 RPMs | `ghcr.io/goproslowyo/bazzite-ovt`, tags `latest` and `YYYYMMDD` |
| Fedora COSMIC Atomic image | `quay.io/fedora-ostree-desktops/cosmic-atomic:45`, Fedora 45 RPMs | `ghcr.io/goproslowyo/fedora-cosmic-ovt`, tags `latest`, `45` and `YYYYMMDD` |
| RPMs for Fedora 43, 44 and 45 | Fedora's `open-vm-tools` source rpm for that release | [Releases](https://github.com/goproslowyo/ovt-wayland/releases) |
| .debs for Debian 13, testing and sid, and Ubuntu 24.04 and 26.04 | upstream 13.1.0 source with Debian's packaging | [Releases](https://github.com/goproslowyo/ovt-wayland/releases) |
| Arch Linux package `open-vm-tools-wayland` | upstream 13.1.0 source with Arch's PKGBUILD | [Releases](https://github.com/goproslowyo/ovt-wayland/releases) |

CI publishes packages only as GitHub release assets. There is no dnf
repository. Each release is tagged `v<version>-<YYYYMMDD>` and carries, for
each Fedora release and each Debian or Ubuntu target, `open-vm-tools` and
`open-vm-tools-desktop`, the two packages the patches change. It also has the
patched source rpm for each Fedora release, the Arch package and a
`SHA256SUMS` file.

The builders produce the other subpackages too, such as `-devel` and `-sdmp`,
but they are unchanged rebuilds and CI does not publish them. Build them from
this repository if you need them.

The RPMs have release `100.fcNN.clipway`, for example
`open-vm-tools-13.1.0-100.fc44.clipway.x86_64.rpm`, so the files for
different Fedora releases have different names. Release 100 sorts above
Fedora's own build of 13.1.0, so dnf and rpm-ostree treat it as an upgrade.

## CI

CI builds on every push to `main` that changes more than Markdown files or
`LICENSE`, every Monday at 07:00 UTC, and on manual dispatch. It reads
`targets.json`, builds the RPMs for each Fedora release in it, the .debs for
each Debian and Ubuntu target and the Arch package, uploads them as workflow
artifacts named `pkg-rpm-fcNN`, `pkg-deb-<name>` and `pkg-arch`, and builds
each image from its release's RPMs.

Only a run on `main` pushes the images with their tags, signs each pushed
digest, fails if `cosign verify` against `cosign.pub` does not pass, and
creates or updates the GitHub release for that day. The release job attaches
the files of every artifact whose name starts with `pkg-`, turns `~` in file
names into `.` as GitHub would, and fails if two files end up with the same
name.

A target that fails does not hold back the rest. The release goes out with the
packages that built, and its notes say which kinds are missing. A second run
on the same day replaces that day's assets and removes any it did not build.

`packaging/release-notes.sh` writes the release notes from the files the
release carries. They list each package with its download link, grouped by
distribution, with the install commands, the images and how to verify them.
To see the notes for a directory of packages, run it from the repository
root with `VERSION`, `TAG`, `REPO` and `SHA` set. Both the images and every
release file get a build provenance attestation, see
[Verifying signatures](signatures.md#build-attestations).

## Local builds

The build is split in two. `builders/fedora-rpm/Containerfile` rebuilds
Fedora's source rpm with the patches for the release in `FEDORA_RELEASE`.
Each `images/<name>/Containerfile` takes those RPMs from a build context named
`rpms` and layers them onto its base. `build.sh` runs both steps locally from
`targets.json`.

```bash
./build.sh rpms 44                 # RPMs into out/fc44/rpms
SIGNED_REPO=ghcr.io/<you>/bazzite-ovt ./build.sh image bazzite
```

`build.sh image` rebuilds the RPMs for the image's release first, and
tags the result `localhost/<image>:<tag>` for each tag in `targets.json`. Run
it with `sudo` to build into the store that `bootc switch --transport
containers-storage` reads. By hand, the same steps are these.

```bash
podman build -f builders/fedora-rpm/Containerfile \
    --build-arg FEDORA_RELEASE=44 -o out/fc44 .
podman build -f images/bazzite/Containerfile \
    --build-context rpms=out/fc44/rpms \
    --build-arg SIGNED_REPO=ghcr.io/<you>/bazzite-ovt \
    -t ghcr.io/<you>/bazzite-ovt:latest .
```

The .debs and the Arch package have their own builders, described in
[builders/debian-deb/README.md](../builders/debian-deb/README.md) and
[packaging/arch/README.md](../packaging/arch/README.md).

## Signing in a fork

`SIGNED_REPO` names the repository the image's signature policy covers and
defaults to the image's repository under `ghcr.io/goproslowyo`. To sign in a
fork, run `COSIGN_PASSWORD="" cosign generate-key-pair`, add `cosign.key` as
the `SIGNING_SECRET` repository secret, and commit `cosign.pub`. Never commit
`cosign.key`.

## Build checks

The build fails rather than ship an unpatched binary. It checks the source
rpm against Fedora's release key, pins `OVT_VERSION` and stops if Fedora ships
another version, and greps the built `libdndcp.so` for at least one log
string from each patch. Each image checks that its RPMs come from the same
Fedora release as its base.

## Adding a patch

Put it in `patches/` named `NNNN-<name>.patch` with `<name>` in
`[A-Za-z0-9._-]`. The builder registers every patch there in sorted order as
`Patch101` onward, after Fedora's own.

## Adding an image

1. Copy `images/fedora-cosmic` to `images/<name>` and change the base image,
   the `SIGNED_REPO` default, and the key and `registries.d` file names.
   Keep the release check, and install only `open-vm-tools` and
   `open-vm-tools-desktop` from `/tmp/rpms`.
2. Add an entry to `images` in `targets.json` with `name`, `image` (the ghcr
   repository name), `containerfile`, `base`, `fedora_release` and `tags`.
   `fedora_release` must also appear under `rpms`. Add it there if it is a
   new release.
3. Build it with `./build.sh image <name>` and check it with
   `bootc container lint`.

CI builds and pushes the new image on the next run on `main`. GitHub creates
the ghcr package on that first push as private, so make it public in the
package settings for `bootc switch` to pull it without logging in.
