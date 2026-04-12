# hetzner-unikernels — Makefile
#
# Prerequisites (minimal):
#   - hcloud CLI
#   HCLOUD_TOKEN env var (Hetzner Cloud API token)
#
# Quick start:
#   make check                   — verify prerequisites
#   make 00-ops-nginx-qemu       — example 0: VM + ops + nginx unikernel in QEMU
#   make 00-ops-nginx-qemu-destroy — destroy example 0
#   make 00-kraft-nginx-qemu    — example 1: VM + kraftkit + nginx unikernel in QEMU (TCG)
#   make 00-kraft-nginx-qemu-destroy — destroy example 1
#   make servers                — list running servers

# ── Configuration ──────────────────────────────────────────────

SERVER_TYPE ?= cpx22
LOCATION    ?= fsn1
BASE_IMAGE  ?= ubuntu-24.04
SSH_KEY_NAME := unikernels-key
SSH_KEY_PATH := .ssh/id_ed25519

# ── Colors ─────────────────────────────────────────────────────

RESET  := \033[0m
BOLD   := \033[1m
RED    := \033[31m
GREEN  := \033[32m
YELLOW := \033[33m
CYAN   := \033[36m

# ── Prerequisite checks ────────────────────────────────────────

.PHONY: check check-hcloud check-token setup-ssh

check: check-hcloud check-token setup-ssh
	@echo "$(GREEN)$(BOLD)All prerequisites met!$(RESET)"

setup-ssh:
	@if [ ! -f $(SSH_KEY_PATH) ]; then \
		echo "$(CYAN)Generating SSH key $(SSH_KEY_PATH)...$(RESET)"; \
		mkdir -p .ssh; \
		ssh-keygen -t ed25519 -f $(SSH_KEY_PATH) -N ""; \
	fi
	@if ! hcloud ssh-key list | grep -q $(SSH_KEY_NAME); then \
		echo "$(CYAN)Uploading SSH key $(SSH_KEY_NAME) to Hetzner...$(RESET)"; \
		PUB_KEY=$$(cat $(SSH_KEY_PATH).pub); \
		hcloud ssh-key create --name $(SSH_KEY_NAME) --public-key="$$PUB_KEY"; \
	fi
	@echo "$(GREEN)SSH key ready$(RESET)"

check-hcloud:
	@which hcloud >/dev/null 2>&1 || { \
		echo "$(RED)$(BOLD)hcloud CLI not found.$(RESET)"; \
		echo ""; \
		echo "Install with:"; \
		echo "  curl -sSLO https://github.com/hetznercloud/cli/releases/latest/download/hcloud-linux-amd64.tar.gz"; \
		echo "  sudo tar -C /usr/local/bin --no-same-owner -xzf hcloud-linux-amd64.tar.gz hcloud"; \
		echo "  rm hcloud-linux-amd64.tar.gz"; \
		echo ""; \
		echo "Or see: https://github.com/hetznercloud/cli/blob/main/docs/tutorials/setup-hcloud-cli.md"; \
		exit 1; }
	@echo "$(CYAN)hcloud$(RESET) found"

check-token:
	@if [ -z "$$HCLOUD_TOKEN" ]; then \
		if ! hcloud context list 2>/dev/null | grep -q 'ACTIVE'; then \
			echo "$(RED)$(BOLD)HCLOUD_TOKEN not set and no active hcloud context.$(RESET)"; \
			echo ""; \
			echo "Set it with:"; \
			echo "  export HCLOUD_TOKEN=\"<your-hetzner-api-token>\""; \
			echo ""; \
			echo "Or create a context:"; \
			echo "  hcloud context create <project-name>"; \
			echo ""; \
			echo "Get a token: https://console.hetzner.cloud/ → Security → API Tokens"; \
			exit 1; \
		fi; \
	fi
	@hcloud server list >/dev/null 2>&1 || { \
		echo "$(RED)$(BOLD)hcloud cannot reach the API — check your token.$(RESET)"; \
		exit 1; }
	@echo "$(GREEN)Hetzner API reachable$(RESET)"

# ── Example 00a: Nanos nginx in QEMU ──────────────────────

.PHONY: 00-ops-nginx-qemu 00-ops-nginx-qemu-destroy 00-ops-nginx-qemu-ip

SSH_KEY ?= unikernels-key

00-ops-nginx-qemu: check
	@echo "$(BOLD)Creating ops-nginx-qemu server with cloud-init...$(RESET)"
	hcloud server create \
		--name ops-nginx-qemu \
		--type $(SERVER_TYPE) \
		--image $(BASE_IMAGE) \
		--location $(LOCATION) \
		--user-data-from-file examples/00-ops-nginx-qemu/cloud-init.yaml \
		--ssh-key $(SSH_KEY) \
		--label example=00-ops-nginx-qemu
	@echo ""
	@echo "$(GREEN)$(BOLD)ops-nginx-qemu deployed!$(RESET)"
	@echo "Cloud-init is installing ops and booting the unikernel (~2-3 min)."
	@echo "Test with:  make 00-ops-nginx-qemu-ip && curl http://$$(make -s 00-ops-nginx-qemu-ip):8083"
	@echo "SSH:  hcloud server ssh ops-nginx-qemu"

00-ops-nginx-qemu-ip:
	@hcloud server list -o columns=ipv4 -l example=00-ops-nginx-qemu | tail -1 | tr -d ' '

00-ops-nginx-qemu-destroy: check
	@echo "$(BOLD)Destroying ops-nginx-qemu...$(RESET)"
	hcloud server delete ops-nginx-qemu
	@echo "$(GREEN)Done.$(RESET)"

# ── Example 01: Kraftkit nginx in QEMU (TCG) ──────────────────

.PHONY: 00-kraft-nginx-qemu 00-kraft-nginx-qemu-destroy 00-kraft-nginx-qemu-ip

00-kraft-nginx-qemu: check
	@echo "$(BOLD)Creating kraft-nginx-qemu server with cloud-init...$(RESET)"
	hcloud server create \
		--name kraft-nginx-qemu \
		--type $(SERVER_TYPE) \
		--image $(BASE_IMAGE) \
		--location $(LOCATION) \
		--user-data-from-file examples/00-kraft-nginx-qemu/cloud-init.yaml \
		--ssh-key $(SSH_KEY) \
		--label example=00-kraft-nginx-qemu
	@echo ""
	@echo "$(GREEN)$(BOLD)kraft-nginx-qemu deployed!$(RESET)"
	@echo "Cloud-init is installing kraftkit and booting the unikernel (~2-3 min)."
	@echo "Test with:  make 00-kraft-nginx-qemu-ip && curl http://$$(make -s 00-kraft-nginx-qemu-ip):8080"
	@echo "SSH:  hcloud server ssh kraft-nginx-qemu"

00-kraft-nginx-qemu-ip:
	@hcloud server list -o columns=ipv4 -l example=00-kraft-nginx-qemu | tail -1 | tr -d ' '


00-kraft-nginx-qemu-destroy: check
	@echo "$(BOLD)Destroying kraft-nginx-qemu...$(RESET)"
	hcloud server delete kraft-nginx-qemu
	@echo "$(GREEN)Done.$(RESET)"


# ── Utility ──────────────────────────────────────────────────

.PHONY: servers clean

servers: check
	@hcloud server list -o columns=id,name,status,ipv4,location,age

clean:
	@echo "Nothing to clean (builds happen on remote servers)."