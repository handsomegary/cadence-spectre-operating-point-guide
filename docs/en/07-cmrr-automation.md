# Chapter 7: CMRR Automation

This chapter documents a reusable common-mode rejection ratio, or CMRR,
automation workflow for a five-transistor OTA in Cadence Virtuoso, Spectre, and
OCEAN.

The source notes contained local paths, project names, net names, and one-run
debug history. This public version keeps the engineering method and uses
placeholders for private environment details.

## 1. Scope

This workflow covers:

1. Differential-mode versus common-mode excitation
2. Creating a complete common-mode netlist copy
3. Common-mode AC OCEAN setup
4. Common-mode raw export validation
5. CMRR post-processing from differential and common-mode gain
6. Bandwidth and spot-value extraction
7. Engineering interpretation
8. Common errors and safe recovery
9. Working checkpoints

The commands are intended for a remote Linux Cadence environment accessed from
MobaXterm or another SSH terminal.

## 2. CMRR Definition

Use the open-loop differential gain and common-mode gain at the same frequency:

```text
CMRR(f) = |Ad(f)| / |Acm(f)|
CMRR_dB(f) = 20 log10(CMRR(f))
CMRR_dB(f) = Ad_dB(f) - Acm_dB(f)
```

`Ad` is the differential-mode gain. `Acm` is the common-mode gain.

Both curves must use the same frequency grid before subtraction or division.

## 3. Differential and Common-Mode Excitation

The existing differential AC testbench uses two opposite-phase input sources:

```text
Vin+ DC value:       VCM + VID/2
Vin- DC value:       VCM - VID/2

Vin+ AC magnitude:   0.5
Vin+ AC phase:       0 deg

Vin- AC magnitude:   0.5
Vin- AC phase:       180 deg
```

Therefore:

```text
Vin,diff = V(vinp) - V(vinn) = 1 V
```

For common-mode AC, create a copied netlist and change only the negative input
source phase:

```text
Vin+ AC magnitude:   0.5
Vin+ AC phase:       0 deg

Vin- AC magnitude:   0.5
Vin- AC phase:       0 deg
```

The common-mode input is:

```text
Vin,cm = (V(vinp) + V(vinn)) / 2 = 0.5 V
```

In the OCEAN script, divide output voltage by the actual common-mode input
waveform. That avoids gain-normalization mistakes caused by the `0.5 V`
excitation amplitude.

## 4. Create a Complete Common-Mode Netlist Copy

Do not copy only the single `netlist` file. The Cadence OCEAN design flow may
also need `netlistHeader`, `amap`, and other generated files in the same
directory.

Create the common-mode netlist directory:

```bash
mkdir -p /home/<linux-user>/simulation/<ota-project>_cmrr/spectre/schematic/netlist
```

Copy the full differential netlist directory:

```bash
cp -a \
  /home/<linux-user>/simulation/<ota-project>/spectre/schematic/netlist/. \
  /home/<linux-user>/simulation/<ota-project>_cmrr/spectre/schematic/netlist/
```

Modify only the copied negative-input source phase:

```bash
sed -i '/^VMINUS .* vsource / s/phase=180/phase=0/' \
  /home/<linux-user>/simulation/<ota-project>_cmrr/spectre/schematic/netlist/netlist
```

Adjust the `sed` pattern to match the actual source name in your netlist.

Verify required files:

```bash
test -f /home/<linux-user>/simulation/<ota-project>_cmrr/spectre/schematic/netlist/netlistHeader && \
echo "NETLIST_HEADER_VERIFIED"
```

```bash
test -d /home/<linux-user>/simulation/<ota-project>_cmrr/spectre/schematic/netlist/amap && \
echo "AMAP_VERIFIED"
```

Verify the copied input sources:

```bash
grep -nE '^V.* vsource ' \
  /home/<linux-user>/simulation/<ota-project>_cmrr/spectre/schematic/netlist/netlist
```

## 5. Common-Mode AC Setup

Example nominal setup:

```text
Process corner:          <process-corner>
Temperature:             27 deg C
VCM:                     800 mV
VID:                     0 V
Output node:             /vout
Load capacitance:        100 fF
Frequency start:         1 Hz
Frequency stop:          100 GHz
Sweep density:           100 points per decade
Expected numeric points: 1101
```

