# examples/02-ops-hello-dd — OPS image dd'd straight onto the VM's disk.
#
# Flow:
#   ops build produces a raw disk image locally (no object storage).
#   We rebuild the shared VM to vanilla Ubuntu, scp the image to /dev/shm,
#   dd it onto /dev/sda, sysrq 'o' poweroff, then hcloud poweron.
#
# The resulting VM boots the unikernel directly — no Linux underneath.

REPO_ROOT := $(shell git rev-parse --show-toplevel)
include $(REPO_ROOT)/lib/common.mk
include $(REPO_ROOT)/lib/deploy-dd.mk

IMAGE_NAME := ops-hello-dd
IMAGE_SRC  := $(HOME)/.ops/images/$(IMAGE_NAME)
IMAGE_OUT  := image/$(IMAGE_NAME).img

.PHONY: build run image deploy clean check-ops

build: check-ops
	go build -o hello-dd main.go
	ops build -t hetzner hello-dd -c config.json

run: check-ops
	ops run main.go -c config.json -p 8080

image: build
	mkdir -p image
	cp $(IMAGE_SRC) $(IMAGE_OUT)
	@echo "Image: $(IMAGE_OUT) ($$(du -h $(IMAGE_OUT) | cut -f1))"

deploy: check image
	$(call ensure-server-vanilla)
	$(call wait-ssh)
	$(call dd-deploy,$(IMAGE_OUT))
	@echo "$(BOLD)Waiting for port 8080...$(RESET)"
	@set -e; IP=$$(hcloud server describe $(SERVER) -o format='{{.PublicNet.IPv4.IP}}'); \
	 until curl -sf --max-time 3 http://$$IP:8080 >/dev/null 2>&1; do sleep 3; done
	@echo ""
	@echo "$(GREEN)$(BOLD)$(SERVER) running 02-ops-hello-dd!$(RESET)"
	@echo "Test: curl http://$$($(MAKE) -s -C $(REPO_ROOT) ip):8080"

clean:
	rm -rf image/ hello-dd

check-ops:
	@which ops >/dev/null 2>&1 || { \
		echo "$(RED)$(BOLD)ops CLI not found.$(RESET)"; \
		echo "Install: curl https://ops.city/get.sh | sh"; \
		exit 1; }
