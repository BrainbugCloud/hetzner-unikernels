# 02-ops-hello-dd — OPS image dd'd straight onto the VM's disk

## Why

Same end result as [`01-ops-hello-http`](../01-ops-hello-http/README.md) — a Go HTTP server running as a unikernel, **as** the VM's OS — but without needing object storage. We build the OPS image locally, `scp` it onto a throwaway Ubuntu VM, `dd` it onto `/dev/sda`, power-cycle, and the VM comes back up as the unikernel.

Why you'd use this:

- **Dev iteration.** Rebuild, redeploy, curl — 45s cycle, no cloud object-storage round-trip.
- **No extra bill.** The shared VM is the same one every other example uses.
- **Teaches you the dd trick**, which generalises to any runtime (Unikraft, etc.). If you can produce a raw disk image, you can boot it on Hetzner this way.

The catch: it's destructive. `dd if=... of=/dev/sda` overwrites the VM's root filesystem. That's fine — the VM is disposable — but it does mean there's a narrow window between "the dd finished" and "the new image boots" where the VM has no usable OS. We handle that with a specific power-cycle dance documented below.

## Prerequisites

```bash
# From the repo root
make check             # verifies hcloud + token

which go ops           # required locally
```

No object-storage credentials needed.

## How it works

```
  your laptop                              Hetzner VM
  ┌─────────────────┐                    ┌─────────────────────┐
  │ main.go         │                    │ (1) Ubuntu 24.04    │
  │ config.json     │──ops build────┐    │                     │
  │                 │              │    │ make ensure-vanilla │
  │ image/          │◀──image──────┘    │                     │
  │   ops-hello-dd  │                    │                     │
  │   .img (80 MB)  │                    │                     │
  └─────────────────┘                    │                     │
           │                              │                     │
           │  scp image → /dev/shm        │ (2) image in tmpfs  │
           └──────────────────────────────▶                     │
                                          │                     │
             ssh: dd /dev/shm/disk.img → /dev/sda                │
                                          │                     │
             ssh: sysrq s (sync)                                 │
             ssh: sysrq o (poweroff)      │ (3) VM powers off   │
                                          │                     │
           hcloud server poweron          │ (4) firmware re-runs│
                                          │     boots new disk  │
                                          │     = unikernel     │ :8080
                                          │                    ◀┼─── HTTP
                                          └─────────────────────┘
```

Three non-obvious choices:

- **`scp` then `dd` from a file, never pipe.** A pipe makes `conv=sync` pad short reads with zeros, corrupting the image. `scp` to `/dev/shm` (tmpfs) avoids both the padding bug and the problem of needing a file after `/dev/sda` is obliterated.
- **`sysrq o` (poweroff) + `hcloud server poweron`, not `sysrq b` (reboot).** Hetzner's hypervisor restarts the vCPU on `sysrq b` without re-running firmware, so the new disk's bootloader never gets enumerated and the VM falls through to PXE. A full power cycle forces firmware re-init.
- **`cp /bin/dd /dev/shm/dd` before writing to sda.** Once the dd overwrites root, *everything* we need has to already be in RAM. That includes dd itself.

## Try it

```bash
# From the repo root
make 02-ops-hello-dd         # builds Go, builds OPS image, deploys

# Once `make` returns:
curl http://$(make -s ip):8080
# -> "Hello World from Nanos Unikernel!"
```

Rebuild loop:

```bash
vim examples/02-ops-hello-dd/main.go
make 02-ops-hello-dd         # ~45s end-to-end
curl http://$(make -s ip):8080
```

## What you should see

```
$ make 02-ops-hello-dd
Building ops-hello-dd image...
(ops build -t hetzner hello-dd -c config.json)
Image: image/ops-hello-dd.img (80M)
Rebuilding unikernel-example to vanilla ubuntu-24.04...
Waiting for SSH on 49.12.xxx.yyy...
Uploading image/ops-hello-dd.img to unikernel-example...
Writing to /dev/sda...
Waiting for server to power off...
Powering on...
Waiting for port 8080...

unikernel-example running 02-ops-hello-dd!
Test: curl http://49.12.xxx.yyy:8080

$ curl http://$(make -s ip):8080
Hello World from Nanos Unikernel!
```

## Things that go wrong

- **"no bootable device" in the Hetzner console** — almost always means the power-cycle wasn't clean. You probably see `sysrq b` in an older Makefile, or a reboot happened before sync finished. Destroy and redeploy; the current `dd-deploy` flow handles this correctly.
- **`scp` hangs on "Host key verification failed"** — happens after the first deploy because the VM's host key changed (rebuild wipes it). The Makefile runs `ssh-keygen -R <ip>` for you, but if you've SSH'd manually, your interactive known_hosts has a stale entry too. `ssh-keygen -R <ip>` once, then retry.
- **Port 8080 opens for 2 seconds then dies** — missing `Platform: hetzner` or `Zone` in `config.json`. Without them, OPS produces a non-bootable image. Our `config.json` has both; if you've forked it, double-check.
- **`ops build` complains about Platform/Zone** — same fix; make sure `CloudConfig.Platform = "hetzner"` and `CloudConfig.Zone` is set.
