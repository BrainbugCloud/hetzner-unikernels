# 03-unikraft-console — Unikraft hello-world, built from source, dd'd to disk

## Why

This is where we stop using OPS and start building from scratch. Unikraft is a second unikernel ecosystem (C-focused, research-rooted) that doesn't have OPS's slick Hetzner integration. It also has an extremely configurable kernel build — Linux-style `defconfig`, kconfig, the whole menuconfig shebang — and supports two boot protocols:

- **GRUB multiboot** — traditional BIOS-style, boots anywhere SeaBIOS works.
- **EFI stub** — the kernel *is* a PE32+ executable; the UEFI firmware boots it directly, no GRUB in between.

Hetzner has two flavours of VM, and they map one-to-one onto these protocols:

| Hetzner type | Firmware | Uses protocol | VGA on VNC? |
|---|---|---|---|
| `cx*` (Intel) | SeaBIOS | GRUB multiboot | yes |
| `cpx*` (AMD) | UEFI-capable | EFI stub | no |

So this example gives you two recipes for turning the same unikernel source into a bootable Hetzner VM disk, depending on which server flavour you want to target.

## Prerequisites

```bash
# From the repo root
make check                                 # hcloud + token
git submodule update --init --recursive    # first time only

# Build tools
apt install gcc make flex bison libncurses-dev uuid-dev \
            dosfstools mtools gdisk \
            grub-efi-amd64-bin grub-pc-bin xorriso \
            qemu-system-x86 ovmf python3

# kraftkit (builds the initramfs via Dockerfile)
curl --proto '=https' --tlsv1.2 -sSf https://get.kraftkit.sh | sh
```

If you forget `--recurse-submodules` on clone: `git submodule update --init`.

## How it works

```
   helloworld.c ──┐
                  │  Dockerfile (gcc + libc)    ┌─ elfloader kernel
                  └─▶ CPIO initramfs            │  (built from
                      (kraft build)             │   third_party/unikraft
                          │                     │   + third_party/app-elfloader)
                          │                     │
         ┌────────────────┼─────────────────────┘
         │                │
         ▼                ▼
   [multiboot]                       [EFI stub]
   grub.cfg + kernel + initramfs     ESP: BOOTX64.EFI + .initrd + .cmdl
            │                                   │
            ▼                                   ▼
   grub-mkrescue → grub-disk.img     sgdisk + mkfs.vfat → efi-disk.img
            │                                   │
            └──────────── dd to ───────────────┘
                              │
                              ▼
                        Hetzner VM's /dev/sda
                              │
                              ▼
                         power-cycle
                              │
                              ▼
                   ┌──────────────────────┐
                   │ Unikraft elfloader   │
                   │  mounts initramfs    │
                   │  execve /helloworld  │
                   │  → serial console    │
                   └──────────────────────┘
```

The **elfloader** is the interesting bit. It's a generic Unikraft kernel that, at boot, mounts a CPIO initramfs (shipped via GRUB module or the ESP) and `execve`s an ELF binary out of it. Your "application" is a regular `gcc -pie -fPIC` binary — no Unikraft linkage, no `#include <uk/...>`. That makes porting trivial: if you can statically-ish build your Go/Rust/C app into a PIE, the elfloader can run it.

## Try it

### Build and test locally (QEMU)

```bash
cd examples/03-unikraft-console

# Multiboot path (~2-3 min first build, then cached)
make build-kernel-grub      # third_party sources → .build-multiboot/elfloader
make build                  # kraft builds the CPIO initramfs
make disk-grub              # grub-mkrescue → image/grub-disk.img (14 MB)
make run-grub               # boots under QEMU, prints hello-world

# EFI path
make build-kernel-efi
make disk-efi               # sgdisk + mkfs.vfat → image/efi-disk.img (12 MB)
make run-efi                # boots under QEMU + OVMF, prints hello-world
```

### Deploy to Hetzner

