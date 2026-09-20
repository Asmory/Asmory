.section .rodata
cmd_init:       .asciz "init"
cmd_acquire:    .asciz "acquire"
cmd_cache:      .asciz "cache"
cmd_add:        .asciz "add"
cmd_status:     .asciz "status"
cmd_restore:    .asciz "restore"
cmd_patch:      .asciz "patch"
cmd_reapply:    .asciz "reapply"
cmd_vendor:     .asciz "vendor"
cmd_target:     .asciz "target"
cmd_info:       .asciz "info"
cmd_search:     .asciz "search"
cmd_help:       .asciz "help"
cmd_version:    .asciz "version"
cmd_versions:   .asciz "versions"
cmd_resolve:    .asciz "resolve"
cmd_explain:    .asciz "explain"
cmd_audit:      .asciz "audit"
cmd_evidence:   .asciz "evidence"
cmd_semantics:  .asciz "semantics"
cmd_match:      .asciz "match"
cmd_vflag:      .asciz "--version"
cmd_hflag:      .asciz "--help"
pkg_simd_dot:   .asciz "simd-dot"

.include "build/generated/cli_registry.inc"

help_msg:
.asciz "Asmory 0.1.0-dev\n\nUsage:\n  asmory init\n  asmory acquire <package> <output>\n  asmory cache <package>\n  asmory add <package>\n  asmory status\n  asmory restore <package>\n  asmory patch <package>\n  asmory reapply <package>\n  asmory vendor <package>\n  asmory target\n  asmory search [query]\n  asmory info <package>\n  asmory versions <package>\n  asmory resolve <package>\n  asmory explain <package>\n  asmory audit <package>\n  asmory evidence <package>\n  asmory semantics <package>\n  asmory match <package> <profile>\n  asmory --version\n  asmory help\n\nAssembly packages with explicit ISA/ABI contracts.\n"
version_msg: .asciz "asmory 0.1.0-dev\n"
unknown_msg: .asciz "asmory: unknown command (try 'asmory help')\n"
missing_pkg_msg: .asciz "asmory info: package name required\n"
missing_acquire_msg:.asciz "asmory acquire: package and output path required\n"
acquire_workspace_msg:.asciz "asmory acquire: no initialized workspace; run 'asmory init' first\n"
acquire_backend_msg:.asciz "asmory acquire: bootstrap transport backend unavailable\n"
acquire_incompat_msg:.asciz "asmory acquire: no compatible resolved Variant for this host\n"
missing_cache_msg:  .asciz "asmory cache: package name required\n"
cache_backend_msg:  .asciz "asmory cache: bootstrap cache backend unavailable\n"
cache_shell_cmd:    .asciz "exec asmory-cache \"$@\""
cache_argv0:        .asciz "asmory-cache"
missing_add_msg:    .asciz "asmory add: package name required\n"
add_workspace_msg:  .asciz "asmory add: no initialized workspace; run 'asmory init' first\n"
add_backend_msg:    .asciz "asmory add: bootstrap installer backend unavailable\n"
add_incompat_msg:   .asciz "asmory add: no compatible resolved Variant for this host\n"
add_shell_cmd:      .asciz "exec asmory-add \"$@\""
add_argv0:          .asciz "asmory-add"
status_backend_msg: .asciz "asmory status: bootstrap state backend unavailable\n"
restore_backend_msg:.asciz "asmory restore: bootstrap state backend unavailable\n"
missing_restore_msg:.asciz "asmory restore: package name required\n"
status_shell_cmd:   .asciz "exec asmory-state status \"$@\""
restore_shell_cmd:  .asciz "exec asmory-state restore \"$@\""
state_argv0:        .asciz "asmory-state"
missing_patch_msg:  .asciz "asmory patch: package name required\n"
patch_backend_msg:  .asciz "asmory patch: bootstrap delta backend unavailable\n"
missing_reapply_msg:.asciz "asmory reapply: package name required\n"
reapply_backend_msg:.asciz "asmory reapply: bootstrap delta backend unavailable\n"
patch_shell_cmd:    .asciz "exec asmory-delta capture \"$@\""
reapply_shell_cmd:  .asciz "exec asmory-delta reapply \"$@\""
delta_argv0:        .asciz "asmory-delta"
missing_vendor_msg: .asciz "asmory vendor: package name required\n"
vendor_backend_msg: .asciz "asmory vendor: bootstrap vendor backend unavailable\n"
vendor_shell_cmd:   .asciz "exec asmory-vendor \"$@\""
vendor_argv0:       .asciz "asmory-vendor"
sh_path:          .asciz "/bin/sh"
sh_name:          .asciz "sh"
sh_c:             .asciz "-c"
acquire_shell_cmd:.asciz "exec asmory-acquire \"$@\""
acquire_argv0:    .asciz "asmory-acquire"
missing_versions_msg: .asciz "asmory versions: package name required\n"
not_found_msg: .asciz "asmory: package not found in bootstrap index\n"

missing_resolve_msg: .asciz "asmory resolve: package name required\n"
missing_explain_msg: .asciz "asmory explain: package name required\n"
missing_audit_msg:   .asciz "asmory audit: package name required\n"
missing_evidence_msg:.asciz "asmory evidence: package name required\n"
missing_semantics_msg:.asciz "asmory semantics: package name required\n"
missing_match_msg:    .asciz "asmory match: package and profile required\n"
unknown_profile_msg:  .asciz "asmory match: profile not in bootstrap semantic index\n"

init_manifest_path: .asciz "asm.toml"
init_lock_path:     .asciz "asm.lock"
init_local_dir:     .asciz ".asmory"
init_deps_dir:      .asciz ".asmory/deps"
init_ignore_path:   .asciz ".asmory/.gitignore"

init_ok_msg:
.asciz "Initialized Asmory workspace\n\n  manifest      asm.toml\n  lockfile      asm.lock\n  local deps    .asmory/deps/\n  dependencies  0\n"

init_already_msg:
.asciz "asmory init: workspace already initialized (asm.toml + asm.lock)\n"

init_partial_msg:
.asciz "asmory init: refusing to overwrite partial workspace metadata; expected both asm.toml and asm.lock\n"

init_fail_msg:
.asciz "asmory init: failed to create workspace files\n"

init_manifest_body:
.ascii "# Asmory project manifest.\n"
.ascii "# User intent lives here; exact resolution lives in asm.lock.\n"
.ascii "schema = 1\n\n"
.ascii "[workspace]\n"
.ascii "resolver_policy = \"asmory-v1\"\n\n"
.ascii "[dependencies]\n"
init_manifest_body_end:

