# hetzner-unikernels

Unikernel examples and tooling for [Hetzner Cloud](https://hetzner.com/cloud) and [Hetzner dedicated servers](https://hetzner.com/dedicated).

## Why Unikernels?

**Minimal attack surface.** A unikernel compiles only what your application needs into the boot image. No shell, no SSH, no package manager, no init system. There's nothing to log into and nothing to exploit. This is zero-trust infrastructure at the OS level.

**Fast boot.** Sub-second to a few seconds, compared to 30–60 seconds for a full VM. That changes how you think about elasticity — spin up on demand, destroy when done, no idle resources.

**Tiny footprint.** Images are megabytes, not gigabytes. Less RAM, less disk, less network transfer. On Hetzner where you pay per resource, that's real money — a small instance running a unikernel can do the work that would need a larger VM with a full OS.

**Immutable deployments.** The image is the deployment. No configuration drift, no patch Tuesday, no "works on my machine." Rebuild and redeploy — infra-as-code taken to its logical end.

**High density.** Each instance is tiny, so you can pack many more onto the same hardware. A single dedicated Hetzner server could run dozens of unikernel VMs where you'd run a handful of containers or traditional VMs.

### The honest caveat

Unikernels aren't for everything. Debugging is harder, the ecosystem is smaller, and you're giving up generality for specialization. If you need a full userspace, you shouldn't be running a unikernel. But for stateless services, API endpoints, edge functions, and network functions — things that do one thing with minimal overhead and maximal security — unikernels are the right tool.

## Supported Runtimes

| Runtime | Language | Hetzner Cloud VMs | Hetzner Dedicated | Notes |
|---|---|---|---|---|
| [Nanos](https://ops.city) | Go, Node, Python, Rust, C… | ✅ QEMU / Native | ✅ KVM | Fast deploy via `ops` CLI |
| [Unikraft](https://unikraft.org) | C, C++, Rust, Go, Python… | ✅ QEMU (TCG) | ✅ KVM | Not a native deployment target |

> **Hetzner Cloud VMs** don't support nested virtualization. To run unikernels on these VMs, both Nanos and Unikraft must be wrapped in QEMU using TCG (Tiny Code Generator) emulation. This bypasses the host's lack of KVM capabilities and allows the unikernel kernels to boot.

## Quick Start

```bash
# 1. Verify prerequisites
make check

# 2. Deploy example 00 — Nanos nginx in QEMU
make 00-ops-nginx-qemu

# 3. Get the IP and test
make 00-ops-nginx-qemu-ip
curl http://<IP>:8083

# 4. Clean up
make 00-ops-nginx-qemu-destroy
```

### Prerequisites

- **hcloud CLI** — [Install guide](https://github.com/hetznercloud/cli/blob/main/docs/tutorials/setup-hcloud-cli.md)
- **HCLOUD_TOKEN** — `export HCLOUD_TOKEN="<your-token>"` or `hcloud context create <name>`

No local ops installation needed — the unikernel is built on the remote server via cloud-init.

## Examples

| # | Example | Description |
|---|---|---|
| 00a | [`00-ops-nginx-qemu`](examples/00-ops-nginx-qemu/) | Nanos nginx unikernel in QEMU on a Hetzner VM |
| 00b | [`00-kraft-nginx-qemu`](examples/00-kraft-nginx-qemu/) | Unikraft nginx unikernel in QEMU (TCG) on a Hetzner VM |

## License

MIT