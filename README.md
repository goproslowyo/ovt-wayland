# ovt-wayland

`open-vm-tools` 13.1.0 rebuilt so that copy and paste and drag and drop work
in a VMware guest under Wayland, in both directions, for every format the
protocol defines. Those are text, RTF, PNG images, files and file contents.
It comes as RPMs for Fedora 43, 44 and 45, .debs for Debian and Ubuntu, an
Arch Linux package, and bootc images based on Bazzite and Fedora COSMIC
Atomic.

Stock `open-vm-tools` has only an X11 copy and paste backend. Under Wayland it
can reach only Xwayland's clipboard, and most compositors refuse clipboard
reads from an unfocused Xwayland client, so copying from guest to host fails.
The patches in `patches/` add a Wayland clipboard backend and make drag
and drop reach native Wayland applications. X11 sessions keep the upstream
backends, with fixes for file transfers on desktops other than GNOME and KDE.

Tracks open-vm-tools [#792](https://github.com/vmware/open-vm-tools/issues/792)
and [#510](https://github.com/vmware/open-vm-tools/issues/510).

## What works where

G is the guest and H is the host.

| Session | Copy and paste G to H | Copy and paste H to G | Drag H to G | Drag G to H |
|---|---|---|---|---|
| KDE Plasma 6.7.5 (KWin) | works, all formats | works, all formats | works, native | works, XDND |
| sway 1.11 (wlroots) | works, all formats | works, all formats | works, native | works, XDND |
| GNOME 50.3 (Mutter) | text and files tested | text, files and images tested | works, XDND | files and text tested |
| Xfce 4.20 on Xorg | works, text and files | works, text and files | works | works |
| COSMIC 1.8 | works, text and files | works, text and files | works, native | works, XDND |
| niri 26.04 | works, text tested | works, text tested | works, native | works, native |

How each row was tested:

- KDE Plasma. Bazzite 44 (Fedora 44) against VMware Workstation Pro 26H1u1
  (26.0.1.25688693) on a Windows 10 Pro 22H2 host. Text, PNG, RTF and files in
  both directions, single and multi-file, by copy and paste and by drag.
  Capabilities negotiate to `0x1555` for copy and paste and `0xaab` for drag and
  drop, the same set the X11 backend reports. Most drag tests predate the native
  drag source and used XDND. Host drags into Dolphin 26.08.1 through the native
  drag source were tested by hand, and the whole list was run again by hand with
  the final build.
- sway. A Fedora 44 VM under VMware Workstation, by hand. Host drags into
  Thunar 4.20.9 and PCManFM (libfm 1.4.1), including multi-file drops and
  file names with spaces. With the final build, text, rich text, images and
  files by copy and paste in both directions, and file and text drags from
  guest to host.
- GNOME. Bluefin 44 under VMware Workstation with Nautilus 50.2.2, by hand.
  Text and file copy and paste in both directions, images from host to guest,
  host drags into Nautilus, and guest drags of files and text out of a
  maximized Nautilus and Text Editor. A test program also drove the plugin's
  own detection window and uinput code through the host to guest sequence,
  and 199 of 200 runs landed the drop. Without patch 0019, host drags into
  Nautilus do not land.
- Xorg. Xfce 4.20 with Thunar 4.20.9 on the Fedora 44 VM, by hand. Text and
  file copy and paste both ways, and file drags both ways. Stock
  `open-vm-tools` loses file pastes and host file drags there, since it
  offers file lists only on GNOME and KDE and blocks the files before Thunar
  can check them.
- niri. niri 26.04 on Fedora 45 COSMIC Atomic with COSMIC Files, by hand.
  File drags in both directions against the host. The pointer sizing from
  the Wayland output was also tested without the host, through mode changes
  and a rotated output. See the known limits for a niri setting that affects
  drags.
- A compositor started from a text console, where `XDG_SESSION_TYPE` is `tty`.
  vmusr was started on sway with that value, and chose the Wayland backend
  and got the uinput device.

## Requirements and compatibility

You need this in a Wayland session. In an X11 session stock `open-vm-tools`
handles GNOME and KDE, and this build adds file copy and file drags on other
desktops such as Xfce, input checks and staging cleanup.

The guest needs:

- `open-vm-tools` 13.1.0 built with GTK4. The patches target that release.
- Xwayland. vmusr loads upstream's desktopEvents plugin, which needs an X
  display to start at all, and drag and drop runs through Xwayland.
- `run-vmblock\x2dfuse.mount` active, for lazy file paste and host to guest
  file drags. See below.
- `vmtoolsd -n vmusr` started through `vmware-user-suid-wrapper`, which hands
  it the vmblock and uinput descriptors. Drag and drop under Wayland needs
  uinput.
- `wl-clipboard`, only as a last fallback where neither of the clipboard
  paths below exists.

What each compositor gets depends on the protocols it offers.

| Compositor offers | Copy and paste | Drag H to G | Drag G to H |
|---|---|---|---|
| `ext-data-control-v1` (KWin and wlroots releases that have it) | full, native | native if it also has `zwlr_layer_shell_v1` | native with layer shell, else XDND, bridged |
| no data control, X selection mirrored (Mutter) | full, through Xwayland | XDND, bridged by Mutter | XDND, bridged |
| neither, `wl-clipboard` installed | one format per copy | XDND to X11 apps only | X11 sources only |

Tested: Plasma 6.7.5, sway 1.11, GNOME 50.3, COSMIC 1.8 and Xfce 4.20 on Xorg,
all against VMware Workstation Pro 26H1u1 on a Windows 10 host. Their guest to
host drags went through XDND. Where the compositor has layer shell, guest to
host drags now use a native drop target first (patch 0021). It was tested with
the host on Plasma 6.7.5, sway 1.11 and niri 26.04, where xwayland-satellite
cannot carry a drag into X at all. It falls back to
XDND where nothing reaches it.
Hyprland 0.56.2 from the `sdegler/hyprland` COPR could not be
tested, because its Xwayland exits on the first window any X11 client maps,
`xterm` included, and vmusr cannot start without it. Not tested: other VMware
hosts such as Fusion, and compositor releases older than their
`ext-data-control-v1` support. Older KWin and sway releases offer only
`wlr-data-control`, which this build does not bind, so they take the Xwayland
path. That works where the compositor mirrors the X selection to Wayland.

## How it works

### Clipboard

Where the compositor implements `ext-data-control-v1`, as KWin and wlroots do,
the backend binds it and owns the selection itself, with no window and no focus.
It offers every format the host sent and answers each request with the bytes for
the type asked for, so one selection carries RTF and plain text at once.

GNOME does not implement data control. There the backend uses the X
`CLIPBOARD` selection through Xwayland, which Mutter keeps in step with the
Wayland one for any X client, focused or not. It owns that selection through
GDK to install a host clip, with every format at once, and reads it only after
GDK reports a change. `wl-clipboard` is the last fallback, for a compositor
with neither data control nor that mirror. `wl-copy` serves one type per
selection and, like `wl-paste`, maps a small window to get focus.

The backend puts a deadline on every selection read and write, so a peer that
stops reading cannot stall the daemon's main loop, which also carries the RPC
channel to the host.

### Host to guest files

Nothing is transferred when you copy. The guest creates a staging directory
under `~/.cache/vmware/drag_and_drop`, puts a vmblock on it, and publishes
paths under `/run/vmblock-fuse/blockdir/`. When an application opens one of
those files, vmblock holds the read and the guest requests the bytes from the
host. Copying a large file on the host and never pasting it transfers
nothing.

File lists go out as `text/uri-list`, `x-special/gnome-copied-files` and
`application/x-kde-cutselection`, so file managers enable Paste. The guest
escapes CR and LF in host-supplied names and rejects any name with a `..`
component.

This needs `run-vmblock\x2dfuse.mount` to be active and `vmtoolsd -n vmusr`
started with `--blockFd`, which `vmware-user-suid-wrapper` does. Both are the
default on Fedora. The Bluefin 44 test guest shipped the mount disabled, and
`systemctl enable --now 'run-vmblock\x2dfuse.mount'` turns it on. Without
vmblock the guest declines a file paste and logs why.

Patch 0022 removes a staging directory about two minutes after its transfer
is over. It keeps a directory while the clipboard still offers its files,
while a drag still uses it, and while any process has a file in it open or
uses it as its working directory. The check runs once a minute. It does not
delete at once, because the guest cannot tell when the target is done. After a
drop, a file manager opens the files a moment later, and some applications
read a dropped file again later.

### Drag and drop

Guest to host drag, of files or text, takes one of two paths.

- Where the compositor has `zwlr_layer_shell_v1`, patch 0021 shows the
  layer-shell overlays as a Wayland drop target. The drag enters them as it
  would any Wayland window, and the overlay reads the file list or text for
  the host. It accepts copy only, since the host reads the files after the
  drop. A drag the host cannot take goes on to the window under the overlay.
  If nothing reaches the overlay, the plugin uses the detection window below.
- Elsewhere the upstream XDND code runs with an Xwayland detection window.
  KWin and Mutter bridge its XDND to native Wayland applications. KWin
  bridges only to managed windows, so under Wayland patch 0013 keeps the
  window managed and waits until the window manager lists it before moving
  the pointer.

Host to guest drag takes one of two paths.

- Where the compositor has `zwlr_layer_shell_v1`, as sway and KWin do, and
  uinput is available, patches 0014 to 0018 run a
  native `wl_data_device` drag. It maps a transparent layer-shell overlay on
  each output, fakes a button press on it through uinput, and starts the drag
  from that press. The overlay unmaps once the drag has started. The files are
  empty placeholders until the target accepts, and the block goes on just
  before the button is released.
- GNOME has no layer shell, so the drag stays on XDND there. Patch 0019 makes
  it meet the conditions under which Mutter bridges XDND to Wayland clients.
  It keeps the detection window above the focused window, presses inside it
  and waits for GTK to start the drag before the pointer moves on, and
  releases once the target accepts or after 1.5 s. Patch 0020 raises the guest
  to host drop target, and presses Escape through uinput to cancel a guest
  drag that is still running 300 ms after a guest to host drop. Both apply
  only when the X window manager says it is Mutter. Another compositor
  without layer shell gets the upstream XDND behaviour.

wlroots does not carry a drag from an X11 source to a Wayland client
([wlroots#841](https://github.com/swaywm/wlroots/pull/841)), which is why
sway needs the native path.

### Known limits

- If you let go of a drag within about 100 ms of entering the VM, the host
  cancels it before the guest learns the pointer position.
- On GNOME a host to guest drag starts about half a second after the pointer
  enters the VM. A drop that comes sooner waits for it.
- On GNOME, after a guest to host drag, move the pointer over the guest once
  before dragging from the host into it. Until then the host holds the guest
  mouse button down and the host to guest drag fails.
- A host copy that carries only RTF, as AbiWord's does, pastes only into
  applications that accept RTF.
- PCManFM (libfm 1.4.1) can crash when a drag leaves it before the data
  arrives. This is a libfm bug.
- If the VMware window scales the guest display rather than resizing it,
  host to guest drags land beside where the host pointer is. Use a guest
  resolution that fits the window, such as View, Autosize, Autofit Guest.
- A file name the host cannot use is changed there. Windows does not allow
  `:`, so the host writes it as `^%`.
- An application that reads a dropped file more than two minutes after the
  drop finds it gone, for example a browser upload form submitted later.
  Drop into a file manager first in that case.
- Pasted files keep the permissions the host reports, so a read-only Windows
  file arrives read-only. That is upstream behaviour.
- A tiling compositor that tiles the detection window stretches it over the
  drop target. Sway floats it on its own. Elsewhere, float it in the
  compositor's configuration, for example in sway syntax
  `for_window [title="vmware-user"] floating enable`.
- On niri, turn off scrolling at the screen edges during a drag, with
  `gestures { dnd-edge-view-scroll { trigger-width 0; }; }`. The guest pointer
  stays at the edge a guest to host drag left from, and niri scrolls the view
  until the drop. With the scrolling on, the host sometimes treated the drag
  as back in the guest and kept the pointer in the VM window.

## Patches

Twenty-two patches against `open-vm-tools 13.1.0-25218885`, applied in order
and grouped by topic. Each builds on its own, and each explains its reasoning
in its commit message. The first four change only upstream code and apply to
X11 sessions as well.

| Patch | What it does |
|---|---|
| `0001-dndcp-validate-host-input` | Validates file lists and file names from the host and from drag sources. |
| `0002-dndcp-any-desktop-file-drop` | Offers file drops and file pastes on desktops other than GNOME and KDE. |
| `0003-dndcp-fake-pointer` | Keeps the faked pointer on the screen and never leaves its button down. |
| `0004-dndcp-drag-read-uri-list` | Reads a guest drag as `text/uri-list` or text instead of through the file portal. |
| `0005-dndcp-wayland-configure` | Adds `--with-wayland` and generates the protocol code at build time. |
| `0006-dndcp-data-control-client` | Clipboard client for `ext-data-control-v1`. |
| `0007-dndcp-wayland-paste-from-host` | Installs host clips in a Wayland session. |
| `0008-dndcp-wayland-copy-to-host` | Sends the guest clipboard to the host in a Wayland session. |
| `0009-dndcp-wl-clipboard-fallback` | Falls back to `wl-clipboard` without data control. |
| `0010-dndcp-gnome-xselection-clipboard` | Copies and pastes through the Xwayland selection on GNOME. |
| `0011-dndcp-wayland-file-copy` | Sends guest file lists to the host. |
| `0012-dndcp-wayland-file-paste` | Pastes host files lazily through vmblock, and file contents. |
| `0013-dndcp-wayland-xdnd` | Drag and drop over Xwayland in a Wayland session. |
| `0014-dndcp-native-drag-overlay` | Maps a layer-shell overlay for a native drag. |
| `0015-dndcp-native-drag-start` | Starts a native `wl_data_device` drag from the faked press. |
| `0016-dndcp-native-drag-host-to-guest` | Uses the native drag for host to guest drags. |
| `0017-dndcp-native-drag-placeholders` | Stages placeholders and blocks only at the drop, for every file drag. |
| `0018-dndcp-native-drag-accept` | Releases only once the target accepts. |
| `0019-dndcp-gnome-drag-host-to-guest` | Host to guest drags into Wayland applications on GNOME. |
| `0020-dndcp-gnome-drag-guest-to-host` | Guest to host drags on GNOME and tiling compositors. |
| `0021-dndcp-native-drop-target` | Receives guest to host drags through a native drop target where layer shell exists. |
| `0022-dndcp-staging-cleanup` | Removes staging directories once their transfers are over. |

### Using the patches elsewhere

Only `builders/`, `images/` and `packaging/` are specific to a distribution. The patches
build into any open-vm-tools 13.1.0 and need the following.

- A GTK4 build (`--with-gtk4`) for drag and drop, which lives in
  `dndUIX11GTK4.cpp` and `dragDetWndX11GTK4.cpp`. The Wayland clipboard
  backend also compiles against GTK3, but only GTK4 builds were tested.
  Upstream's GTK4 code uses the `signal<R, T...>` syntax that newer
  libsigc++ 3 releases removed. Fedora's package carries
  `open-vm-tools-sigc++3.patch` for it, and the Arch package reuses it.
- `wayland-client`, `wayland-scanner` and `wayland-protocols` 1.39 or later,
  found through pkg-config. The build generates the protocol code from their
  XML and from the vendored `wlr-layer-shell` XML. Configure turns Wayland
  support on when they are all present. `--with-wayland` makes it fail
  without them, and `--without-wayland` builds the upstream X11 plugin.
- `ext-data-control-v1` in the compositor for the full clipboard, and
  `zwlr_layer_shell_v1` plus the uinput descriptor for the native drag source.

## Images and packages

Each build produces these. `targets.json` lists them, and CI builds from it.

| Target | Built from | Where |
|---|---|---|
| Bazzite image | `ghcr.io/ublue-os/bazzite:stable`, Fedora 44 RPMs | `ghcr.io/goproslowyo/bazzite-ovt`, tags `latest` and `YYYYMMDD` |
| Fedora COSMIC Atomic image | `quay.io/fedora-ostree-desktops/cosmic-atomic:45`, Fedora 45 RPMs | `ghcr.io/goproslowyo/fedora-cosmic-ovt`, tags `latest`, `45` and `YYYYMMDD` |
| RPMs for Fedora 43, 44 and 45 | Fedora's `open-vm-tools` source rpm for that release | [Releases](https://github.com/goproslowyo/ovt-wayland/releases) |
| .debs for Debian 13, testing and sid, and Ubuntu 24.04 and 26.04 | upstream 13.1.0 source with Debian's packaging | [Releases](https://github.com/goproslowyo/ovt-wayland/releases) |
| Arch Linux package `open-vm-tools-wayland` | upstream 13.1.0 source with Arch's PKGBUILD | [Releases](https://github.com/goproslowyo/ovt-wayland/releases) |

Packages are published only as GitHub release assets. There is no dnf
repository. Each release is tagged `v<version>-<YYYYMMDD>` and carries, for
each Fedora release and each Debian or Ubuntu target, `open-vm-tools` and
`open-vm-tools-desktop`, the two packages the patches change. It also has the
patched source rpm for each Fedora release, the Arch package and a
`SHA256SUMS` file. The builders produce the other subpackages too, such as
`-devel` and `-sdmp`, but they are unchanged rebuilds and are not published.
Build them from this repository if you need them. The RPMs have release `100.fcNN.clipway`, for example
`open-vm-tools-13.1.0-100.fc44.clipway.x86_64.rpm`, so the files for
different Fedora releases have different names. Release 100 sorts above
Fedora's own build of 13.1.0, so dnf and rpm-ostree treat it as an upgrade.

## Install

### Bootc images

Switch to the image for your desktop and reboot.

```bash
sudo bootc switch ghcr.io/goproslowyo/bazzite-ovt:latest
# or
sudo bootc switch ghcr.io/goproslowyo/fedora-cosmic-ovt:latest
systemctl reboot
```

After that, `sudo bootc upgrade` and a reboot pick up new builds. To roll
back, run `sudo bootc rollback`, or `bootc switch` back to the base image,
`ghcr.io/ublue-os/bazzite:stable` or
`quay.io/fedora-ostree-desktops/cosmic-atomic:45`. If you have a local
`rpm-ostree override replace` of open-vm-tools, remove it first with
`sudo rpm-ostree override reset open-vm-tools open-vm-tools-desktop`.
Customise the image in its Containerfile under `images/`. With local
`rpm-ostree install` changes, `bootc upgrade` refuses to run until
`rpm-ostree reset`.

The Fedora COSMIC image also enables `vmtoolsd.service` and
`run-vmblock\x2dfuse.mount`.

### RPMs on Fedora

Download `open-vm-tools` and `open-vm-tools-desktop` for your Fedora release
from the [latest release](https://github.com/goproslowyo/ovt-wayland/releases/latest). The other `open-vm-tools` subpackages, such as
`open-vm-tools-sdmp`, require the same version as `open-vm-tools` and are not
in the release. If you have one installed, remove it first or build it from
this repository.

```bash
rel=$(rpm -E %fedora)
base=https://github.com/goproslowyo/ovt-wayland/releases/latest/download
curl -LO "$base/open-vm-tools-13.1.0-100.fc$rel.clipway.x86_64.rpm"
curl -LO "$base/open-vm-tools-desktop-13.1.0-100.fc$rel.clipway.x86_64.rpm"
curl -LO "$base/SHA256SUMS"
sha256sum -c --ignore-missing SHA256SUMS
```

On an atomic desktop such as Silverblue, Kinoite or Bazzite, replace the
base image's packages and reboot.

```bash
sudo rpm-ostree override replace \
    ./open-vm-tools-13.1.0-100.fc$rel.clipway.x86_64.rpm \
    ./open-vm-tools-desktop-13.1.0-100.fc$rel.clipway.x86_64.rpm
systemctl reboot
```

`sudo rpm-ostree override reset open-vm-tools open-vm-tools-desktop` undoes
it.

On Fedora Workstation and other dnf systems, install them over the stock
packages, restart the service and log out and back in.

```bash
sudo dnf install \
    ./open-vm-tools-13.1.0-100.fc$rel.clipway.x86_64.rpm \
    ./open-vm-tools-desktop-13.1.0-100.fc$rel.clipway.x86_64.rpm
sudo systemctl restart vmtoolsd
```

If Fedora later ships a newer `open-vm-tools` version, a normal update
replaces this build with it. `sudo dnf distro-sync open-vm-tools
open-vm-tools-desktop` goes back to Fedora's build.

### Debs on Debian and Ubuntu

Download the `open-vm-tools` and `open-vm-tools-desktop` .debs for your
release from the latest release and install them with
`sudo apt install ./open-vm-tools_*.deb ./open-vm-tools-desktop_*.deb`.
[builders/debian-deb/README.md](builders/debian-deb/README.md) has the full
steps.

### Arch Linux

Download `open-vm-tools-wayland-*-x86_64.pkg.tar.zst` from the latest
release and install it. It replaces `open-vm-tools`; answer yes when pacman
asks to remove it.

    sudo pacman -U ./open-vm-tools-wayland-*-x86_64.pkg.tar.zst
    sudo systemctl enable --now vmtoolsd.service vmware-vmblock-fuse.service

Log out and back in so `vmtoolsd -n vmusr` starts with the new plugin.
`vmware-vmblock-fuse.service` mounts `/run/vmblock-fuse`, which file paste
and host to guest file drags need. pacman does not upgrade the package from
the Arch repositories, so install each new release the same way. To go back,
run `sudo pacman -S open-vm-tools`.
[packaging/arch/README.md](packaging/arch/README.md) explains how the
package is built.

### Verifying signatures

CI signs each image with cosign. The image installs `cosign.pub` as
`/etc/pki/containers/<image>.pub`, adds a `sigstoreSigned` policy for its
repository to the containers policy, and enables sigstore attachments in
`/etc/containers/registries.d/<image>.yaml`, where `<image>` is `bazzite-ovt`
or `fedora-cosmic-ovt`. Bazzite keeps its policy in
`/etc/containers/policy.json`, and Fedora 45 in
`/usr/share/containers/policy.json`.

A machine that has its own `/etc/containers/policy.json`, for example one
upgraded from Fedora 44 or edited by hand, reads only that file, so the
policy in the COSMIC image does not apply there. Check with
`grep fedora-cosmic-ovt /etc/containers/policy.json`; if the file exists and
the image is missing from it, copy the entry from
`/usr/share/containers/policy.json` or remove the local file.

Because the policy ships inside the image, the first switch from the base
image cannot check the signature. Once the machine runs the image, every
`bootc upgrade` and `bootc switch` to its repository pulls through that
policy, and a build without a valid signature is refused.

Bazzite's policy has `reject` as its top-level default, so there you can also
pass `--enforce-container-sigpolicy`, which makes bootc check that the policy
requires signatures before it pulls.

```bash
sudo bootc switch --enforce-container-sigpolicy ghcr.io/goproslowyo/bazzite-ovt:latest
```

Fedora's policy accepts anything by default, and
`--enforce-container-sigpolicy` refuses such a policy, so on the COSMIC image
use plain `bootc switch` and `bootc upgrade`. The repository entry still
applies to them. The `ostree-image-signed:docker://` form is for
`rpm-ostree rebase`. `bootc switch` takes a plain image reference.

## Building

CI builds on every push to `main` that changes more than Markdown files or
`LICENSE`, every Monday at 07:00 UTC, and on manual dispatch. It reads
`targets.json`, builds the RPMs for each Fedora release in it, the .debs for
each Debian and Ubuntu target and the Arch package, uploads them as workflow
artifacts named `pkg-rpm-fcNN`, `pkg-deb-<name>` and `pkg-arch`, and builds
each image from its release's RPMs. Only a run on `main` pushes the images
with their tags, signs each pushed digest, fails if `cosign verify` against
`cosign.pub` does not pass, and creates or updates the GitHub release for that
day. The release job attaches the files of every artifact whose name starts
with `pkg-`, turns `~` in file names into `.` as GitHub would, and fails if
two files end up with the same name. A target that fails does not hold back
the rest. The release goes out with the packages that built, and its notes say
which kinds are missing. A second run on the same day replaces that day's
assets and removes any it did not build.

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

`SIGNED_REPO` names the repository the image's signature policy covers and
defaults to the image's repository under `ghcr.io/goproslowyo`. To sign in a
fork, run `COSIGN_PASSWORD="" cosign generate-key-pair`, add `cosign.key` as
the `SIGNING_SECRET` repository secret, and commit `cosign.pub`. Never commit
`cosign.key`.

The build fails rather than ship an unpatched binary. It checks the source
rpm against Fedora's release key, pins `OVT_VERSION` and stops if Fedora ships
another version, and greps the built `libdndcp.so` for at least one log
string from each patch. Each image checks that its RPMs come from the same
Fedora release as its base.

To add a patch, put it in `patches/` named `NNNN-<name>.patch` with `<name>`
in `[A-Za-z0-9._-]`. The builder registers every patch there in sorted order
as `Patch101` onward, after Fedora's own.

### Adding an image

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

## Debugging

`vmtoolsd -n vmusr` starts from `/etc/xdg/autostart/vmware-user.desktop`
through `vmware-user-suid-wrapper`, which passes the uinput and vmblock
descriptors. Do not replace it with a unit that runs `vmtoolsd` directly,
since that breaks file paste and drag and drop.

Logging is off by default. To turn it on, add this to
`/etc/vmware-tools/tools.conf` and log out and back in.

```ini
[logging]
log = true
vmusr.level = debug
vmusr.handler = file
vmusr.data = /run/user/1000/vmusr.log
```

The log records the path of every file pasted or dragged, so keep it in your
own runtime directory. Use `grep -a`, since some upstream lines contain NULs.

```bash
log=/run/user/$(id -u)/vmusr.log
grep -a 'ping reply caps' $log              # want 1555 and aab
grep -a 'using ext-data-control-v1' $log    # native clipboard
grep -a 'reading the selection only' $log   # wl-clipboard fallback, "through X"
grep -a 'vmblock' $log                      # want "ready"
grep -a 'drag source' $log                  # native drag source ready, or why not
```

- A host to guest file paste logs `added block for`, then
  `paste observed, requesting files` only when you paste. A transfer at copy
  time is a bug.
- A guest to host drag logs `managed after`,
  `XDND accept reached the detection window`, then
  `drag entering, telling the host`.
- A native host to guest drag logs `placeholders under`,
  `drag started from serial` and `formats natively`. On the drop it logs
  a `target` line that says `is willing`, then `the target took the drop`.
  `never agreed` means the button came up on a refusal.
- A GNOME host to guest drag logs `above other windows`, `DND drag begin`
  and `moving to the host's pointer`. On the drop, a `releasing, target` line
  says `accepted`, or `never accepted` when Mutter did not bridge the drag.
  `GTK did not start the drag` means the press missed the detection window.
  `the pointer never reached the detection` window usually means the host
  still holds the button from a guest to host drag.
- A native guest to host drag logs `native drop target shown on`,
  `a drag entered the drop target, reading text/uri-list` and
  `drag entering, telling the host`. On the drop it logs
  `finished the drop of`. `nothing reached the native drop target` means it
  fell back to the detection window.
- `the guest drag outlived the drop; cancelling it` means patch 0020 pressed
  Escape after a guest to host drop on GNOME.
- `PruneStagingDirectories` logs `removed` and the path of each staging
  directory it deletes.

A copy from guest to host logs nothing until the host asks for the
selection, which happens when you paste on the host, not at copy time.

## Credits and licence

The clipboard backend is derived from
[clipway](https://github.com/krisztianfekete/clipway) by Krisztián Fekete,
which provided the original text-only version. LGPL-2.1, inherited from
open-vm-tools.