init_lock_body:
.ascii "# Generated by Asmory. Do not edit by hand.\n"
.ascii "# Exact resolved reality will be recorded here.\n"
.ascii "schema = 1\n"
.ascii "resolver_policy = \"asmory-v1\"\n"
.ascii "dependency_count = 0\n"
init_lock_body_end:

init_ignore_body:
.ascii "# Exact dependency materializations are reconstructed from asm.lock.\n"
.ascii "deps/\n"
.ascii ".staging/\n"
.ascii ".restore/\n"
.ascii ".delta/\n"
.ascii ".vendor/\n"
.ascii "workspace.lock\n"
init_ignore_body_end:

search_msg:
.asciz "bootstrap index\n\nNAME       VERSION  TARGET                         DESCRIPTION\nsimd-dot   0.1.0    x86_64 / AVX2 + FMA / SysV64  AVX2/FMA f32 dot product\n"

versions_msg:
.asciz "simd-dot releases\n\nVERSION  PUBLISHED   VARIANTS  STATUS\n0.1.0    2026-09-20  2         active\n"

info_msg:
.asciz "simd-dot 0.1.0\n\nPackage\n  license      MIT\n  status       example\n\nTarget\n  arch         x86_64\n  os           linux\n  object       elf64\n  abi          sysv64\n  baseline     x86-64-v3\n  requires     avx2, fma\n\nToolchain\n  assembler    gas >= 2.40\n\nExports\n  simd_dot_f32\n"

res_title:          .asciz "Resolved dependency\n\n"
res_explain_title:  .asciz "Resolution explanation\n\n"
res_audit_title:    .asciz "Artifact and review status\n\n"
semantic_title:     .asciz "Semantic identity\n\n"
semantic_match_title:.asciz "Semantic match\n\n"
semantic_lab_fp:     .asciz "  fingerprint  "
semantic_lab_iface:  .asciz "  interface    "
semantic_lab_align:  .asciz "  requires alignment  "
semantic_lab_abs:    .asciz "  abs error <= "
semantic_lab_rel:    .asciz "  rel error <= "
semantic_lab_det:    .asciz "  determinism  "
semantic_lab_facets: .asciz "  facets       source of truth\n"
semantic_lab_result: .asciz "  result       "
semantic_lab_reason: .asciz "  reason       "
semantic_lab_request:.asciz "  request      "
semantic_lab_endpoint:.asciz "  endpoint     "
perf_title:         .asciz "Performance Evidence\n\n"
perf_head:          .asciz "Performance\n"
perf_lab_benchmark: .asciz "  benchmark    "
perf_lab_contract:  .asciz "  contract sha "
perf_lab_status:    .asciz "  status       "
perf_lab_accepted:  .asciz "  accepted     "
perf_lab_ranking:   .asciz "  ranking      "
perf_lab_endpoint:  .asciz "  endpoint     "
res_sem_head:       .asciz "Semantics\n"
res_machine_head:   .asciz "\nMachine\n"
res_select_head:    .asciz "\nSelection\n"
res_user_head:      .asciz "User intent\n"
res_defaults_head:  .asciz "\nExpanded defaults\n"
res_candidates_head:.asciz "\nCandidates\n"
res_security_head:  .asciz "\nSecurity\n"
res_artifact_head:  .asciz "Artifact\n"

res_lab_package:    .asciz "  package      "
res_lab_release:    .asciz "  release      "
res_lab_capability: .asciz "  capability   "
res_lab_profile:    .asciz "  profile      "
res_lab_provider:   .asciz "  provider     "
res_lab_requires:   .asciz "  requires     "
res_lab_result:     .asciz "  result       "
res_lab_variant:    .asciz "  variant      "
res_lab_alternate:  .asciz "  alternate    "
res_lab_artifact:   .asciz "  artifact     "
res_lab_filename:   .asciz "  filename     "
res_lab_sha256:     .asciz "  sha256       "
res_lab_policy:     .asciz "  policy       "
res_lab_dependency: .asciz "  dependency   "
res_lab_version:    .asciz "  version      "
res_lab_review:     .asciz "  review       "
res_lab_anchor:     .asciz "  anchor       "
res_lab_safety:     .asciz "  registry     "
res_lab_advisories: .asciz "  advisories   "
res_lab_integrity:  .asciz "  local integrity  "

res_compatible:     .asciz "compatible"
res_incompatible:   .asciz "incompatible"
res_default_version:.asciz "default -> 0.1.0"
res_not_evaluated:  .asciz "not evaluated"
res_candidate_note: .asciz "  candidates   stable + experimental compatible set\n"
res_final_none:     .asciz "  final        none\n"
res_final_prefix:   .asciz "  final        "
res_fail_msg:       .asciz "asmory resolve: no compatible Variant; host lacks AVX2/FMA required by simd-dot\n"
res_audit_note:     .asciz "\nNote\n  Exact Artifact != Safe Artifact\n  Digest verification proves identity, not benign behavior.\n"

target_head: .asciz "Asmory host target\n\n"
arch_line:   .asciz "Target\n  arch         x86_64\n  os           linux\n  object       elf64\n  abi          sysv64\n"
vendor_pre:  .asciz "  cpu_vendor   "
newline:     .asciz "\n"
isa_head:    .asciz "\nISA\n  baseline     "
feat_head:   .asciz "\n  features\n"

baseline_v1: .asciz "x86-64-v1\n"
baseline_v2: .asciz "x86-64-v2\n"
baseline_v3: .asciz "x86-64-v3\n"
baseline_v4: .asciz "x86-64-v4\n"

lab_sse2:    .asciz "    sse2       "
lab_sse42:   .asciz "    sse4.2     "
lab_avx:     .asciz "    avx        "
lab_avx2:    .asciz "    avx2       "
lab_fma:     .asciz "    fma        "
lab_bmi1:    .asciz "    bmi1       "
lab_bmi2:    .asciz "    bmi2       "
lab_avx512f: .asciz "    avx512f    "
lab_avx512bw:.asciz "    avx512bw   "
lab_avx512vl:.asciz "    avx512vl   "
yes_msg:     .asciz "yes\n"
no_msg:      .asciz "no\n"

.section .bss
.align 8
vendor_buf:  .skip 13
leaf1_ecx:   .long 0
leaf1_edx:   .long 0
leaf7_ebx:   .long 0
ext1_ecx:    .long 0
xcr0_val:    .quad 0
avx_ok:      .byte 0
avx512_ok:   .byte 0
baseline_ptr:.quad 0
envp_ptr:    .quad 0
.align 8
acquire_exec_argv: .skip 128

