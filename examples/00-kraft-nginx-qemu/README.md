# 00-kraft-nginx-qemu — kraftkit + nginx, running in QEMU on a Hetzner VM

## Why

Same shape as [`00-ops-nginx-qemu`](../00-ops-nginx-qemu/README.md), but with Unikraft's kraftkit instead of OPS. Pick this one if you want to compare the two runtime ecosystems side-by-side on identical plumbing — or if you're going to move on to the Unikraft-from-source examples (`03-unikraft-console`) and want to see kraftkit in its simplest, pre-packaged form first.

`kraft run` with `--disable-acceleration` asks for pure software emulation, which is what Hetzner cloud VMs need (no nested virt). The nginx image comes from Unikraft's public catalog at `unikraft.org/nginx:1.25` — zero configuration on your end.

## Prerequisites

```bash
# From the repo root
make check          # verifies hcloud CLI + token
```

## How it works

```
           your laptop                        Hetzner cpx22 VM
       ┌──────────────────┐              ┌──────────────────────────┐
       │ hcloud server    │─create──────▶│ Ubuntu 24.04             │
       │   --user-data    │              │ cloud-init:              │
       │   cloud-init.yaml│              │   apt install kraftkit   │
       └──────────────────┘              │   kraft run              │
                                         │     unikraft.org/nginx   │
                                         │     -p 8080:80           │
                                         │     --disable-accel      │
                                         │                          │
                                         │   ┌──────────────────┐   │
                                         │   │ QEMU (software)  │   │
                                         │   │  ┌────────────┐  │   │ :8080
                                         │   │  │  nginx     │◀─┼───┼─── HTTP
                                         │   │  │  unikernel │  │   │
                                         │   │  └────────────┘  │   │
                                         │   └──────────────────┘   │
                                         └──────────────────────────┘
```

The only real difference from `00-ops-nginx-qemu`: the unikernel binary comes from the Unikraft catalog (`unikraft.org/nginx:1.25`) rather than the OPS catalog (`eyberg/nginx:1.18.0`), and it listens on 8080 rather than 8083. Both run under the same Ubuntu + QEMU sandwich.

## Try it

```bash
# From the repo root
make 00-kraft-nginx-qemu     # ~2-3 min for cloud-init

curl http://$(make -s ip):8080
```

## What you should see

```
$ curl http://$(make -s ip):8080
<!DOCTYPE html>
<html>
<head><title>Welcome to nginx!</title>
…
```

From inside the VM (`make ssh`, then `tail /root/kraftkit.log`):

```
[kraftkit] verifying...
kraft version 0.11.x
[kraftkit] running nginx unikernel...
[kraftkit] nginx is up on port 8080
[kraftkit] done — nginx reachable on port 80 and 8080
```

## Things that go wrong

- **`curl: (7) Failed to connect`** for 2–3 minutes — cloud-init is still running. `kraft run --detach` returns quickly but QEMU takes a bit to finish booting the unikernel.
- **`apt install kraftkit` fails** — the Unikraft deb repo is occasionally slow. Rerun `/root/setup-kraftkit.sh` inside the VM (`make ssh`) or `make 00-kraft-nginx-qemu` again to rebuild from scratch.
- **nginx comes up but 404s on `/`** — the bundled `unikraft.org/nginx:1.25` image ships a working default page. If it's 404ing, something mangled the catalog image during pull; destroy and redeploy.