```bash
# From the repo root:
make 03-unikraft-console              # default: GRUB/multiboot on cpx22

# Or explicitly:
make -C examples/03-unikraft-console deploy-grub
make -C examples/03-unikraft-console deploy-efi
```

For **VGA output visible in Hetzner's VNC console**, the VM has to be created as a **cx** (Intel/SeaBIOS) type, not `cpx`. Rescaling cx → cpx preserves firmware, so the VGA keeps working after upgrade. `SERVER_TYPE=cx22 make 03-unikraft-console` if this is a fresh deployment.

## Switching to an experimental Unikraft branch

The stable branch is pinned by the submodules. To try `staging`, someone's fork, or a feature branch:

```bash
# Checkout all four Unikraft submodules to the same branch in one shot:
make -C examples/03-unikraft-console use-branch UK_BRANCH=staging

# Or just core:
git -C third_party/unikraft checkout staging

# Rebuild:
rm -rf examples/03-unikraft-console/.build-*
make -C examples/03-unikraft-console build-kernel-grub
```

When you're done, `git -C third_party/<repo> checkout stable` returns to the pinned state.

## Using a custom defconfig

The Makefile defaults to `defconfigs/multiboot` (or `defconfigs/efi` for the EFI build). To try a variant:

```bash
cp defconfigs/multiboot defconfigs/multiboot-networking
# edit it (add CONFIG_LIBLWIP=y etc.)
make build-kernel-grub DEFCONFIG=defconfigs/multiboot-networking
```

Anything Unikraft's kconfig accepts goes here. The resulting kernel still uses the `grub-disk.img` flow; only the kernel binary changes.

## What you should see

```
$ make run-grub
Powered by Unikraft Kiviuq (0.20.0~07044e69)
Hello World from Unikraft on Hetzner!
..............

$ make run-efi                                   # QEMU + OVMF
BdsDxe: loading Boot0001 "UEFI QEMU HARDDISK..."
BdsDxe: starting Boot0001 "UEFI QEMU HARDDISK..."
[    0.000000] ERR:  [libvgacons] Could not initialize the VGA driver
Powered by Unikraft Kiviuq (0.20.0~07044e69)
Hello World from Unikraft on Hetzner!
..............
```

(The VGA-init error in the EFI build is expected — UEFI exits boot services before Unikraft tries to probe VGA. We rely on serial or GOP instead.)

## Things that go wrong

- **`grub-mkrescue: command not found`** — install `grub-pc-bin grub-efi-amd64-bin xorriso`. On stripped Ubuntu minimal images these aren't pulled in by default.
- **Submodule dirs are empty** — `git submodule update --init`. Or re-clone with `--recurse-submodules`.
- **Kernel build fails on `mkfs.vfat` / `mmd` / `sgdisk`** — install `dosfstools mtools gdisk`.
- **`make run-efi` hangs at `Booting from Hard Disk...`** — OVMF files missing. Set `OVMF_CODE=/path/to/OVMF_CODE.fd` and `OVMF_VARS=/path/to/OVMF_VARS.fd` to where your distro keeps them.
- **`deploy-grub` to a cpx server: no output in VNC** — expected. cpx is UEFI-only (no VGA console). Either use `deploy-efi` on cpx, or create a cx-flavour server.
- **`deploy-efi` lands and VNC shows PXE boot** — the disk image is fine but the power-cycle didn't reset firmware. Watch for the sequence: Makefile prints "Waiting for server to power off", then "Powering on". If the server doesn't leave the powered-off state, `hcloud server poweron unikernel-example` by hand.

## What's actually pinned

```
third_party/unikraft        07044e69cb3d  Release: v0.20.0 Kiviuq
third_party/lib-lwip        82a9126286fe
third_party/lib-libelf      5d6c4d49bcc3
third_party/app-elfloader   d122bbdb9f24
```

These are the HEADs of each repo's `stable` branch at the time the submodules were added. Nothing forces you to stay there — switch branches freely via `make use-branch` or ad-hoc `git checkout`, and the build picks it up on next `make build-kernel-*`.
