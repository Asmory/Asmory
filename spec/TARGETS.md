# Target Model — Draft 0

Asmory treats a target as a compatibility tuple rather than a single architecture string.

Conceptually:

```text
Target = Architecture
       × OS
       × ObjectFormat
       × ABI
       × ISABaseline
       × ISAFeatureSet
       × ToolchainConstraints
```

Optional microarchitecture tuning is metadata layered on top; it is not automatically a hard compatibility requirement.

## Example targets

These are different targets even though the first three all use x86-64:

```text
x86_64 / Linux / ELF64 / SysV64 / x86-64-v2
x86_64 / Linux / ELF64 / SysV64 / x86-64-v3 + AVX2 + FMA
x86_64 / Windows / COFF64 / Win64 / AVX2 + FMA
aarch64 / Linux / ELF64 / AAPCS64 / Armv8.2-A + CRC
riscv64 / Linux / ELF64 / LP64D / RV64GCV
```

## Hard constraints vs tuning

Hard constraints answer: **will this code execute correctly?**

Tuning answers: **which compatible implementation should be preferred for this microarchitecture?**

Asmory must never select an incompatible variant merely because it is marked as faster.
