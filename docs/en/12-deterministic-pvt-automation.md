# Chapter 12: Deterministic PVT Automation

This chapter expands the Chapter 11 baseline into a deterministic
process-corner PVT campaign. It focuses on the pre-simulation workflow:
generating corner-specific OCEAN scripts, running the core and full matrices,
refining near-zero VID linearity, extracting transient metrics, and building a
consolidated report.

The source notes contained a real Linux username, project path, simulation
root, and local project naming. This public version keeps the engineering
sequence and replaces private environment details with placeholders.

```text
Document version: 1
Date: 2026-09-03
Status: verified pre-simulation continuation
```

## 1. Scope and Freeze Rule

The deterministic PVT campaign starts only after the nominal baseline has been
frozen.

Example frozen nominal baseline:

```text
Process corner:              TT
Temperature:                 27 deg C
VDD:                         1.2 V
Bias voltage:                550 mV
Input common-mode voltage:   800 mV
Differential DC input:       0 V
Load capacitance:            100 fF
```

The frozen baseline includes:

```text
DC operating point
VCM sweep
VID sweep
Open-loop AC
Unity-feedback STB
Closed-loop transient
Open-loop noise
Noise contribution ranking
CMRR
PSRR+
PSRR-
```

Any schematic sizing, bias, model, load, or netlist change invalidates the
frozen baseline and requires the affected analyses to be rerun.

## 2. Public Path Convention

Use placeholders when documenting or sharing the workflow:

```bash
cd /home/<linux-user>/cadence_projects/<ota-project> || exit 1

PROJECT_DIR="$PWD"
RESULT_ROOT="/home/<linux-user>/simulation/<ota-project>_ocean"
PVT_ROOT="$RESULT_ROOT/pvt_process"
GENERATED_ROOT="$PROJECT_DIR/generated_pvt"
PVT_CORNERS="ff ss fnsp snfp"
```

Do not publish real Linux usernames, VM addresses, PDK roots, foundry model
files, raw PSF trees, netlists, or unsanitized logs.

The corner names above are examples for the reusable template. Always confirm
the actual model-section names in the installed PDK before running or editing a
public script.

## 3. Runner Modes

The process-corner runner is:

```text
scripts/pvt/run_process_corners.sh
```

It supports three separate modes:

| Mode | Purpose |
| --- | --- |
| `prepare` | Generate and validate corner-specific OCEAN scripts. Do not start OCEAN or Spectre. |
| `core` | Run the minimal process matrix: DCOP, open-loop AC, and unity-feedback STB. |
| `full` | Run the complete deterministic set after the core matrix is clean. |

Keep these modes separate. A clean `prepare` step proves that generated paths
and model-section rewrites are sensible before simulation time is spent.

## 4. Exact Execution Sequence

Run from the project directory. The trailing backslash is the shell
line-continuation character.

First check shell syntax:

```bash
bash -n scripts/pvt/run_process_corners.sh
```

Generate corner-specific OCEAN scripts:

```bash
PROJECT_DIR="$PWD" \
RESULT_ROOT="/home/<linux-user>/simulation/<ota-project>_ocean" \
PVT_CORNERS="ff ss fnsp snfp" \
bash scripts/pvt/run_process_corners.sh prepare
```

Run the core matrix:

```bash
PROJECT_DIR="$PWD" \
RESULT_ROOT="/home/<linux-user>/simulation/<ota-project>_ocean" \
PVT_CORNERS="ff ss fnsp snfp" \
bash scripts/pvt/run_process_corners.sh core
```

Run the full deterministic matrix only after the core matrix is clean:

```bash
PVT_FORCE=0 \
PROJECT_DIR="$PWD" \
RESULT_ROOT="/home/<linux-user>/simulation/<ota-project>_ocean" \
PVT_CORNERS="ff ss fnsp snfp" \
bash scripts/pvt/run_process_corners.sh full
```

When saving logs with `tee`, keep failure propagation visible:

```bash
set -o pipefail
```

## 5. Generated-Script Contract

For each corner, the runner creates a private generated OCEAN copy. The
canonical root-level OCEAN sources are not edited.

Core source mapping:

```text
dcop        -> dcop.ocn
ac_openloop -> ac_sweep.ocn
stb_unity   -> stb_sweep.ocn
```

Full source mapping adds:

```text
dc_vcm           -> vcm_sweep.ocn
dc_vid           -> vid_sweep.ocn
tran_small       -> tran_small.ocn
tran_large       -> tran_large.ocn
tran_slew_140m   -> tran_slew_140m.ocn
noise_openloop   -> noise_openloop.ocn
ac_commonmode    -> cmrr_sweep.ocn
ac_psrr_plus     -> psrr_plus_sweep.ocn
ac_psrr_minus    -> psrr_minus_sweep.ocn
```

Generated filenames follow a corner-specific convention:

```text
generated_pvt/<corner>/<base-script>_<corner>.ocn
```

Example:

```text
generated_pvt/ff/ac_sweep_ff.ocn
```

The runner rewrites the nominal model section to the selected corner. Do not
silently substitute model sections from another Cadence or PDK installation.

## 6. Reuse and Rerun Policy

