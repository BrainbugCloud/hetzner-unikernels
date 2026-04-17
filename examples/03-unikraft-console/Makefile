# examples/03-unikraft-console — Unikraft hello-world built from source, dd'd to disk.
#
# Unikraft has two pieces:
#   1. A kernel (the elfloader) built from the Unikraft source tree in
#      third_party/. This is a stable binary per-defconfig; we don't rebuild
#      it every time the app changes.
#   2. An initramfs built by kraft from helloworld.c via Dockerfile -- that's
#      what ships the hello-world binary.
#
# The two boot protocols we demo:
#   - GRUB multiboot  -> MBR disk image, works on Hetzner cx (SeaBIOS)
#   - EFI stub        -> GPT/ESP disk image, works on Hetzner cpx (UEFI)
#
# Override knobs:
#   UK_BRANCH=<branch>  switch all submodules to <branch> (default: stable)
#   DEFCONFIG=<path>    defconfig to use (default: defconfigs/multiboot)
#
# See README.md for the full story.

REPO_ROOT := $(shell git rev-parse --show-toplevel)
include $(REPO_ROOT)/lib/common.mk
include $(REPO_ROOT)/lib/deploy-dd.mk

# ── Sources (submodules under third_party/) ────────────────────────────

UK_ROOT    ?= $(REPO_ROOT)/third_party/unikraft
UK_APP     ?= $(REPO_ROOT)/third_party/app-elfloader
UK_LIBS    ?= $(REPO_ROOT)/third_party/lib-lwip:$(REPO_ROOT)/third_party/lib-libelf
UK_BRANCH  ?= stable

DEFCONFIG  ?= defconfigs/multiboot
DEFCONFIG_ABS := $(abspath $(DEFCONFIG))

# Separate build dirs so GRUB and EFI builds don't clobber each other.
UK_BUILD_MB  = $(CURDIR)/.build-multiboot
UK_BUILD_EFI = $(CURDIR)/.build-efi

KERNEL_MB  = $(UK_BUILD_MB)/elfloader_qemu-x86_64
KERNEL_EFI = $(UK_BUILD_EFI)/elfloader_qemu-x86_64
INITRD     = .unikraft/build/initramfs-x86_64.cpio
GRUB_IMG   = image/grub-disk.img
EFI_IMG    = image/efi-disk.img
STUB_NAME  = app-elfloader

OVMF_CODE  ?= /usr/share/OVMF/OVMF_CODE_4M.fd
OVMF_VARS  ?= /usr/share/OVMF/OVMF_VARS_4M.fd

.PHONY: build run use-branch deploy \
        build-kernel-grub build-kernel-efi \
        disk-grub disk-efi run-grub run-efi \
        deploy-grub deploy-efi clean

# ── Default deploy target (dispatched to by top-level `make 03-...`) ───

deploy: deploy-grub

# ── kraft: build the initramfs (helloworld binary) ─────────────────────

build:
	KRAFTKIT_NO_CHECK_UPDATES=true \
	  kraft build --no-update --no-prompt --plat qemu --arch x86_64

run:
	KRAFTKIT_NO_CHECK_UPDATES=true \
	  kraft run --no-prompt --plat qemu --arch x86_64 --disable-acceleration -M 128M

# ── Switch all submodule branches at once ──────────────────────────────

use-branch:
	@echo "Switching all Unikraft submodules to branch: $(UK_BRANCH)"
	@for m in $(UK_ROOT) $(UK_APP) $(REPO_ROOT)/third_party/lib-lwip $(REPO_ROOT)/third_party/lib-libelf; do \
		git -C $$m fetch origin $(UK_BRANCH) && git -C $$m checkout $(UK_BRANCH); \
	done

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
	@printf 'set default=0\nset timeout=0\n\nmenuentry "Unikraft" {\n    multiboot /boot/kernel console=ttyS0 vfs.fstab=[ "initrd0:/:extract:::" ] -- /helloworld\n    module /boot/initramfs.cpio\n    boot\n}\n' > $(BUILDDIR)/boot/grub/grub.cfg
	grub-mkrescue -o $(GRUB_IMG) $(BUILDDIR)/ 2>&1 | tail -1
	@rm -rf $(BUILDDIR)
	@echo "GRUB disk: $(GRUB_IMG) ($$(du -h $(GRUB_IMG) | cut -f1))"

