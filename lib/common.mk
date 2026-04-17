# lib/common.mk — shared configuration, colours, and prerequisite checks.
# Included by the top-level Makefile and by every examples/*/Makefile.
#
# Provides:
#   - REPO_ROOT                   absolute path to the repo (for includes/paths)
#   - SERVER / SERVER_TYPE / …    shared Hetzner server config (overridable)
#   - colour variables            RESET / BOLD / RED / GREEN / CYAN
#   - check-hcloud / check-token  prerequisite checks with actionable errors
#   - check                       umbrella check (hcloud + token)
#   - ip / ssh / destroy / servers   utility targets that work on SERVER

# ── Resolve the repo root once, regardless of who's including this ─────
# `git rev-parse --show-toplevel` works from any subdir (submodule-safe).
REPO_ROOT ?= $(shell git rev-parse --show-toplevel)

# ── Shared Hetzner server (one VM, rebuilt per example) ───────────────
SERVER      ?= unikernel-example
SERVER_TYPE ?= cpx22
LOCATION    ?= fsn1
BASE_IMAGE  ?= ubuntu-24.04
SSH_KEY      ?= unikernel-key
SSH_KEY_PATH ?= $(HOME)/.ssh/$(SSH_KEY)

# ── Minimum hcloud version (rebuild --user-data-from-file needs >= 1.62) ─
HCLOUD_MIN_VERSION := 1.62.0

# ── Colours (ANSI) ────────────────────────────────────────────────────
RESET  := \033[0m
BOLD   := \033[1m
RED    := \033[31m
GREEN  := \033[32m
CYAN   := \033[36m

# ── Prerequisite checks ────────────────────────────────────────────────

.PHONY: check check-hcloud check-token

check: check-hcloud check-token
	@echo "$(GREEN)$(BOLD)All prerequisites met!$(RESET)"

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
			echo "  Get a token: https://console.hetzner.cloud/ -> Security -> API Tokens"; \
			exit 1; \
		fi; \
	fi
	@hcloud server list >/dev/null 2>&1 || { \
		echo "$(RED)$(BOLD)hcloud cannot reach the API -- check your token.$(RESET)"; \
		echo "  export HCLOUD_TOKEN=\"<your-hetzner-api-token>\""; \
		exit 1; }
	@echo "$(GREEN)Hetzner API reachable$(RESET)"

# ── Utility targets on the shared server ──────────────────────────────

# ensure-ssh-key — generate ~/.ssh/unikernel-key if absent, upload to Hetzner if not there.
# Called by ensure-server-vanilla so the key always exists before server creation.
.PHONY: ensure-ssh-key
ensure-ssh-key:
	@if [ ! -f "$(SSH_KEY_PATH)" ]; then \
		echo "$(CYAN)Generating SSH key $(SSH_KEY_PATH)...$(RESET)"; \
		ssh-keygen -t ed25519 -C "unikernel-key" -N "" -f "$(SSH_KEY_PATH)" >/dev/null; \
	fi
	@if ! hcloud ssh-key describe $(SSH_KEY) >/dev/null 2>&1; then \
		echo "$(CYAN)Uploading $(SSH_KEY) to Hetzner...$(RESET)"; \
		hcloud ssh-key create --name $(SSH_KEY) --public-key-from-file "$(SSH_KEY_PATH).pub"; \
	fi

.PHONY: ip ssh destroy servers

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