.section .text
.global _start
.type _start,@function
_start:
    mov (%rsp), %r12
    lea 16(%rsp,%r12,8), %rax
    mov %rax, envp_ptr(%rip)
    cmp $2, %r12
    jb .show_help
    mov 16(%rsp), %r13

    mov %r13, %rdi
    lea cmd_init(%rip), %rsi
    call streq
    test %eax, %eax
    jnz .do_init

    mov %r13, %rdi
    lea cmd_acquire(%rip), %rsi
    call streq
    test %eax, %eax
    jnz .do_acquire

    mov %r13, %rdi
    lea cmd_cache(%rip), %rsi
    call streq
    test %eax, %eax
    jnz .do_cache

    mov %r13, %rdi
    lea cmd_add(%rip), %rsi
    call streq
    test %eax, %eax
    jnz .do_add

    mov %r13, %rdi
    lea cmd_status(%rip), %rsi
    call streq
    test %eax, %eax
    jnz .do_status

    mov %r13, %rdi
    lea cmd_restore(%rip), %rsi
    call streq
    test %eax, %eax
    jnz .do_restore

    mov %r13, %rdi
    lea cmd_patch(%rip), %rsi
    call streq
    test %eax, %eax
    jnz .do_patch

    mov %r13, %rdi
    lea cmd_reapply(%rip), %rsi
    call streq
    test %eax, %eax
    jnz .do_reapply

    mov %r13, %rdi
    lea cmd_vendor(%rip), %rsi
    call streq
    test %eax, %eax
    jnz .do_vendor

    mov %r13, %rdi
    lea cmd_target(%rip), %rsi
    call streq
    test %eax, %eax
    jnz .do_target

    mov %r13, %rdi
    lea cmd_versions(%rip), %rsi
    call streq
    test %eax, %eax
    jnz .do_versions

    mov %r13, %rdi
    lea cmd_resolve(%rip), %rsi
    call streq
    test %eax, %eax
    jnz .do_resolve

    mov %r13, %rdi
    lea cmd_explain(%rip), %rsi
    call streq
    test %eax, %eax
    jnz .do_explain

    mov %r13, %rdi
    lea cmd_audit(%rip), %rsi
    call streq
    test %eax, %eax
    jnz .do_audit

    mov %r13, %rdi
    lea cmd_evidence(%rip), %rsi
    call streq
    test %eax, %eax
    jnz .do_evidence

    mov %r13, %rdi
    lea cmd_semantics(%rip), %rsi
    call streq
    test %eax, %eax
    jnz .do_semantics

    mov %r13, %rdi
    lea cmd_match(%rip), %rsi
    call streq
    test %eax, %eax
    jnz .do_match

    mov %r13, %rdi
    lea cmd_info(%rip), %rsi
    call streq
    test %eax, %eax
    jnz .do_info

    mov %r13, %rdi
    lea cmd_search(%rip), %rsi
    call streq
    test %eax, %eax
    jnz .do_search

    mov %r13, %rdi
    lea cmd_help(%rip), %rsi
    call streq
    test %eax, %eax
    jnz .show_help

    mov %r13, %rdi
    lea cmd_hflag(%rip), %rsi
    call streq
    test %eax, %eax
    jnz .show_help

    mov %r13, %rdi
    lea cmd_version(%rip), %rsi
    call streq
    test %eax, %eax
    jnz .show_version

    mov %r13, %rdi
    lea cmd_vflag(%rip), %rsi
    call streq
    test %eax, %eax
    jnz .show_version

    lea unknown_msg(%rip), %rdi
    call print_cstr
    mov $2, %edi
    jmp exit_process

.show_help:
    lea help_msg(%rip), %rdi
    call print_cstr
    xor %edi, %edi
    jmp exit_process

.show_version:
    lea version_msg(%rip), %rdi
    call print_cstr
    xor %edi, %edi
    jmp exit_process

.do_init:
    lea init_manifest_path(%rip), %rdi
    call path_exists
    mov %eax, %r14d

    lea init_lock_path(%rip), %rdi
    call path_exists
    mov %eax, %r15d

    mov %r14d, %eax
    and %r15d, %eax
    jnz .init_already

    cmp %r14d, %r15d
    jne .init_partial

    lea init_local_dir(%rip), %rdi
    call mkdir_if_missing
    test %rax, %rax
    js .init_fail

    lea init_deps_dir(%rip), %rdi
    call mkdir_if_missing
    test %rax, %rax
    js .init_fail

    lea init_ignore_path(%rip), %rdi
    lea init_ignore_body(%rip), %rsi
    mov $(init_ignore_body_end-init_ignore_body), %rdx
    call create_text_exclusive
    test %rax, %rax
    jz .init_create_manifest
    cmp $-17, %rax
    jne .init_fail

.init_create_manifest:
    lea init_manifest_path(%rip), %rdi
    lea init_manifest_body(%rip), %rsi
    mov $(init_manifest_body_end-init_manifest_body), %rdx
    call create_text_exclusive
    test %rax, %rax
    js .init_fail

    lea init_lock_path(%rip), %rdi
    lea init_lock_body(%rip), %rsi
    mov $(init_lock_body_end-init_lock_body), %rdx
    call create_text_exclusive
    test %rax, %rax
    jns .init_success

    lea init_manifest_path(%rip), %rdi
    mov $87, %eax
    syscall
    jmp .init_fail

.init_success:
    lea init_ok_msg(%rip), %rdi
    call print_cstr
    xor %edi, %edi
    jmp exit_process

.init_already:
    lea init_already_msg(%rip), %rdi
    call print_cstr
    xor %edi, %edi
    jmp exit_process

.init_partial:
    lea init_partial_msg(%rip), %rdi
    call print_cstr
    mov $6, %edi
    jmp exit_process

.init_fail:
    lea init_fail_msg(%rip), %rdi
    call print_cstr
    mov $7, %edi
    jmp exit_process

.do_acquire:
    cmp $4, %r12
    jb .missing_acquire

    lea init_manifest_path(%rip), %rdi
    call path_exists
    test %eax, %eax
    jz .acquire_no_workspace

    lea init_lock_path(%rip), %rdi
    call path_exists
    test %eax, %eax
    jz .acquire_no_workspace

    mov 24(%rsp), %rdi
    lea registry_pkg_name(%rip), %rsi
    call streq
    test %eax, %eax
    jz .pkg_not_found

    call check_bootstrap_variant
    test %eax, %eax
    jz .acquire_incompatible

    lea acquire_exec_argv(%rip), %r10

    lea sh_name(%rip), %rax
    mov %rax, 0(%r10)
    lea sh_c(%rip), %rax
    mov %rax, 8(%r10)
    lea acquire_shell_cmd(%rip), %rax
    mov %rax, 16(%r10)
    lea acquire_argv0(%rip), %rax
    mov %rax, 24(%r10)
    lea registry_pkg_name(%rip), %rax
    mov %rax, 32(%r10)
    lea registry_version(%rip), %rax
    mov %rax, 40(%r10)
    lea registry_artifact_sha256(%rip), %rax
    mov %rax, 48(%r10)
    mov 32(%rsp), %rax
    mov %rax, 56(%r10)
    movq $0, 64(%r10)

    lea sh_path(%rip), %rdi
    mov %r10, %rsi
    mov envp_ptr(%rip), %rdx
    mov $59, %eax
    syscall

    lea acquire_backend_msg(%rip), %rdi
    call print_cstr
    mov $8, %edi
    jmp exit_process

