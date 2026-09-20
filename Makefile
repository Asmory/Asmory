AS ?= as
LD ?= ld
ASFLAGS := --64
LDFLAGS := -z noexecstack
BUILD := build

REGISTRY_OBJ := $(BUILD)/registry/server.o
REGISTRY_BIN := $(BUILD)/asmory-registry
CLI_OBJ := $(BUILD)/cli/main.o
CLI_BIN := $(BUILD)/asmory
CLI_REGISTRY_INC := $(BUILD)/generated/cli_registry.inc
EXAMPLE_OBJ := $(BUILD)/examples/simd-dot/dot.o
TUNED_OBJ := $(BUILD)/examples/simd-dot/dot_4acc.o
VARIANT_BENCH_OBJ := $(BUILD)/benchmarks/simd-dot/compare_variants.o
VARIANT_BENCH_BIN := $(BUILD)/benchmarks/simd-dot-variants
CONFORMANCE_OBJ := $(BUILD)/conformance/simd-dot/basic.o
CONFORMANCE_GENERIC := $(BUILD)/conformance/simd-dot/generic
CONFORMANCE_4ACC := $(BUILD)/conformance/simd-dot/4acc
BENCH_OBJ := $(BUILD)/benchmarks/simd-dot/bench.o
BENCH_BIN := $(BUILD)/benchmarks/simd-dot-bench
PACKAGE_ARCHIVE := $(BUILD)/packages/simd-dot-0.1.0.tar.gz
RELEASE_JSON := $(BUILD)/registry-data/simd-dot-0.1.0.json
EVIDENCE_JSON := $(BUILD)/registry-data/simd-dot-evidence.json
SIMD_DOT_PACKAGE_INPUTS := $(shell find examples/simd-dot -type f -print | sort)
STATIC := $(wildcard registry/static/*) $(wildcard registry/data/*)

.PHONY: all registry cli examples packages registry-data evidence-index run check smoke cli-smoke dev clean install-user perf-build perf perf-variants optimize-simd-dot contract-check conformance-build conformance

all: registry cli examples

registry: $(REGISTRY_BIN)
cli: $(CLI_BIN)
examples: $(EXAMPLE_OBJ)
packages: $(PACKAGE_ARCHIVE)
registry-data: $(RELEASE_JSON) $(EVIDENCE_JSON)
evidence-index: $(EVIDENCE_JSON)

$(BUILD)/registry $(BUILD)/cli $(BUILD)/generated $(BUILD)/examples/simd-dot $(BUILD)/packages $(BUILD)/registry-data $(BUILD)/benchmarks/simd-dot $(BUILD)/performance $(BUILD)/conformance/simd-dot:
	mkdir -p $@

$(PACKAGE_ARCHIVE): $(SIMD_DOT_PACKAGE_INPUTS) | $(BUILD)/packages
	tar --sort=name --mtime='UTC 1970-01-01' --owner=0 --group=0 --numeric-owner -czf $@ -C examples simd-dot

$(RELEASE_JSON): registry/data/simd-dot-release-0.1.0.json.in $(PACKAGE_ARCHIVE) scripts/render-release-json.sh | $(BUILD)/registry-data
	./scripts/render-release-json.sh $(PACKAGE_ARCHIVE) registry/data/simd-dot-release-0.1.0.json.in $@

$(EVIDENCE_JSON): $(PACKAGE_ARCHIVE) examples/simd-dot/performance.toml scripts/render-evidence-index.sh | $(BUILD)/registry-data
	./scripts/render-evidence-index.sh $(PACKAGE_ARCHIVE) examples/simd-dot/performance.toml $@


$(REGISTRY_OBJ): registry/src/server.S $(STATIC) $(PACKAGE_ARCHIVE) $(RELEASE_JSON) $(EVIDENCE_JSON) | $(BUILD)/registry
	$(AS) $(ASFLAGS) $< -o $@

$(REGISTRY_BIN): $(REGISTRY_OBJ)
	$(LD) $(LDFLAGS) $< -o $@

$(CLI_REGISTRY_INC): $(RELEASE_JSON) $(EVIDENCE_JSON) scripts/render-cli-registry-inc.sh | $(BUILD)/generated
	./scripts/render-cli-registry-inc.sh $(RELEASE_JSON) $(EVIDENCE_JSON) $@

$(CLI_OBJ): cli/src/main.S $(CLI_REGISTRY_INC) | $(BUILD)/cli
	$(AS) $(ASFLAGS) -I. $< -o $@

$(CLI_BIN): $(CLI_OBJ)
	$(LD) $(LDFLAGS) $< -o $@

$(EXAMPLE_OBJ): examples/simd-dot/src/dot.S | $(BUILD)/examples/simd-dot
	$(AS) $(ASFLAGS) $< -o $@

$(BENCH_OBJ): examples/simd-dot/bench/bench.S | $(BUILD)/benchmarks/simd-dot
	$(AS) $(ASFLAGS) $< -o $@

$(BENCH_BIN): $(BENCH_OBJ) $(EXAMPLE_OBJ)
	$(LD) $(LDFLAGS) $^ -o $@

perf-build: $(BENCH_BIN)

perf: $(BENCH_BIN) $(PACKAGE_ARCHIVE)
	./scripts/bench-simd-dot.sh

run: $(REGISTRY_BIN)
	./$(REGISTRY_BIN)

install-user: $(CLI_BIN)
	install -Dm755 $(CLI_BIN) $(HOME)/.local/bin/asmory
	@echo 'installed: $(HOME)/.local/bin/asmory'

dev: clean all check smoke cli-smoke

check: all contract-check
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
	@wc -c registry/static/* registry/data/* $(PACKAGE_ARCHIVE) $(RELEASE_JSON)
	@echo '== example symbols =='
	@nm $(EXAMPLE_OBJ)

smoke: $(REGISTRY_BIN)
	./scripts/smoke.sh

cli-smoke: $(CLI_BIN)
	./scripts/cli-smoke.sh

clean:
	rm -rf $(BUILD)

$(TUNED_OBJ): examples/simd-dot/src/dot_4acc.S | $(BUILD)/examples/simd-dot
	$(AS) $(ASFLAGS) $< -o $@

$(VARIANT_BENCH_OBJ): examples/simd-dot/bench/compare_variants.S | $(BUILD)/benchmarks/simd-dot
	$(AS) $(ASFLAGS) $< -o $@

$(VARIANT_BENCH_BIN): $(VARIANT_BENCH_OBJ) $(EXAMPLE_OBJ) $(TUNED_OBJ)
	$(LD) $(LDFLAGS) $^ -o $@

perf-variants: $(VARIANT_BENCH_BIN) $(PACKAGE_ARCHIVE)
	./scripts/bench-simd-dot-variants.sh
	./scripts/validate-performance-evidence.sh

optimize-simd-dot: conformance perf-variants
	./scripts/build-optimization-report.sh

$(CONFORMANCE_OBJ): examples/simd-dot/conformance/basic.S | $(BUILD)/conformance/simd-dot
	$(AS) $(ASFLAGS) $< -o $@

$(CONFORMANCE_GENERIC): $(CONFORMANCE_OBJ) $(EXAMPLE_OBJ)
	$(LD) $(LDFLAGS) --defsym=asmory_contract_target=simd_dot_f32 $^ -o $@

$(CONFORMANCE_4ACC): $(CONFORMANCE_OBJ) $(TUNED_OBJ)
	$(LD) $(LDFLAGS) --defsym=asmory_contract_target=simd_dot_f32_4acc $^ -o $@

contract-check:
	./scripts/check-contract-model.sh

conformance-build: $(CONFORMANCE_GENERIC) $(CONFORMANCE_4ACC)

conformance: conformance-build
	./scripts/conformance-simd-dot.sh