Common-mode gain expression:

```lisp
vcmWave = (v("/vinp") + v("/vinn")) / 2
cmGainWave = v("/vout") / vcmWave
```

Save the common-mode gain raw data to:

```text
/home/<linux-user>/simulation/<ota-project>_ocean/ac_commonmode/cm_gain_raw.txt
```

## 6. Standard Execution Flow

Enter the Cadence project directory:

```bash
cd /home/<linux-user>/cadence_projects/<ota-project> || exit 1
```

Run the common-mode AC sweep:

```bash
set -o pipefail
ocean -nograph -restore cmrr_sweep.ocn 2>&1 | tee cmrr_sweep_run.log
run_status=${PIPESTATUS[0]}
echo "OCEAN_EXIT_STATUS=$run_status"
```

Read `PIPESTATUS` only after returning to the Linux shell prompt.

Verify the raw file:

```bash
if [ -s /home/<linux-user>/simulation/<ota-project>_ocean/ac_commonmode/cm_gain_raw.txt ]; then
    echo "COMMON_MODE_RAW_VERIFIED"
else
    echo "ERROR: COMMON_MODE_RAW_MISSING"
fi
```

```bash
wc -l /home/<linux-user>/simulation/<ota-project>_ocean/ac_commonmode/cm_gain_raw.txt
```

Example checkpoint:

```text
OCEAN_EXIT_STATUS=0
COMMON_MODE_RAW_VERIFIED
File lines=1104
Numeric points=1101
```

## 7. CMRR Post-Processing

Analyzer inputs:

```text
Differential open-loop gain:
/home/<linux-user>/simulation/<ota-project>_ocean/ac_openloop/ac_gain_raw.txt

Common-mode gain:
/home/<linux-user>/simulation/<ota-project>_ocean/ac_commonmode/cm_gain_raw.txt
```

Run the analyzer:

```bash
awk \
  -v combined="/home/<linux-user>/simulation/<ota-project>_ocean/ac_commonmode/cmrr_combined_raw.txt" \
  -f analyze_cmrr_v1.awk \
  /home/<linux-user>/simulation/<ota-project>_ocean/ac_openloop/ac_gain_raw.txt \
  /home/<linux-user>/simulation/<ota-project>_ocean/ac_commonmode/cm_gain_raw.txt \
  | tee /home/<linux-user>/simulation/<ota-project>_ocean/ac_commonmode/cmrr_analysis.txt
```

Verify output files:

```bash
ls -lh \
  /home/<linux-user>/simulation/<ota-project>_ocean/ac_commonmode/cmrr_analysis.txt \
  /home/<linux-user>/simulation/<ota-project>_ocean/ac_commonmode/cmrr_combined_raw.txt
```

## 8. Example CMRR Results

Example source checkpoint:

```text
DIFFERENTIAL_NUMERIC_POINTS=1101
COMMON_MODE_NUMERIC_POINTS=1101
FREQUENCY_GRID=VERIFIED
FREQUENCY_START=1 Hz
FREQUENCY_STOP=100 GHz

LOW_FREQUENCY_DIFFERENTIAL_GAIN=31.434620 V/V
LOW_FREQUENCY_DIFFERENTIAL_GAIN=29.948160 dB
LOW_FREQUENCY_COMMON_MODE_GAIN=0.04026189 V/V
LOW_FREQUENCY_COMMON_MODE_GAIN=-27.902110 dB
LOW_FREQUENCY_CMRR=780.753710 V/V
LOW_FREQUENCY_CMRR=57.850270 dB

DIFFERENTIAL_UNITY_GAIN_FREQUENCY=949.525439 MHz
CMRR_3DB_BANDWIDTH=58.853855 MHz
CMRR_40DB_BANDWIDTH=414.847335 MHz
CMRR_20DB_BANDWIDTH=2.049543 GHz
CMRR_0DB_CROSSING=24.755596 GHz

MINIMUM_CMRR_1HZ_TO_UGF=30.762290 dB
MINIMUM_CMRR_FREQUENCY=933.254300 MHz
MAXIMUM_CMRR_1HZ_TO_UGF=57.850270 dB
MAXIMUM_CMRR_FREQUENCY=1 Hz
CMRR_AT_NEAREST_UGF=30.465873 dB
```