.missing_acquire:
    lea missing_acquire_msg(%rip), %rdi
    call print_cstr
    mov $2, %edi
    jmp exit_process

.acquire_no_workspace:
    lea acquire_workspace_msg(%rip), %rdi
    call print_cstr
    mov $9, %edi
    jmp exit_process

.acquire_incompatible:
    lea acquire_incompat_msg(%rip), %rdi
    call print_cstr
    mov $4, %edi
    jmp exit_process

.do_cache:
    cmp $3, %r12
    jb .missing_cache

    mov 24(%rsp), %rdi
    lea registry_pkg_name(%rip), %rsi
    call streq
    test %eax, %eax
    jz .pkg_not_found

    # Cache is global infrastructure. It does not imply project ownership
    # and therefore intentionally does not require asm.toml / asm.lock.
    lea acquire_exec_argv(%rip), %r10

    lea sh_name(%rip), %rax
    mov %rax, 0(%r10)
    lea sh_c(%rip), %rax
    mov %rax, 8(%r10)
    lea cache_shell_cmd(%rip), %rax
    mov %rax, 16(%r10)
    lea cache_argv0(%rip), %rax
    mov %rax, 24(%r10)
    lea registry_pkg_name(%rip), %rax
    mov %rax, 32(%r10)
    lea registry_version(%rip), %rax
    mov %rax, 40(%r10)
    lea registry_artifact_sha256(%rip), %rax
    mov %rax, 48(%r10)
    movq $0, 56(%r10)

    lea sh_path(%rip), %rdi
    mov %r10, %rsi
    mov envp_ptr(%rip), %rdx
    mov $59, %eax
    syscall

    lea cache_backend_msg(%rip), %rdi
    call print_cstr
    mov $8, %edi
    jmp exit_process

.missing_cache:
    lea missing_cache_msg(%rip), %rdi
    call print_cstr
    mov $2, %edi
    jmp exit_process

.do_add:
    cmp $3, %r12
    jb .missing_add

    lea init_manifest_path(%rip), %rdi
    call path_exists
    test %eax, %eax
    jz .add_no_workspace

    lea init_lock_path(%rip), %rdi
    call path_exists
    test %eax, %eax
    jz .add_no_workspace

    mov 24(%rsp), %rdi
    lea registry_pkg_name(%rip), %rsi
    call streq
    test %eax, %eax
    jz .pkg_not_found

    call check_bootstrap_variant
    test %eax, %eax
    jz .add_incompatible

    lea acquire_exec_argv(%rip), %r10

    lea sh_name(%rip), %rax
    mov %rax, 0(%r10)
    lea sh_c(%rip), %rax
    mov %rax, 8(%r10)
    lea add_shell_cmd(%rip), %rax
    mov %rax, 16(%r10)
    lea add_argv0(%rip), %rax
    mov %rax, 24(%r10)

    lea registry_pkg_name(%rip), %rax
    mov %rax, 32(%r10)
    lea registry_version(%rip), %rax
    mov %rax, 40(%r10)
    lea registry_capability(%rip), %rax
    mov %rax, 48(%r10)
    lea registry_semantic_fingerprint(%rip), %rax
    mov %rax, 56(%r10)
    lea registry_profile(%rip), %rax
    mov %rax, 64(%r10)
    lea registry_provider(%rip), %rax
    mov %rax, 72(%r10)
    lea registry_variant_primary(%rip), %rax
    mov %rax, 80(%r10)
    lea registry_artifact_sha256(%rip), %rax
    mov %rax, 88(%r10)
    lea registry_review_state(%rip), %rax
    mov %rax, 96(%r10)
    lea registry_safety_state(%rip), %rax
    mov %rax, 104(%r10)
    movq $0, 112(%r10)

    lea sh_path(%rip), %rdi
    mov %r10, %rsi
    mov envp_ptr(%rip), %rdx
    mov $59, %eax
    syscall

    lea add_backend_msg(%rip), %rdi
    call print_cstr
    mov $8, %edi
    jmp exit_process

.missing_add:
    lea missing_add_msg(%rip), %rdi
    call print_cstr
    mov $2, %edi
    jmp exit_process

.add_no_workspace:
    lea add_workspace_msg(%rip), %rdi
    call print_cstr
    mov $9, %edi
    jmp exit_process

.add_incompatible:
    lea add_incompat_msg(%rip), %rdi
    call print_cstr
    mov $4, %edi
    jmp exit_process

.do_status:
    lea acquire_exec_argv(%rip), %r10

    lea sh_name(%rip), %rax
    mov %rax, 0(%r10)
    lea sh_c(%rip), %rax
    mov %rax, 8(%r10)
    lea status_shell_cmd(%rip), %rax
    mov %rax, 16(%r10)
    lea state_argv0(%rip), %rax
    mov %rax, 24(%r10)
    movq $0, 32(%r10)

    lea sh_path(%rip), %rdi
    mov %r10, %rsi
    mov envp_ptr(%rip), %rdx
    mov $59, %eax
    syscall

    lea status_backend_msg(%rip), %rdi
    call print_cstr
    mov $8, %edi
    jmp exit_process

.do_restore:
    cmp $3, %r12
    jb .missing_restore

    lea acquire_exec_argv(%rip), %r10

    lea sh_name(%rip), %rax
    mov %rax, 0(%r10)
    lea sh_c(%rip), %rax
    mov %rax, 8(%r10)
    lea restore_shell_cmd(%rip), %rax
    mov %rax, 16(%r10)
    lea state_argv0(%rip), %rax
    mov %rax, 24(%r10)
    mov 24(%rsp), %rax
    mov %rax, 32(%r10)
    movq $0, 40(%r10)

    lea sh_path(%rip), %rdi
    mov %r10, %rsi
    mov envp_ptr(%rip), %rdx
    mov $59, %eax
    syscall

    lea restore_backend_msg(%rip), %rdi
    call print_cstr
    mov $8, %edi
    jmp exit_process

.missing_restore:
    lea missing_restore_msg(%rip), %rdi
    call print_cstr
    mov $2, %edi
    jmp exit_process

