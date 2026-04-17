# examples/00-ops-nginx-qemu — OPS + nginx running in QEMU on a Hetzner VM.
#
# Flow:
#   cloud-init installs ops on an Ubuntu VM, ops runs an nginx unikernel
#   under QEMU (software emulation — Hetzner cloud VMs have no nested virt).
#
# The unikernel listens on 8083 on the VM's public IP.

REPO_ROOT := $(shell git rev-parse --show-toplevel)
include $(REPO_ROOT)/lib/common.mk
include $(REPO_ROOT)/lib/deploy-dd.mk

.PHONY: deploy clean

deploy: check
	$(call ensure-server-cloudinit,cloud-init.yaml)
	@echo ""
	@echo "$(GREEN)$(BOLD)$(SERVER) running 00-ops-nginx-qemu!$(RESET)"
	@echo "Cloud-init is installing ops and booting the unikernel (~2-3 min)."
	@echo "  http://$$($(MAKE) -s -C $(REPO_ROOT) ip):8083"
	@echo "SSH: make ssh"

clean:
	@# Nothing to clean locally — everything runs on the VM.
	@:
