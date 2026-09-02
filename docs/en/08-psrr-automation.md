# Chapter 8: PSRR Automation

This chapter documents a reusable PSRR+ and PSRR- automation workflow for a
five-transistor OTA in Cadence Virtuoso, Spectre, and OCEAN.

The source notes contained local paths, project names, net names, one-run
checkpoint names, and script hashes. This public version keeps the engineering
method and uses placeholders for private environment details.

## 1. Scope

This workflow covers:

1. PSRR definition choices
2. Shared PSRR AC conditions
3. PSRR+ supply-injection setup
4. PSRR- local-VSS setup
5. OCEAN execution and raw export validation
6. Formal input-referred PSRR and direct rejection post-processing
7. PSRR+ and PSRR- result comparison
8. Engineering interpretation
9. Common errors and safe recovery
10. Working checkpoints

The commands are intended for a remote Linux Cadence environment accessed from
MobaXterm or another SSH terminal.

## 2. PSRR Definitions

For supply rejection, always state which definition is being reported.

This workflow saves two representations:

```text
Direct supply rejection = |Vsupply / Vout|
Formal input-referred PSRR = |Ad / (Vout / Vsupply)|
```

In dB:

```text
Direct rejection dB = -Supply-to-output gain dB
Formal PSRR dB = Differential gain dB - Supply-to-output gain dB
```

The main reported PSRR metric in this chapter uses the formal input-referred
definition. Direct rejection is still useful because it tracks the real
supply-to-output coupling path.

## 3. Shared AC Conditions

Example nominal setup:

```text
Process corner:          <process-corner>
Temperature:             27 deg C
VDD:                     1.2 V
VCM:                     800 mV
VID:                     0 V
Load capacitance:        100 fF
Frequency start:         1 Hz
Frequency stop:          100 GHz
Sweep density:           100 points per decade
Expected numeric points: 1101
```

Turn off all differential input AC excitation during PSRR simulation:

```text
Vin+ DC value:       VCM + VID/2
Vin+ AC magnitude:   0
Vin+ AC phase:       0 deg

Vin- DC value:       VCM - VID/2
Vin- AC magnitude:   0
Vin- AC phase:       180 deg
```

Use the already verified differential open-loop AC result as the `Ad(f)` input
for formal PSRR post-processing:

```text
/home/<linux-user>/simulation/<ota-project>_ocean/ac_openloop/ac_gain_raw.txt
```

## 4. PSRR+ Testbench

For PSRR+, inject a `1 V` small-signal AC source on the positive supply:

```text
VDD source: DC = 1.2 V, AC magnitude = 1 V, phase = 0 deg
VSS:        global 0
Inputs:     DC bias only, AC magnitude = 0
Bias:       DC only
```

Example OCEAN expressions:

```lisp
vddWave = v("/vdd")
supplyGainWave = v("/vout") / vddWave
directPsrrPlusWave = vddWave / v("/vout")
```

Create a result directory:

```bash
mkdir -p /home/<linux-user>/simulation/<ota-project>_ocean/ac_psrr_plus
```

Run PSRR+:

```bash
cd /home/<linux-user>/cadence_projects/<ota-project> || exit 1
set -o pipefail
ocean -nograph -restore psrr_plus_sweep.ocn 2>&1 | tee psrr_plus_sweep_run.log
run_status=${PIPESTATUS[0]}
echo "OCEAN_EXIT_STATUS=$run_status"
```

Verify raw data:

```bash
if [ -s /home/<linux-user>/simulation/<ota-project>_ocean/ac_psrr_plus/psrr_plus_raw.txt ]; then
    echo "PSRR_PLUS_RAW_VERIFIED"
else
    echo "ERROR: PSRR_PLUS_RAW_MISSING"
fi
```

## 5. PSRR- Testbench

For PSRR-, do not inject AC directly into Spectre global node `0`. Create a
local VSS node, then connect the OTA negative-supply terminals to that node.

The fixed-absolute-input setup used by this workflow is:

