# hetzner-unikernels — Makefile
#
# Prerequisites:
#   - hcloud CLI
#   - HCLOUD_TOKEN env var or active hcloud context
#
# Examples 00 and 03 share one server (rebuild, not delete+create).
# Example 01 uses OPS native instance management.
#
# Quick start:
#   make check                — verify hcloud prerequisites
#   make servers              — list running servers
#   make 00-ops-nginx-qemu    — example 00a: ops + nginx in QEMU via cloud-init
#   make 00-kraft-nginx-qemu  — example 00b: kraftkit + nginx in QEMU via cloud-init
#   make 01-ops-hello-http    — example 01: native OPS deploy to Hetzner (ops image + instance)
#   make 02-ops-hello-dd      — example 02: OPS image dd'd to disk, HTTP server on :8080
#   make ip                   — print shared server IP (for 00 and 03)
#   make ssh                  — SSH into shared server
#   make destroy              — delete shared server (stop billing)

# ── Configuration ──────────────────────────────────────────────

SERVER_TYPE ?= cpx22
LOCATION    ?= fsn1
BASE_IMAGE  ?= ubuntu-24.04
SSH_KEY     ?= bb-podman-key
SERVER      ?= unikernel-example

# ── Colors ─────────────────────────────────────────────────────

RESET  := \033[0m
BOLD   := \033[1m
RED    := \033[31m
GREEN  := \033[32m
CYAN   := \033[36m

# ── Prerequisite checks ────────────────────────────────────────

.PHONY: check check-hcloud check-token check-ops check-ops-storage

check: check-hcloud check-token
	@echo "$(GREEN)$(BOLD)All prerequisites met!$(RESET)"

HCLOUD_MIN_VERSION := 1.62.0

check-hcloud:
	@which hcloud >/dev/null 2>&1 || { \
		echo "$(RED)$(BOLD)hcloud CLI not found.$(RESET)"; \
		echo ""; \
		echo "Install with:"; \
		echo "  curl -sSLO https://github.com/hetznercloud/cli/releases/latest/download/hcloud-linux-amd64.tar.gz"; \
		echo "  sudo tar -C /usr/local/bin --no-same-owner -xzf hcloud-linux-amd64.tar.gz hcloud"; \
		echo "  rm hcloud-linux-amd64.tar.gz"; \
		exit 1; }
	@VERS=$$(hcloud version 2>/dev/null | awk '{print $$2}'); \
	 if [ -z "$$VERS" ] || printf '%s\n' "$(HCLOUD_MIN_VERSION)" "$$VERS" | sort -V | head -1 | grep -qv "$(HCLOUD_MIN_VERSION)"; then \
		echo "$(RED)$(BOLD)hcloud >= $(HCLOUD_MIN_VERSION) required (found $$VERS).$(RESET)"; \
		echo ""; \
		echo "Update with:"; \
		echo "  curl -sSLO https://github.com/hetznercloud/cli/releases/latest/download/hcloud-linux-amd64.tar.gz"; \
		echo "  sudo tar -C /usr/local/bin --no-same-owner -xzf hcloud-linux-amd64.tar.gz hcloud"; \
		echo "  rm hcloud-linux-amd64.tar.gz"; \
		exit 1; \
	 fi
	@echo "$(CYAN)hcloud$(RESET) $$(hcloud version | awk '{print $$2}')"

check-token:
	@if [ -z "$$HCLOUD_TOKEN" ]; then \
		if ! hcloud context list 2>/dev/null | grep -q 'ACTIVE'; then \
			echo "$(RED)$(BOLD)HCLOUD_TOKEN not set and no active hcloud context.$(RESET)"; \
			echo ""; \
			echo "  export HCLOUD_TOKEN=\"<your-hetzner-api-token>\""; \
			echo ""; \
			echo "  Or create a context:  hcloud context create <project-name>"; \
			echo "  Get a token: https://console.hetzner.cloud/ → Security → API Tokens"; \
			exit 1; \
		fi; \
	fi
	@hcloud server list >/dev/null 2>&1 || { \
		echo "$(RED)$(BOLD)hcloud cannot reach the API — check your token.$(RESET)"; \
		echo "  export HCLOUD_TOKEN=\"<your-hetzner-api-token>\""; \
		exit 1; }
	@echo "$(GREEN)Hetzner API reachable$(RESET)"

check-ops:
	@which ops >/dev/null 2>&1 || { \
		echo "$(RED)$(BOLD)ops CLI not found.$(RESET)"; \
		echo "Install: curl https://ops.city/get.sh | sh"; \
		exit 1; }
	@echo "$(CYAN)ops$(RESET) found"

check-ops-storage:
	@FAIL=0; \
	 [ -n "$$HCLOUD_TOKEN" ] || { echo "  $(RED)HCLOUD_TOKEN$(RESET) not set"; FAIL=1; }; \
	 [ -n "$$OBJECT_STORAGE_KEY" ] || { echo "  $(RED)OBJECT_STORAGE_KEY$(RESET) not set"; FAIL=1; }; \
	 [ -n "$$OBJECT_STORAGE_SECRET" ] || { echo "  $(RED)OBJECT_STORAGE_SECRET$(RESET) not set"; FAIL=1; }; \
	 BUCKET=$$(python3 -c "import json; print(json.load(open('examples/01-ops-hello-http/config.json'))['CloudConfig'].get('BucketName',''))" 2>/dev/null); \
	 [ -n "$$BUCKET" ] || { echo "  $(RED)BucketName$(RESET) not set in examples/01-ops-hello-http/config.json"; FAIL=1; }; \
	 [ $$FAIL -eq 0 ] || { \
		echo ""; \
		echo "$(BOLD)Example 01 requires OPS Hetzner credentials:$(RESET)"; \
		echo ""; \
		echo "  export HCLOUD_TOKEN=\"<your-hetzner-api-token>\""; \
		echo "  export OBJECT_STORAGE_KEY=\"<your-storage-access-key>\""; \
		echo "  export OBJECT_STORAGE_SECRET=\"<your-storage-secret-key>\""; \
		echo "  export OBJECT_STORAGE_DOMAIN=\"...\"  (optional, default: your-objectstorage.com)"; \
		echo ""; \
		echo "  Set BucketName and Zone in examples/01-ops-hello-http/config.json"; \
		echo ""; \
		echo "  Get credentials: https://console.hetzner.cloud/ → Object Storage"; \
		exit 1; }
	@echo "$(CYAN)OPS storage credentials set$(RESET)"

# ── Shared helpers (examples 00, 03) ───────────────────────────
#
# ensure-server CLOUD_INIT_FILE
#   Create server if absent; rebuild with cloud-init if it exists.
define ensure-server
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

# ensure-server-vanilla
#   Create server if absent; rebuild to clean ubuntu (no cloud-init) if it exists.
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

# wait-ssh
#   Clear stale known_hosts entry and poll until SSH is available.
define wait-ssh
	@set -e; \
	 IP=$$(hcloud server describe $(SERVER) -o format='{{.PublicNet.IPv4.IP}}'); \
	 ssh-keygen -R $$IP 2>/dev/null || true; \
	 echo "$(BOLD)Waiting for SSH on $$IP...$(RESET)"; \
	 until ssh -q -o StrictHostKeyChecking=no -o ConnectTimeout=5 root@$$IP exit 2>/dev/null; \
	   do sleep 3; done
endef

# ── Example 00: OPS/Nanos nginx in QEMU via cloud-init ─────────

.PHONY: 00-ops-nginx-qemu

00-ops-nginx-qemu: check
	$(call ensure-server,examples/00-ops-nginx-qemu/cloud-init.yaml)
	@echo ""
	@echo "$(GREEN)$(BOLD)$(SERVER) running 00-ops-nginx-qemu!$(RESET)"
	@echo "Cloud-init is installing ops and booting the unikernel (~2-3 min)."
	@echo "  http://$$(make -s ip):8083"
	@echo "SSH:  make ssh"

# ── Example 00b: Kraftkit nginx in QEMU via cloud-init ─────────

.PHONY: 00-kraft-nginx-qemu

00-kraft-nginx-qemu: check
	$(call ensure-server,examples/00-kraft-nginx-qemu/cloud-init.yaml)
	@echo ""
	@echo "$(GREEN)$(BOLD)$(SERVER) running 00-kraft-nginx-qemu!$(RESET)"
	@echo "Cloud-init is installing kraftkit and booting the unikernel (~2-3 min)."
	@echo "Test with:  curl http://$$(make -s ip):8080"
	@echo "SSH:        make ssh"

# ── Example 01: OPS hello-http deployed natively to Hetzner ───
#
# Requires: HCLOUD_TOKEN, OBJECT_STORAGE_DOMAIN, OBJECT_STORAGE_KEY,
#           OBJECT_STORAGE_SECRET, and BucketName set in config.json.
#
# Flow: ops image create → Hetzner snapshot → ops instance create

.PHONY: 01-ops-hello-http 01-ops-hello-http-destroy

01-ops-hello-http: check check-ops check-ops-storage
	@echo "$(BOLD)Building and uploading image to Hetzner...$(RESET)"
	cd examples/01-ops-hello-http && go build -o hello-http main.go && ops image create -t hetzner -c config.json hello-http
	@echo "$(BOLD)Creating Hetzner instance...$(RESET)"
	-cd examples/01-ops-hello-http && ops instance delete ops-hello-http -t hetzner -c config.json 2>/dev/null
	cd examples/01-ops-hello-http && ops instance create ops-hello-http -t hetzner -c config.json -p 8080
	@echo ""
	@echo "$(GREEN)$(BOLD)ops-hello-http instance running!$(RESET)"
	@echo "List with: ops instance list -t hetzner -c examples/01-ops-hello-http/config.json"

01-ops-hello-http-destroy: check-ops
	@echo "$(BOLD)Deleting ops-hello-http instance and image...$(RESET)"
	-cd examples/01-ops-hello-http && ops instance delete ops-hello-http -t hetzner -c config.json
	-cd examples/01-ops-hello-http && ops image delete ops-hello-http -t hetzner -c config.json
	@echo "$(GREEN)Done.$(RESET)"

# ── Example 02: OPS hello-http dd'd to disk ───────────────────

.PHONY: 02-ops-hello-dd

02-ops-hello-dd: check
	@echo "$(BOLD)Building ops-hello-dd image...$(RESET)"
	$(MAKE) -C examples/02-ops-hello-dd image
	$(call ensure-server-vanilla)
	$(call wait-ssh)
	@set -e; \
	 test -f examples/02-ops-hello-dd/image/ops-hello-dd.img || { echo "Image not found — run make -C examples/02-ops-hello-dd image"; exit 1; }; \
	 IP=$$(hcloud server describe $(SERVER) -o format='{{.PublicNet.IPv4.IP}}'); \
	 echo "$(BOLD)Deploying image via dd...$(RESET)"; \
	 echo "$(BOLD)Uploading image to server...$(RESET)"; \
	 scp -o StrictHostKeyChecking=no \
	     examples/02-ops-hello-dd/image/ops-hello-dd.img root@$$IP:/dev/shm/disk.img; \
	 echo "$(BOLD)Writing image to disk...$(RESET)"; \
	 ssh -o StrictHostKeyChecking=no \
	     -o ServerAliveInterval=2 \
	     -o ServerAliveCountMax=3 \
	     root@$$IP \
	   "cp /bin/dd /dev/shm/dd && \
	    blkdiscard /dev/sda -f || true && \
	    /dev/shm/dd if=/dev/shm/disk.img of=/dev/sda bs=4M conv=sync && \
	    echo s > /proc/sysrq-trigger && echo o > /proc/sysrq-trigger" || true; \
	 echo "$(BOLD)Waiting for server to power off...$(RESET)"; \
	 until [ "$$(hcloud server describe $(SERVER) -o format='{{.Status}}')" = "off" ]; do sleep 3; done; \
	 echo "$(BOLD)Powering on...$(RESET)"; \
	 hcloud server poweron $(SERVER); \
	 echo "$(BOLD)Waiting for port 8080...$(RESET)"; \
	 until curl -sf --max-time 3 http://$$IP:8080 >/dev/null 2>&1; do sleep 3; done
	@echo ""
	@echo "$(GREEN)$(BOLD)$(SERVER) running 02-ops-hello-dd!$(RESET)"
	@echo "Test with: make ip | xargs -I{} curl http://{}:8080"

# ── Utility ────────────────────────────────────────────────────

.PHONY: ip ssh destroy servers clean

ip:
	@hcloud server describe $(SERVER) -o format='{{.PublicNet.IPv4.IP}}'

ssh: check
	hcloud server ssh $(SERVER)

destroy: check
	@echo "$(BOLD)Destroying $(SERVER)...$(RESET)"
	hcloud server delete $(SERVER)
	@echo "$(GREEN)Done.$(RESET)"

servers: check
	@hcloud server list -o columns=id,name,status,ipv4,location,age

clean:
	$(MAKE) -C examples/02-ops-hello-dd clean
