# Testing

This page says how each row of the
[What works where](../README.md#what-works-where) table was tested.

## Summary

Plasma 6.7.5, sway 1.11, GNOME 50.3, COSMIC 1.8 and Xfce 4.20 on Xorg were
all tested against VMware Workstation Pro 26H1u1 on a Windows 10 host. Their
guest to host drags went through XDND. Where the compositor has layer shell,
guest to host drags now use a native drop target first (patch 0405). It was
tested with the host on Plasma 6.7.5, sway 1.11 and niri 26.04, where
xwayland-satellite cannot carry a drag into X at all. It falls back to XDND
where nothing reaches it.

Hyprland 0.56.2 from the `sdegler/hyprland` COPR could not be tested, because
its Xwayland exits on the first window any X11 client maps, `xterm` included,
and vmusr cannot start without it.

Not tested: other VMware hosts such as Fusion, and compositor releases older
than their `ext-data-control-v1` support.

## KDE Plasma

Bazzite 44 (Fedora 44) against VMware Workstation Pro 26H1u1
(26.0.1.25688693) on a Windows 10 Pro 22H2 host. Text, PNG, RTF and files in
both directions, single and multi-file, by copy and paste and by drag.
Capabilities negotiate to `0x1555` for copy and paste and `0xaab` for drag and
drop, the same set the X11 backend reports. Most drag tests predate the native
drag source and used XDND. Host drags into Dolphin 26.08.1 through the native
drag source were tested by hand, and the whole list was run again by hand with
the final build.

## sway

A Fedora 44 VM under VMware Workstation, by hand. Host drags into Thunar
4.20.9 and PCManFM (libfm 1.4.1), including multi-file drops and file names
with spaces. With the final build, text, rich text, images and files by copy
and paste in both directions, and file and text drags from guest to host.

## GNOME

Bluefin 44 under VMware Workstation with Nautilus 50.2.2, by hand. Text and
file copy and paste in both directions, images from host to guest, host drags
into Nautilus, and guest drags of files and text out of a maximized Nautilus
and Text Editor. A test program also drove the plugin's own detection window
and uinput code through the host to guest sequence, and 199 of 200 runs
landed the drop. Without patch 0404, host drags into Nautilus do not land.

## Xfce on Xorg

Xfce 4.20 with Thunar 4.20.9 on the Fedora 44 VM, by hand. Text and file copy
and paste both ways, and file drags both ways. Stock `open-vm-tools` loses
file pastes and host file drags there, since it offers file lists only on
GNOME and KDE and blocks the files before Thunar can check them.

## niri

niri 26.04 on Fedora 45 COSMIC Atomic with COSMIC Files, by hand. File drags
in both directions against the host. The pointer sizing from the Wayland
output was also tested without the host, through mode changes and a rotated
output. See the [known limits](../README.md#known-limits) for a niri setting
that affects drags.

## Compositor started from a text console

Here `XDG_SESSION_TYPE` is `tty`. vmusr was started on sway with that value,
and chose the Wayland backend and got the uinput device.
