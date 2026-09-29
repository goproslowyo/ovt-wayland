# How it works

Stock `open-vm-tools` has only an X11 copy and paste backend. Under Wayland it
can reach only Xwayland's clipboard, and most compositors refuse clipboard
reads from an unfocused Xwayland client, so copying from guest to host fails.
The patches in [`patches/`](../patches) add a Wayland clipboard backend and
make drag and drop reach native Wayland applications. X11 sessions keep the
upstream backends, with fixes for file transfers on desktops other than GNOME
and KDE.

## What each compositor gets

What each compositor gets depends on the protocols it offers. G is the guest
and H is the host.

| Compositor offers | Copy and paste | Drag H to G | Drag G to H |
|---|---|---|---|
| `ext-data-control-v1` (KWin and wlroots releases that have it) | full, native | native if it also has `zwlr_layer_shell_v1` | native with layer shell, else XDND, bridged |
| no data control, GNOME (Mutter) | full, through Xwayland | XDND, bridged by Mutter | XDND, bridged |
| no data control, anything else | off | XDND to X11 apps only | X11 sources only |

Older KWin and sway releases offer only `wlr-data-control`, which this build
does not bind, so copy and paste stays off there. The Xwayland path works only
on GNOME, where Mutter keeps the X selection and the Wayland one in step in
both directions.

## Clipboard

Where the compositor implements `ext-data-control-v1`, as KWin and wlroots do,
the backend binds it and owns the selection itself, with no window and no focus.
It offers every format the host sent and answers each request with the bytes for
the type asked for, so one selection carries RTF and plain text at once.

GNOME does not implement data control. There the backend uses the X
`CLIPBOARD` selection through Xwayland, which Mutter keeps in step with the
Wayland one for any X client, focused or not. It owns that selection through
GDK to install a host clip, with every format at once, and reads it only after
GDK reports a change. Other compositors do not keep the two selections in step
both ways, so without data control copy and paste stays off there.

An earlier `wl-clipboard` fallback was removed, because it could not run.
vmusr does not start without an X display, and on these compositors no change
ever reaches the X selection it watches.

The backend puts a deadline on every selection read and write, so a peer that
stops reading cannot stall the daemon's main loop, which also carries the RPC
channel to the host.

## Host to guest files

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

Patch 0501 removes a staging directory about two minutes after its transfer
is over. It keeps a directory while the clipboard still offers its files,
while a drag still uses it, and while any process has a file in it open or
uses it as its working directory. The check runs once a minute. It does not
delete at once, because the guest cannot tell when the target is done. After a
drop, a file manager opens the files a moment later, and some applications
read a dropped file again later.

## Drag and drop

Guest to host drag, of files or text, takes one of two paths.

- Where the compositor has `zwlr_layer_shell_v1`, patch 0405 shows the
  layer-shell overlays as a Wayland drop target. The drag enters them as it
  would any Wayland window, and the overlay reads the file list or text for
  the host. It accepts copy only, since the host reads the files after the
  drop. A drag the host cannot take goes on to the window under the overlay.
  If nothing reaches the overlay, the plugin uses the detection window below.
- Elsewhere the upstream XDND code runs with an Xwayland detection window.
  KWin and Mutter bridge its XDND to native Wayland applications. KWin
  bridges only to managed windows, so under Wayland patch 0401 keeps the
  window managed and waits until the window manager lists it before moving
  the pointer.

Host to guest drag takes one of two paths.

- Where the compositor has `zwlr_layer_shell_v1`, as sway and KWin do, and
  uinput is available, patches 0402 and 0403 run a native `wl_data_device`
  drag. It maps a transparent layer-shell overlay on each output, fakes a
  button press on it through uinput, and starts the drag from that press. The
  overlay unmaps once the drag has started. The files are empty placeholders
  until the target accepts, and the block goes on just before the button is
  released.
- GNOME has no layer shell, so the drag stays on XDND there. Patch 0404 makes
  it meet the conditions under which Mutter bridges XDND to Wayland clients.
  It keeps the detection window above the focused window, presses inside it
  and waits for GTK to start the drag before the pointer moves on, and
  releases once the target accepts or after 1.5 s. It also raises the guest
  to host drop target, and presses Escape through uinput to cancel a guest
  drag that is still running 300 ms after a guest to host drop. Both apply
  only when the X window manager says it is Mutter. Another compositor
  without layer shell gets the upstream XDND behaviour.

wlroots does not carry a drag from an X11 source to a Wayland client
([wlroots#841](https://github.com/swaywm/wlroots/pull/841)), which is why
sway needs the native path.

## Using the patches elsewhere

Only `builders/`, `images/` and `packaging/` are specific to a distribution.
The patches build into any open-vm-tools 13.1.0 and need the following.

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

The [patch table](../README.md#patches) lists what each patch does.
