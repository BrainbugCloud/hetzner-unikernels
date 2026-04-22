# examples/04-unikraft-go-http — Go HTTP server on Unikraft, dd'd to disk.
#
# Same two-piece model as 03-unikraft-console:
#   1. A kernel (elfloader) built from third_party/ sources.
#   2. An initramfs built by kraft from server.go via Dockerfile.
#
# The difference from 03: lwip + virtio-net are compiled in, and the kernel
# cmdline carries a static IP so the Go server can bind and accept connections.
#
# Boot protocols:
#   - GRUB multiboot  -> MBR disk, works on Hetzner cx (SeaBIOS)
#   - EFI stub        -> GPT/ESP disk, works on Hetzner cpx (UEFI + GOP console)
#
# Override knobs:
#   GATEWAY=<ip>       default gateway (default: 172.31.1.1)
#   DEFCONFIG=<path>   defconfig for the kernel build (default: defconfigs/multiboot)
#
# See README.md for the full story.

REPO_ROOT := $(shell git rev-parse --show-toplevel)
HCLOUD    := /usr/local/bin/hcloud
include $(REPO_ROOT)/lib/common.mk
include $(REPO_ROOT)/lib/deploy-dd.mk

# ── Sources (submodules under third_party/) ────────────────────────────

UK_ROOT    ?= $(REPO_ROOT)/third_party/unikraft
UK_APP     ?= $(REPO_ROOT)/third_party/app-elfloader
UK_LIBS    ?= $(REPO_ROOT)/third_party/lib-lwip:$(REPO_ROOT)/third_party/lib-libelf

DEFCONFIG  ?= defconfigs/multiboot
DEFCONFIG_ABS := $(abspath $(DEFCONFIG))

UK_BUILD_MB  = $(CURDIR)/.build-multiboot
UK_BUILD_EFI = $(CURDIR)/.build-efi

KERNEL_MB  = $(UK_BUILD_MB)/elfloader_qemu-x86_64
KERNEL_EFI = $(UK_BUILD_EFI)/elfloader_qemu-x86_64
INITRD     = .unikraft/build/initramfs-x86_64.cpio
GRUB_IMG   = image/grub-disk.img
EFI_IMG    = image/efi-disk.img
STUB_NAME  = app-elfloader

# Static IP baked into the disk image.
# deploy-grub / deploy-efi override this with the real server IP from hcloud.
# For QEMU (run-grub / run-efi) the default gives QEMU's user-mode network.
IP      ?= 10.0.2.15/24:10.0.2.2
GATEWAY ?= 172.31.1.1

OVMF_CODE  ?= /usr/share/OVMF/OVMF_CODE_4M.fd
OVMF_VARS  ?= /usr/share/OVMF/OVMF_VARS_4M.fd

.PHONY: build run deploy \
        build-kernel-grub build-kernel-efi \
        disk-grub disk-efi run-grub run-efi \
        deploy-grub deploy-efi clean

# ── Default deploy target ──────────────────────────────────────────────

deploy: deploy-efi

# ── kraft: build the initramfs (Go HTTP server binary) ────────────────

build:
	KRAFTKIT_NO_CHECK_UPDATES=true \
	  kraft build --no-update --no-prompt --plat qemu --arch x86_64

run:
	KRAFTKIT_NO_CHECK_UPDATES=true \
	  kraft run --no-prompt --plat qemu --arch x86_64 --disable-acceleration -M 256M

# ── Elfloader kernel builds ────────────────────────────────────────────

build-kernel-grub:
	@test -d $(UK_ROOT)/support || { echo "$(RED)third_party/unikraft is empty -- run 'git submodule update --init'$(RESET)"; exit 1; }
	@mkdir -p $(UK_BUILD_MB)
	$(MAKE) -C $(UK_ROOT) A=$(UK_APP) L=$(UK_LIBS) O=$(UK_BUILD_MB) \
	  CROSS_COMPILE='' defconfig DEFCONFIG=$(DEFCONFIG_ABS)
	$(MAKE) -C $(UK_ROOT) A=$(UK_APP) L=$(UK_LIBS) O=$(UK_BUILD_MB) \
	  CROSS_COMPILE='' -j$$(nproc)
	@echo "Kernel (multiboot): $(KERNEL_MB) ($$(du -h $(KERNEL_MB) | cut -f1))"

build-kernel-efi:
	@test -d $(UK_ROOT)/support || { echo "$(RED)third_party/unikraft is empty -- run 'git submodule update --init'$(RESET)"; exit 1; }
	@mkdir -p $(UK_BUILD_EFI)
	$(MAKE) -C $(UK_ROOT) A=$(UK_APP) L=$(UK_LIBS) O=$(UK_BUILD_EFI) \
	  CROSS_COMPILE='' defconfig DEFCONFIG=$(abspath defconfigs/efi)
	$(MAKE) -C $(UK_ROOT) A=$(UK_APP) L=$(UK_LIBS) O=$(UK_BUILD_EFI) \
	  CROSS_COMPILE='' -j$$(nproc)
	@echo "Kernel (EFI stub): $(KERNEL_EFI) ($$(du -h $(KERNEL_EFI) | cut -f1))"

$(KERNEL_MB):
	$(MAKE) build-kernel-grub

$(KERNEL_EFI):
	$(MAKE) build-kernel-efi

$(INITRD):
	$(MAKE) build

# ── GRUB MBR disk image ────────────────────────────────────────────────

