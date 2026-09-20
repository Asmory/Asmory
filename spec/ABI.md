# ABI Model — Draft 0

Asmory packages must state the ABI/calling convention expected by exported symbols.

Examples include:

- SysV AMD64;
- Windows x64;
- AAPCS64;
- RISC-V psABI variants.

The manifest/export contract will eventually need machine-readable descriptions for:

- argument/return locations;
- preserved and clobbered registers;
- stack alignment;
- red-zone/shadow-space assumptions;
- vector-register state;
- unwind metadata;
- symbol visibility;
- PIC/PIE assumptions.

The goal is to prevent the common failure mode where an object links successfully but violates the consumer's ABI at runtime.