.do_patch:
    cmp $3, %r12
    jb .missing_patch

    lea acquire_exec_argv(%rip), %r10
    lea sh_name(%rip), %rax
    mov %rax, 0(%r10)
    lea sh_c(%rip), %rax
    mov %rax, 8(%r10)
    lea patch_shell_cmd(%rip), %rax
    mov %rax, 16(%r10)
    lea delta_argv0(%rip), %rax
    mov %rax, 24(%r10)
    mov 24(%rsp), %rax
    mov %rax, 32(%r10)
    movq $0, 40(%r10)

    lea sh_path(%rip), %rdi
    mov %r10, %rsi
    mov envp_ptr(%rip), %rdx
    mov $59, %eax
    syscall

    lea patch_backend_msg(%rip), %rdi
    call print_cstr
    mov $8, %edi
    jmp exit_process

.missing_patch:
    lea missing_patch_msg(%rip), %rdi
    call print_cstr
    mov $2, %edi
    jmp exit_process

.do_reapply:
    cmp $3, %r12
    jb .missing_reapply

    lea acquire_exec_argv(%rip), %r10
    lea sh_name(%rip), %rax
    mov %rax, 0(%r10)
    lea sh_c(%rip), %rax
    mov %rax, 8(%r10)
    lea reapply_shell_cmd(%rip), %rax
    mov %rax, 16(%r10)
    lea delta_argv0(%rip), %rax
    mov %rax, 24(%r10)
    mov 24(%rsp), %rax
    mov %rax, 32(%r10)
    movq $0, 40(%r10)

    lea sh_path(%rip), %rdi
    mov %r10, %rsi
    mov envp_ptr(%rip), %rdx
    mov $59, %eax
    syscall

    lea reapply_backend_msg(%rip), %rdi
    call print_cstr
    mov $8, %edi
    jmp exit_process

.missing_reapply:
    lea missing_reapply_msg(%rip), %rdi
    call print_cstr
    mov $2, %edi
    jmp exit_process

.do_vendor:
    cmp $3, %r12
    jb .missing_vendor

    lea acquire_exec_argv(%rip), %r10
    lea sh_name(%rip), %rax
    mov %rax, 0(%r10)
    lea sh_c(%rip), %rax
    mov %rax, 8(%r10)
    lea vendor_shell_cmd(%rip), %rax
    mov %rax, 16(%r10)
    lea vendor_argv0(%rip), %rax
    mov %rax, 24(%r10)
    mov 24(%rsp), %rax
    mov %rax, 32(%r10)
    movq $0, 40(%r10)

    lea sh_path(%rip), %rdi
    mov %r10, %rsi
    mov envp_ptr(%rip), %rdx
    mov $59, %eax
    syscall

    lea vendor_backend_msg(%rip), %rdi
    call print_cstr
    mov $8, %edi
    jmp exit_process

.missing_vendor:
    lea missing_vendor_msg(%rip), %rdi
    call print_cstr
    mov $2, %edi
    jmp exit_process

.do_search:
    lea search_msg(%rip), %rdi
    call print_cstr
    xor %edi, %edi
    jmp exit_process

.do_versions:
    cmp $3, %r12
    jb .missing_versions
    mov 24(%rsp), %rdi
    lea pkg_simd_dot(%rip), %rsi
    call streq
    test %eax, %eax
    jz .pkg_not_found
    lea versions_msg(%rip), %rdi
    call print_cstr
    xor %edi, %edi
    jmp exit_process
.missing_versions:
    lea missing_versions_msg(%rip), %rdi
    call print_cstr
    mov $2, %edi
    jmp exit_process

.do_info:
    cmp $3, %r12
    jb .missing_pkg
    mov 24(%rsp), %rdi
    lea pkg_simd_dot(%rip), %rsi
    call streq
    test %eax, %eax
    jz .pkg_not_found
    lea info_msg(%rip), %rdi
    call print_cstr
    xor %edi, %edi
    jmp exit_process
.missing_pkg:
    lea missing_pkg_msg(%rip), %rdi
    call print_cstr
    mov $2, %edi
    jmp exit_process
.pkg_not_found:
    lea not_found_msg(%rip), %rdi
    call print_cstr
    mov $3, %edi
    jmp exit_process

.do_resolve:
    cmp $3, %r12
    jb .missing_resolve
    mov 24(%rsp), %rdi
    lea registry_pkg_name(%rip), %rsi
    call streq
    test %eax, %eax
    jz .pkg_not_found

    call check_bootstrap_variant
    test %eax, %eax
    jz .resolve_incompatible

    lea res_title(%rip), %rdi
    call print_cstr

    lea res_lab_package(%rip), %rdi
    lea registry_pkg_name(%rip), %rsi
    call print_kv
    lea res_lab_release(%rip), %rdi
    lea registry_version(%rip), %rsi
    call print_kv

    lea res_sem_head(%rip), %rdi
    call print_cstr
    lea res_lab_capability(%rip), %rdi
    lea registry_capability(%rip), %rsi
    call print_kv
    lea res_lab_profile(%rip), %rdi
    lea registry_profile(%rip), %rsi
    call print_kv
    lea res_lab_provider(%rip), %rdi
    lea registry_provider(%rip), %rsi
    call print_kv

    lea res_machine_head(%rip), %rdi
    call print_cstr
    lea res_lab_requires(%rip), %rdi
    lea registry_required_isa(%rip), %rsi
    call print_kv
    lea res_lab_result(%rip), %rdi
    lea res_compatible(%rip), %rsi
    call print_kv

    lea res_select_head(%rip), %rdi
    call print_cstr
    lea res_lab_variant(%rip), %rdi
    lea registry_variant_primary(%rip), %rsi
    call print_kv
    lea res_lab_artifact(%rip), %rdi
    lea registry_artifact_kind(%rip), %rsi
    call print_kv
    lea res_lab_filename(%rip), %rdi
    lea registry_artifact_filename(%rip), %rsi
    call print_kv
    lea res_lab_sha256(%rip), %rdi
    lea registry_artifact_sha256(%rip), %rsi
    call print_kv
    lea res_lab_policy(%rip), %rdi
    lea registry_artifact_policy(%rip), %rsi
    call print_kv
    lea res_lab_dependency(%rip), %rdi
    lea registry_dependency_kind(%rip), %rsi
    call print_kv

    xor %edi, %edi
    jmp exit_process

.resolve_incompatible:
    lea res_fail_msg(%rip), %rdi
    call print_cstr
    mov $4, %edi
    jmp exit_process

.missing_resolve:
    lea missing_resolve_msg(%rip), %rdi
    call print_cstr
    mov $2, %edi
    jmp exit_process

