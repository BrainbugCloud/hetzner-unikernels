# Example 00a — OPS/Nanos Nginx in QEMU

Spin up a Hetzner Cloud VM, install [OPS](https://ops.city), and run the prebuilt nginx 1.18.0 unikernel inside QEMU.

## What happens

1. `hcloud` creates a cpx22 VM with cloud-init
2. Cloud-init installs `qemu-system-x86` and `ops`
3. `ops pkg load` downloads the `eyberg/nginx:1.18.0` package and boots it in QEMU
4. Nginx listens on port **8083** inside the VM
5. iptables redirects port 80 → 8083 for easy public access

## Deploy

```bash
make 00-ops-nginx-qemu
```

## Test

```bash
make 00-ops-nginx-qemu-ip    # print the VM IP
curl http://<IP>:8083
curl http://<IP>:80
```

Expected: `Hello from Nanos!`

## SSH

```bash
hcloud server ssh ops-nginx-qemu
ps aux | grep qemu          # the unikernel is a QEMU process
```

## Destroy

```bash
make 00-ops-nginx-qemu-destroy
```

## Notes

- The prebuilt `eyberg/nginx:1.18.0` package listens on **8083** (http) and **8084** (https)
- OPS installs to `/.ops` when $HOME is `/` (cloud-init context)
- No custom image build needed — this is the fastest way to get a unikernel running