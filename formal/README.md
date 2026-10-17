# Formal verification of `tt_um_kouskos56_seg7`

SymbiYosys (`sby`) proofs of the shipped RTL — the actual `src/tt_um_kouskos56_seg7.v`,
not a model of it. Everything here runs offline on one machine; no CI job is needed to
reproduce it.

## What is proven, and what is not

Proven, for all inputs and all reachable states:

* the prescaler's tick condition is exactly `prescale >= terminal`, over **all 2^24
  counter encodings** at each of the four speed settings, not merely the ones the
  counter can reach from reset;
* no state exists where the counter is past its terminal count and the tick does not
  fire (this is the bug the `==` → `>=` change fixed, and the negative control below
  shows the property set catches it);
* the prescaler transfer relation (clear on tick, +1 otherwise, hold when `ena` is low),
  the BCD step relation, reset behaviour, the segment table, the dp/`pause` mirror and
  the tied-off `uio_*` pins;
* a bounded-response property: after an enabled cycle the display can never wait more
  than the terminal count of the *currently selected* speed for the next tick, so
  raising the speed takes effect immediately instead of after a wrap.

Not proven here, and not claimable by this flow:

* that `uo_out[6:0]` bit *n* reaches the physical segment it names — that is board
  wiring on the demo carrier, invisible in this netlist;
