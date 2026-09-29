# Debugging

`vmtoolsd -n vmusr` starts from `/etc/xdg/autostart/vmware-user.desktop`
through `vmware-user-suid-wrapper`, which passes the uinput and vmblock
descriptors. Do not replace it with a unit that runs `vmtoolsd` directly,
since that breaks file paste and drag and drop.

## Turn on logging

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
grep -a 'reading the selection only' $log   # GNOME X selection, "through X"
grep -a 'vmblock' $log                      # want "ready"
grep -a 'drag source' $log                  # native drag source ready, or why not
```

## What the log should show

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
- `the guest drag outlived the drop; cancelling it` means patch 0404 pressed
  Escape after a guest to host drop on GNOME.
- `PruneStagingDirectories` logs `removed` and the path of each staging
  directory it deletes.

A copy from guest to host logs nothing until the host asks for the
selection, which happens when you paste on the host, not at copy time.
