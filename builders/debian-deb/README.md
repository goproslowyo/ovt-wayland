# Debian and Ubuntu packages

This builder makes open-vm-tools 13.1.0 .debs with the patches in `patches/`.
Debian and Ubuntu ship 13.0.10 or older, and the patches target 13.1.0, so
it combines the upstream 13.1.0 release with Debian's packaging.

## Installing

The packages are attached to the GitHub releases of this repository. There is
no apt repository. Each file name carries the release it was built for, after
the version:

| Release | Suffix |
| --- | --- |
| Debian 13 (trixie) | `~debian13` |
| Debian testing (forky) | `~debian.forky` |
| Debian unstable (sid) | `~debian.sid` |
| Ubuntu 24.04 | `~ubuntu24.04` |
| Ubuntu 26.04 | `~ubuntu26.04` |

GitHub may show the `~` as a `.` in the download name. apt reads the version
from inside the file, so the name does not matter.

Download `open-vm-tools_*` and `open-vm-tools-desktop_*` for your release into
an empty directory, and install both from there:

```sh
sudo apt install ./open-vm-tools_*.deb ./open-vm-tools-desktop_*.deb
```

apt installs them over the distro's packages and pulls any missing
dependencies from your normal archive. Log out and back in, or reboot, so the
desktop session starts the new `vmtoolsd -n vmusr`.

`open-vm-tools-sdmp`, `open-vm-tools-containerinfo`,
`open-vm-tools-salt-minion` and `open-vm-tools-dev` each depend on the exact
version of `open-vm-tools`, and the release does not carry them. If you have
one installed from the distro, apt removes it when you install these
packages. Build the full set with this builder if you need them.

To go back to the distro's packages, install them with their version, for
example `sudo apt install open-vm-tools=2:13.0.10-1ubuntu1
open-vm-tools-desktop=2:13.0.10-1ubuntu1`. `apt-cache policy open-vm-tools`
lists the versions available.

Your distro will not replace these packages with its own 13.0.x or 13.1.0
build, because ours sort higher. A newer upstream release from your distro,
such as 13.1.1, does replace them. Hold the packages with
`sudo apt-mark hold open-vm-tools open-vm-tools-desktop` if you want to keep
the patched build until a new release here.

## Building

Run from the repository root. `BASE` names a Docker Hub library image.

```sh
podman build -f builders/debian-deb/Containerfile \
    --build-arg BASE=ubuntu:24.04 \
    --output type=local,dest=out/ubuntu-24.04 .
builders/debian-deb/install-test.sh ubuntu:24.04 out/ubuntu-24.04/debs
```

The build runs in a single step with its work tree on a tmpfs, and purges the
build dependencies at the end, so it leaves no large layers behind. The
dependencies alone take 1.6 GB on Ubuntu 24.04 and 3.7 GB on Debian testing,
most of it Go sources for the containerinfo plugin. The last stage is
`FROM scratch` with the packages in `/debs`, and `--output` copies them out.

`install-test.sh` installs `open-vm-tools` and `open-vm-tools-desktop` in a
fresh container of the target, lets apt pull their dependencies from the
target's archive, and checks the installed version and the libraries
`vmtoolsd` and `libdndcp.so` link. `vmtoolsd` exits at once outside a
VMware VM, so the test does not run it. It does not start a desktop session.

| BASE | Version built |
| --- | --- |
| `debian:trixie` | `2:13.1.0-100ovtwayland1~debian13` |
| `debian:testing` | `2:13.1.0-100ovtwayland1~debian.forky` |
| `debian:unstable` with `DISTRO_TAG=debian.sid` | `2:13.1.0-100ovtwayland1~debian.sid` |
| `ubuntu:24.04` | `2:13.1.0-100ovtwayland1~ubuntu24.04` |
| `ubuntu:26.04` | `2:13.1.0-100ovtwayland1~ubuntu26.04` |

Ubuntu 26.10 (`ubuntu:devel`) does not build yet. It has GTK 4.24 with
gtkmm 4.22, and gtkmm's `gdkmm/cursor.h` declares `GdkCursorClass`, which
GTK 4.24 now defines itself, so every file that includes `gtkmm.h` fails.
Stock open-vm-tools built with GTK4 fails the same way. Ubuntu's own package
builds with GTK3. Debian sid has GTK 4.24 with gtkmm 4.24 and builds, so 26.10
should build once it gets gtkmm 4.24.

## Sources

`build.sh fetch` downloads two files and checks each against a SHA-256 pinned
in the Containerfile.

