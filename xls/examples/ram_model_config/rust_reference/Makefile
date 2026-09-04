# Builds and runs the Rust reference examples (see ../README.md). Not part
# of the Bazel build. Prefers whatever's already on the machine; anything
# missing (nightly, or even rustup itself) is fetched into a project-local,
# disposable directory instead of machine-wide. `make clean` removes it all.

BIN_DIR := build
TOOLCHAIN_DIR := $(abspath $(BIN_DIR)/local-toolchain)
LOCAL_ENV := RUSTUP_HOME=$(TOOLCHAIN_DIR)/rustup CARGO_HOME=$(TOOLCHAIN_DIR)/cargo

HAVE_SYSTEM_RUSTUP := $(shell command -v rustup >/dev/null 2>&1 && echo 1)
ifeq ($(HAVE_SYSTEM_RUSTUP),1)
RUSTUP := rustup
else
RUSTUP := $(TOOLCHAIN_DIR)/cargo/bin/rustup
endif

# A system rustup with no nightly yet still gets used directly, just
# pointed at a project-local home for that one install.
HAVE_NATIVE_NIGHTLY := $(if $(HAVE_SYSTEM_RUSTUP),$(shell rustup toolchain list 2>/dev/null | grep -q '^nightly' && echo 1))
ifeq ($(HAVE_NATIVE_NIGHTLY),1)
NIGHTLY_ENV :=
else
NIGHTLY_ENV := $(LOCAL_ENV)
endif

NIGHTLY_RUSTC := $(NIGHTLY_ENV) $(RUSTUP) run nightly rustc

.PHONY: all run clean trait_bound struct_update run-trait_bound run-struct_update \
        bootstrap-rustup install-nightly-toolchain

all: trait_bound struct_update

run: run-trait_bound run-struct_update

trait_bound: $(BIN_DIR)/trait_bound
run-trait_bound: trait_bound
	$(BIN_DIR)/trait_bound

struct_update: $(BIN_DIR)/struct_update
run-struct_update: struct_update
	$(BIN_DIR)/struct_update

# trait_bound.rs only needs stable Rust, but falls back to nightly (a strict
# superset) if there's no system rustc at all.
$(BIN_DIR)/trait_bound: trait_bound.rs | $(BIN_DIR)
	@if command -v rustc >/dev/null 2>&1; then \
		echo "==> Found system rustc: $$(command -v rustc)"; \
		echo "==> Compiling $< with system rustc"; \
		rustc --edition 2021 $< -o $@; \
	else \
		echo "==> No system rustc found; will use the nightly toolchain instead"; \
		$(MAKE) install-nightly-toolchain && \
		echo "==> Compiling $< with the nightly toolchain" && \
		$(NIGHTLY_RUSTC) --edition 2021 $< -o $@; \
	fi
	@echo "==> Built $@"

$(BIN_DIR)/struct_update: struct_update.rs | install-nightly-toolchain $(BIN_DIR)
	@echo "==> Compiling $< with the nightly toolchain"
	$(NIGHTLY_RUSTC) --edition 2021 $< -o $@
	@echo "==> Built $@"

bootstrap-rustup: | $(BIN_DIR)
ifeq ($(HAVE_SYSTEM_RUSTUP),1)
	@echo "==> Found system rustup: $$(command -v rustup)"
else
	@if [ -x "$(RUSTUP)" ]; then \
		echo "==> Already bootstrapped rustup into $(TOOLCHAIN_DIR)"; \
	else \
		echo "==> No system rustup found"; \
		if ! command -v curl >/dev/null 2>&1; then \
			echo "error: curl not found on PATH; needed to bootstrap rustup." >&2; \
			echo "Install curl, or install rustup yourself from https://rustup.rs." >&2; \
			exit 1; \
		fi; \
		echo "==> Bootstrapping rustup into $(TOOLCHAIN_DIR) (project-local, not machine-wide)"; \
		curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | \
			$(LOCAL_ENV) sh -s -- -y --no-modify-path --default-toolchain none; \
	fi
endif

install-nightly-toolchain: bootstrap-rustup
	@if $(NIGHTLY_ENV) $(RUSTUP) toolchain list 2>/dev/null | grep -q '^nightly'; then \
		echo "==> Found nightly toolchain (already installed)"; \
	else \
		echo "==> Installing a nightly toolchain$(if $(NIGHTLY_ENV), into $(TOOLCHAIN_DIR) (project-local, not machine-wide),)"; \
		$(NIGHTLY_ENV) $(RUSTUP) toolchain install nightly --profile minimal --no-self-update; \
	fi

$(BIN_DIR):
	mkdir -p $(BIN_DIR)

clean:
	rm -rf $(BIN_DIR)