Use existing results only when the expected artifacts are valid.

```text
PVT_ADOPT_EXISTING=1
```

This allows the runner to adopt an existing result after validation. A verified
completion marker is skipped safely.

```text
PVT_FORCE=1
```

This deliberately reruns a corner/test even when a marker exists. Use it only
when the source script, model section, simulator setup, or measurement
definition changed.

The runner records per-corner/per-test status in a timestamped TSV and uses
per-test completion markers. Crash retries and startup delays are recorded in
the log. A retry is not a substitute for final artifact validation.

## 7. Refined Near-Zero VID Linearity

The coarse VID sweep finds the usable range. It is not always fine enough to
certify strict near-zero linearity.

Use:

```text
scripts/pvt/refine_vid_linearity.sh
```

Example refined run for sensitive corners:

```bash
PROJECT_DIR="$PWD" \
RESULT_ROOT="/home/<linux-user>/simulation/<ota-project>_ocean" \
PVT_CORNERS="ss fnsp" \
VID_REFINED_START="-5m" \
VID_REFINED_STOP="5m" \
VID_REFINED_STEP="10u" \
bash scripts/pvt/refine_vid_linearity.sh
```

The refined export records `VOUT` versus `VID` and the saturation margins of
the relevant MOS devices. Use the refined output for the final 0.1 percent or
1 percent linearity table.

Do not confuse a MOS saturation range with a linearity range. Devices can stay
in saturation while the transfer curve no longer meets the chosen linearity
criterion.

## 8. Completed-Corner Transient Extraction

After the required corners have valid transient raw files, run:

```bash
PROJECT_DIR="$PWD" \
RESULT_ROOT="/home/<linux-user>/simulation/<ota-project>_ocean" \
PVT_CORNERS="ff ss fnsp snfp" \
bash scripts/pvt/analyze_process_corner_transients.sh
```

The analyzer should reject missing or malformed waveform files. It should write
one metric record per corner and preserve:

```text
Stimulus definition
Sample times
Rise and fall measurements
Settling criterion
Slew rate
Overshoot
Undershoot
```

A completed process run with no transient extraction is not a complete corner
characterization.

## 9. Consolidated Report

Build the process-corner report only after the status TSV and transient metric
files are complete:

```bash
RESULT_ROOT="/home/<linux-user>/simulation/<ota-project>_ocean" \
PVT_CORNERS="ff ss fnsp snfp" \
bash scripts/pvt/build_process_corner_report.sh
```

Expected report artifacts:

```text
process_corner_report_<run-id>.txt
process_corner_metrics_long_<run-id>.tsv
process_corner_comparison_<run-id>.tsv
process_corner_report_<run-id>.sha256
```

Every report should identify the source result root, corner list, model
section, simulator status, warning count, and generated-file checksums. Keep
reports private until all paths, PDK names, machine names, and unpublished
circuit names have been sanitized.

## 10. Acceptance Gates

Accept the deterministic PVT campaign only when:

1. The nominal baseline hash and conditions are unchanged.
2. Every requested corner has the expected generated OCEAN files.
3. Every requested core/full test has a valid result directory.
4. Each test status is `PASSED` or an explicitly documented adopted result.
5. No hard Spectre/OCEAN error appears in a supposedly passed log.
6. Refined VID analysis has no parser or numeric errors.
7. Transient extraction has the expected metric rows.
8. The consolidated report and SHA-256 file exist.
9. Corner names and model sections are present exactly as intended.

Warnings and notices are evidence to review, not automatic failures. A
successful process exit without required output artifacts is still a failure.

## 11. Filename and Shell Notes

Keep these practical notes with the automation workflow:

1. `loopStb` may be the generated STB analysis instance, while `stb` may be the
   PSF/OCEAN result name. Use the result name required by `getData`.
2. Some older Spectre/OCEAN environments can return `nil` for waveform
   reductions in scripted exports. Fixed-time samples are a portable fallback.
3. Keep `run_process_corners.sh`, `refine_vid_linearity.sh`,
   `analyze_process_corner_transients.sh`, and
   `build_process_corner_report.sh` as separate filenames.
4. Run `bash -n` before execution.
5. Use `set -o pipefail` when piping to `tee`.
6. Use numeric sorting that supports scientific notation when comparing
   frequency values.
7. Do not delete generated corner directories solely because their timestamps
   are older; each corner is a distinct valid combination.

## 12. Privacy and Retention

Keep private:

1. Real Linux usernames and machine addresses
2. PDK root paths and foundry model files
3. Raw PSF and netlist trees
4. Generated reports before path sanitization
5. Logs that expose private infrastructure

Keep for reproducibility:

1. Final runner and report-builder scripts
2. Exact generated-file and result-root naming scheme
3. Status TSVs, report checksums, and completion markers
4. Frozen baseline summary and this chapter

## 13. Completion State and Next Chapter

This stage documents the deterministic pre-Monte-Carlo characterization
workflow. After the deterministic PVT campaign is accepted, the next chapter can
document offset, performance, and correlated-transient Monte Carlo automation,
including random-stream correlation checks.

Post-simulation review remains intentionally deferred until real sanitized PVT
reports are available.
