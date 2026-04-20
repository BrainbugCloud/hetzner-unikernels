# Hardware survey — how `docs/compatibility.md` was produced

The [compatibility matrix](./compatibility.md) summarises firmware, chipset,
CPU features and server-type availability across Hetzner Cloud. To keep the
summary honest we collect the underlying data by ordering a short-lived
Ubuntu VM in every (server type, location) combination and reading the
hardware straight from the guest. This page describes that process so the
matrix can be refreshed without guesswork.

## What we collect per VM

The guest-side collection is intentionally small and boring — everything
comes from tools that ship with a stock Ubuntu Server image:

- `/sys/firmware/efi` — present → TianoCore UEFI, absent → SeaBIOS.
- `dmidecode -t bios / -t system / -t processor` — BIOS vendor, BIOS
  date, chipset identifiers.
- `lscpu` and `/proc/cpuinfo` — CPU model, vendor, full CPU flag list.
- `lspci -nn` — PCI topology (Q35 virtio 1.0 devices look materially
  different from i440FX).
- `dmesg | grep -iE "BIOS-e820|efi:.*mem"` — a snippet of the memory map
  (useful when debugging paging issues).

The script extracts the flags that are relevant to Unikraft builds —
`pdpe1gb`, `rdrand`, `rdseed`, `avx`, `avx2`, `aes`, `sse4_2`, `vmx`,
`svm`, `x2apic`, `la57`, `sha_ni` — into a compact TSV summary.

## What the script does

For every combination in its cross product of server types and locations:

1. `hcloud server create` a minimal VM on vanilla Ubuntu 24.04 with a
   pre-uploaded SSH key.
2. Wait for SSH on the public IP.
3. Run the collection block above over SSH, dump the raw output to
   `<type>-<location>.txt`.
4. `hcloud server delete` the VM.

Combinations that fail at create time (server type unavailable in a
location, type out of stock) are recorded with status `CREATE_FAILED` and
the `hcloud` error message is preserved. Combinations where SSH never
comes up are recorded as `SSH_TIMEOUT`.

After the sweep, the script walks the per-combo files and writes a single
`summary.tsv` with one row per combination: firmware, BIOS vendor, CPU
model, 0/1 for each relevant CPU flag, and a count of PCI devices.

The script is resumable: re-running with an existing `OUTDIR` skips any
combo whose output file already contains a successful status marker, so a
partial sweep can be topped up without rebuilding VMs that already
reported. It is also idempotent per combo — the VM is deleted before the
next iteration starts, so stale VMs cannot accumulate.

## Running it

Prerequisites:

- `hcloud` CLI authenticated (`HCLOUD_TOKEN` env var, or an active
  `hcloud context`).
- An SSH key named `unikernel-key` uploaded to the same Hetzner project
  as the one the token scopes to, with the matching private key at
  `~/.ssh/unikernel-key`.

Invocation:

```bash
HCLOUD_TOKEN=<token> ./survey-hw.sh
```

Output lands in `hw-survey-<timestamp>/` alongside the script. The final
`summary.tsv` is what feeds the matrix in
[`docs/compatibility.md`](./compatibility.md).

To edit the cross product, change the `TYPES` and `LOCATIONS` arrays
near the top of the script. The collection block is deliberately
self-contained so it can be adapted to pick up additional data without
touching the orchestration around it.

## The script

Save as `survey-hw.sh` and make it executable (`chmod +x survey-hw.sh`).

