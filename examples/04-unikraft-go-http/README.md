# 04-unikraft-go-http — Go HTTP server on Unikraft, dd'd to disk

## Why

This picks up where `03-unikraft-console` leaves off. Same two-piece Unikraft model (elfloader kernel + CPIO initramfs), same dd deploy — but now the initramfs carries a Go HTTP server instead of a hello-world, and the kernel has lwip + virtio-net compiled in so it can actually receive connections.

The result is a real unikernel web server: a single-purpose VM image, no OS, no processes, one binary, ~50 MB of memory, booted from zero in under a second.

## How it works

```
   server.go ──┐
               │  Dockerfile (Go static-pie)   ┌─ elfloader kernel
               └─▶ CPIO initramfs              │  (with lwip + virtio-net)
                   (kraft build)               │  (built from third_party/)
                       │                       │
        ───────────────┼───────────────────────┘
                       │
                       ▼
              [multiboot]                    [EFI stub]
              GRUB + kernel + initramfs      ESP: BOOTX64.EFI + .initrd + .cmdl
                                                           │
                              ───── dd to ────────────────┘
                                        │
                                        ▼
                                 Hetzner VM /dev/sda
                                        │
                                        ▼
                                   power-cycle
                                        │
                                        ▼
                            ┌─────────────────────────┐
                            │  Unikraft elfloader      │
                            │   mounts initramfs       │
                            │   configures lwip NIC    │
                            │   execve /server         │
                            │   → HTTP on :8080        │
                            └─────────────────────────┘
```

The static IP is baked into the kernel cmdline at disk-build time. The deploy targets query it from hcloud automatically; for local QEMU runs the default (`10.0.2.15/24:10.0.2.2`) uses QEMU's user-mode network.

## Prerequisites

```bash
# From the repo root
make check
git submodule update --init --recursive

# Build tools
apt install gcc make flex bison libncurses-dev uuid-dev \
            dosfstools mtools gdisk \
            grub-efi-amd64-bin grub-pc-bin xorriso \
            qemu-system-x86 ovmf python3

# kraftkit
curl --proto '=https' --tlsv1.2 -sSf https://get.kraftkit.sh | sh
```

## Try it

### Build and test locally (QEMU)

```bash
cd examples/04-unikraft-go-http

# Multiboot path
make build-kernel-grub      # third_party sources → .build-multiboot/elfloader
make build                  # kraft builds the CPIO initramfs (Go binary)
make run-grub               # boots under QEMU, server on localhost:8080

# In another terminal:
curl http://localhost:8080/
# Hello from Go on Unikraft!

# EFI path
make build-kernel-efi
make run-efi                # boots under QEMU + OVMF, server on localhost:8080
```

### Deploy to Hetzner

```bash
# From the repo root (EFI / cpx, default):
make 04-unikraft-go-http

# Or multiboot / cx:
make -C examples/04-unikraft-go-http deploy-grub SERVER_TYPE=cx22

# The Makefile prints the curl command on success:
#   curl http://<SERVER_IP>:8080/
```

The deploy targets handle everything: create/rebuild the server, query its IP, bake that IP into the disk image, scp, dd, power-cycle.

## Firmware and server type

| Hetzner type | Firmware | Target | VNC console |
|---|---|---|---|
| `cx*` (Intel) | SeaBIOS | `deploy-grub` | VGA (visible) |
| `cpx*` (AMD) | UEFI | `deploy-efi` | GOP framebuffer |

The EFI defconfig includes `CONFIG_LIBUKCONSOLE_GOP=y`, which enables the GOP framebuffer driver added in our unikraft fork — so you get output in Hetzner's VNC console on cpx instances.

## Static IP

Unikraft's lwip stack takes a static IP via the kernel cmdline:

```
netdev.ip=<addr>/<prefix>:<gateway>
```

Hetzner routes each public IP as a /32 with a fixed gateway of `172.31.1.1`. The deploy targets automate this:

```makefile
deploy-efi:
    $(call ensure-server-vanilla)
    $(eval _IP := $(shell hcloud server describe $(SERVER) -o format='...'))
    $(MAKE) disk-efi IP=$(_IP)/32:$(GATEWAY)
    ...
```

To use a different gateway: `make deploy-efi GATEWAY=<your-gw>`.

## What you should see

```
$ make run-grub
Powered by Unikraft Kiviuq (0.20.0~cafd8aba)
Listening on :8080...

$ curl http://localhost:8080/
Hello from Go on Unikraft!
```

## Things that go wrong

- **`grub-mkrescue: command not found`** — install `grub-pc-bin grub-efi-amd64-bin xorriso`.
- **`craft build` fails / no initramfs** — make sure kraftkit is installed and Docker is running.
- **Server boots but curl times out** — the IP in the image doesn't match the server's real IP. This happens if you manually moved the server; run `make deploy-efi` again to rebuild and redeploy.
- **EFI VNC blank on cpx** — the GOP driver is in our fork (`feat/gop-console-stable`). Make sure `third_party/unikraft` is on that branch (check with `git -C third_party/unikraft branch`).
- **`deploy-efi` lands but VM PXE boots** — power-cycle didn't reset firmware. Run `hcloud server poweron $(SERVER)` by hand.