- `open-vm-tools-13.1.0-25218885.tar.gz` from the GitHub release
  `stable-13.1.0`. This is the tarball Fedora builds from.
- `open-vm-tools_13.0.10-1.1.debian.tar.xz`, Debian's newest packaging, from
  snapshot.debian.org, with deb.debian.org as a fallback while the file is
  still in the pool.

Debian's orig tarball is a snapshot of the upstream git repository with the
sources in `open-vm-tools/`, and `debian/rules` builds from that directory.
The release tarball is unpacked into the same place.

## Changes to Debian's packaging

`build.sh prepare` makes these changes and checks each one took effect.

- `builders/debian-deb/patches/*.patch` go into `debian/patches/ovt-debian/`
  after Debian's series. They are in Debian's quilt format.
- Our patches go into `debian/patches/ovt-wayland/` and at the end of
  `debian/patches/series`. They come from `git format-patch` inside
  `open-vm-tools/`, so the script adds that directory to the paths in their
  file headers. `dpkg-source --before-build` then applies the whole series
  without fuzz, and a patch that does not apply stops the build.
- `debian/rules` configures with `--with-gtk4 --with-wayland` in place of
  `--with-gtk3`, as the Fedora package does. The Wayland backend also builds
  with GTK3, but the patches have only been tested with GTK4. `--with-wayland`
  makes configure fail rather than build the plugin without the backend.
- Build-Depends swaps `libgtkmm-3.0-dev` and `libgtk-3-dev` for
  `libgtkmm-4.0-dev` and `libgtk-4-dev`, and adds `libwayland-dev` and
  `wayland-protocols (>= 1.39)`. ext-data-control-v1 first appeared in
  wayland-protocols 1.39.
- `dh_installchangelogs` no longer names `ReleaseNotes.md`, which is in the
  git repository but not in the release tarball.
- A new changelog entry sets the version.

## Debian's patches

All four patches in Debian's 13.0.10-1.1 series apply to 13.1.0 without fuzz
and are kept. None were dropped or refreshed.

| Patch | Status in 13.1.0 |
| --- | --- |
| `glib-free` | Kept. The glib-free RPC channel stubs define `g_free`, which glib 2.78 and later turn into a macro. |
| `use-debian-pam` | Kept, Debian-specific. Installs `pam/debian` as `/etc/pam.d/vmtoolsd`. |
| `debian/scsi-udev-rule` | Kept, Debian-specific. Sets the SCSI disk timeout through `ATTR{timeout}`. |
| `upstream/pr-783.patch` | Kept, not merged upstream in 13.1.0. Fixes the build with the C23 const-returning `strchr` family in glibc 2.43. |

The builder carries one more patch, in `patches/` next to this file, which
goes after Debian's series and before ours.

| Patch | Why |
| --- | --- |
| `openssl4-const.patch` | Ubuntu 26.10 has OpenSSL 4, where `X509_get_subject_name()` and friends return const pointers, and `certverify.c` fails with `-Werror`. Copied unchanged from Ubuntu's 2:13.0.10-1ubuntu6, which took it from Fedora. It only adds `const`, so it builds with OpenSSL 3 as well. Debian's packaging does not have it yet (Debian bug 1138384). |

## Version

Debian's epoch is 2, so the version is
`2:13.1.0-100ovtwayland<PKG_REV>~<DISTRO_TAG>`. It sorts above the 12.5.0
and 13.0.10 packages Debian and Ubuntu ship today, and the `100` revision
sorts above a Debian or Ubuntu upload of 13.1.0 itself, such as
`2:13.1.0-1ubuntu1`. The Fedora RPMs use release 100 for the same reason. A
distro upload of a newer upstream version still replaces the patched build.

`DISTRO_TAG` defaults to `<ID><VERSION_ID>` from `/etc/os-release`, or
`<ID>.<VERSION_CODENAME>` when there is no `VERSION_ID`. Debian testing and
sid both report forky, so the sid build passes `DISTRO_TAG=debian.sid`.

## Output

`/debs` holds every binary package except the debug symbols:
`open-vm-tools`, `open-vm-tools-desktop`, `open-vm-tools-dev`,
`open-vm-tools-sdmp`, `open-vm-tools-containerinfo` and, on amd64,
`open-vm-tools-salt-minion`. The last four depend on the exact
`open-vm-tools` version. Releases carry only `open-vm-tools` and
`open-vm-tools-desktop`, the two packages the patches change.

`build.sh check` then looks in the built `libdndcp.so` for one log string per
patch, the same list the Fedora builder checks, and confirms it links
`libwayland-client` and `libgtk-4`.