```bash
#!/usr/bin/env bash
# survey-hw.sh — enumerate (server_type × location) hardware on Hetzner Cloud.
#
# For every (type, location) in the cross product below, this creates a tiny
# VM on vanilla Ubuntu, collects CPU / firmware / PCI info, and deletes the
# VM. Per-combo raw output lands in $OUTDIR/<type>-<location>.txt; a compact
# comparison matrix is written to $OUTDIR/summary.tsv.
#
# Requires: HCLOUD_TOKEN env var, the unikernel-key SSH key already uploaded
# to Hetzner, hcloud CLI at /usr/local/bin/hcloud.

set -u
: "${HCLOUD_TOKEN:?HCLOUD_TOKEN required}"
export HCLOUD_TOKEN

HCLOUD=/usr/local/bin/hcloud
SSH_KEY_NAME=unikernel-key
SSH_KEY_PATH=${HOME}/.ssh/unikernel-key
IMAGE=ubuntu-24.04

TYPES=(cx23 cpx11 ccx13)
LOCATIONS=(hil ash sin hel1 fsn1 nbg1)

OUTDIR=${OUTDIR:-$(pwd)/hw-survey-$(date +%Y%m%d-%H%M%S)}
mkdir -p "$OUTDIR"
echo "Output dir: $OUTDIR"

SSH_OPTS=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null
          -o LogLevel=ERROR -o ConnectTimeout=5 -i "$SSH_KEY_PATH")

survey_one() {
  local type="$1" loc="$2"
  local name="hwsurvey-${type}-${loc}"
  local out="$OUTDIR/${type}-${loc}.txt"

  if [ -s "$out" ] && grep -q "^OK$" "$out"; then
    echo "[$(date +%H:%M:%S)] $type @ $loc — SKIP (already OK)"
    return
  fi
  : >"$out"

  echo "[$(date +%H:%M:%S)] $type @ $loc"

  if ! $HCLOUD server create --name "$name" --type "$type" --image "$IMAGE" \
       --location "$loc" --ssh-key "$SSH_KEY_NAME" >"$out.create" 2>&1; then
    {
      echo "### STATUS"
      echo "CREATE_FAILED"
      echo "### CREATE_LOG"
      cat "$out.create"
    } >"$out"
    rm -f "$out.create"
    $HCLOUD server delete "$name" >/dev/null 2>&1 || true
    return
  fi
  rm -f "$out.create"

  local ip
  ip=$($HCLOUD server describe "$name" -o format='{{.PublicNet.IPv4.IP}}')

  local i=0
  until ssh -q "${SSH_OPTS[@]}" root@"$ip" exit 2>/dev/null; do
    i=$((i+1))
    if [ $i -gt 80 ]; then
      echo "### STATUS" >"$out"
      echo "SSH_TIMEOUT ip=$ip" >>"$out"
      $HCLOUD server delete "$name" >/dev/null 2>&1 || true
      return
    fi
    sleep 3
  done

  ssh "${SSH_OPTS[@]}" root@"$ip" bash <<'REMOTE' >"$out" 2>&1
echo "### STATUS"; echo OK
echo "### uname"; uname -a
echo "### firmware"
if [ -d /sys/firmware/efi ]; then echo EFI; else echo BIOS; fi
echo "### dmidecode-bios";      dmidecode -t bios 2>/dev/null
echo "### dmidecode-system";    dmidecode -t system 2>/dev/null
echo "### dmidecode-processor"; dmidecode -t processor 2>/dev/null
echo "### lscpu";               lscpu
echo "### cpuinfo-model";       grep -m1 "model name" /proc/cpuinfo
echo "### cpuinfo-flags";       grep -m1 "^flags" /proc/cpuinfo
echo "### lspci";               lspci -nn
echo "### e820";                dmesg | grep -iE "BIOS-e820|efi:.*mem" | head -40
REMOTE

  $HCLOUD server delete "$name" >/dev/null 2>&1 || true
}

# Serial to keep API/quota load polite.
for loc in "${LOCATIONS[@]}"; do
  for type in "${TYPES[@]}"; do
    survey_one "$type" "$loc"
  done
done

# ── Summary ───────────────────────────────────────────────────────────
extract() { # $1=file $2=section
  awk -v s="### $2" '$0==s{f=1;next} /^### /{f=0} f' "$1"
}
get_flag() { # $1=file flag_name  → 1 if present in cpuinfo-flags, else 0
  grep -m1 "^flags" "$1" 2>/dev/null | grep -qw "$2" && echo 1 || echo 0
}

FLAGS=(pdpe1gb rdrand rdseed avx avx2 aes sse4_2 vmx svm x2apic la57 sha_ni)

{
  printf "type\tlocation\tfirmware\tbios_vendor\tcpu_model"
  for f in "${FLAGS[@]}"; do printf "\t%s" "$f"; done
  printf "\tpci_count\n"

  for loc in "${LOCATIONS[@]}"; do
    for type in "${TYPES[@]}"; do
      out="$OUTDIR/${type}-${loc}.txt"
      [ -s "$out" ] || { printf "%s\t%s\tMISSING\n" "$type" "$loc"; continue; }

      status=$(extract "$out" STATUS | head -1)
      if [ "$status" != "OK" ]; then
        printf "%s\t%s\t%s\n" "$type" "$loc" "$status"
        continue
      fi

      fw=$(extract "$out" firmware | head -1)
      vendor=$(extract "$out" dmidecode-bios | awk -F: '/Vendor/{gsub(/^ +/,"",$2);print $2;exit}')
      model=$(extract "$out" cpuinfo-model | sed 's/.*: //')
      pci_count=$(extract "$out" lspci | grep -c .)

      printf "%s\t%s\t%s\t%s\t%s" "$type" "$loc" "$fw" "$vendor" "$model"
      for f in "${FLAGS[@]}"; do
        printf "\t%s" "$(get_flag "$out" "$f")"
      done
      printf "\t%s\n" "$pci_count"
    done
  done
} >"$OUTDIR/summary.tsv"

echo
echo "Summary → $OUTDIR/summary.tsv"
column -t -s $'\t' "$OUTDIR/summary.tsv"
```
