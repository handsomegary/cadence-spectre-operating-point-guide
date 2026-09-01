# Chapter 5: Closed-Loop Transient Automation

This chapter documents a reusable closed-loop transient automation workflow for
Cadence Virtuoso, Spectre, and OCEAN.

The source notes contained local project paths, working checkpoint names, and
case-specific logs. This public version keeps the engineering method and
replaces private environment details with placeholders.

## 1. Scope

This workflow covers:

1. Small-signal closed-loop transient, such as a 10 mV input step
2. Large-signal closed-loop transient, such as a 100 mV input step
3. Slew-rate ceiling checks, such as a 140 mV input step
4. Separation between OCEAN scripts, Spectre results, raw waveform exports, and
   post-processing reports
5. Pre-run checks, execution, validation, AWK analysis, and working checkpoints
6. Safe interpretation of common command and post-processing errors

These commands are intended to run on the remote Linux host through MobaXterm or
another SSH terminal. Do not assume the Windows machine can directly access the
remote Linux file system.

## 2. Directory Responsibilities

Keep OCEAN scripts in the Cadence project directory. Keep PSF data, raw exports,
and analysis reports in simulation result directories.

Example layout:

```text
Cadence project and OCEAN scripts:
/home/<linux-user>/cadence_projects/<ota-project>

OCEAN result root:
/home/<linux-user>/simulation/<ota-project>_ocean

10 mV transient results:
/home/<linux-user>/simulation/<ota-project>_ocean/tran_small

100 mV transient results:
/home/<linux-user>/simulation/<ota-project>_ocean/tran_large

140 mV slew-ceiling transient results:
/home/<linux-user>/simulation/<ota-project>_ocean/tran_slew_140m
```

Typical scripts:

```text
tran_small.ocn
tran_large.ocn
tran_slew_140m.ocn
analyze_tran_140m.awk
```

Do not look for original `.ocn` scripts inside the simulation result directory
unless you intentionally copied them there.

## 3. Overall Data Flow

The intended flow is:

```text
OCEAN script
  -> Spectre transient simulation
  -> PSF database
  -> ASCII raw waveform export
  -> AWK post-processing
  -> text analysis report
  -> engineering comparison and conclusion
```

OCEAN sets design variables, transient time settings, saved signals, and output
files. AWK reads an existing ASCII raw file and calculates metrics. AWK does not
modify the PSF database and does not rerun Spectre.

## 4. Pre-Run Checks

Enter the Cadence project directory:

```bash
cd /home/<linux-user>/cadence_projects/<ota-project> || exit 1
pwd
```

Confirm the transient scripts exist:

```bash
ls -lh tran_small.ocn tran_large.ocn tran_slew_140m.ocn
```

Check each script for result directory, step size, stop time, maximum time step,
and output file:

```bash
grep -nE 'resultsDir|VSTEP|stop|maxstep|output|transient completed' tran_small.ocn
grep -nE 'resultsDir|VSTEP|stop|maxstep|output|transient completed' tran_large.ocn
grep -nE 'resultsDir|VSTEP|stop|maxstep|output|transient completed' tran_slew_140m.ocn
```

Check for running Cadence or Spectre processes:

```bash
pgrep -af 'virtuoso|ocean|spectre|cdsMsgServer'
```

Do not start another simulation if you are unsure whether an existing process is
still writing to the same result directory.

## 5. OCEAN Execution Pattern

Run one transient case at a time and keep a separate log for each case.

The `pipefail` setting prevents `tee` from hiding an OCEAN failure:

```bash
set -o pipefail
```

Small-signal case:

```bash
cd /home/<linux-user>/cadence_projects/<ota-project> || exit 1
set -o pipefail
ocean -nograph -restore tran_small.ocn 2>&1 | tee tran_small_run.log
run_status=${PIPESTATUS[0]}
echo "OCEAN_EXIT_STATUS=$run_status"
```

Large-signal case:

```bash
cd /home/<linux-user>/cadence_projects/<ota-project> || exit 1
set -o pipefail
ocean -nograph -restore tran_large.ocn 2>&1 | tee tran_large_run.log
run_status=${PIPESTATUS[0]}
echo "OCEAN_EXIT_STATUS=$run_status"
```

Slew-ceiling case:

```bash
cd /home/<linux-user>/cadence_projects/<ota-project> || exit 1
set -o pipefail
ocean -nograph -restore tran_slew_140m.ocn 2>&1 | tee tran_slew_140m_run.log
run_status=${PIPESTATUS[0]}
echo "OCEAN_EXIT_STATUS=$run_status"
```

If a valid raw file already exists and the circuit or script has not changed,
do not rerun the simulation just to rerun post-processing.

## 6. Post-Run Validation

Do not trust a transient run only because the terminal did not show obvious red
text. Check all of these:

1. OCEAN/Spectre did not report a fatal error.
2. The expected raw file exists and is not empty.
3. The PSF directory exists.
4. The raw file contains a reasonable number of numeric rows.
5. Input and output steady-state values are plausible.
6. Step direction and transition timing match the intended test.

Example validation for a 140 mV case:

```bash
cd /home/<linux-user>/simulation/<ota-project>_ocean/tran_slew_140m || exit 1
ls -ld psf
ls -lh tran_slew_140m_raw.txt
wc -l tran_slew_140m_raw.txt
head -5 tran_slew_140m_raw.txt
tail -5 tran_slew_140m_raw.txt
```

Check the run log:

```bash
cd /home/<linux-user>/cadence_projects/<ota-project> || exit 1
grep -nEi 'ERROR|FATAL|SYNTAX|Segmentation|SPECTRE-' tran_slew_140m_run.log
tail -80 tran_slew_140m_run.log
```

The source workflow found a raw file with three header or nonnumeric rows plus
thousands of numeric data rows. Header rows are normal as long as the numeric
data count is reasonable.

## 7. Transient Metrics

Each transient case should save at least these metrics:

```text
PRE_RISE_VIN
HIGH_FINAL_VIN
POST_FALL_VIN
PRE_RISE_VOUT
HIGH_FINAL_VOUT
POST_FALL_VOUT
ACTUAL_INPUT_STEP
ACTUAL_RISE_STEP
ACTUAL_FALL_STEP
CLOSED_LOOP_GAIN
RISE_TIME_10_TO_90
FALL_TIME_90_TO_10
MAX_POSITIVE_SR_20PS
MAX_NEGATIVE_SR_20PS
MAX_POSITIVE_SR_50PS
MAX_NEGATIVE_SR_50PS
RISE_SETTLING_1PCT
RISE_SETTLING_0P1PCT
FALL_SETTLING_1PCT
FALL_SETTLING_0P1PCT
RISE_MAX
FALL_MIN
RISE_OVERSHOOT
FALL_UNDERSHOOT
```

Rise and fall time should use 10% and 90% thresholds based on the actual output
step, not the supply voltage and not the ideal commanded input level.

Settling bands should also use the actual output step and final output value,
especially when finite closed-loop gain creates a DC tracking error.

## 8. AWK Post-Processing

Use a persistent analyzer script instead of relying on `/tmp`, because `/tmp`
may be cleared after reboot.

If an analyzer was developed in `/tmp`, copy it into the project directory:

```bash
cd /home/<linux-user>/cadence_projects/<ota-project> || exit 1
cp -p -- /tmp/analyze_tran_140m.awk analyze_tran_140m.awk
cmp -s -- /tmp/analyze_tran_140m.awk analyze_tran_140m.awk && echo "ANALYZER_VERIFIED"
ls -lh analyze_tran_140m.awk
```

Run the analyzer from the result directory and save the report with `tee`:

```bash
cd /home/<linux-user>/simulation/<ota-project>_ocean/tran_slew_140m || exit 1
awk -f /home/<linux-user>/cadence_projects/<ota-project>/analyze_tran_140m.awk \
    tran_slew_140m_raw.txt | tee tran_slew_140m_analysis.txt
```

Verify the analysis report:

```bash
test -s tran_slew_140m_analysis.txt && echo "ANALYSIS_FILE_VERIFIED"
cat tran_slew_140m_analysis.txt
```

## 9. Working Checkpoint Pattern

Create checkpoints in the Cadence project directory where the OCEAN script
actually lives.

Use byte-by-byte verification:

```bash
cd /home/<linux-user>/cadence_projects/<ota-project> || exit 1
checkpoint="tran_slew_140m.ocn.working_$(date +%Y%m%d_%H%M%S)"
if cp -p -- tran_slew_140m.ocn "$checkpoint"; then
    if cmp -s -- tran_slew_140m.ocn "$checkpoint"; then
        echo "CHECKPOINT_VERIFIED"
        echo "SOURCE=$PWD/tran_slew_140m.ocn"
        echo "CHECKPOINT=$PWD/$checkpoint"
        ls -lh -- tran_slew_140m.ocn "$checkpoint"
    else
        echo "ERROR: The checkpoint does not match the source."
    fi
else
    echo "ERROR: Checkpoint creation failed."
fi
```

`cp -p` preserves timestamps, so the checkpoint may display the original
modification time. That is normal. The `cmp -s` result is the important proof.

## 10. Example Results

Example 100 mV transient checkpoint:

```text
CLOSED_LOOP_GAIN=0.965503 V/V
RISE_TIME_10_TO_90=300.717540 ps
FALL_TIME_90_TO_10=308.804621 ps
MAX_POSITIVE_SR_20PS=380.875000 V/us
MAX_NEGATIVE_SR_20PS=-349.280000 V/us
MAX_POSITIVE_SR_50PS=377.725000 V/us
MAX_NEGATIVE_SR_50PS=-347.208333 V/us
RISE_SETTLING_1PCT=0.509337 ns
RISE_SETTLING_0P1PCT=0.929337 ns
FALL_SETTLING_1PCT=0.497341 ns
FALL_SETTLING_0P1PCT=0.979341 ns
```