1. Tail-device source and body connect to local `vss`.
2. NM input-pair bodies connect to local `vss`.
3. A VSS source between local `vss` and global `0` provides `DC = 0 V` and
   `AC = 1 V`.
4. VDD, input sources, tail-bias voltage source, and external load capacitor
   still reference global `0`.

This is a fixed-absolute-input and fixed-absolute-bias PSRR- test. If the real
system generates the bias voltage from a VSS-referenced circuit, create a
separate tracking-bias PSRR- variant and do not mix it with this curve.

Create a complete PSRR- netlist directory copy:

```bash
mkdir -p /home/<linux-user>/simulation/<ota-project>_psrr_minus/spectre/schematic/netlist
cp -a \
  /home/<linux-user>/simulation/<ota-project>_psrr_plus/spectre/schematic/netlist/. \
  /home/<linux-user>/simulation/<ota-project>_psrr_minus/spectre/schematic/netlist/
```

Modify only the copied netlist. The exact device and source names depend on
your schematic, so first inspect the relevant lines with `grep`, then make only
these logical changes:

```text
Tail device source/body:      0 -> vss
Input-pair bodies:            0 -> vss
VDD source:                   AC=1 -> DC-only
Added local VSS source:       VSS (vss 0) vsource dc=0 mag=1 phase=0 type=sine
```

If you automate the edits with `sed`, match the exact netlist names from your
own file and keep a `.pre_psrr_minus` backup.

Example OCEAN expressions:

```lisp
vssWave = v("/vss")
supplyGainWave = v("/vout") / vssWave
directPsrrMinusWave = vssWave / v("/vout")
```

Run PSRR-:

```bash
set -o pipefail
ocean -nograph -restore psrr_minus_sweep.ocn 2>&1 | tee psrr_minus_sweep_run.log
run_status=${PIPESTATUS[0]}
echo "OCEAN_EXIT_STATUS=$run_status"
```

Check the log and raw data:

```bash
grep -nEi 'ERROR|FATAL|SYNTAX|Segmentation|SPECTRE-|PSRR- AC sweep completed' \
psrr_minus_sweep_run.log
```

```bash
if [ -s /home/<linux-user>/simulation/<ota-project>_ocean/ac_psrr_minus/psrr_minus_raw.txt ]; then
    echo "PSRR_MINUS_RAW_VERIFIED"
else
    echo "ERROR: PSRR_MINUS_RAW_MISSING"
fi
```

## 6. PSRR Post-Processing

Run the PSRR+ analyzer:

```bash
awk \
  -v combined="/home/<linux-user>/simulation/<ota-project>_ocean/ac_psrr_plus/psrr_plus_combined_raw.txt" \
  -f analyze_psrr_plus_v1.awk \
  /home/<linux-user>/simulation/<ota-project>_ocean/ac_openloop/ac_gain_raw.txt \
  /home/<linux-user>/simulation/<ota-project>_ocean/ac_psrr_plus/psrr_plus_raw.txt \
  | tee /home/<linux-user>/simulation/<ota-project>_ocean/ac_psrr_plus/psrr_plus_analysis.txt
```

Run the PSRR- analyzer:

```bash
awk \
  -v combined="/home/<linux-user>/simulation/<ota-project>_ocean/ac_psrr_minus/psrr_minus_combined_raw.txt" \
  -f analyze_psrr_minus_v1.awk \
  /home/<linux-user>/simulation/<ota-project>_ocean/ac_openloop/ac_gain_raw.txt \
  /home/<linux-user>/simulation/<ota-project>_ocean/ac_psrr_minus/psrr_minus_raw.txt \
  | tee /home/<linux-user>/simulation/<ota-project>_ocean/ac_psrr_minus/psrr_minus_analysis.txt
```

Both analyzers should confirm:

```text
DIFFERENTIAL_NUMERIC_POINTS=1101
PSRR_*_NUMERIC_POINTS=1101
FREQUENCY_GRID=VERIFIED
```

## 7. Example PSRR+ Results

Example formal input-referred PSRR+ results:

```text
LOW_FREQUENCY_FORMAL_PSRR_PLUS=31.452236 V/V
LOW_FREQUENCY_FORMAL_PSRR_PLUS=29.953026 dB
PSRR_PLUS_3DB_BANDWIDTH=185.697346 MHz
PSRR_PLUS_20DB_BANDWIDTH=553.847737 MHz
PSRR_PLUS_10DB_BANDWIDTH=1.802096 GHz
PSRR_PLUS_0DB_CROSSING=5.392464 GHz
MINIMUM_PSRR_PLUS_1HZ_TO_UGF=15.725680 dB
PSRR_PLUS_AT_NEAREST_UGF=15.530523 dB
```

Spot values:

```text
1 Hz:       29.953026 dB
1 kHz:      29.953026 dB
1 MHz:      29.952903 dB
10 MHz:     29.940518 dB
100 MHz:    28.852231 dB
1 GHz:      15.138914 dB
10 GHz:     -5.574950 dB
100 GHz:   -22.029000 dB
```

## 8. Example PSRR- Results

Example formal input-referred PSRR- results:

```text
LOW_FREQUENCY_FORMAL_PSRR_MINUS=31.458994 V/V
LOW_FREQUENCY_FORMAL_PSRR_MINUS=29.954892 dB
PSRR_MINUS_3DB_BANDWIDTH=59.132436 MHz
PSRR_MINUS_20DB_BANDWIDTH=176.984285 MHz
PSRR_MINUS_10DB_BANDWIDTH=594.338332 MHz
PSRR_MINUS_0DB_CROSSING=2.186329 GHz
MINIMUM_PSRR_MINUS_1HZ_TO_UGF=6.268900 dB
PSRR_MINUS_AT_NEAREST_UGF=6.082411 dB
```

Spot values:

```text
1 Hz:       29.954892 dB
1 kHz:      29.954892 dB
1 MHz:      29.953658 dB
10 MHz:     29.832983 dB
100 MHz:    24.106233 dB
1 GHz:       5.711071 dB
10 GHz:     -2.456120 dB
100 GHz:   -11.361810 dB
```

## 9. PSRR+ and PSRR- Comparison

Example comparison:

| Metric | PSRR+ | PSRR- |
| --- | ---: | ---: |
| Low-frequency formal PSRR | 29.953 dB | 29.955 dB |
| 3 dB bandwidth | 185.697 MHz | 59.132 MHz |
| 20 dB bandwidth | 553.848 MHz | 176.984 MHz |
| 10 dB bandwidth | 1.802 GHz | 594.338 MHz |
| 0 dB crossing | 5.392 GHz | 2.186 GHz |
| Formal PSRR at 100 MHz | 28.852 dB | 24.106 dB |
| Formal PSRR near UGF | 15.531 dB | 6.082 dB |
| Formal PSRR at 1 GHz | 15.139 dB | 5.711 dB |

## 10. Engineering Interpretation

Example interpretation:

1. Low-frequency PSRR+ and PSRR- are almost identical; the difference is only
   about `0.0019 dB`.
2. Low-frequency supply-to-output gain is close to `1 V/V` on both rails. The
   output nearly follows low-frequency supply ripple, so formal PSRR near
   `30 dB` mainly comes from differential open-loop gain, not from strong
   supply-path isolation.
3. PSRR- has only about one third of the PSRR+ 3 dB bandwidth, so negative-rail
   coupling degrades earlier in the mid/high-frequency range.
4. At 100 MHz, PSRR- is about `4.75 dB` lower than PSRR+. Near UGF, PSRR- is
   about `9.45 dB` lower.
5. For high-speed operation, negative-rail cleanliness is more critical than
   positive-rail cleanliness in this example.
6. Formal PSRR becomes negative above UGF. Those very-high-frequency values are
   useful for curve-continuity checks, but they should not be treated as the
   normal closed-loop operating-range specification.
7. For precision-grade supply rejection, about `30 dB` low-frequency PSRR is not
   enough. For a basic high-speed OTA, acceptability still depends on real
   supply ripple, closed-loop noise gain, and signal bandwidth.

## 11. Improvement Directions

Common ways to improve PSRR:

