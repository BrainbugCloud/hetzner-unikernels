# Hetzner Cloud compatibility

Two boot paths cover Hetzner Cloud x86 VMs: a GRUB multiboot image for VMs
whose firmware is SeaBIOS, and an EFI-stub image for VMs whose firmware is
TianoCore UEFI. Which path applies depends on the server type and its
generation, not on the family name alone. This document records what we
observed and what it means for a Unikraft build.

Data below is a point-in-time snapshot (April 2026). Hetzner's fleet rolls
over — expect the matrix to need refreshing periodically.

## Server-type naming

Customer-facing x86 server types follow the pattern `<family><size><generation>`:

- **Family**: `cx` (shared vCPU, Intel/AMD), `cpx` (shared vCPU, AMD),
  `ccx` (dedicated vCPU, AMD). The `cax` ARM family is out of scope here.
- **First digit — size tier**, 1 (smallest) through 5 or 6 (biggest).
  cpx11 has 2 vCPU / 2 GB; cpx51 has 16 vCPU / 32 GB.
- **Second digit — generation**. Hetzner has run three generations of cx,
  two of cpx, and one of ccx since 2024.

Currently orderable public tiers:

| Tier | CPU | Firmware | Chipset |
|---|---|---|---|
| cpx gen 1 (`cpx11/21/31/41/51`) | AMD EPYC Rome | SeaBIOS | i440FX |
| cpx gen 2 (`cpx12/22/32/42/52/62`) | AMD EPYC Genoa | TianoCore UEFI | Q35 + virtio 1.0 |
| cx  gen 3 (`cx23/33/43/53`) | mixed: Intel Xeon Skylake or AMD EPYC Rome (location-dependent — Hetzner recycles older hardware into this tier) | SeaBIOS | i440FX |
| ccx gen 3 (`ccx13/23/33/43/53/63`) | AMD EPYC Milan | TianoCore UEFI | Q35 |

Availability by location is uneven. `cpx` gen 1 has been retired for new
orders in the EU and in Singapore; it remains orderable in the US
(`ash`, `hil`). `cx` gen 3 is currently EU-only. `ccx` gen 3 is broadly
available with occasional stock gaps.

## Testing methodology

For each (server type, location) combination we ordered a minimal
Ubuntu 24.04 VM, waited for SSH, and collected:

- firmware type (`/sys/firmware/efi` present → UEFI, otherwise BIOS);
- BIOS vendor and version from `dmidecode -t bios`;
- CPU model and flag list from `/proc/cpuinfo` and `lscpu`;
- PCI topology from `lspci -nn`;
- a sample of the e820 / EFI memory map from `dmesg`.

Each VM was destroyed as soon as the data was captured. Combinations that
returned "Server Type is unavailable in this location" from the Hetzner API
were recorded as unavailable without further inspection.

## Compatibility matrix

CPU features relevant to Unikraft builds:

| Tier | `pdpe1gb` | `rdrand` | `rdseed` | `la57` | `sha_ni` |
|---|---|---|---|---|---|
| cpx gen 1 (EPYC Rome)   | ✓ | ✓ | ✓ | — | ✓ |
| cpx gen 2 (EPYC Genoa)  | ✓ | ✓ | ✓ | ✓ | ✓ |
| cx  gen 3, Intel Skylake  | ✓ | ✓ | ✓ | — | — |
| cx  gen 3, EPYC Rome     | ✓ | ✓ | ✓ | — | ✓ |
| ccx gen 3 (EPYC Milan)  | ✓ | ✓ | ✓* | — | ✓ |

\* Some `ccx` hosts do not advertise `rdseed` but always advertise `rdrand`;
`LIBUKRANDOM_LCPU` falls back to `rdrand` transparently.

Every public tier advertises 1 GiB huge pages (`pdpe1gb`) and a hardware
RNG (`rdrand`), so neither is a build constraint on customer-facing
Hetzner Cloud. The generation boundary that matters for image building is
**firmware and chipset**, not CPU feature masking.

Availability we observed:

| Tier | fsn1 | nbg1 | hel1 | ash | hil | sin |
|---|---|---|---|---|---|---|
| cpx gen 1 | —   | —   | —   | ✓   | ✓   | —   |
| cpx gen 2 | ✓   | ?   | ?   | ?   | ?   | ?   |
| cx  gen 3 | ✓   | ✓   | ✓   | —   | —   | —   |
| ccx gen 3 | ✓   | ✓   | ✓   | —   | ✓   | ✓   |