Example 140 mV transient checkpoint:

```text
ACTUAL_INPUT_STEP=140.000000 mV
ACTUAL_RISE_STEP=135.141600 mV
ACTUAL_FALL_STEP=135.141600 mV
CLOSED_LOOP_GAIN=0.965297 V/V
RISE_TIME_10_TO_90=304.685794 ps
FALL_TIME_90_TO_10=316.884457 ps
MAX_POSITIVE_SR_20PS=527.820000 V/us
MAX_NEGATIVE_SR_20PS=-467.490000 V/us
MAX_POSITIVE_SR_50PS=523.088000 V/us
MAX_NEGATIVE_SR_50PS=-464.868000 V/us
RISE_SETTLING_1PCT=0.520061 ns
RISE_SETTLING_0P1PCT=0.924061 ns
FALL_SETTLING_1PCT=0.506299 ns
FALL_SETTLING_0P1PCT=0.996299 ns
RISE_OVERSHOOT=0.21355 percent
FALL_UNDERSHOOT=0.50229 percent
```

The source notes also mention a completed 10 mV case. Use its own saved report
as the authority for exact numbers rather than copying unverified values into a
summary.

## 11. Slew-Rate Ceiling Interpretation

When comparing 100 mV and 140 mV cases, use the output step ratio, rise/fall
time ratio, and slew-rate ratio together.

Guidelines:

```text
Mostly linear behavior:
  Larger step produces roughly proportional slew-rate increase.
  Rise/fall time stays roughly similar.
  Settling time does not change dramatically.

Hard slew-rate ceiling:
  Slew rate stays near the smaller-step value.
  Rise/fall time increases roughly with step size.
```

Example source conclusion:

```text
HARD_SLEW_RATE_CEILING=NO
POSITIVE_PATH_COMPRESSION=MINIMAL
NEGATIVE_PATH_COMPRESSION=MILD
LARGE_SIGNAL_OPERATION_AT_140MV=ACCEPTABLE
```

If different slope windows were used, prefer the comparison with matching
actual windows. In the source workflow, the 20 ps window was the cleaner
comparison between 100 mV and 140 mV.

## 12. Common Error Interpretation

`awk` reports `unexpected newline`:

```text
The post-processing command has a syntax error.
The raw waveform and PSF data are not damaged by this.
Avoid breaking lines after <, >, <=, >=, &&, or ||.
```

`cp` reports `cannot stat`:

```text
The source path does not exist.
No checkpoint was created.
Confirm the location with pwd, ls, or find.
```

`sha256sum` reports `No such file`:

```text
The previous copy step probably failed, so the checkpoint file does not exist.
This does not affect the original script.
```

`echo` prints `Checkpoint saved`:

```text
echo only prints text.
It does not prove that cp succeeded.
Use if cp ...; then ... fi plus cmp -s.
```

One run failed, then a later run succeeded:

```text
Judge the final result by the final run log, PSF directory, raw file, numeric row count, and analysis report.
Do not reject a successful later result only because an older log contains errors.
```

## 13. Completion Checklist

For each transient case:

```text
[ ] OCEAN script is in the Cadence project directory.
[ ] Working checkpoint was created and verified before risky edits.
[ ] resultsDir points to the correct independent case directory.
[ ] VSTEP, stop time, and maxstep were checked.
[ ] OCEAN log was saved.
[ ] OCEAN exit status was checked.
[ ] PSF directory exists.
[ ] ASCII raw file exists and is nonempty.
[ ] Numeric row count is reasonable.
[ ] Input and output steady-state values are plausible.
[ ] Rise/fall time was calculated.
[ ] Positive and negative slew rates were calculated.
[ ] Actual slope window was recorded.
[ ] 1% and 0.1% settling were calculated.
[ ] Overshoot and undershoot were calculated.
[ ] Analysis output was saved with tee.
[ ] Larger-step and smaller-step results were compared.
[ ] Engineering conclusion was recorded.
```

## 14. Transient Stage Status

Example project status after this workflow:

```text
DC OP:                              complete
VCM sweep:                          complete
VID sweep:                          complete
Open-loop AC:                       complete
Formal STB:                         complete
10 mV closed-loop transient:         complete
100 mV closed-loop transient:        complete
140 mV slew-ceiling transient:       complete
140 mV post-processing:              complete
140 mV analysis report:              saved
140 mV OCEAN working checkpoint:     created and verified
```

At that point, nominal transient automation and large-signal slew-ceiling
checking can be treated as complete for the documented conditions. PVT,
temperature, supply, load, and mismatch sweeps still need separate coverage.
