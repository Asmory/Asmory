AS ?= as
LD ?= ld
ASFLAGS := --64
LDFLAGS := -z noexecstack
BUILD := build

REGISTRY_OBJ := $(BUILD)/registry/server.o
REGISTRY_BIN := $(BUILD)/asmory-registry
CLI_OBJ := $(BUILD)/cli/main.o
CLI_BIN := $(BUILD)/asmory
ACQUIRE_HELPER := $(BUILD)/asmory-acquire
CACHE_HELPER := $(BUILD)/asmory-cache
ADD_HELPER := $(BUILD)/asmory-add
MATERIALIZE_HELPER := $(BUILD)/asmory-materialize
STATE_HELPER := $(BUILD)/asmory-state
DELTA_HELPER := $(BUILD)/asmory-delta
VENDOR_HELPER := $(BUILD)/asmory-vendor
WORKSPACE_HELPER := $(BUILD)/asmory-workspace
FORK_HELPER := $(BUILD)/asmory-fork
PUBLISH_HELPER := $(BUILD)/asmory-publish
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
SEMANTICS_JSON := $(BUILD)/registry-data/simd-dot-semantics.json
CAPABILITY_JSON := $(BUILD)/registry-data/capability-math-dot-f32.json
PROFILE_CORE_JSON := $(BUILD)/registry-data/profile-simd-dot-core-v1.json
PROFILE_STRICT_JSON := $(BUILD)/registry-data/profile-simd-dot-strict-v1.json
SIMD_DOT_PACKAGE_INPUTS := $(shell find examples/simd-dot -type f -print | sort)
STATIC := $(wildcard registry/static/*) $(wildcard registry/data/*)

.PHONY: all registry cli examples packages registry-data evidence-index semantic-index semantic-check run check smoke cli-smoke workspace-smoke acquire-smoke cache-smoke add-smoke state-smoke delta-smoke vendor-smoke repo-workspace-smoke fork-publication-smoke dev clean install-user perf-build perf-power-status perf perf-variants optimize-simd-dot contract-check conformance-build conformance

all: registry cli examples

registry: $(REGISTRY_BIN)
cli: $(CLI_BIN) $(ACQUIRE_HELPER) $(CACHE_HELPER) $(ADD_HELPER) $(MATERIALIZE_HELPER) $(STATE_HELPER) $(DELTA_HELPER) $(VENDOR_HELPER) $(WORKSPACE_HELPER) $(FORK_HELPER) $(PUBLISH_HELPER)
examples: $(EXAMPLE_OBJ)
packages: $(PACKAGE_ARCHIVE)
registry-data: $(RELEASE_JSON) $(EVIDENCE_JSON) $(SEMANTICS_JSON) $(CAPABILITY_JSON) $(PROFILE_CORE_JSON) $(PROFILE_STRICT_JSON)
evidence-index: $(EVIDENCE_JSON)
semantic-index: $(SEMANTICS_JSON) $(CAPABILITY_JSON) $(PROFILE_CORE_JSON) $(PROFILE_STRICT_JSON)
semantic-check: semantic-index
	./scripts/check-semantic-matching.sh

$(BUILD)/registry $(BUILD)/cli $(BUILD)/generated $(BUILD)/examples/simd-dot $(BUILD)/packages $(BUILD)/registry-data $(BUILD)/benchmarks/simd-dot $(BUILD)/performance $(BUILD)/conformance/simd-dot:
	mkdir -p $@

$(PACKAGE_ARCHIVE): $(SIMD_DOT_PACKAGE_INPUTS) asmory.workspace.toml scripts/asmory-workspace.py | $(BUILD)/packages
	./scripts/asmory-workspace.py pack simd-dot $@

$(RELEASE_JSON): registry/data/simd-dot-release-0.1.0.json.in $(PACKAGE_ARCHIVE) scripts/render-release-json.sh | $(BUILD)/registry-data
	./scripts/render-release-json.sh $(PACKAGE_ARCHIVE) registry/data/simd-dot-release-0.1.0.json.in $@

$(EVIDENCE_JSON): $(PACKAGE_ARCHIVE) examples/simd-dot/performance.toml scripts/render-evidence-index.sh | $(BUILD)/registry-data
	./scripts/render-evidence-index.sh $(PACKAGE_ARCHIVE) examples/simd-dot/performance.toml $@

$(SEMANTICS_JSON) $(CAPABILITY_JSON) $(PROFILE_CORE_JSON) $(PROFILE_STRICT_JSON) &: examples/simd-dot/semantics.toml examples/simd-dot/profiles/core-v1.toml examples/simd-dot/profiles/strict-v1.toml examples/simd-dot/conformance/suite.toml scripts/semantic_model.py scripts/render-semantic-index.sh | $(BUILD)/registry-data
	./scripts/render-semantic-index.sh \
	  examples/simd-dot/semantics.toml \
	  examples/simd-dot/profiles/core-v1.toml \
	  examples/simd-dot/profiles/strict-v1.toml \
	  examples/simd-dot/conformance/suite.toml \
	  $(BUILD)/registry-data


$(REGISTRY_OBJ): registry/src/server.S $(STATIC) $(PACKAGE_ARCHIVE) $(RELEASE_JSON) $(EVIDENCE_JSON) $(SEMANTICS_JSON) $(CAPABILITY_JSON) $(PROFILE_CORE_JSON) $(PROFILE_STRICT_JSON) | $(BUILD)/registry
	$(AS) $(ASFLAGS) $< -o $@

$(REGISTRY_BIN): $(REGISTRY_OBJ)
	$(LD) $(LDFLAGS) $< -o $@

$(CLI_REGISTRY_INC): $(RELEASE_JSON) $(EVIDENCE_JSON) $(SEMANTICS_JSON) scripts/render-cli-registry-inc.sh | $(BUILD)/generated
	./scripts/render-cli-registry-inc.sh $(RELEASE_JSON) $(EVIDENCE_JSON) $(SEMANTICS_JSON) $@

$(CLI_OBJ): cli/src/main.S $(CLI_REGISTRY_INC) | $(BUILD)/cli
	$(AS) $(ASFLAGS) -I. $< -o $@

$(CLI_BIN): $(CLI_OBJ)
	$(LD) $(LDFLAGS) $< -o $@

$(ACQUIRE_HELPER): scripts/asmory-acquire.sh | $(BUILD)/cli
	cp $< $@
	chmod 0755 $@

$(CACHE_HELPER): scripts/asmory-cache.sh | $(BUILD)/cli
	cp $< $@
	chmod 0755 $@

$(ADD_HELPER): scripts/asmory-add.sh | $(BUILD)/cli
	cp $< $@
	chmod 0755 $@

$(MATERIALIZE_HELPER): scripts/asmory-materialize.py | $(BUILD)/cli
	cp $< $@
	chmod 0755 $@

$(STATE_HELPER): scripts/asmory-state.py | $(BUILD)/cli
	cp $< $@
	chmod 0755 $@

$(DELTA_HELPER): scripts/asmory-delta.py | $(BUILD)/cli
	cp $< $@
	chmod 0755 $@

$(VENDOR_HELPER): scripts/asmory-vendor.py | $(BUILD)/cli
	cp $< $@
	chmod 0755 $@

$(WORKSPACE_HELPER): scripts/asmory-workspace.py | $(BUILD)/cli
	cp $< $@
	chmod 0755 $@

$(FORK_HELPER): scripts/asmory-fork.py | $(BUILD)/cli
	cp $< $@
	chmod 0755 $@

$(PUBLISH_HELPER): scripts/asmory-publish.py | $(BUILD)/cli
	cp $< $@
	chmod 0755 $@

$(EXAMPLE_OBJ): examples/simd-dot/src/dot.S | $(BUILD)/examples/simd-dot
	$(AS) $(ASFLAGS) $< -o $@

$(BENCH_OBJ): examples/simd-dot/bench/bench.S | $(BUILD)/benchmarks/simd-dot
	$(AS) $(ASFLAGS) $< -o $@

$(BENCH_BIN): $(BENCH_OBJ) $(EXAMPLE_OBJ)
	$(LD) $(LDFLAGS) $^ -o $@

perf-build: $(BENCH_BIN)

perf-power-status:
	./scripts/performance-power-session.sh status

perf: $(BENCH_BIN) $(PACKAGE_ARCHIVE)
	./scripts/bench-simd-dot.sh

run: $(REGISTRY_BIN)
	./$(REGISTRY_BIN)

install-user: $(CLI_BIN) $(ACQUIRE_HELPER) $(CACHE_HELPER) $(ADD_HELPER) $(MATERIALIZE_HELPER) $(STATE_HELPER) $(DELTA_HELPER) $(VENDOR_HELPER) $(WORKSPACE_HELPER) $(FORK_HELPER) $(PUBLISH_HELPER)
	install -Dm755 $(CLI_BIN) $(HOME)/.local/bin/asmory
	install -Dm755 $(ACQUIRE_HELPER) $(HOME)/.local/bin/asmory-acquire
	install -Dm755 $(CACHE_HELPER) $(HOME)/.local/bin/asmory-cache
	install -Dm755 $(ADD_HELPER) $(HOME)/.local/bin/asmory-add
	install -Dm755 $(MATERIALIZE_HELPER) $(HOME)/.local/bin/asmory-materialize
	install -Dm755 $(STATE_HELPER) $(HOME)/.local/bin/asmory-state
	install -Dm755 $(DELTA_HELPER) $(HOME)/.local/bin/asmory-delta
	install -Dm755 $(VENDOR_HELPER) $(HOME)/.local/bin/asmory-vendor
	install -Dm755 $(WORKSPACE_HELPER) $(HOME)/.local/bin/asmory-workspace
	install -Dm755 $(FORK_HELPER) $(HOME)/.local/bin/asmory-fork
	install -Dm755 $(PUBLISH_HELPER) $(HOME)/.local/bin/asmory-publish
	@echo 'installed: asmory + acquisition/cache/add/materialize/state/delta/vendor/workspace/fork/publish helpers'

dev: clean all check smoke cli-smoke

check: all contract-check semantic-check workspace-smoke repo-workspace-smoke
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

workspace-smoke: $(CLI_BIN)
	./scripts/workspace-smoke.sh

acquire-smoke: registry cli packages
	./scripts/acquire-smoke.sh

cache-smoke: registry cli packages
	./scripts/cache-smoke.sh

add-smoke: registry cli packages
	./scripts/add-smoke.sh

state-smoke: registry cli packages
	./scripts/state-smoke.sh

delta-smoke: registry cli packages
	./scripts/delta-smoke.sh

vendor-smoke: registry cli packages
	./scripts/vendor-smoke.sh

repo-workspace-smoke: cli packages
	./scripts/repo-workspace-smoke.sh

fork-publication-smoke: registry cli packages
	./scripts/fork-publication-smoke.sh

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
