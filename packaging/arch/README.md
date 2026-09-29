# Arch Linux

`PKGBUILD` builds `open-vm-tools-wayland`. It starts from Arch's
`open-vm-tools` 6:13.1.0-3 PKGBUILD, commit
[`a2334c0c`](https://gitlab.archlinux.org/archlinux/packaging/packages/open-vm-tools/-/commit/a2334c0c598a9efdc14f9bdf62aa827e19135d84),
and changes these things.

- It applies every patch in `patches/` after Arch's GCC 16 patch.
- It builds the GTK4 plugin with `--with-gtk4 --with-wayland`. Arch's
  package builds the GTK3 one, and drag and drop in these patches needs GTK4.
- It applies Fedora's `open-vm-tools-sigc++3.patch` from Fedora's 13.1.0-2
  package. gtkmm-4.0 uses libsigc++ 3, which no longer accepts the
  `signal<R, T...>` syntax in upstream's dndcp headers.
- `gtkmm-4.0`, `libsigc++-3.0`, `libxtst` and `wayland` become dependencies
  and `wayland-protocols` a build dependency.
- It provides and conflicts with `open-vm-tools`, so installing it replaces
  the repository package.

`vmtoolsd.pam`, `vmtoolsd.service`, `vmware-vmblock-fuse.service` and
`open-vm-tools-gcc16.patch` are copied unchanged from the same Arch commit.
Arch's packaging files are 0BSD. The two patches are LGPL-2.1, as
open-vm-tools is.

## Building

`build.sh` builds the package in an `archlinux` container and writes it to
the directory you give it. Run it from the repository root.

```bash
mkdir -p out
podman run --rm -v "$PWD":/src:ro,z -v "$PWD/out":/out:z \
    docker.io/library/archlinux:latest /src/packaging/arch/build.sh /out
```

It builds as an unprivileged user with makepkg, fails if the plugin lacks a
log string from each group of patches, installs the package in the container
and copies `open-vm-tools-wayland-6:13.1.0-1-x86_64.pkg.tar.zst` to `out/`.

On an Arch machine, `prepare.sh` puts the PKGBUILD, its files and the patches
in one directory for makepkg.

```bash
packaging/arch/prepare.sh /tmp/ovt-arch
cd /tmp/ovt-arch
makepkg -si
```

`prepare.sh` fails if the `_patches` list in the PKGBUILD differs from
`patches/`. After you add or rename a patch, update `_patches`. The patches
come from this repository, so the PKGBUILD skips their checksums, and a
changed patch needs no PKGBUILD edit. Run `updpkgsums` only when a file
from Arch, Fedora or upstream changes.
