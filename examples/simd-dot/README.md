# simd-dot

Minimal Asmory example package exporting an AVX2/FMA float32 dot-product
kernel through the SysV AMD64 ABI.

It exercises the complete Project → Release → Variant → Artifact model.


## Performance power session

`simd-dot` is the first Asmory reference package to exercise managed benchmark
power policy. Performance runs temporarily switch supported host controls to
`performance`, verify the state, and restore the previous policy afterward.

Compatibility fallback is permitted only when the host exposes no supported
controllable power-policy interface.