disk-grub: $(KERNEL_MB) $(INITRD)
	@mkdir -p image
	$(eval BUILDDIR := $(shell mktemp -d))
	@mkdir -p $(BUILDDIR)/boot/grub
	@cp $(KERNEL_MB) $(BUILDDIR)/boot/kernel
	@cp $(INITRD) $(BUILDDIR)/boot/initramfs.cpio
	@printf 'set default=0\nset timeout=0\n\nmenuentry "Unikraft go-http" {\n    multiboot /boot/kernel console=ttyS0 netdev.ip=$(IP) vfs.fstab=[ "initrd0:/:extract:::" ] -- /server\n    module /boot/initramfs.cpio\n    boot\n}\n' > $(BUILDDIR)/boot/grub/grub.cfg
	grub-mkrescue -o $(GRUB_IMG) $(BUILDDIR)/ 2>&1 | tail -1
	@rm -rf $(BUILDDIR)
	@echo "GRUB disk: $(GRUB_IMG) ($$(du -h $(GRUB_IMG) | cut -f1))"

# ── GPT/ESP UEFI disk image ────────────────────────────────────────────

disk-efi: $(KERNEL_EFI) $(INITRD)
	@mkdir -p image
	@printf 'console=ttyS0 netdev.ip=$(IP) vfs.fstab=[initrd0:/:extract:::] -- /server' > image/$(STUB_NAME).cmdl
	dd if=/dev/zero of=image/esp.img bs=1M count=16 status=none
	/usr/sbin/mkfs.vfat -F 16 image/esp.img >/dev/null
	/usr/bin/mmd    -i image/esp.img ::EFI ::EFI/BOOT
	/usr/bin/mcopy  -i image/esp.img $(KERNEL_EFI)           ::EFI/BOOT/BOOTX64.EFI
	/usr/bin/mcopy  -i image/esp.img $(INITRD)               ::EFI/BOOT/$(STUB_NAME).initrd
	/usr/bin/mcopy  -i image/esp.img image/$(STUB_NAME).cmdl ::EFI/BOOT/$(STUB_NAME).cmdl
	dd if=/dev/zero of=$(EFI_IMG) bs=1M count=18 status=none
	/usr/sbin/sgdisk -Z $(EFI_IMG) >/dev/null 2>&1
	/usr/sbin/sgdisk -n 1:2048:+16M -t 1:EF00 $(EFI_IMG) >/dev/null 2>&1
	dd if=image/esp.img of=$(EFI_IMG) bs=512 seek=2048 conv=notrunc status=none
	@rm -f image/esp.img image/$(STUB_NAME).cmdl
	@echo "EFI disk: $(EFI_IMG) ($$(du -h $(EFI_IMG) | cut -f1))"

# ── Local QEMU tests ───────────────────────────────────────────────────

run-grub: disk-grub
	qemu-system-x86_64 \
	  -machine pc -cpu qemu64,+pdpe1gb,+rdrand,+rdseed \
	  -m 256M -no-reboot \
	  -device virtio-net-pci,netdev=net0 -netdev user,id=net0,hostfwd=tcp::8080-:8080 \
	  -display none -serial stdio \
	  -cdrom $(GRUB_IMG)

run-efi: disk-efi
	@cp $(OVMF_VARS) image/ovmf-vars.fd
	qemu-system-x86_64 \
	  -machine pc-i440fx-7.0,smm=off \
	  -cpu qemu64,-vmx,-svm,+x2apic,+pdpe1gb,+rdrand,+rdseed \
	  -m 256M -no-reboot \
	  -drive if=pflash,format=raw,readonly=on,file=$(OVMF_CODE) \
	  -drive if=pflash,format=raw,file=image/ovmf-vars.fd \
	  -drive file=$(EFI_IMG),if=ide,format=raw \
	  -device virtio-net-pci,netdev=net0 -netdev user,id=net0,hostfwd=tcp::8080-:8080 \
	  -display none -serial stdio

# ── Hetzner dd deploy ──────────────────────────────────────────────────
#
# Query the server IP first, rebuild the disk with it baked in, then deploy.
# Hetzner uses /32 point-to-point routing with gateway 172.31.1.1.

deploy-grub:
	$(call ensure-server-vanilla)
	$(eval _IP := $(shell hcloud server describe $(SERVER) -o format='{{.PublicNet.IPv4.IP}}'))
	$(MAKE) disk-grub IP=$(_IP)/32:$(GATEWAY)
	$(call wait-ssh)
	$(call dd-deploy,$(GRUB_IMG))
	@echo ""
	@echo "$(GREEN)$(BOLD)$(SERVER) is running 04-unikraft-go-http (GRUB)!$(RESET)"
	@echo "  curl http://$(_IP):8080/"

deploy-efi:
	$(call ensure-server-vanilla)
	$(eval _IP := $(shell hcloud server describe $(SERVER) -o format='{{.PublicNet.IPv4.IP}}'))
	$(MAKE) disk-efi IP=$(_IP)/32:$(GATEWAY)
	$(call wait-ssh)
	$(call dd-deploy,$(EFI_IMG))
	@echo ""
	@echo "$(GREEN)$(BOLD)$(SERVER) is running 04-unikraft-go-http (EFI)!$(RESET)"
	@echo "  curl http://$(_IP):8080/"

# ── Clean ──────────────────────────────────────────────────────────────

clean:
	rm -rf .build-multiboot .build-efi .unikraft image/
