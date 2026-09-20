# Package Names — Draft 1

Asmory lookups use a canonical normalized project identity.

## Valid spelling

ASCII letters, digits, `.`, `_`, and `-` are allowed. A name must begin and end
with a letter or digit.

## Normalization

For lookup and ownership:

1. lowercase ASCII letters;
2. replace every run of `.`, `_`, or `-` with one `-`.

```text
SIMD.Dot
simd_dot
simd---dot
Simd-._-Dot

→ simd-dot
```

These spellings therefore cannot be registered as separate Projects.

The Draft 1 rule intentionally follows the well-tested normalization shape
used by Python package indexes.
