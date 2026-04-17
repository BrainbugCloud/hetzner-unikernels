# 01-ops-hello-http — OPS native deploy via Hetzner snapshot

## Why

This is the "OPS is a first-class citizen on Hetzner" story. Unlike the `00-*` examples (which boot the unikernel inside QEMU on a Linux VM), this one boots the unikernel **as** the VM's operating system. No Linux underneath, no QEMU layer, no 10× emulation penalty. The VM *is* your Go HTTP server.

OPS's Hetzner integration does it in three steps behind the scenes:

1. Build a raw disk image locally.
2. Upload the image to **Hetzner Object Storage** (S3-compatible).
3. Ask Hetzner to **snapshot** the uploaded image and boot a VM from that snapshot.

The trade-off: you need object storage credentials and you're paying for a bucket. The trade-off vs. `02-ops-hello-dd` (which avoids object storage): this flow creates a real reusable Hetzner snapshot, so you can boot N instances from one image — object storage is the "upload once, deploy many" pattern.

## Prerequisites

```bash
# From the repo root
make check                  # verifies hcloud + token

# This example additionally needs:
export OBJECT_STORAGE_KEY="<access-key>"
export OBJECT_STORAGE_SECRET="<secret-key>"
# OBJECT_STORAGE_DOMAIN is optional; default is your-objectstorage.com

# Also: in config.json, set CloudConfig.BucketName to a bucket you own
# and CloudConfig.Zone to the region it lives in (hel1 or nbg1 or fsn1).
```

Get object-storage credentials: [Hetzner console → Security → S3 credentials](https://console.hetzner.cloud/) and create a bucket in the zone that matches `CloudConfig.Zone` in `config.json`.

```bash
which go ops              # both required locally
```

## How it works

```
   your laptop                                    Hetzner
   ┌───────────────┐      ops image create      ┌──────────────────┐
   │ main.go       │──go build──▶ hello-http    │ Object Storage   │
   │ config.json   │                             │ (S3)             │
   │               │──ops build──▶ hello-http.  │   s3://<bucket>/ │
   │               │              img (raw)     │                  │
   │               │──────────upload────────────▶  ← hello-http.img│
   └───────────────┘                             │                  │
                           ops instance create   │  snapshot: ←─────┼
                           ──────────────────────▶  from object URL│
                                                 │                  │
                                                 │  boot cpx22 VM   │ :8080
                                                 │  from snapshot ◀─┼─── HTTP
                                                 └──────────────────┘
```

`config.json` controls the whole flow — `BucketName`, `Zone`, `Flavor`, `Ports`. OPS reads it, does the S3 upload, calls Hetzner's snapshot API, then `ops instance create` boots a VM off that snapshot.

## Try it

```bash
# From the repo root:
make 01-ops-hello-http       # builds Go, uploads, creates snapshot, boots VM

# Once it's done:
curl http://<instance-ip>:8080
# -> "Hello World from Nanos Unikernel!"

# List your running unikernel instances:
ops instance list -t hetzner -c examples/01-ops-hello-http/config.json

# Tear down (instance + image, but not the bucket):
make -C examples/01-ops-hello-http destroy
```

## What you should see

```
$ make 01-ops-hello-http
Building and uploading image to Hetzner...
(compiling main.go)
(ops uploads hello-http.img to Hetzner Object Storage)
(ops creates Hetzner snapshot)
Creating Hetzner instance...
(hcloud boots a cpx22 VM from the snapshot)

ops-hello-http instance running!
List:    ops instance list -t hetzner -c config.json

$ curl http://<instance-ip>:8080
Hello World from Nanos Unikernel!
```

## Things that go wrong

- **"image not found"** right after upload — S3 upload finished but Hetzner's snapshot creation takes 10–30s. OPS polls automatically; if it gives up too early, wait a minute and `make 01-ops-hello-http` again (it will see the existing image and skip to `instance create`).
- **Instance boots but port 8080 is closed** — almost always a `CloudConfig` mistake. `Platform` must be `hetzner`, `Zone` must match your bucket's region, and `Uefi: true` is required on modern Hetzner server types. Our `config.json` has all three; if you've edited it, double-check.
- **"InvalidAccessKeyId"** — your S3 credentials are the *object-storage* key/secret from the Hetzner console, not your Hetzner Cloud API token. Two different things, easy to swap.

## Not tested in CI

This example is skipped from the weekly CI (see `.github/workflows/test-examples.yml`) because it requires an object-storage bucket that costs real money and adds another secret. Verify manually when you touch it.
