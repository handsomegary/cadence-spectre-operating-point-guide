# Chapter 6: Open-Loop Noise Automation

This chapter documents a reusable open-loop noise automation workflow for a
five-transistor OTA in Cadence Virtuoso, Spectre, and OCEAN.

The source notes contained local paths, project names, script checkpoint names,
and one-run debug history. This public version keeps the engineering method and
uses placeholders for private environment details.

## 1. Scope

This workflow covers:

1. Open-loop noise testbench checks
2. OCEAN noise simulation setup
3. Output-noise raw export validation
4. Differential input-referred noise calculation
5. White-noise floor estimation
6. 1/f noise corner extraction
7. Integrated RMS output and input-referred noise
8. Working checkpoints
9. Common errors and safe interpretation

The commands are intended for a remote Linux Cadence environment accessed from
MobaXterm or another SSH terminal.

## 2. Testbench and Differential Input

The open-loop AC/noise testbench uses two input sources:

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

For this differential source setup, avoid treating only one input source as the
complete input probe. Instead:

```text
Input-referred noise density =
Output noise density / differential open-loop gain magnitude
```

Use the differential gain from the open-loop AC result at the same frequency
grid.

## 3. When to Reopen the Schematic

If the schematic, device sizes, wiring, load, supply, bias, and source
properties have not changed, reuse the existing verified netlist.

Return to Virtuoso when any of these change:

1. MOS width, length, or multiplier
2. Load capacitor or any output loading
3. Supply, bias, or input source settings
4. Feedback or other wiring
5. Added noise probe, port, or component

After schematic edits, run **Check and Save**, recreate the netlist, and only
then run OCEAN.

## 4. Noise Analysis Setup

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
Output noise unit:       V/sqrt(Hz)
```

Noise analysis block:

```lisp
analysis('noise
    ?start "1"
    ?stop "100G"
    ?dec "100"
    ?p "/vout"
    ?n ""
    ?oprobe ""
    ?iprobe ""
)
```

Read the output-noise waveform:

```lisp
outNoise = getData("out" ?result "noise")
```

## 5. Standard Execution Flow

Enter the Cadence project directory:

```bash
cd /home/<linux-user>/cadence_projects/<ota-project> || exit 1
```

Confirm scripts exist:

```bash
ls -lh noise_openloop.ocn analyze_noise_v2.awk
```

Check important OCEAN settings:

```bash
grep -nE 'simulator|design|resultsDir|modelFile|desVar|analysis|start|stop|dec|iprobe|getData' \
noise_openloop.ocn
```

Confirm no unexpected Cadence or Spectre process is still running:

```bash
pgrep -af 'virtuoso|ocean|spectre|cdsMsgServer'
```

Run noise simulation:

```bash
set -o pipefail
ocean -nograph -restore noise_openloop.ocn 2>&1 | tee noise_openloop_run.log
run_status=${PIPESTATUS[0]}
echo "OCEAN_EXIT_STATUS=$run_status"
```

## 6. Success Criteria

Do not rely only on OCEAN exit status or a printed completion message. Verify
that the raw file exists and contains data:

```bash
grep -nEi 'ERROR|FATAL|SYNTAX|Segmentation|SPECTRE-|noise analysis completed' \
noise_openloop_run.log
```

```bash
if [ -s /home/<linux-user>/simulation/<ota-project>_ocean/noise_openloop/output_noise_raw.txt ]; then
    echo "NOISE_RAW_VERIFIED"
else
    echo "ERROR: NOISE_RAW_MISSING"
fi
```

```bash
wc -l /home/<linux-user>/simulation/<ota-project>_ocean/noise_openloop/output_noise_raw.txt
head -8 /home/<linux-user>/simulation/<ota-project>_ocean/noise_openloop/output_noise_raw.txt
tail -5 /home/<linux-user>/simulation/<ota-project>_ocean/noise_openloop/output_noise_raw.txt
```

Example checkpoint:

```text
OCEAN_EXIT_STATUS=0
NOISE_RAW_VERIFIED
File lines=1104
Numeric points=1101
Frequency start=1 Hz
Frequency stop=100 GHz
```

The extra lines are headers or blank formatting rows.

## 7. Post-Processing Inputs

The analyzer uses:

```text
Open-loop AC gain:
/home/<linux-user>/simulation/<ota-project>_ocean/ac_openloop/ac_gain_raw.txt

