# hetzner-unikernels

Five ways to run a unikernel on [Hetzner Cloud](https://hetzner.com/cloud), arranged from easiest to most hands-on. Pick one, run it, read the per-example README, then try the next.

## Why read this

Unikernels are tiny single-purpose OS images. You compile your application, a libc, a kernel, and nothing else into one binary that boots on bare metal (or a hypervisor). Result: megabyte-size images, sub-second boot, no shell to SSH into, no package manager to patch.

[Nanos/OPS](https://ops.city) has first-class Hetzner support — `ops image create -t hetzner` just works. [Unikraft](https://unikraft.org) doesn't, yet. This repo fills that gap: it shows you the deployment techniques OPS gives you for free, then shows you how to reproduce them from source for Unikraft.

The reader we have in mind: a software engineer who writes Go/Rust/C daily, knows their way around Make and Docker, has SSH'd into cloud VMs before, but has never manually assembled a multiboot GRUB image or poked at a UEFI firmware variable. We'll take you there.

## Quick start

```bash
git clone --recurse-submodules https://github.com/BrainbugCloud/hetzner-unikernels.git
cd hetzner-unikernels
export HCLOUD_TOKEN="<your-token>"       # console.hetzner.cloud → Security → API Tokens

make check                                # verifies hcloud CLI + token
make 00-ops-nginx-qemu                    # ~3 min; brings up a VM with nginx-in-QEMU
curl http://$(make -s ip):8083            # "Welcome to nginx!"

make destroy                              # when you're done, stop the billing
```

Every example uses the same shared Hetzner VM (name: `unikernel-example`). Running a different example **rebuilds** it rather than creating a second VM — keeps the bill to one VM-hour per example, not N.

### Prerequisites

- **hcloud CLI ≥ 1.62** — [install](https://github.com/hetznercloud/cli/blob/main/docs/tutorials/setup-hcloud-cli.md).
- **HCLOUD_TOKEN** in env, or `hcloud context create <name>` with an active context.
- **Example-specific**: `go`, `ops` (OPS examples), `kraft`, `gcc`, `make`, `grub-mkrescue`, `mkfs.vfat`, `qemu-system-x86` (Unikraft example). Each example's README lists what it needs.

## The examples

From simplest to most hands-on. Every entry is a directory under `examples/` with its own README and Makefile.

| # | Target | What it shows | What you learn |
|---|---|---|---|
| 00a | `make 00-ops-nginx-qemu` | Ubuntu VM installs OPS via cloud-init, runs nginx-as-a-unikernel under software QEMU | How a unikernel fits into a "safe" sandbox. 10× slower than native but zero firmware risk. |
| 00b | `make 00-kraft-nginx-qemu` | Same sandwich, but with Unikraft/kraftkit's nginx catalog image | kraftkit's `kraft run` UX; identical pattern, different runtime ecosystem |
| 01 | `make 01-ops-hello-http` | OPS uploads the image to Hetzner **object storage**, creates a Hetzner **snapshot**, boots a VM off the snapshot | "Upload once, boot many." Needs object-storage credentials. The official OPS/Hetzner path. |
| 02 | `make 02-ops-hello-dd` | Same OPS image, but `scp`'d to a throwaway Ubuntu VM and `dd`'d onto `/dev/sda` — no object storage | The `dd` trick. Fast dev-iteration. Generalises to any runtime that can produce a raw disk image. |
| 03 | `make 03-unikraft-console` | Unikraft built from source (via git submodules), packaged as a GRUB-multiboot or EFI-stub disk image, dd'd to the VM | Building a unikernel from kconfig up. Both Hetzner boot protocols (cx/SeaBIOS and cpx/UEFI). |

## Hetzner firmware matters

Server type is set at creation time and persists through rebuilds and rescales:

| Type | CPU | Firmware | GRUB multiboot | VGA in VNC | Use for |
|---|---|---|---|---|---|
| **cx** (Intel) | shared | SeaBIOS | ✅ | ✅ | 03 with `deploy-grub`, when you want to see the console |
| **cpx** (AMD) | shared | UEFI-capable | ✅ (but no VGA) | ❌ | 03 with `deploy-efi`; general-purpose default |

- Create the server as **cx** if you want VGA output in Hetzner's VNC console.
- **Rescaling cx → cpx preserves firmware** (still SeaBIOS under the hood), so VGA keeps working.
- The `dd` deploy path works on both, as long as you use `sysrq 'o'` (poweroff) + `hcloud server poweron` — `sysrq 'b'` (reboot) leaves firmware in stale state and the new disk boots to PXE.

For the full per-generation breakdown (cpx gen 1 vs gen 2, cx gen 3, ccx gen 3), the CPU feature flags each tier exposes, which combinations are orderable in which location, and which Unikraft build target fits which server class, see [`docs/compatibility.md`](docs/compatibility.md). The methodology behind that matrix — what we measure on each VM and the script that drives the sweep — is documented in [`docs/hardware-survey.md`](docs/hardware-survey.md).

## Shared server semantics

There's one `SERVER=unikernel-example` VM. Every example target either:
- **Creates it** if it doesn't exist.
- **Rebuilds it** (hcloud `server rebuild` — same VM, fresh OS) if it does.

This keeps billing tight: one VM-hour per example you run, not five. If you forget about it, **`make destroy`** deletes it. There's also `make servers` to see what's running and `make ssh` to shell in (when the current example has SSH on).

## Repo layout

```
hetzner-unikernels/
├── README.md                         — you are here
├── CONTRIBUTING.md                   — signed-commit workflow
├── Makefile                          — thin dispatcher (just delegates to examples/*)
├── lib/                              — shared Makefile fragments
│   ├── common.mk                     — config, colours, check-hcloud/check-token, ip/ssh/destroy
│   └── deploy-dd.mk                  — the scp → dd → sysrq → poweron flow
├── third_party/                      — git submodules (Unikraft sources, stable branch)
│   ├── unikraft/                     — github.com/unikraft/unikraft
│   ├── lib-lwip/                     — github.com/unikraft/lib-lwip
│   ├── lib-libelf/                   — github.com/unikraft/lib-libelf
│   └── app-elfloader/                — github.com/unikraft/app-elfloader
└── examples/
    ├── 00-ops-nginx-qemu/            — OPS + nginx in QEMU
    ├── 00-kraft-nginx-qemu/          — kraftkit + nginx in QEMU
    ├── 01-ops-hello-http/            — OPS native deploy via object storage
    ├── 02-ops-hello-dd/              — OPS dd deploy (no object storage)
    └── 03-unikraft-console/          — Unikraft from source, GRUB + EFI, dd deploy
        └── defconfigs/               — multiboot / efi (override with DEFCONFIG=...)
```

## CI

A weekly GitHub Action deploys `00-ops-nginx-qemu`, `00-kraft-nginx-qemu`, and `02-ops-hello-dd` end-to-end on a real Hetzner VM (name: `unikernel-ci`, separate from the dev `unikernel-example` so the two don't step on each other). See [`.github/workflows/test-examples.yml`](.github/workflows/test-examples.yml). Examples 01 and 03 are skipped: 01 needs a paid object-storage bucket; 03's verification is visual (serial console output), no network signal.

### Hetzner token: where it lives, how to set it

The workflow reads `HCLOUD_TOKEN` from a **repo-scoped GitHub Actions secret**. That's the only right place for it: encrypted at rest, not exposed to pull requests from forks, not in any file in this repo.

Set it once:

```bash
# From a machine where `gh` is authed (see CONTRIBUTING.md):
gh secret set HCLOUD_TOKEN --repo BrainbugCloud/hetzner-unikernels
# paste your Hetzner API token when prompted
```

Recommended: use a **project-scoped** Hetzner token (not account-root), read-write on servers, no object-storage access — the CI doesn't touch object storage. Rotate yearly or if leaked.

**Do not** check the token into `.github/workflows/*.yml`, into `../secrets/password-store.yaml.plain`, or into any file in this repo. The `../secrets/` file is for local dev (it holds a GitHub PAT used by `gh auth login`); it's not a transport for cloud-provider credentials.

To trigger a run manually (e.g., after editing the workflow or an example):

```bash
gh workflow run test-examples.yml --repo BrainbugCloud/hetzner-unikernels
gh run watch --repo BrainbugCloud/hetzner-unikernels
```

## License

MIT.
