# ovt-wayland

`open-vm-tools` 13.1.0 rebuilt so that copy and paste and drag and drop work
in a VMware guest under Wayland, in both directions, for text, RTF, PNG
images, files and file contents. It comes as RPMs for Fedora 43, 44 and 45,
.debs for Debian and Ubuntu, an Arch Linux package, and bootc images based on
Bazzite and Fedora COSMIC Atomic. It tracks open-vm-tools
[#792](https://github.com/vmware/open-vm-tools/issues/792) and
[#510](https://github.com/vmware/open-vm-tools/issues/510).

## What works where

G is the guest and H is the host. [docs/testing.md](docs/testing.md) says how
each row was tested.

| Session | Copy and paste G to H | Copy and paste H to G | Drag H to G | Drag G to H |
|---|---|---|---|---|
| KDE Plasma 6.7.5 (KWin) | works, all formats | works, all formats | works, native | works, XDND |
| sway 1.11 (wlroots) | works, all formats | works, all formats | works, native | works, XDND |
| GNOME 50.3 (Mutter) | text and files tested | text, files and images tested | works, XDND | files and text tested |
| Xfce 4.20 on Xorg | works, text and files | works, text and files | works | works |
| COSMIC 1.8 | works, text and files | works, text and files | works, native | works, XDND |
| niri 26.04 | works, text, images and files | works, text, images and files | works, native | works, native |

## Requirements

You need this in a Wayland session. In an X11 session stock `open-vm-tools`
handles GNOME and KDE, and this build adds file copy and file drags on other
desktops such as Xfce, input checks and staging cleanup. The guest needs:

- `open-vm-tools` 13.1.0 built with GTK4. The patches target that release.
- Xwayland. vmusr loads upstream's desktopEvents plugin, which needs an X
  display to start at all, and drag and drop runs through Xwayland.
- `run-vmblock\x2dfuse.mount` active, for lazy file paste and host to guest
  file drags.
- `vmtoolsd -n vmusr` started through `vmware-user-suid-wrapper`, which hands
  it the vmblock and uinput descriptors. Drag and drop under Wayland needs
  uinput.
- For copy and paste outside GNOME, a compositor with `ext-data-control-v1`.
  [How it works](docs/how-it-works.md#what-each-compositor-gets) shows what
  each compositor gets.

## Install

Packages are assets of the
[GitHub releases](https://github.com/goproslowyo/ovt-wayland/releases). There
is no dnf repository. [Building](docs/building.md#images-and-packages) lists
every target.

### Bootc images

```bash
sudo bootc switch ghcr.io/goproslowyo/bazzite-ovt:latest
# or
sudo bootc switch ghcr.io/goproslowyo/fedora-cosmic-ovt:latest
systemctl reboot
```

`sudo bootc upgrade` and a reboot pick up new builds. To roll back, run
`sudo bootc rollback`, or `bootc switch` back to the base image,
`ghcr.io/ublue-os/bazzite:stable` or
`quay.io/fedora-ostree-desktops/cosmic-atomic:45`.
Remove a local `rpm-ostree override replace` of open-vm-tools first with
`sudo rpm-ostree override reset open-vm-tools open-vm-tools-desktop`. With local
`rpm-ostree install` changes, `bootc upgrade` refuses to run until `rpm-ostree
reset`.
Customise an image in its Containerfile under `images/`. The Fedora COSMIC
image also enables `vmtoolsd.service` and `run-vmblock\x2dfuse.mount`.

### RPMs on Fedora

Download `open-vm-tools` and `open-vm-tools-desktop` for your Fedora release.
Other subpackages such as `open-vm-tools-sdmp` require the same version and
are not in the release, so remove them first or build them from this repository.

```bash
rel=$(rpm -E %fedora)
base=https://github.com/goproslowyo/ovt-wayland/releases/latest/download
curl -LO "$base/open-vm-tools-13.1.0-100.fc$rel.clipway.x86_64.rpm"
curl -LO "$base/open-vm-tools-desktop-13.1.0-100.fc$rel.clipway.x86_64.rpm"
curl -LO "$base/SHA256SUMS"
sha256sum -c --ignore-missing SHA256SUMS
```

On an atomic desktop such as Silverblue, Kinoite or Bazzite, replace the base
image's packages and reboot. `sudo rpm-ostree override reset open-vm-tools
open-vm-tools-desktop` undoes it.

```bash
sudo rpm-ostree override replace \
    ./open-vm-tools-13.1.0-100.fc$rel.clipway.x86_64.rpm \
    ./open-vm-tools-desktop-13.1.0-100.fc$rel.clipway.x86_64.rpm
systemctl reboot
```

On Fedora Workstation and other dnf systems, install over the stock packages,
restart the service, and log out and back in. A newer Fedora `open-vm-tools`
replaces this build on a normal update. `sudo dnf distro-sync open-vm-tools
open-vm-tools-desktop` goes back to Fedora's build.

```bash
sudo dnf install \
    ./open-vm-tools-13.1.0-100.fc$rel.clipway.x86_64.rpm \
    ./open-vm-tools-desktop-13.1.0-100.fc$rel.clipway.x86_64.rpm
sudo systemctl restart vmtoolsd
```

### Debs on Debian and Ubuntu

Download the `open-vm-tools` and `open-vm-tools-desktop` .debs for your release
and run `sudo apt install ./open-vm-tools_*.deb ./open-vm-tools-desktop_*.deb`.
[builders/debian-deb/README.md](builders/debian-deb/README.md) has the full
steps.

### Arch Linux

Download `open-vm-tools-wayland-*-x86_64.pkg.tar.zst` and install it. It
replaces `open-vm-tools`, so answer yes when pacman asks to remove it.

    sudo pacman -U ./open-vm-tools-wayland-*-x86_64.pkg.tar.zst
    sudo systemctl enable --now vmtoolsd.service vmware-vmblock-fuse.service

Log out and back in so `vmtoolsd -n vmusr` starts with the new plugin. The
vmblock service mounts `/run/vmblock-fuse`, which file paste and host to guest
file drags need. pacman does not upgrade the package from the Arch
repositories, so install each new release the same way. `sudo pacman -S
open-vm-tools` goes back.

## Known limits

- If you let go of a drag within about 100 ms of entering the VM, the host
  cancels it before the guest learns the pointer position.
- On GNOME a host to guest drag starts about half a second after the pointer
  enters the VM. A sooner drop waits for it.
- On GNOME, after a guest to host drag, move the pointer over the guest once
  before dragging from the host. Until then the host holds the guest mouse
  button down and the drag fails.
- A host copy with only RTF, as AbiWord's, pastes only into applications that
  accept RTF.
- PCManFM (libfm 1.4.1) can crash when a drag leaves it before the data
  arrives. This is a libfm bug.
- If the VMware window scales the guest display, host to guest drags land
  beside the host pointer. Use a guest resolution that fits the window, such
  as View, Autosize, Autofit Guest.
- The host changes a file name it cannot use. Windows does not allow `:`, so
  the host writes it as `^%`.
- An application that reads a dropped file more than two minutes after the
  drop, such as a browser upload form, finds it gone. Drop into a file manager
  first.
- Pasted files keep the permissions the host reports, so a read-only Windows
  file arrives read-only. That is upstream behaviour.
- A tiling compositor that tiles the detection window stretches it over the
  drop target. Sway floats it on its own. Elsewhere float it in the
  compositor's configuration, for example in sway syntax `for_window
  [title="vmware-user"] floating enable`.
- The host sends its clipboard a moment after the VM gets focus, so an instant
  paste can get the previous clip.
- COSMIC Files can paste a stale clipboard. Reopen the window.
- On niri, vmusr can start before X is ready and exit. Log in again.
- On niri, set `gestures { dnd-edge-view-scroll { trigger-width 0; }; }`. Its
  edge scrolling can stop guest to host drags.

## Patches

Fifteen patches against `open-vm-tools 13.1.0-25218885`, applied in order and
numbered by group. Each builds on its own and explains its reasoning in its
commit message. The 01 group changes only upstream code, applies to X11
sessions as well and could go upstream on its own.

| Patch | What it does |
|---|---|
| **01, fixes to upstream code** | |
| `0101-dndcp-validate-host-input` | Validates file lists and file names from the host and from drag sources. |
| `0102-dndcp-any-desktop-file-drop` | Offers file drops and file pastes on desktops other than GNOME and KDE. |
| `0103-dndcp-fake-pointer` | Keeps the faked pointer on the screen and never leaves its button down. |
| `0104-dndcp-drag-read-uri-list` | Reads a guest drag as `text/uri-list` or text instead of through the file portal. |
| **02, Wayland clipboard** | |
| `0201-dndcp-wayland-configure` | Adds `--with-wayland` and generates the protocol code at build time. |
| `0202-dndcp-data-control-client` | Clipboard client for `ext-data-control-v1`. |
| `0203-dndcp-wayland-clipboard` | Copy and paste in both directions through data control. |
| `0204-dndcp-gnome-xselection-clipboard` | Copy and paste through the Xwayland selection on GNOME. |
| **03, files** | |
| `0301-dndcp-wayland-file-copy-paste` | File copy to the host, and lazy file paste from the host through vmblock. |
| **04, drag and drop** | |
| `0401-dndcp-wayland-xdnd` | Drag and drop over Xwayland in a Wayland session. |
| `0402-dndcp-native-drag-source` | A native `wl_data_device` drag from a layer-shell overlay and a faked press. |
| `0403-dndcp-native-drag-host-to-guest` | Host to guest drags through the native drag, with placeholders and a release once the target accepts. |
| `0404-dndcp-gnome-drag` | Drags in both directions on GNOME, and guest to host drags on tiling compositors. |
| `0405-dndcp-native-drop-target` | Guest to host drags through a native drop target where layer shell exists. |
| **05, cleanup** | |
| `0501-dndcp-staging-cleanup` | Removes staging directories once their transfers are over. |

## More documentation

- [How it works](docs/how-it-works.md) covers the clipboard, file transfer,
  drag and drop, and use of the patches in other builds.
- [Testing](docs/testing.md) says how each desktop was tested.
- [Building](docs/building.md) covers local builds, CI, releases and adding an
  image.
- [Verifying signatures](docs/signatures.md) explains the cosign policy in the
  images.
- [Debugging](docs/debugging.md) shows how to turn on the log and what to look
  for.
- [builders/debian-deb/README.md](builders/debian-deb/README.md) and [packaging/arch/README.md](packaging/arch/README.md) explain how the .debs and the Arch package are built.

## Credits and licence

The clipboard backend is derived from
[clipway](https://github.com/krisztianfekete/clipway)
by Krisztián Fekete, which provided the original text-only version.
LGPL-2.1, inherited from open-vm-tools.
