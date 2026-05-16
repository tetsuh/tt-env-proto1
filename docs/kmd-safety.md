# KMD safety operations

`tt-env` proto1 treats the Tenstorrent Kernel Mode Driver (KMD) as a singleton
system resource. KMD operations are intentionally conservative: they stop before
changing module state when devices are in use, Secure Boot is enabled, or the
current state cannot be checked safely.

## Scope

Proto1 supports Ubuntu 22.04 with Secure Boot disabled. It can install the
`tenstorrent-dkms` package, load the `tenstorrent` module, and swap an already-loaded
module by unloading and reloading it. MOK enrollment and Secure Boot workflows
are out of scope for proto1.

## Safety protocol

Before a KMD install or swap operation, proto1 checks whether Secure Boot is
applicable:

1. If `/sys/firmware/efi` does not exist, the machine is treated as non-EFI and
   Secure Boot is not applicable.
2. On EFI systems, `mokutil --sb-state` must be available and must report
   `SecureBoot disabled` or `SecureBoot not enabled`.
3. If Secure Boot is enabled, proto1 aborts and prints a message naming the
   proto1 limitation.

Before swapping a loaded module, proto1 also runs the device preflight:

1. It enumerates `/dev/tenstorrent/*`.
2. It checks device holders with `lsof`, or `fuser` when `lsof` is unavailable.
3. If any process holds a device node, the operation aborts and reports the PID
   and command name.
4. If neither `lsof` nor `fuser` is available when device nodes exist, the
   preflight fails closed.

Only after those checks pass does proto1 unload or load the KMD module.

## Swap and rollback behavior

When the module is already loaded, proto1 unloads it with `rmmod` and then
reloads it with `modprobe`. If the reload fails, proto1 attempts a rollback by
loading the same module again:

- If rollback succeeds, proto1 logs the rollback and returns a non-zero status
  so the caller knows the requested swap did not complete.
- If rollback also fails, proto1 exits with an error because the machine is left
  without the expected KMD module loaded.

When the module is not already loaded, proto1 only runs `modprobe`. If that load
fails, there is no prior loaded state to restore, so the operation exits with an
error.

## Failure modes and recovery

| Failure | Meaning | Operator action |
|---|---|---|
| Secure Boot enabled | Proto1 cannot safely manage KMD on this host. | Disable Secure Boot or use a future workflow that supports MOK enrollment. |
| `mokutil` missing on EFI | Proto1 cannot verify Secure Boot state. | Install `mokutil`, then retry. |
| Device holders found | A process is using `/dev/tenstorrent/*`. | Stop the reported processes or workloads, then retry. |
| `lsof` and `fuser` missing | Proto1 cannot prove devices are idle. | Install `lsof` or `fuser`, then retry. |
| `rmmod` fails | The loaded module could not be removed. | Inspect kernel logs and active users of the module before retrying. |
| `modprobe` fails after unload | Reload failed and rollback is attempted. | If rollback succeeds, inspect package/module state before retrying. If rollback fails, load the module manually or reboot into a known-good state. |

## Manual checks

On real Ubuntu 22.04 hardware, operators can inspect the same state manually:

```bash
mokutil --sb-state
sudo lsof /dev/tenstorrent/*
sudo fuser /dev/tenstorrent/*
lsmod | grep -w '^tenstorrent'
```

Do not force `rmmod` while workloads are active. Stop Tenstorrent applications
first, confirm that no process holds device nodes, then retry the KMD operation.