.do_explain:
    cmp $3, %r12
    jb .missing_explain
    mov 24(%rsp), %rdi
    lea registry_pkg_name(%rip), %rsi
    call streq
    test %eax, %eax
    jz .pkg_not_found

    lea res_explain_title(%rip), %rdi
    call print_cstr

    lea res_user_head(%rip), %rdi
    call print_cstr
    lea res_lab_package(%rip), %rdi
    lea registry_pkg_name(%rip), %rsi
    call print_kv
    lea res_lab_version(%rip), %rdi
    lea res_default_version(%rip), %rsi
    call print_kv

    lea res_defaults_head(%rip), %rdi
    call print_cstr
    lea res_lab_policy(%rip), %rdi
    lea registry_artifact_policy(%rip), %rsi
    call print_kv
    lea res_lab_dependency(%rip), %rdi
    lea registry_dependency_kind(%rip), %rsi
    call print_kv

    lea res_sem_head(%rip), %rdi
    call print_cstr
    lea res_lab_capability(%rip), %rdi
    lea registry_capability(%rip), %rsi
    call print_kv
    lea res_lab_profile(%rip), %rdi
    lea registry_profile(%rip), %rsi
    call print_kv
    lea semantic_lab_fp(%rip), %rdi
    lea registry_semantic_fingerprint(%rip), %rsi
    call print_kv

    lea res_candidates_head(%rip), %rdi
    call print_cstr
    lea res_lab_variant(%rip), %rdi
    lea registry_variant_primary(%rip), %rsi
    call print_kv
    lea res_lab_alternate(%rip), %rdi
    lea registry_variant_alternate(%rip), %rsi
    call print_kv
    lea res_candidate_note(%rip), %rdi
    call print_cstr

    lea perf_head(%rip), %rdi
    call print_cstr
    lea perf_lab_benchmark(%rip), %rdi
    lea registry_perf_benchmark(%rip), %rsi
    call print_kv
    lea perf_lab_status(%rip), %rdi
    lea registry_perf_evidence_status(%rip), %rsi
    call print_kv
    lea perf_lab_accepted(%rip), %rdi
    lea registry_perf_evidence_count(%rip), %rsi
    call print_kv
    lea perf_lab_ranking(%rip), %rdi
    lea registry_perf_ranking(%rip), %rsi
    call print_kv

    lea res_machine_head(%rip), %rdi
    call print_cstr
    lea res_lab_requires(%rip), %rdi
    lea registry_required_isa(%rip), %rsi
    call print_kv

    call check_bootstrap_variant
    test %eax, %eax
    jz .explain_incompatible

    lea res_lab_result(%rip), %rdi
    lea res_compatible(%rip), %rsi
    call print_kv
    lea res_final_prefix(%rip), %rdi
    call print_cstr
    lea registry_variant_primary(%rip), %rdi
    call print_cstr
    lea newline(%rip), %rdi
    call print_cstr
    xor %edi, %edi
    jmp exit_process

.explain_incompatible:
    lea res_lab_result(%rip), %rdi
    lea res_incompatible(%rip), %rsi
    call print_kv
    lea res_final_none(%rip), %rdi
    call print_cstr
    xor %edi, %edi
    jmp exit_process

.missing_explain:
    lea missing_explain_msg(%rip), %rdi
    call print_cstr
    mov $2, %edi
    jmp exit_process

.do_semantics:
    cmp $3, %r12
    jb .missing_semantics
    mov 24(%rsp), %rdi
    lea registry_pkg_name(%rip), %rsi
    call streq
    test %eax, %eax
    jz .pkg_not_found

    lea semantic_title(%rip), %rdi
    call print_cstr
    lea res_lab_capability(%rip), %rdi
    lea registry_capability(%rip), %rsi
    call print_kv
    lea res_lab_profile(%rip), %rdi
    lea registry_profile(%rip), %rsi
    call print_kv
    lea res_lab_provider(%rip), %rdi
    lea registry_provider(%rip), %rsi
    call print_kv
    lea semantic_lab_fp(%rip), %rdi
    lea registry_semantic_fingerprint(%rip), %rsi
    call print_kv
    lea semantic_lab_iface(%rip), %rdi
    lea registry_semantic_interface(%rip), %rsi
    call print_kv
    lea semantic_lab_align(%rip), %rdi
    lea registry_semantic_alignment(%rip), %rsi
    call print_kv
    lea semantic_lab_abs(%rip), %rdi
    lea registry_semantic_abs_error(%rip), %rsi
    call print_kv
    lea semantic_lab_rel(%rip), %rdi
    lea registry_semantic_rel_error(%rip), %rsi
    call print_kv
    lea semantic_lab_det(%rip), %rdi
    lea registry_semantic_determinism(%rip), %rsi
    call print_kv
    lea semantic_lab_facets(%rip), %rdi
    call print_cstr
    lea semantic_lab_endpoint(%rip), %rdi
    lea registry_semantic_endpoint(%rip), %rsi
    call print_kv
    xor %edi, %edi
    jmp exit_process

.missing_semantics:
    lea missing_semantics_msg(%rip), %rdi
    call print_cstr
    mov $2, %edi
    jmp exit_process

.do_match:
    cmp $4, %r12
    jb .missing_match
    mov 24(%rsp), %rdi
    lea registry_pkg_name(%rip), %rsi
    call streq
    test %eax, %eax
    jz .pkg_not_found

    mov 32(%rsp), %rdi
    lea registry_semantic_core_profile(%rip), %rsi
    call streq
    test %eax, %eax
    jnz .match_core

    mov 32(%rsp), %rdi
    lea registry_semantic_strict_profile(%rip), %rsi
    call streq
    test %eax, %eax
    jnz .match_strict

    lea unknown_profile_msg(%rip), %rdi
    call print_cstr
    mov $3, %edi
    jmp exit_process

.match_core:
    lea semantic_match_title(%rip), %rdi
    call print_cstr
    lea semantic_lab_request(%rip), %rdi
    lea registry_semantic_core_profile(%rip), %rsi
    call print_kv
    lea semantic_lab_result(%rip), %rdi
    lea registry_semantic_core_result(%rip), %rsi
    call print_kv
    lea semantic_lab_fp(%rip), %rdi
    lea registry_semantic_fingerprint(%rip), %rsi
    call print_kv
    xor %edi, %edi
    jmp exit_process

.match_strict:
    lea semantic_match_title(%rip), %rdi
    call print_cstr
    lea semantic_lab_request(%rip), %rdi
    lea registry_semantic_strict_profile(%rip), %rsi
    call print_kv
    lea semantic_lab_result(%rip), %rdi
    lea registry_semantic_strict_result(%rip), %rsi
    call print_kv
    lea semantic_lab_reason(%rip), %rdi
    lea registry_semantic_strict_reason(%rip), %rsi
    call print_kv
    mov $5, %edi
    jmp exit_process

