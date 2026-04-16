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

## Quick Start

```bash
# 1. Verify prerequisites
make check

# 2. Deploy an example
make 00-ops-nginx-qemu     # nginx in QEMU via cloud-init
make 02-ops-hello-dd        # Go HTTP server dd'd to disk

# 3. Get the IP and test
make ip
curl http://$(make -s ip):8080

# 4. SSH into the server (cloud-init examples only)
make ssh

# 5. Clean up
make destroy
```

### Prerequisites

- **hcloud CLI** >= 1.62 — [Install guide](https://github.com/hetznercloud/cli/blob/main/docs/tutorials/setup-hcloud-cli.md)
- **HCLOUD_TOKEN** — `export HCLOUD_TOKEN="<your-token>"` or `hcloud context create <name>`
- **ops CLI** — `curl https://ops.city/get.sh | sh` (examples 01, 02)

### Server reuse

All examples share one Hetzner VM (`SERVER=unikernel-example`). First run creates it; subsequent runs rebuild it. This avoids hourly billing for multiple servers. Run `make destroy` when done.

## Examples

| # | Target | Description | Requires |
|---|---|---|---|
| 00a | `make 00-ops-nginx-qemu` | OPS nginx in QEMU via cloud-init | hcloud |
| 00b | `make 00-kraft-nginx-qemu` | Kraftkit nginx in QEMU via cloud-init | hcloud |
| 01 | `make 01-ops-hello-http` | Native OPS deploy: snapshot + instance | hcloud, ops, object storage |
| 02 | `make 02-ops-hello-dd` | OPS image dd'd to disk, HTTP server on :8080 | hcloud, ops |

### Example 00a/00b: QEMU via cloud-init

Spins up a Hetzner VM, installs OPS or Kraftkit via cloud-init, and runs a unikernel inside QEMU on the VM. No local tooling needed beyond `hcloud`.

### Example 01: Native OPS deployment

Uses `ops image create -t hetzner` to build the image, upload to Hetzner Object Storage, create a snapshot, and boot an instance from it. Requires object storage credentials:

```bash
export OBJECT_STORAGE_KEY="<your-key>"
export OBJECT_STORAGE_SECRET="<your-secret>"
```

### Example 02: dd deployment (no object storage)

Builds the OPS image locally with `ops build -t hetzner`, uploads it to the VM via `scp`, writes it to `/dev/sda` with `dd`, and power-cycles the server. No object storage needed — ideal for dev iteration.

```bash
make 02-ops-hello-dd
curl http://$(make -s ip):8080
```

## License

MIT