Output noise:
/home/<linux-user>/simulation/<ota-project>_ocean/noise_openloop/output_noise_raw.txt
```

Both files should have the same numeric frequency grid. Verify this before
dividing output noise by gain.

Run the analyzer and save both the combined per-frequency data and the final
report:

```bash
cd /home/<linux-user>/cadence_projects/<ota-project> || exit 1
awk \
  -v combined="/home/<linux-user>/simulation/<ota-project>_ocean/noise_openloop/noise_combined_raw.txt" \
  -f analyze_noise_v2.awk \
  /home/<linux-user>/simulation/<ota-project>_ocean/ac_openloop/ac_gain_raw.txt \
  /home/<linux-user>/simulation/<ota-project>_ocean/noise_openloop/output_noise_raw.txt \
  | tee /home/<linux-user>/simulation/<ota-project>_ocean/noise_openloop/noise_analysis_final.txt
```

Check key lines:

```bash
grep -E 'FREQUENCY_GRID|UNITY_GAIN|WHITE_NOISE|FLICKER_NOISE' \
/home/<linux-user>/simulation/<ota-project>_ocean/noise_openloop/noise_analysis_final.txt
```

## 8. White-Noise Floor and 1/f Corner

Choose the white-noise estimation band from a flat region of the
input-referred noise curve. A low-frequency band can still be dominated by
flicker noise and overestimate the white floor.

Example source workflow:

```text
Bad first estimate band:       1 MHz to 10 MHz
Reason:                        noise was still falling with frequency
Refined white-noise band:      100 MHz to 400 MHz
Points in refined band:        61
```

Example refined result:

```text
Input-referred white-noise floor: 7.4005 nV/sqrt(Hz)
1/f noise corner:                 13.8629 MHz
```

The corner definition used here:

```text
Input-referred noise amplitude reaches sqrt(2) times the white-noise floor.
```

This is equivalent to the total noise power spectral density being twice the
white-noise PSD.

## 9. Example Noise Results

Example source checkpoint:

```text
AC_NUMERIC_POINTS=1101
NOISE_NUMERIC_POINTS=1101
FREQUENCY_GRID=VERIFIED
FREQUENCY_START=1 Hz
FREQUENCY_STOP=100 GHz
DC_GAIN=31.434620 V/V
DC_GAIN=29.948160 dB
UNITY_GAIN_FREQUENCY=949.525439 MHz
INPUT_REFERRED_WHITE_NOISE_FLOOR=7.4005 nV/sqrt(Hz)
FLICKER_NOISE_CORNER=13.8629 MHz
```

Input-referred spot noise examples:

```text
1 Hz:      58.9052 uV/sqrt(Hz)
10 Hz:     15.7811 uV/sqrt(Hz)
100 Hz:    4.27035 uV/sqrt(Hz)
1 kHz:     1.17402 uV/sqrt(Hz)
10 kHz:    330.507 nV/sqrt(Hz)
100 kHz:   96.2628 nV/sqrt(Hz)
1 MHz:     29.8152 nV/sqrt(Hz)
10 MHz:    11.5036 nV/sqrt(Hz)
100 MHz:   7.64716 nV/sqrt(Hz)
1 GHz:     7.37774 nV/sqrt(Hz)
```

Integrated output noise examples:

```text
1 Hz to 1 kHz:    3.89587 mV RMS
1 Hz to 10 kHz:   4.23829 mV RMS
1 Hz to 100 kHz:  4.49883 mV RMS
1 Hz to 1 MHz:    4.71934 mV RMS
1 Hz to 10 MHz:   4.95443 mV RMS
1 Hz to 100 MHz:  5.20139 mV RMS
1 Hz to UGF:      5.24821 mV RMS
1 Hz to 100 GHz:  5.25221 mV RMS
```

Integrated input-referred noise examples:

```text
1 Hz to 1 kHz:    123.936 uV RMS
1 Hz to 10 kHz:   134.829 uV RMS
1 Hz to 100 kHz:  143.117 uV RMS
1 Hz to 1 MHz:    150.133 uV RMS
1 Hz to 10 MHz:   157.775 uV RMS
1 Hz to 100 MHz:  176.956 uV RMS
1 Hz to UGF:      276.975 uV RMS
```

## 10. Engineering Interpretation

Example interpretation:

1. The 100 MHz to 400 MHz band forms a stable input-referred white-noise
   plateau near `7.4 nV/sqrt(Hz)`.
2. The 1 GHz spot noise is close to the refined white-noise floor, supporting
   the floor estimate.
3. A 1/f corner near `13.86 MHz` means a wide low-frequency range is still
   flicker-noise dominated.
4. For low-frequency, DC, or precision-amplifier applications, flicker noise may
   be a major limitation.
5. If the real system has a high-pass response, calculate band-limited
   integrated noise using the actual signal bandwidth.
6. Open-loop output-referred integrated noise is not automatically the final
   closed-loop system output noise. Closed-loop noise requires the noise gain,
   feedback network, and real signal bandwidth.
7. Do not identify a dominant device before reading a device noise contribution
   summary.

## 11. Working Checkpoints

Create and verify checkpoints for both the OCEAN script and analyzer:

```bash
cd /home/<linux-user>/cadence_projects/<ota-project> || exit 1
cp -p noise_openloop.ocn noise_openloop.ocn.working_YYYYMMDD_HHMMSS
cp -p analyze_noise_v2.awk analyze_noise_v2.awk.working_YYYYMMDD_HHMMSS
```

Verify byte-for-byte:

```bash
cmp -s -- noise_openloop.ocn noise_openloop.ocn.working_YYYYMMDD_HHMMSS && \
echo "OCEAN_CHECKPOINT_VERIFIED"
```

```bash
cmp -s -- analyze_noise_v2.awk analyze_noise_v2.awk.working_YYYYMMDD_HHMMSS && \
echo "ANALYZER_CHECKPOINT_VERIFIED"
```

## 12. Common Errors and Fixes

`OCN-6004: ocean session was not created`:

```text
Likely cause: the OCEAN script only contains the analysis tail and is missing
simulator, design, resultsDir, modelFile, and desVar setup.