* gate-level equivalence to the shipped GDS (LibreLane/CI's job), timing, and anything
  analog;
* anything about the `uio_in`/`ui_in[7:4]` inputs, which the design deliberately ignores.

## Running it

From the **repo root** — the `[files]` paths in each `.sby` resolve against the working
directory, not against the `.sby` file:

```bat
cd <repo root>
<oss-cad-suite>\environment.bat
sby -f formal\seg7_reset.sby
```

or all five in one line from Git Bash:

```sh
for f in seg7_reset seg7_free seg7_decode seg7_eq_reset seg7_eq_free; do
  cmd //C "<oss-cad-suite>\\environment.bat && sby -f formal/$f.sby" > formal/$f.log 2>&1
done
```

Calling plain `sby` from Git Bash works only if the suite comes first on `PATH`. If Git's
own `/mingw64/bin` is ahead of it, `yosys.exe` dies during process startup and every build
reports `DONE (ERROR, rc=16)` with `base: finished (returncode=3221225785)` (0xC0000005) and
an empty `model/design.log` — a toolchain problem, not a design one. Either run through
`environment.bat` as above, or hoist the suite: `export PATH="<oss-cad-suite>/lib:$PATH"`.

Each build settles in about a second (the flattened design is 120 cells, and no property
needs the counter unrolled), so the whole set costs a few seconds rather than the minutes a
harden run takes.

## The five builds and their measured results

Tool versions: Yosys 0.69+260, `sby` 0.69, engine `smtbmc bitwuzla`, `mode prove`, `depth 4`
(except the decoder build, which is `mode bmc`, `depth 1`).

| build | RTL | state at step 0 | claims | result |
|---|---|---|---|---|
| `seg7_reset.sby` | shipped | reset forced | all except P5s | **PASS** (rc=0) |
| `seg7_free.sby` | shipped | free (`prescale`, `value` arbitrary) | all except P5s, except the reachable-digit claim | **PASS** (rc=0) |
| `seg7_decode.sby` | shipped | free | P5s segment table: `value` is free at step 0, so one run tries all 16 encodings and asserts the 10 valid ones | **PASS** (rc=0) |
| `seg7_eq_reset.sby` | pre-fix (`==`) | reset forced | same as `seg7_reset` | **UNKNOWN** (rc=4) — P1 and P2 break at the induction step |
| `seg7_eq_free.sby` | pre-fix (`==`) | free | same as `seg7_free` | **FAIL** (rc=2) — P1 and P2 break in the base case, step 1 |

`sby` reports UNKNOWN when a property is not k-inductive, so for the negative control it
means "cannot prove this design", which is the correct answer — but the FAIL row is the
one to quote, because it is a concrete counterexample rather than a missing proof.

## Negative control

`negative_control/tt_um_kouskos56_seg7_eq.v` is `git show 0dc6fbf:src/tt_um_kouskos56_seg7.v`
— the design as it stood before the fix — plus the `` `ifdef FORMAL `` hook, so
`diff` shows only that hook and the header. Its one functional difference is
`wire tick = (prescale == terminal);`.

Running the same property set against it gives a counterexample at base-case step 1:

```
speed    = 2'b10      -> terminal = 24'h0F_FFFF
prescale = 24'h8F_FFFF                  (already past the terminal count)
tick     = 1'b0                         (with ==, it stays 0)
```

`prescale` is 9,437,183 while the terminal count of the speed just selected is 1,048,575,
so with `==` the pulse is missed and the digit stays frozen until the 24-bit counter wraps
and re-reaches 0x0F_FFFF: 8,388,608 cycles = 2^23, about 0.34 s at 25 MHz and 0.17 s at
50 MHz. The state is reachable in one cycle — hold `speed = 00` until `prescale =
0x8F_FFFF`, then switch to `speed = 10`. The shipped design ticks on that very cycle, which
is what P1/P2 prove.

This matters for how much to trust a passing proof: a property set that the buggy design
also satisfies proves nothing. Here the same file, same depth, same engine separates the
two. The separation is not formal-only: `test/smoke_tb.v` fails exactly the speed-jump
check against the same control file (see `test/README.md`), so a simulator reaches the
same conclusion as the prover.

## The properties

`seg7_props.svh` numbers them; the file carries the reasoning, this is the index.

| id | claim | style |
|---|---|---|
| P0 | `terminal` matches the datasheet divider for all four `speed` values | combinational |
| P1 | `tick === (prescale >= terminal)` | combinational, so exhaustive over 2^24 x 4 |
| P2 | never `prescale > terminal` without `tick` — the no-freeze claim | combinational |
| P3 | prescaler transfer: 0 on tick, +1 otherwise, hold while `ena` low | 1-step |
| P4 | BCD step: only an enabled unpaused tick moves the digit; 9→0 and 0→9 wrap | 1-step |
| P4r | `value <= 9` | reachable-state invariant, reset build only |
| P5 | `uo_out[7] === pause`, `uio_out`/`uio_oe` tied to 0 | combinational |
| P5s | `uo_out[6:0]` equals the segment table for a valid digit | combinational, own build |
| P7 | releasing reset clears both `prescale` and `value` | 1-step |
| P6a | the reference watchdog never exceeds `prescale` | lemma, makes P6 inductive |
| P6 | an enabled non-tick cycle never waits longer than the current `terminal` | k-induction |
| P6 | bounded response: an enabled gap between ticks never exceeds the current `terminal` | k-induction, needs P6a |
| P6a | lemma: the reference watchdog never leads the real prescaler | k-induction |
| P7 | releasing reset clears both counters | 1-step |

P6 is the property that separates a `>=` prescaler from a `==` one on *behaviour* rather
than on the tick equation: it says the datasheet claim "raising the speed takes effect on
the next cycle" holds with no bound on how long the counter has been running. It only
becomes inductive with the P6a lemma, because otherwise k-induction hands the solver an
arbitrary watchdog against a small terminal count — a state the design cannot be in.

## Build switches

`seg7_props.svh` is included from inside the module body (see the comment at the top of
that file for why: Yosys has no `bind`, so a checker outside the module cannot see
`prescale`, `terminal` or `tick`). Two defines, set on the `read_verilog` line, pick what a
build claims:

* `SEG7_FREE_INIT` — leave registers that have no declared initial value unconstrained at
  time 0, so the claims cover all 2^24 counter states rather than only those reachable
  from reset. In this build the reachable-state invariant P4r is gated off, because a free
  `value` of 10..15 is an artefact of the assumption, not a design bug.
* `SEG7_SKIP_DECODE` — drop P5s. P5s is proven on its own in `seg7_decode.sby` for the
  reason given next.

Both `.sby` task families and the decoder build are separate files because `sby` 0.69 has
no per-task option overrides — a task-prefixed `[options]` line is rejected.

## Yosys/sby behaviour found the hard way

Documented nowhere I could find, and each one cost a run:

1. **`;` is not a comment in a `.sby` file; `#` is.** A stray `;` produces
   "In an incomprehensible mode 'None'".
2. **`[files]` is `DEST SOURCE`**, and SOURCE resolves against the current directory.
   Getting it backwards gives "destination filename must be a relative path without /../".
3. **`bind` is not supported**, and a hierarchical reference like `dut.value` is accepted
   with a warning and silently becomes an implicitly declared, undriven identifier — the
   proof then "passes" about nothing. Use `` `ifdef FORMAL `` + `include` inside the module.
4. **`read_verilog -formal` defines FORMAL** (and drops `SYNTHESIS`), so a hook guarded by
   FORMAL is inert for LibreLane, Icarus, Verilator and the TT precheck. That is what makes
   it safe to put properties in the shipped file.
5. **Registers without an initial value are free at step 0**, in both modes. Useful for
   over-approximation, wrong for helper state: a watchdog that starts at an arbitrary count
   reports violations the design cannot produce. Every checker register here is explicitly
   initialised.
6. **The unreachable `default:` branch of the decoder's `case` becomes don't-cares.** In the
   formal netlist `value = 11` drives `seg = 100_0000`, not the all-blank the RTL asks for.
   Claims about digits 10..15 would be claims about the netlist, so they are not made.
7. **A `case` in `always @(*)` is inferred as a ROM whose don't-care entries are replaced by
   free `$anyseq` inputs.** The read then depends on a free choice, so the decoder equality
   passes BMC and fails k-induction. Reproduced on a 12-line standalone ROM, so it is a
   translation property, not a design property — hence P5s lives in its own `mode bmc`
   build, where a free `value` at step 0 makes one run cover all 16 encodings.
8. `-c` on the `yosys` command line is TCL; a plain script needs `-s`.

## Reading the output

`formal/<build>_<task>/` holds the generated model, the engine logs and any trace;
`formal/*.log` is the per-build transcript. Both are machine output and git-ignored.
For a failing property, the summary line names the file and line inside `seg7_props.svh`,
and `trace_induct.vcd` (induction) or `trace.vcd` (base case) is the witness —
`gtkwave formal\seg7_eq_free_eq_free\engine_0\trace.vcd`.