Spot values:

```text
1 Hz:     57.850270 dB
1 kHz:    57.850270 dB
1 MHz:    57.849030 dB
10 MHz:   57.727760 dB
100 MHz:  51.942680 dB
1 GHz:    29.867804 dB
10 GHz:    3.725720 dB
```

## 9. Engineering Interpretation

Example interpretation:

1. CMRR is almost flat from 1 Hz to about 10 MHz, so low-frequency common-mode
   rejection is stable.
2. Low-frequency CMRR is `57.85 dB`, or about `780.8 V/V`. This is reasonable
   for a basic five-transistor OTA, but it is not a precision high-CMRR
   amplifier result.
3. The 3 dB CMRR bandwidth is about `58.85 MHz`.
4. CMRR is still `51.94 dB` at 100 MHz, so mid-frequency common-mode rejection
   remains useful.
5. CMRR stays above `40 dB` until about `414.85 MHz`.
6. The differential unity-gain frequency is about `949.5 MHz`; near UGF, CMRR is
   about `30.5 dB`, or about 33x rejection.
7. The high-frequency CMRR drop mainly comes from differential-gain roll-off,
   not from a sudden common-mode gain instability.
8. Results far above UGF should not be treated as the normal closed-loop
   operating region, but they are useful for checking curve continuity.
9. Whether the result is acceptable depends on the specification. For a general
   high-speed OTA it may be acceptable; for low-frequency precision use, about
   `57.85 dB` usually needs improvement.

## 10. CMRR Improvement Directions

Common ways to improve CMRR:

1. Increase the output resistance of the NM tail current source.
2. Increase tail-device channel length, then re-check headroom, bias current,
   and speed.
3. Improve NM input-pair matching and layout symmetry.
4. Improve PM current-mirror matching.
5. If the topology allows it, use a cascoded tail source or another
   higher-output-resistance bias structure.
6. After sizing or topology changes, re-run DC VCM, VID, AC, STB, transient,
   noise, and CMRR.

## 11. Common Error and Fix

Example error:

```text
netlistHeader file not found
amap directory is missing
```

Likely cause:

```text
Only the single netlist file was copied. The complete Cadence netlist directory
was not copied.
```

Effect:

```text
Spectre did not really run. Existing AC, noise, transient, and other results are
not damaged by this failed common-mode attempt.
```

Fix:

```bash
cp -a source_netlist_directory/. destination_netlist_directory/
```

Then modify only the copied input-source phase.

If a script error leaves you at the OCEAN prompt:

```text
>
```

Exit OCEAN first:

```lisp
exit()
```

Return to the Linux shell prompt before running shell commands such as
`PIPESTATUS`, `grep`, or `awk`.

## 12. Working Checkpoints

Save the OCEAN script, analyzer, and common-mode netlist copy:

```bash
cd /home/<linux-user>/cadence_projects/<ota-project> || exit 1
stamp=$(date +%Y%m%d_%H%M%S)

cp -p -- cmrr_sweep.ocn "cmrr_sweep.ocn.working_$stamp"
cp -p -- analyze_cmrr_v1.awk "analyze_cmrr_v1.awk.working_$stamp"
cp -p -- \
  /home/<linux-user>/simulation/<ota-project>_cmrr/spectre/schematic/netlist/netlist \
  "/home/<linux-user>/simulation/<ota-project>_cmrr/spectre/schematic/netlist/netlist.working_$stamp"
```

## 13. Completion Status

```text
[x] Independent common-mode netlist directory created.
[x] Original differential netlist preserved.
[x] Vin+ and Vin- common-mode phase verified.
[x] Common-mode AC sweep completed.
[x] 1101 numeric points verified.
[x] Differential/common-mode frequency grid verified.
[x] Full CMRR curve calculated.
[x] Low-frequency CMRR calculated.
[x] 3 dB, 40 dB, 20 dB, and 0 dB bandwidths calculated.
[x] CMRR near UGF calculated.
[x] Formal analysis and combined raw files saved.
[ ] Working checkpoints created and verified.
```

## 14. Next Step

CMRR baseline characterization is complete. After creating and verifying
checkpoints, continue with [Chapter 8: PSRR Automation](08-psrr-automation.md).