.missing_match:
    lea missing_match_msg(%rip), %rdi
    call print_cstr
    mov $2, %edi
    jmp exit_process

.do_evidence:
    cmp $3, %r12
    jb .missing_evidence
    mov 24(%rsp), %rdi
    lea registry_pkg_name(%rip), %rsi
    call streq
    test %eax, %eax
    jz .pkg_not_found

    lea perf_title(%rip), %rdi
    call print_cstr
    lea perf_head(%rip), %rdi
    call print_cstr

    lea perf_lab_benchmark(%rip), %rdi
    lea registry_perf_benchmark(%rip), %rsi
    call print_kv
    lea perf_lab_contract(%rip), %rdi
    lea registry_perf_contract_sha256(%rip), %rsi
    call print_kv
    lea perf_lab_status(%rip), %rdi
    lea registry_perf_evidence_status(%rip), %rsi
    call print_kv
    lea perf_lab_accepted(%rip), %rdi
    lea registry_perf_evidence_count(%rip), %rsi
    call print_kv
    lea perf_lab_ranking(%rip), %rdi
    lea registry_perf_ranking(%rip), %rsi
    call print_kv
    lea perf_lab_endpoint(%rip), %rdi
    lea registry_perf_endpoint(%rip), %rsi
    call print_kv

    xor %edi, %edi
    jmp exit_process

.missing_evidence:
    lea missing_evidence_msg(%rip), %rdi
    call print_cstr
    mov $2, %edi
    jmp exit_process

.do_audit:
    cmp $3, %r12
    jb .missing_audit
    mov 24(%rsp), %rdi
    lea registry_pkg_name(%rip), %rsi
    call streq
    test %eax, %eax
    jz .pkg_not_found

    lea res_audit_title(%rip), %rdi
    call print_cstr

    lea res_artifact_head(%rip), %rdi
    call print_cstr
    lea res_lab_package(%rip), %rdi
    lea registry_pkg_name(%rip), %rsi
    call print_kv
    lea res_lab_release(%rip), %rdi
    lea registry_version(%rip), %rsi
    call print_kv
    lea res_lab_sha256(%rip), %rdi
    lea registry_artifact_sha256(%rip), %rsi
    call print_kv
    lea res_lab_integrity(%rip), %rdi
    lea res_not_evaluated(%rip), %rsi
    call print_kv

    lea res_security_head(%rip), %rdi
    call print_cstr
    lea res_lab_review(%rip), %rdi
    lea registry_review_state(%rip), %rsi
    call print_kv
    lea res_lab_anchor(%rip), %rdi
    lea registry_reviewed_anchor(%rip), %rsi
    call print_kv
    lea res_lab_safety(%rip), %rdi
    lea registry_safety_state(%rip), %rsi
    call print_kv
    lea res_lab_advisories(%rip), %rdi
    lea registry_advisories(%rip), %rsi
    call print_kv

    lea res_audit_note(%rip), %rdi
    call print_cstr
    xor %edi, %edi
    jmp exit_process

.missing_audit:
    lea missing_audit_msg(%rip), %rdi
    call print_cstr
    mov $2, %edi
    jmp exit_process

.do_target:
    call detect_cpu
    lea target_head(%rip), %rdi
    call print_cstr
    lea arch_line(%rip), %rdi
    call print_cstr
    lea vendor_pre(%rip), %rdi
    call print_cstr
    lea vendor_buf(%rip), %rdi
    call print_cstr
    lea newline(%rip), %rdi
    call print_cstr
    lea isa_head(%rip), %rdi
    call print_cstr
    mov baseline_ptr(%rip), %rdi
    call print_cstr
    lea feat_head(%rip), %rdi
    call print_cstr

    lea lab_sse2(%rip), %rdi
    mov leaf1_edx(%rip), %eax
    bt $26, %eax
    setc %sil
    call print_feature

    lea lab_sse42(%rip), %rdi
    mov leaf1_ecx(%rip), %eax
    bt $20, %eax
    setc %sil
    call print_feature

    lea lab_avx(%rip), %rdi
    movzbl avx_ok(%rip), %esi
    call print_feature

    lea lab_avx2(%rip), %rdi
    mov leaf7_ebx(%rip), %eax
    bt $5, %eax
    setc %sil
    and avx_ok(%rip), %sil
    call print_feature

    lea lab_fma(%rip), %rdi
    mov leaf1_ecx(%rip), %eax
    bt $12, %eax
    setc %sil
    and avx_ok(%rip), %sil
    call print_feature

    lea lab_bmi1(%rip), %rdi
    mov leaf7_ebx(%rip), %eax
    bt $3, %eax
    setc %sil
    call print_feature

    lea lab_bmi2(%rip), %rdi
    mov leaf7_ebx(%rip), %eax
    bt $8, %eax
    setc %sil
    call print_feature

    lea lab_avx512f(%rip), %rdi
    mov leaf7_ebx(%rip), %eax
    bt $16, %eax
    setc %sil
    and avx512_ok(%rip), %sil
    call print_feature

    lea lab_avx512bw(%rip), %rdi
    mov leaf7_ebx(%rip), %eax
    bt $30, %eax
    setc %sil
    and avx512_ok(%rip), %sil
    call print_feature

    lea lab_avx512vl(%rip), %rdi
    mov leaf7_ebx(%rip), %eax
    bt $31, %eax
    setc %sil
    and avx512_ok(%rip), %sil
    call print_feature

    xor %edi, %edi
    jmp exit_process

# eax=1 when this bootstrap package's Machine Contract is legal.
check_bootstrap_variant:
    call detect_cpu

    cmpb $1, avx_ok(%rip)
    jne .cbv_no

    mov leaf7_ebx(%rip), %eax
    bt $5, %eax
    jnc .cbv_no

    mov leaf1_ecx(%rip), %eax
    bt $12, %eax
    jnc .cbv_no

    mov $1, %eax
    ret

.cbv_no:
    xor %eax, %eax
    ret

# Detect CPUID leaves and classify x86-64 baseline.
detect_cpu:
    push %rbx
    xor %eax, %eax
    cpuid
    mov %eax, %r14d
    mov %ebx, vendor_buf(%rip)
    mov %edx, vendor_buf+4(%rip)
    mov %ecx, vendor_buf+8(%rip)
    movb $0, vendor_buf+12(%rip)

    cmp $1, %r14d
    jb .baseline
    mov $1, %eax
    cpuid
    mov %ecx, leaf1_ecx(%rip)
    mov %edx, leaf1_edx(%rip)

    # AVX usable only when CPU advertises AVX+OSXSAVE and XCR0 enables XMM/YMM.
    mov %ecx, %eax
    mov %eax, %edx
    and $((1<<27)|(1<<28)), %edx
    cmp $((1<<27)|(1<<28)), %edx
    jne .leaf7
    xor %ecx, %ecx
    xgetbv
    shl $32, %rdx
    or %rax, %rdx
    mov %rdx, xcr0_val(%rip)
    mov %edx, %eax
    and $0x6, %eax
    cmp $0x6, %eax
    jne .leaf7
    movb $1, avx_ok(%rip)
    mov xcr0_val(%rip), %rax
    and $0xe6, %eax
    cmp $0xe6, %eax
    jne .leaf7
    movb $1, avx512_ok(%rip)

