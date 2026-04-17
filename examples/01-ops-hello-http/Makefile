# examples/01-ops-hello-http — OPS native deploy via Hetzner snapshot.
#
# Flow:
#   ops image create -t hetzner ...  uploads to Hetzner Object Storage,
#                                    then creates a Hetzner snapshot.
#   ops instance create ...          boots a VM from that snapshot.
#
# Requires: HCLOUD_TOKEN, OBJECT_STORAGE_KEY, OBJECT_STORAGE_SECRET,
# BucketName + Zone in config.json. See the per-example README.

REPO_ROOT := $(shell git rev-parse --show-toplevel)
include $(REPO_ROOT)/lib/common.mk

IMAGE_NAME    := ops-hello-http
INSTANCE_NAME := ops-hello-http

.PHONY: build image deploy destroy clean check-ops check-ops-storage

build:
	go build -o hello-http main.go

image: build
	ops image create -t hetzner -c config.json hello-http

deploy: check check-ops check-ops-storage image
	-ops instance delete $(INSTANCE_NAME) -t hetzner -c config.json 2>/dev/null
	ops instance create $(IMAGE_NAME) -t hetzner -c config.json -p 8080
	@echo ""
	@echo "$(GREEN)$(BOLD)ops-hello-http instance running!$(RESET)"
	@echo "List:    ops instance list -t hetzner -c config.json"
	@echo "Destroy: make -C examples/01-ops-hello-http destroy"

destroy:
	-ops instance delete $(INSTANCE_NAME) -t hetzner -c config.json
	-ops image delete $(IMAGE_NAME) -t hetzner -c config.json

clean: destroy
	rm -f hello-http

check-ops:
	@which ops >/dev/null 2>&1 || { \
		echo "$(RED)$(BOLD)ops CLI not found.$(RESET)"; \
		echo "Install: curl https://ops.city/get.sh | sh"; \
		exit 1; }

check-ops-storage:
	@FAIL=0; \
	 [ -n "$$OBJECT_STORAGE_KEY" ] || { echo "  $(RED)OBJECT_STORAGE_KEY$(RESET) not set"; FAIL=1; }; \
	 [ -n "$$OBJECT_STORAGE_SECRET" ] || { echo "  $(RED)OBJECT_STORAGE_SECRET$(RESET) not set"; FAIL=1; }; \
	 BUCKET=$$(python3 -c "import json; print(json.load(open('config.json'))['CloudConfig'].get('BucketName',''))" 2>/dev/null); \
	 [ -n "$$BUCKET" ] || { echo "  $(RED)BucketName$(RESET) not set in config.json"; FAIL=1; }; \
	 [ $$FAIL -eq 0 ] || { \
		echo ""; \
		echo "$(BOLD)Example 01 requires OPS Hetzner credentials:$(RESET)"; \
		echo "  export OBJECT_STORAGE_KEY=\"<your-storage-access-key>\""; \
		echo "  export OBJECT_STORAGE_SECRET=\"<your-storage-secret-key>\""; \
		echo "  Set BucketName and Zone in config.json"; \
		echo "  Get credentials: https://console.hetzner.cloud/ -> Object Storage"; \
		exit 1; }