1. Increase the output resistance of the PM active load and NM tail-current
   source.
2. Use cascodes or regulated-cascode bias structures if headroom allows it.
3. Add appropriate VDD, VSS, and bias-node decoupling, then include realistic
   package and PCB impedance in system-level evaluation.
4. If the bias voltage is generated by a VSS-referenced circuit, run a separate
   tracking-bias PSRR- analysis.
5. Improve supply routing, guarding, substrate isolation, and layout symmetry.
6. After sizing or topology changes, re-run DC operating point, VCM, VID, AC,
   STB, transient, noise, CMRR, and both PSRR simulations.

## 12. Common Errors and Guardrails

Do not copy only one netlist file:

```text
OCEAN design flow may also need netlistHeader, amap, and other Cadence
netlist-directory files.
```

If OCEAN shows this prompt:

```text
>
```

you are still inside the OCEAN parser. Exit first:

```lisp
exit()
```

Then run shell commands such as `PIPESTATUS`, `grep`, or `awk`.

Save `PIPESTATUS` immediately after the pipeline finishes and the shell prompt
returns.

An OCEAN completion `printf` is not proof of success. Real success requires:

```text
Raw file exists
Raw file is not empty
Numeric point count is correct
Frequency grid matches the differential AC run
Log has no fatal error
```

When checking that the PSRR- analyzer does not accidentally contain PSRR+
variables, avoid broad patterns such as `grep -E 'plus|\+'`, because that also
matches normal AWK arithmetic operators. Use exact names:

```bash
grep -nE 'psrr_plus|psrrPlus|PSRR_PLUS|PSRR\+' analyze_psrr_minus_v1.awk
```

The expected result is no output.

## 13. Working Checkpoints

Save PSRR+ artifacts after verification:

```bash
cd /home/<linux-user>/cadence_projects/<ota-project> || exit 1
stamp=$(date +%Y%m%d_%H%M%S)

cp -p -- psrr_plus_sweep.ocn "psrr_plus_sweep.ocn.working_$stamp"
cp -p -- analyze_psrr_plus_v1.awk "analyze_psrr_plus_v1.awk.working_$stamp"
cp -p -- \
  /home/<linux-user>/simulation/<ota-project>_psrr_plus/spectre/schematic/netlist/netlist \
  "/home/<linux-user>/simulation/<ota-project>_psrr_plus/spectre/schematic/netlist/netlist.working_$stamp"
```

Save PSRR- artifacts after verification:

```bash
cp -p -- psrr_minus_sweep.ocn "psrr_minus_sweep.ocn.working_$stamp"
cp -p -- analyze_psrr_minus_v1.awk "analyze_psrr_minus_v1.awk.working_$stamp"
cp -p -- \
  /home/<linux-user>/simulation/<ota-project>_psrr_minus/spectre/schematic/netlist/netlist \
  "/home/<linux-user>/simulation/<ota-project>_psrr_minus/spectre/schematic/netlist/netlist.working_$stamp"
```

Verify with `sha256sum` or `cmp -s` and keep matching hashes in private lab
notes, not in a public tutorial.

## 14. Completion Status

```text
[x] Independent PSRR+ netlist directory created and verified.
[x] PSRR+ AC sweep completed.
[x] PSRR+ 1101 numeric points verified.
[x] Formal and direct PSRR+ analysis completed.
[x] PSRR+ working checkpoints created and verified.
[x] Independent PSRR- local-VSS netlist directory created and verified.
[x] PSRR- AC sweep completed.
[x] PSRR- 1101 numeric points verified.
[x] PSRR- and differential AC frequency grids verified.
[x] Formal and direct PSRR- analysis completed.
[x] PSRR+ and PSRR- analysis and combined raw data saved.
[x] PSRR- working checkpoints created and verified.
```

## 15. Next Step

PSRR baseline characterization is complete. The next useful artifact is an
integrated baseline summary table covering DC, AC, STB, transient, noise, CMRR,
and PSRR. Use that table to plan PVT corners, load sweep, VCM-dependent PSRR,
and Monte Carlo analysis.