.leaf7:
    cmp $7, %r14d
    jb .ext
    mov $7, %eax
    xor %ecx, %ecx
    cpuid
    mov %ebx, leaf7_ebx(%rip)

.ext:
    mov $0x80000000, %eax
    cpuid
    cmp $0x80000001, %eax
    jb .baseline
    mov $0x80000001, %eax
    cpuid
    mov %ecx, ext1_ecx(%rip)

.baseline:
    lea baseline_v1(%rip), %rax
    mov %rax, baseline_ptr(%rip)

    # v2: LAHF/SAHF, CMPXCHG16B, POPCNT, SSE3, SSSE3, SSE4.1, SSE4.2
    mov leaf1_ecx(%rip), %eax
    bt $13, %eax
    jnc .done_baseline
    bt $23, %eax
    jnc .done_baseline
    bt $0, %eax
    jnc .done_baseline
    bt $9, %eax
    jnc .done_baseline
    bt $19, %eax
    jnc .done_baseline
    bt $20, %eax
    jnc .done_baseline
    mov ext1_ecx(%rip), %edx
    bt $0, %edx
    jnc .done_baseline
    lea baseline_v2(%rip), %rax
    mov %rax, baseline_ptr(%rip)

    # v3: AVX/AVX2, BMI1/2, F16C, FMA, LZCNT, MOVBE
    cmpb $1, avx_ok(%rip)
    jne .done_baseline
    mov leaf7_ebx(%rip), %edx
    bt $3, %edx
    jnc .done_baseline
    bt $5, %edx
    jnc .done_baseline
    bt $8, %edx
    jnc .done_baseline
    mov leaf1_ecx(%rip), %eax
    bt $29, %eax
    jnc .done_baseline
    bt $12, %eax
    jnc .done_baseline
    bt $22, %eax
    jnc .done_baseline
    mov ext1_ecx(%rip), %eax
    bt $5, %eax
    jnc .done_baseline
    lea baseline_v3(%rip), %rax
    mov %rax, baseline_ptr(%rip)

    # v4: AVX512F, BW, CD, DQ, VL and OS support for ZMM/opmask state.
    cmpb $1, avx512_ok(%rip)
    jne .done_baseline
    mov leaf7_ebx(%rip), %eax
    bt $16, %eax
    jnc .done_baseline
    bt $17, %eax
    jnc .done_baseline
    bt $28, %eax
    jnc .done_baseline
    bt $30, %eax
    jnc .done_baseline
    bt $31, %eax
    jnc .done_baseline
    lea baseline_v4(%rip), %rax
    mov %rax, baseline_ptr(%rip)

.done_baseline:
    pop %rbx
    ret

# rdi = label c-string, sil = bool
print_feature:
    push %rsi
    call print_cstr
    pop %rsi
    test %sil, %sil
    jz .pf_no
    lea yes_msg(%rip), %rdi
    jmp print_cstr
.pf_no:
    lea no_msg(%rip), %rdi
    jmp print_cstr

# rdi=label c-string, rsi=value c-string.
print_kv:
    push %rsi
    call print_cstr
    pop %rdi
    call print_cstr
    lea newline(%rip), %rdi
    call print_cstr
    ret

# eax=1 when path exists, otherwise eax=0.
path_exists:
    mov $21, %eax
    xor %esi, %esi
    syscall
    test %rax, %rax
    sete %al
    movzbl %al, %eax
    ret

# rdi=path. Return 0 on success or existing directory.
mkdir_if_missing:
    mov $83, %eax
    mov $493, %esi
    syscall
    test %rax, %rax
    jns .mim_ok
    cmp $-17, %rax
    je .mim_ok
    ret
.mim_ok:
    xor %eax, %eax
    ret

# rdi=path, rsi=data, rdx=len. Never overwrites an existing path.
create_text_exclusive:
    push %rbx
    push %r12
    mov %rdi, %r12
    mov %rsi, %r8
    mov %rdx, %r9

    mov %rdi, %rsi
    mov $-100, %rdi
    mov $193, %edx
    mov $420, %r10d
    mov $257, %eax
    syscall
    test %rax, %rax
    js .cte_open_fail

    mov %rax, %rbx
    mov %rbx, %rdi
    mov %r8, %rsi
    mov %r9, %rdx
    call write_all_fd
    mov %rax, %r8

    mov $3, %eax
    mov %rbx, %rdi
    syscall

    test %r8, %r8
    jns .cte_ok

    mov %r12, %rdi
    mov $87, %eax
    syscall
    mov $-5, %rax
    jmp .cte_done

.cte_ok:
    xor %eax, %eax
    jmp .cte_done

.cte_open_fail:
.cte_done:
    pop %r12
    pop %rbx
    ret

# rdi=fd, rsi=buffer, rdx=len. Return 0 or -EIO.
write_all_fd:
.waf_loop:
    test %rdx, %rdx
    jz .waf_ok
    mov $1, %eax
    syscall
    test %rax, %rax
    jle .waf_fail
    add %rax, %rsi
    sub %rax, %rdx
    jmp .waf_loop
.waf_ok:
    xor %eax, %eax
    ret
.waf_fail:
    mov $-5, %rax
    ret

# int streq(const char *a, const char *b) -> eax 0/1
streq:
    xor %eax, %eax
.st_loop:
    movzbq (%rdi), %rcx
    movzbq (%rsi), %rdx
    cmp %dl, %cl
    jne .st_no
    test %cl, %cl
    je .st_yes
    inc %rdi
    inc %rsi
    jmp .st_loop
.st_yes:
    mov $1, %eax
.st_no:
    ret

# print zero-terminated string at rdi to stdout.
print_cstr:
    push %rdi
    mov %rdi, %rsi
    xor %rdx, %rdx
.pc_len:
    cmpb $0, (%rsi,%rdx)
    je .pc_write
    inc %rdx
    jmp .pc_len
.pc_write:
    mov $1, %eax
    mov $1, %edi
    syscall
    pop %rdi
    ret

exit_process:
    mov $60, %eax
    syscall
.size _start, .-_start
