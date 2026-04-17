# lib/deploy-dd.mk — shared "dd a disk image onto a Hetzner VM" helper.
# Depends on lib/common.mk (SERVER, colours). Include it first.
#
# Provides three defines:
#   ensure-server-vanilla  create or rebuild SERVER on plain Ubuntu (no cloud-init).
#   wait-ssh               clear stale known_hosts, poll until SSH accepts us.
#   dd-deploy IMG          scp IMG to /dev/shm, dd onto /dev/sda, sysrq 'o' poweroff,
#                          hcloud poweron (so firmware reinitialises — sysrq 'b' reboot
#                          leaves vCPU state stale and new disk boots to PXE).

SSH_OPTS = -o StrictHostKeyChecking=no

# ── Create-or-rebuild on vanilla Ubuntu ───────────────────────────────
define ensure-server-vanilla
	@if hcloud server describe $(SERVER) >/dev/null 2>&1; then \
		echo "$(BOLD)Rebuilding $(SERVER) to vanilla $(BASE_IMAGE)...$(RESET)"; \
		hcloud server rebuild $(SERVER) --image $(BASE_IMAGE); \
	else \
		echo "$(BOLD)Creating $(SERVER)...$(RESET)"; \
		hcloud server create \
			--name $(SERVER) \
			--type $(SERVER_TYPE) \
			--image $(BASE_IMAGE) \
			--location $(LOCATION) \
			--ssh-key $(SSH_KEY); \
	fi
endef

# ── Create-or-rebuild with a cloud-init file ──────────────────────────
# Usage: $(call ensure-server-cloudinit,path/to/cloud-init.yaml)
define ensure-server-cloudinit
	@if hcloud server describe $(SERVER) >/dev/null 2>&1; then \
		echo "$(BOLD)Rebuilding $(SERVER) with cloud-init...$(RESET)"; \
		hcloud server rebuild $(SERVER) \
			--image $(BASE_IMAGE) \
			--user-data-from-file $(1); \
	else \
		echo "$(BOLD)Creating $(SERVER)...$(RESET)"; \
		hcloud server create \
			--name $(SERVER) \
			--type $(SERVER_TYPE) \
			--image $(BASE_IMAGE) \
			--location $(LOCATION) \
			--ssh-key $(SSH_KEY) \
			--user-data-from-file $(1); \
	fi
endef

# ── Wait for SSH to come up on SERVER ─────────────────────────────────
define wait-ssh
	@set -e; \
	 IP=$$(hcloud server describe $(SERVER) -o format='{{.PublicNet.IPv4.IP}}'); \
	 ssh-keygen -R $$IP 2>/dev/null || true; \
	 echo "$(BOLD)Waiting for SSH on $$IP...$(RESET)"; \
	 until ssh -q $(SSH_OPTS) -o ConnectTimeout=5 root@$$IP exit 2>/dev/null; \
	   do sleep 3; done
endef

# ── dd a disk image onto the server's /dev/sda and boot into it ───────
# Usage: $(call dd-deploy,path/to/disk.img)
#
# Why scp + file, not pipe-through-ssh: conv=sync pads short reads from a
# pipe with zeros, corrupting the image. File reads are never short.
#
# Why sysrq 'o' (poweroff) + hcloud poweron instead of 'b' (reboot):
# Hetzner's hypervisor restarts the vCPU on sysrq 'b' without re-running
# firmware, so the new disk's bootloader never gets enumerated and the VM
# falls through to PXE. Full power cycle forces firmware re-init.
#
# /dev/shm/dd and /dev/shm/disk.img: we copy dd to tmpfs because once the
# dd overwrites /dev/sda, the rootfs is gone. Everything we need has to
# already be in RAM.
define dd-deploy
	@test -n "$$HCLOUD_TOKEN" || test -n "$$(hcloud context active 2>/dev/null)" || { echo "$(RED)HCLOUD_TOKEN not set$(RESET)"; exit 1; }
	@test -f $(1) || { echo "$(RED)Image not found: $(1)$(RESET)"; exit 1; }
	@echo "$(BOLD)Uploading $(1) to $(SERVER)...$(RESET)"
	@set -e; \
	 IP=$$(hcloud server describe $(SERVER) -o format='{{.PublicNet.IPv4.IP}}'); \
	 scp $(SSH_OPTS) $(1) root@$$IP:/dev/shm/disk.img; \
	 echo "$(BOLD)Writing to /dev/sda...$(RESET)"; \
	 ssh $(SSH_OPTS) -o ServerAliveInterval=2 -o ServerAliveCountMax=3 root@$$IP \
	   "cp /bin/dd /dev/shm/dd && \
	    blkdiscard /dev/sda -f || true && \
	    /dev/shm/dd if=/dev/shm/disk.img of=/dev/sda bs=4M conv=sync && \
	    echo s > /proc/sysrq-trigger && echo o > /proc/sysrq-trigger" || true; \
	 echo "$(BOLD)Waiting for server to power off...$(RESET)"; \
	 until [ "$$(hcloud server describe $(SERVER) -o format='{{.Status}}')" = "off" ]; do sleep 3; done; \
	 echo "$(BOLD)Powering on...$(RESET)"; \
	 hcloud server poweron $(SERVER)
endef
