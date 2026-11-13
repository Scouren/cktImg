# Assembly comparison checker

`asm_probe.py` is vendored byte-for-byte from the repository-author supplied
`zig` skill, `scripts/asm_probe.py`, read on 2026-11-13. Its source content
SHA-256 is `8eb1df763b67cb6c92157dfb6dd11f7959b06ec2c34242316f8da0e059b5e129`.
The skill source is maintained in
<https://github.com/OmarSiwy/NixOSConfig/tree/main/skills/zig>.
No build step reads an agent's home directory or downloads the checker.

`zig build test-codegen` emits the runtime-input pair in
`tests/codegen.zig` for x86_64 Linux, x86_64_v3, ReleaseFast, then runs this
checker through `codegen_check.py` and its named method checks.
`zig build test` includes that step.
The object is neither linked nor installed, including in the WASM graph.
Its separate build options disable the unrelated C ABI, ZON configuration
reader and LaTeX emitter; product options are unchanged. Both exports take
runtime inputs and produce the same optional three-bit index before the
exported byte conversion. The hand path writes the complete recognition
and output scan directly, without calling the shared output helper.
FOLDED, IDENTICAL, EQUIVALENT and NEGATIVE are static codegen verdicts;
they do not establish functional equivalence or runtime speed. Consumer
tests establish the query's semantic boundaries separately.

The vendored checker self-test includes added indirect-call residue and
missing symbols. The repository wrapper additionally requires identical
ordered direct callee targets and rejects external tail jumps and indirect
calls, so a small wrapper cannot hide more work in a different callee.
Its literal mutations reject full-role classification behind an apparent
smaller export, extra calls, tail wrappers and added instructions. The
first emitted query object was rejected by this guard: its generated path
called `block_symbols.role`, while the direct path called `library.portRole`.
The actual query probe must additionally be mutation-checked by
introducing extra runtime work in a copied probe source and observing a
nonzero checker exit. Keep that build's log with the feature validation.

The final iteration-19 object reports **IDENTICAL**: 90 instructions, ten
branches and the same two direct callees in each export. The production
helper is inline in both real placement callers, not only in the probe.
A compiled copied-source runtime-work mutation reports **RESIDUE** at
99 versus 90 instructions and is rejected. The direct implementation stays
at the original 90-instruction baseline. These are static abstraction-cost
measurements, not a runtime speed claim.