Legend: ✓ = orderable and verified, — = unavailable (API error or out of
stock), ? = not tested.

## Unikraft configuration per server class

The customer-facing fleet collapses into two build targets.

### BIOS / SeaBIOS / i440FX — cpx gen 1, cx gen 3

- **Boot protocol**: `CONFIG_KVM_BOOT_PROTO_MULTIBOOT=y`.
- **Image format**: GRUB multiboot on an MBR disk. `dd` to `/dev/sda`.
- **Console**: `CONFIG_LIBVGACONS=y` gives text output on Hetzner's VNC
  console. This is the only firmware class where the VNC console shows
  kernel output without an extra driver.
- **PCI topology**: legacy virtio-pci on i440FX. Expect virtio-net and
  virtio-blk. No virtio-rng.
- **Randomness**: `LIBUKRANDOM_LCPU` with `rdrand` works on every tested
  host. Passing a seed via `random.seed=` on the kernel cmdline also
  works.
- **Paging**: no special configuration; 1 GiB pages are available. The
  direct-map path (`HAVE_PAGING_DIRECTMAP`) works out of the box.

### UEFI / TianoCore / Q35 — cpx gen 2, ccx gen 3

- **Boot protocol**: EFI stub. Build an ESP containing `BOOTX64.EFI` and
  (optionally) the kernel cmdline and initramfs as sibling files.
- **Image format**: GPT disk with an EFI System Partition. `dd` to
  `/dev/sda`; firmware variables are not touched, so the image is fully
  self-describing.
- **Console**: no text-VGA. Use a GOP console driver (this repo's
  `feat/unikraft-gop-console` branch has a working one) to see kernel
  output on Hetzner's VNC console. Hetzner does not expose a serial
  console, so GOP is the practical option for bring-up.
- **PCI topology**: Q35 with virtio-1.0 devices behind QEMU PCIe root
  ports. In addition to virtio-net and virtio-blk you will see
  virtio-console, virtio-gpu, **virtio-rng**, virtio-balloon, virtio-scsi
  and a QEMU XHCI USB controller. The virtio-GPU (device id 16) is
  harmless if the unikernel does not bind it.
- **Randomness**: `LIBUKRANDOM_LCPU` still works, but virtio-rng is
  present and is the cleaner entropy source on this class of host if
  your Unikraft build includes a virtio-rng driver.
- **Paging**: no special configuration. cpx gen 2 advertises 5-level
  paging (`la57`); current Unikraft x86 builds use 4-level and ignore it.

### Picking a server type for a Unikraft build

- Multiboot-only build → a BIOS tier: **cx gen 3** in the EU, **cpx gen 1**
  in the US.
- EFI-only build → a UEFI tier: **cpx gen 2** or **ccx gen 3**.
- You want kernel output in the VNC console without writing a GOP console
  driver → a BIOS tier.
- You want predictable, non-noisy performance → **ccx gen 3**.

## Sources

- Hetzner pressroom, *Hetzner introduces new shared vCPU cloud servers*
  (2024-06-06): <https://www.hetzner.com/pressroom/new-cx-plans/>
- CloudFleet, *Hetzner Cloud introduces CX Gen3 and CPX Gen2* (2025-10):
  <https://cloudfleet.ai/blog/partner-news/2025-10-hetzner-cloud-introduces-new-shared-vcpu-server-families-cx-gen3-and-cpx-gen2/>
- Spare Cores instance pages:
  <https://sparecores.com/server/hcloud/cpx22>,
  <https://sparecores.com/server/hcloud/cpx11>
- Spare Cores blog, *A closer look at Hetzner Cloud's new CX servers*:
  <https://sparecores.com/article/hetzner-new-cx-servers>
- Hetzner docs — Locations:
  <https://docs.hetzner.com/cloud/general/locations/>
- Better Stack, *Hetzner Cloud Review 2026*:
  <https://betterstack.com/community/guides/web-servers/hetzner-cloud-review/>
- VPSBenchmarks — Hetzner instance types:
  <https://www.vpsbenchmarks.com/instance_types/hetzner>