# ── GPT/ESP UEFI disk image ────────────────────────────────────────────

disk-efi: $(KERNEL_EFI) $(INITRD)
	@mkdir -p image
	@printf 'console=ttyS0 vfs.fstab=[ "initrd0:/:extract:::" ] -- /helloworld\n' > image/$(STUB_NAME).cmdl
	@# FAT16 ESP (10 MB -- FAT32 requires >=33MB, FAT16 fits small EFI contents)
	dd if=/dev/zero of=image/esp.img bs=1M count=10 status=none
	mkfs.vfat -F 16 image/esp.img >/dev/null
	mmd    -i image/esp.img ::EFI ::EFI/BOOT
	mcopy  -i image/esp.img $(KERNEL_EFI)          ::EFI/BOOT/BOOTX64.EFI
	mcopy  -i image/esp.img $(INITRD)              ::EFI/BOOT/$(STUB_NAME).initrd
	mcopy  -i image/esp.img image/$(STUB_NAME).cmdl ::EFI/BOOT/$(STUB_NAME).cmdl
	@# GPT wrapper (12 MB -- 10MB ESP + ~2MB for GPT primary/backup headers)
	dd if=/dev/zero of=$(EFI_IMG) bs=1M count=12 status=none
	sgdisk -Z $(EFI_IMG) >/dev/null 2>&1
	sgdisk -n 1:2048:+10M -t 1:EF00 $(EFI_IMG) >/dev/null 2>&1
	dd if=image/esp.img of=$(EFI_IMG) bs=512 seek=2048 conv=notrunc status=none
	@rm -f image/esp.img image/$(STUB_NAME).cmdl
	@echo "EFI disk: $(EFI_IMG) ($$(du -h $(EFI_IMG) | cut -f1))"

# ── Local QEMU tests ───────────────────────────────────────────────────

run-grub: disk-grub
	qemu-system-x86_64 \
	  -machine pc -cpu qemu64,+pdpe1gb,+rdrand,+rdseed \
	  -m 128M -no-reboot \
	  -device virtio-net-pci,netdev=net0 -netdev user,id=net0 \
	  -display none -serial stdio \
	  -cdrom $(GRUB_IMG)

run-efi: disk-efi
	@cp $(OVMF_VARS) image/ovmf-vars.fd
	qemu-system-x86_64 \
	  -machine pc-i440fx-7.0,smm=off \
	  -cpu qemu64,-vmx,-svm,+x2apic,+pdpe1gb,+rdrand,+rdseed \
	  -m 128M -no-reboot \
	  -drive if=pflash,format=raw,readonly=on,file=$(OVMF_CODE) \
	  -drive if=pflash,format=raw,file=image/ovmf-vars.fd \
	  -drive file=$(EFI_IMG),if=ide,format=raw \
	  -device virtio-net-pci,netdev=net0 -netdev user,id=net0 \
	  -display none -serial stdio

# ── Hetzner dd deploy ──────────────────────────────────────────────────

deploy-grub: disk-grub
	$(call ensure-server-vanilla)
	$(call wait-ssh)
	$(call dd-deploy,$(GRUB_IMG))
	@echo ""
	@echo "$(GREEN)$(BOLD)$(SERVER) running 03-unikraft-console (GRUB)!$(RESET)"
	@echo "Check Hetzner VNC console for serial output."
	@echo "(For VGA output, create the server as 'cx' type, not 'cpx'.)"

deploy-efi: disk-efi
	$(call ensure-server-vanilla)
	$(call wait-ssh)
	$(call dd-deploy,$(EFI_IMG))
	@echo ""
	@echo "$(GREEN)$(BOLD)$(SERVER) running 03-unikraft-console (EFI)!$(RESET)"
	@echo "Check Hetzner VNC console for serial output."

# ── Clean ──────────────────────────────────────────────────────────────

clean:
	rm -rf .build-multiboot .build-efi .unikraft image/ *.o
