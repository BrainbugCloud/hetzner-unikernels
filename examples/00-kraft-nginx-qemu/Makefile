# examples/00-kraft-nginx-qemu — kraftkit + nginx running in QEMU on a Hetzner VM.
#
# Same shape as 00-ops-nginx-qemu but using kraftkit (Unikraft) instead of OPS.
# Cloud-init installs kraft on an Ubuntu VM, kraft pulls and runs nginx under
# QEMU. Unikernel listens on 8080 on the VM's public IP.

REPO_ROOT := $(shell git rev-parse --show-toplevel)
include $(REPO_ROOT)/lib/common.mk
include $(REPO_ROOT)/lib/deploy-dd.mk

.PHONY: deploy clean

deploy: check
	$(call ensure-server-cloudinit,cloud-init.yaml)
	@echo ""
	@echo "$(GREEN)$(BOLD)$(SERVER) running 00-kraft-nginx-qemu!$(RESET)"
	@echo "Cloud-init is installing kraftkit and booting the unikernel (~2-3 min)."
	@echo "Test with:  curl http://$$($(MAKE) -s -C $(REPO_ROOT) ip):8080"
	@echo "SSH:        make ssh"

clean:
	@:
