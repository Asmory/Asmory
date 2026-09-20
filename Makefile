AS ?= as
LD ?= ld
ASFLAGS := --64
LDFLAGS := -z noexecstack
BUILD := build

REGISTRY_OBJ := $(BUILD)/registry/server.o
REGISTRY_BIN := $(BUILD)/asmory-registry
CLI_OBJ := $(BUILD)/cli/main.o
CLI_BIN := $(BUILD)/asmory
EXAMPLE_OBJ := $(BUILD)/examples/simd-dot/dot.o
PACKAGE_ARCHIVE := $(BUILD)/packages/simd-dot-0.1.0.tar.gz
STATIC := $(wildcard registry/static/*) $(wildcard registry/data/*)

.PHONY: all registry cli examples packages run check smoke cli-smoke dev clean install-user

all: registry cli examples

registry: $(REGISTRY_BIN)
cli: $(CLI_BIN)
examples: $(EXAMPLE_OBJ)
packages: $(PACKAGE_ARCHIVE)

$(BUILD)/registry $(BUILD)/cli $(BUILD)/examples/simd-dot $(BUILD)/packages:
	mkdir -p $@

$(PACKAGE_ARCHIVE): examples/simd-dot/asm.toml examples/simd-dot/src/dot.S | $(BUILD)/packages
	tar --sort=name --mtime='UTC 1970-01-01' --owner=0 --group=0 --numeric-owner -czf $@ -C examples simd-dot

$(REGISTRY_OBJ): registry/src/server.S $(STATIC) $(PACKAGE_ARCHIVE) | $(BUILD)/registry
	$(AS) $(ASFLAGS) $< -o $@

$(REGISTRY_BIN): $(REGISTRY_OBJ)
	$(LD) $(LDFLAGS) $< -o $@

$(CLI_OBJ): cli/src/main.S | $(BUILD)/cli
	$(AS) $(ASFLAGS) $< -o $@

$(CLI_BIN): $(CLI_OBJ)
	$(LD) $(LDFLAGS) $< -o $@

$(EXAMPLE_OBJ): examples/simd-dot/src/dot.S | $(BUILD)/examples/simd-dot
	$(AS) $(ASFLAGS) $< -o $@

run: $(REGISTRY_BIN)
	./$(REGISTRY_BIN)

install-user: $(CLI_BIN)
	install -Dm755 $(CLI_BIN) $(HOME)/.local/bin/asmory
	@echo 'installed: $(HOME)/.local/bin/asmory'

dev: clean all check smoke cli-smoke

check: all
	@echo '== registry binary =='
	@file $(REGISTRY_BIN)
	@echo 'bytes:'
	@wc -c < $(REGISTRY_BIN)
	@echo '== cli binary =='
	@file $(CLI_BIN)
	@$(CLI_BIN) --version
	@echo 'bytes:'
	@wc -c < $(CLI_BIN)
	@echo '== embedded assets =='
	@wc -c registry/static/* registry/data/* $(PACKAGE_ARCHIVE)
	@echo '== example symbols =='
	@nm $(EXAMPLE_OBJ)

smoke: $(REGISTRY_BIN)
	./scripts/smoke.sh

cli-smoke: $(CLI_BIN)
	./scripts/cli-smoke.sh

clean:
	rm -rf $(BUILD)