Effect: Spectre did not run and no raw file was generated. Existing AC, STB, or
transient results are not damaged.

Fix: copy the verified header from a working AC script, then append the noise
analysis block.
```

`OCEAN_EXIT_STATUS=0` but raw file is missing:

```text
A script can still print a completion message and exit after an earlier command
failed. Verify success with test -s, line count, frequency start, and frequency
stop.
```

AWK function parameter named `index`:

```text
index is a built-in AWK function name. Rename the custom parameter, for example
to spotIndex.
```

`FLICKER_NOISE_CORNER=NOT_FOUND`:

```text
The white-noise estimation band may not be in the flat white-noise region.
Move the estimation band to a confirmed plateau and rerun the analyzer.
```

`SPECTRE-17101`:

```text
This is a future-compatibility warning about checklimitdest=psf. It is not a
noise-convergence error and does not invalidate the raw data by itself.
```

## 13. Completion Checklist

```text
[ ] Differential source and input normalization confirmed.
[ ] Output node and load capacitance confirmed.
[ ] Independent noise results directory created.
[ ] Noise OCEAN script created and verified.
[ ] Noise simulation completed over the intended frequency range.
[ ] Output noise raw file saved.
[ ] Numeric point count and frequency range verified.
[ ] AC/noise frequency grid verified.
[ ] Input-referred spot noise calculated.
[ ] Integrated RMS noise calculated.
[ ] White-noise floor refined from a flat band.
[ ] 1/f noise corner extracted.
[ ] Final analysis report saved.
[ ] OCEAN working checkpoint created.
[ ] Analyzer working checkpoint created.
[ ] Device noise contribution summary collected.
[ ] Closed-loop integrated noise calculated for the real application bandwidth.
```

## 14. Next Step

The next useful noise sub-analysis is device noise contribution ranking:

```text
Input pair contribution
Current mirror load contribution
Tail device contribution
Other bias or load contribution
```

Only after device contribution ranking should you decide whether to increase
input-pair area, adjust the current mirror, modify the bias device, or change
the operating current. After noise, continue with CMRR and PSRR automation.
