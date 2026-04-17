# hetzner-unikernels — top-level orchestrator.
#
# The real logic lives in:
#   lib/common.mk          shared config, checks, ip/ssh/destroy/servers
#   lib/deploy-dd.mk       dd-deploy flow (included by examples that need it)
#   examples/<name>/Makefile   per-example build + deploy
#
# From the repo root:
#   make check                     verify hcloud + token
#   make servers | ip | ssh        shared-server utilities
#   make destroy                   delete the shared server
#   make <example-name>            deploy that example (see list below)
#   make clean                     clean all example build output
#
# Examples:
#   00-ops-nginx-qemu     OPS + nginx in QEMU on the VM (cloud-init)
#   00-kraft-nginx-qemu   kraftkit + nginx in QEMU on the VM (cloud-init)
#   01-ops-hello-http     OPS native deploy via snapshot (needs object storage)
#   02-ops-hello-dd       OPS image dd'd straight onto the VM's disk
#   03-unikraft-console   Unikraft hello-world built from source, dd'd to disk
#
# See examples/<name>/README.md for the per-example story.

include lib/common.mk

# ── Example dispatch ───────────────────────────────────────────────────

EXAMPLES := \
	00-ops-nginx-qemu \
	00-kraft-nginx-qemu \
	01-ops-hello-http \
	02-ops-hello-dd \
	03-unikraft-console

.PHONY: $(EXAMPLES)

$(EXAMPLES): check
	$(MAKE) -C examples/$@ deploy

# ── Clean (delegate to each example that knows how) ────────────────────

.PHONY: clean
clean:
	@for e in $(EXAMPLES); do \
		if [ -f examples/$$e/Makefile ]; then \
			$(MAKE) --no-print-directory -C examples/$$e clean 2>/dev/null || true; \
		fi; \
	done
