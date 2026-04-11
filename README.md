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
| [Nanos / OPS](https://ops.city) | Go, Node, Python, Rust, C… | ✅ Native (object storage + cloud-init) | ✅ KVM | First-class Hetzner support via `ops` CLI |
| [Unikraft](https://unikraft.org) | C, C++, Rust, Go, Python… | ⚠️ Custom boot setup required | ✅ KVM | No nested virt on cloud VMs; works on dedicated |

> **Hetzner Cloud VMs** don't support nested virtualization. OPS works around this with a cloud-init + `dd` approach — boot a generic Ubuntu VM, write the unikernel image directly to disk, and reboot into it. Other runtimes can use the same technique but need manual setup.

## Examples

See the [`examples/`](examples/) directory for ready-to-deploy unikernel examples.

## License

MIT