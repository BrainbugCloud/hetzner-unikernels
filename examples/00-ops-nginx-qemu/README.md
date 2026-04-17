# 00-ops-nginx-qemu — OPS + nginx, running in QEMU on a Hetzner VM

## Why

This is the safest entry point into unikernels on Hetzner. You don't install anything locally, you don't care about Hetzner's firmware quirks, you don't pay for object storage. You just spin up an Ubuntu VM, tell cloud-init to install OPS, and let it boot an nginx unikernel under software-emulated QEMU.

It's also the **slowest** option. QEMU on a VM without KVM is pure software emulation — expect nginx to serve requests at something like 1/10th native speed. But as a "what is a unikernel even" demo, it's perfect: you can SSH into the Ubuntu VM and poke at the QEMU process, attach strace, read logs. The training-wheels version.

## Prerequisites

```bash
# From the repo root
make check          # verifies hcloud CLI + token
```

The only thing this example needs that `make check` won't verify for you is an SSH key named `bb-podman-key` (the default) uploaded to your Hetzner project — or set `SSH_KEY=<your-key-name>` when you run.

## How it works

```
           your laptop                        Hetzner cpx22 VM
       ┌──────────────────┐              ┌──────────────────────────┐
       │ hcloud server    │─create──────▶│ Ubuntu 24.04             │
       │   --user-data    │              │ cloud-init runs:         │
       │   cloud-init.yaml│              │   apt install qemu       │
       └──────────────────┘              │   curl get.sh | sh       │
                                         │   ops pkg load nginx     │
                                         │     -p 8083              │
                                         │                          │
                                         │   ┌──────────────────┐   │
                                         │   │ QEMU (software)  │   │
                                         │   │  ┌────────────┐  │   │
                                         │   │  │  nginx     │  │   │ :8083
                                         │   │  │  unikernel │◀─┼───┼────── HTTP
                                         │   │  └────────────┘  │   │
                                         │   └──────────────────┘   │
                                         └──────────────────────────┘
```

Two indirections: Hetzner boots Ubuntu, Ubuntu runs QEMU, QEMU runs nginx-as-a-unikernel. The unikernel itself never sees the hypervisor directly — it sees QEMU's virtual hardware.

## Try it

```bash
# From the repo root
make 00-ops-nginx-qemu        # ~2-3 min for cloud-init to finish

# Once it's done:
curl http://$(make -s ip):8083

# SSH in and look around:
make ssh
# then: cat /root/run.log
```

## What you should see

```
$ curl http://$(make -s ip):8083
<!DOCTYPE html>
<html>
<head><title>Welcome to nginx!</title>
…
```

Inside the VM (`make ssh` and then `tail /root/run.log`):

```
[ops] found ops at: /root/.ops/bin/ops
[ops] pulling nginx 1.18.0 package...
[ops] running nginx unikernel (QEMU, port 8083)...
[ops] nginx is up on port 8083
[ops] done — nginx reachable on port 80 and 8083
```

## Things that go wrong

- **`curl: (7) Failed to connect`** for 2–3 minutes after `make` returns — expected. `make` finishes as soon as Hetzner says the VM is running; cloud-init still needs to `apt install qemu`, download the OPS binary, pull the nginx package, and wait for QEMU to boot the unikernel. Watch `/root/run.log` on the VM if you want to follow along.
- **`ops pkg get` hangs or times out** — OPS's package CDN occasionally has a bad day. SSH in, `kill` the hung `ops` process, and rerun `/root/run-nginx-unikernel.sh`. Not persistent; the next run almost always works.
- **Port 8083 closed after a reboot** — the iptables rule and the QEMU process are both ephemeral. Rebooting the VM drops them. `make 00-ops-nginx-qemu` again to redeploy (it will rebuild cloud-init, not create a new server).
