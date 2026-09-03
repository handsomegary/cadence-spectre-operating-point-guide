# Chapter 13: Monte Carlo Automation and Reporting

This chapter continues the frozen baseline and deterministic PVT workflow from
Chapter 12. It documents Monte Carlo preparation, random-stream correlation,
scalar schemas, statistical report builders, and acceptance gates.

The source notes contained real result roots, PDK details, wrapper names, and
local filenames. This public version keeps the method and replaces private
environment details with placeholders.

```text
Document version: 1
Date: 2026-09-03
Status: verified pre-simulation continuation
```

## 1. Monte Carlo Freeze Contract

Monte Carlo must use the same verified unity-feedback topology as the frozen
baseline.

Example production settings:

```text
Input common-mode voltage:  0.8 V
VDD:                        1.2 V
Temperature:                27 deg C
Seed:                       20260902
Production run count:       200
Operating point:            UNITY_FEEDBACK
Load capacitance:           100 fF
```

The canonical netlists remain read-only. Each runner copies the source into a
private result/input tree, validates the topology, transforms only the intended
MOS devices, and records input checksums.

## 2. Device-Wrapper and PDK Contract

Randomized MOS devices should use wrapper models from the installed PDK.

Public template variables:

```text
MC_NOMINAL_NMOS_MODEL
MC_NOMINAL_PMOS_MODEL
MC_NMOS_MISMATCH_WRAPPER
MC_PMOS_MISMATCH_WRAPPER
MC_MODEL_SECTION
```

For a five-transistor OTA example, the generated netlist should contain:

```text
Five wrapper devices
Five mismatch-enabled devices
Zero remaining nominal MOS model instances
One correctly connected STB probe
```

Do not substitute wrapper names, model sections, or nominal model references
from another PDK installation without checking the installed model library and
generated netlist.

## 3. Campaign Map

Example offset Monte Carlo result roots:

```text
/home/<linux-user>/simulation/<ota-project>_ocean/monte_carlo_offset/all_n200_seed20260902
/home/<linux-user>/simulation/<ota-project>_ocean/monte_carlo_offset/process_n200_seed20260902
/home/<linux-user>/simulation/<ota-project>_ocean/monte_carlo_offset/mismatch_n200_seed20260902
```

Example performance Monte Carlo result roots:

```text
/home/<linux-user>/simulation/<ota-project>_ocean/monte_carlo_performance/all_n200_seed20260902
/home/<linux-user>/simulation/<ota-project>_ocean/monte_carlo_performance/process_n200_seed20260902
/home/<linux-user>/simulation/<ota-project>_ocean/monte_carlo_performance/mismatch_n200_seed20260902
```

Example correlated transient Monte Carlo result root:

```text
/home/<linux-user>/simulation/<ota-project>_ocean/monte_carlo_transient_validation/all_n200_seed20260902
```

Each production tree has its own `input`, `psf`, `logs`, `summary`, `report`,
and completion-marker structure. Do not combine files from different run IDs.

## 4. Performance Monte Carlo Runner

Public template:

```text
scripts/monte-carlo/run_monte_carlo_performance_smoke.sh
```

Run a syntax check first:

```bash
bash -n scripts/monte-carlo/run_monte_carlo_performance_smoke.sh
```

Recommended sequence:

```bash
MC_STB_BASE_NETLIST="/home/<linux-user>/simulation/<ota-project>_stb/spectre/schematic/netlist/netlist" \
MC_MODEL_FILE="/home/<linux-user>/pdk/models/spectre/model.lib" \
MC_MODEL_SECTION="<mc-model-section>" \
MC_NOMINAL_NMOS_MODEL="<nominal-nmos-model>" \
MC_NOMINAL_PMOS_MODEL="<nominal-pmos-model>" \
MC_NMOS_MISMATCH_WRAPPER="<nmos-mismatch-wrapper>" \
MC_PMOS_MISMATCH_WRAPPER="<pmos-mismatch-wrapper>" \
MC_NUMRUNS=10 \
MC_VARIATIONS=all \
MC_SEED=20260902 \
bash scripts/monte-carlo/run_monte_carlo_performance_smoke.sh full
```

After the smoke run passes, run production:

```bash
set -o pipefail

MC_NUMRUNS=200 \
MC_VARIATIONS=all \
MC_SEED=20260902 \
bash scripts/monte-carlo/run_monte_carlo_performance_smoke.sh full 2>&1 | \
tee monte_carlo_performance_all_n200.log

performance_status=${PIPESTATUS[0]}
echo "MONTE_CARLO_PERFORMANCE_EXIT_STATUS=$performance_status"
```

Process-only and mismatch-only production runs use the same seed and topology
with `MC_VARIATIONS=process` and `MC_VARIATIONS=mismatch`.

## 5. Performance Scalar Schema

The performance scalar file has six numeric columns per sample:

```text
1. VOUT_DC_V
2. VDD_CURRENT_A
3. VDD_POWER_W
4. LOOP_GAIN_DB_1HZ
5. UGF_HZ
6. PHASE_MARGIN_DEG
```

Definitions:

| Metric | Meaning |
| --- | --- |
| `VOUT_DC_V` | Closed-loop DC output voltage at the unity-feedback operating point. |
| `VDD_CURRENT_A` | Current through the VDD source using Spectre terminal-current sign convention. |
| `VDD_POWER_W` | Positive supply power; prefer this for consumed power reporting. |
| `LOOP_GAIN_DB_1HZ` | Loop-gain magnitude in dB at 1 Hz. |
| `UGF_HZ` | Unity-gain frequency from the loop-gain waveform. |
| `PHASE_MARGIN_DEG` | Formal positive phase margin using the corrected sign convention. |

Negative `VDD_CURRENT_A` values can be expected from terminal-current sign
convention. `VDD_POWER_W` is the preferred positive power metric.

## 6. Performance Report Builder

Public templates:

```text
scripts/monte-carlo/build_monte_carlo_performance_report.sh
scripts/monte-carlo/analyze_monte_carlo_performance_v1.awk
```

Example:

```bash
MC_PERFORMANCE_RESULT_ROOT="/home/<linux-user>/simulation/<ota-project>_ocean/monte_carlo_performance/all_n200_seed20260902" \
MC_EXPECTED_COUNT=200 \
bash scripts/monte-carlo/build_monte_carlo_performance_report.sh
```

The builder rejects a source run that:

1. Is not marked `PASSED`
2. Has the wrong row count
3. Contains nonnumeric rows
4. Contains rows with the wrong column count
5. Has nonpositive UGF values

A successful report emits report, analysis, sample table, and SHA-256 files.

## 7. Offset Monte Carlo

Offset Monte Carlo should be run separately for `all`, `process`, and
`mismatch` variations with the same seed and topology.

The offset report should retain:

```text
Valid sample count
Nominal centering voltage
Nominal VOUT at VID=0
Worst-case offset table
Checksums
Status files
Completion markers
```

Large raw offset waveform files may be removed only after `offset.mcdata`,
`offset.mcparam`, reports, checksums, status files, and completion markers have
been verified.

## 8. Correlated Transient Monte Carlo

Public template:

```text
scripts/monte-carlo/run_monte_carlo_transient_validation.sh
```

The transient run intentionally uses the same seed and random streams as the
all-variation performance run. Before correlating sample IDs, compare the
process and mismatch stream hashes byte for byte.

Verified stimulus pattern:

```text
Step amplitude:      +10 mV
Step delay:          1 ns
Rise/fall time:      10 ps
Pulse width:         10 ns
Pulse period:        1 us
Transient stop:      30 ns
Maximum step:        20 ps
```

The long pulse period prevents a second pulse inside the 30 ns observation
window.

Required transient scalar columns:

```text
1. VOUT_DC_V
2. VOUT_AT_5NS_V
3. VOUT_AT_10NS_V
4. VOUT_AT_20NS_V
5. VOUT_AT_30NS_V
6. VDD_CURRENT_A
7. VDD_POWER_W
```

## 9. Transient Report Builder

Public templates:

```text
scripts/monte-carlo/build_monte_carlo_transient_report.sh
scripts/monte-carlo/analyze_monte_carlo_transient_v1.awk
```

Example:

```bash
MC_TRANSIENT_RESULT_ROOT="/home/<linux-user>/simulation/<ota-project>_ocean/monte_carlo_transient_validation/all_n200_seed20260902" \
MC_EXPECTED_COUNT=200 \
bash scripts/monte-carlo/build_monte_carlo_transient_report.sh
```

The report builder derives high-step amplitude, high-step error, and return
errors at fixed times. It does not require waveform max/min reductions inside
Monte Carlo `oceanEval`.

## 10. Statistical Report Convention

Every report includes:

| Field | Meaning |
| --- | --- |
| `N` | Number of valid samples. |
| `MEAN` | Arithmetic mean of the valid samples. |
| `SAMPLE_SIGMA` | Sample standard deviation. |
| `MIN` | Minimum valid sample. |
| `MAX` | Maximum valid sample. |

The report also preserves the complete tab-separated sample table and SHA-256
checksums.

## 11. Acceptance Gates

Accept a production campaign only when:

1. Spectre exit status is 0.
2. Log error count is 0.
3. Failed Monte Carlo iterations is 0.
4. Expected row count is exactly 200, or the documented production count.
5. All scalar rows have the required numeric column count.
6. No invalid numeric rows are present.
7. UGF is positive in every performance row.
8. Formal phase margin uses the corrected sign convention.
9. Required report, sample, analysis, checksum, status, and `.complete` files exist.
10. Correlated transient process and mismatch hashes match the reference run.

Warnings and notices in an otherwise clean Spectre log do not automatically
fail a campaign. Any warning that changes a measured value must be investigated
and documented.

## 12. Version and Filename Notes

Keep these corrections visible:

1. Some Spectre/OCEAN environments can return `nil` for max/min waveform
   reductions inside Monte Carlo `oceanEval`; fixed-time scalar samples are a
   portable fallback.
2. `loopStb` may be the STB analysis instance, while `stb` may be the PSF/OCEAN
   result name.
3. Formal phase margin should use the sign convention verified for the local
   loop-gain waveform.
4. Use exact runner and report filenames; do not merge a following command into
   a `tee` filename.
5. Use whitespace-aware parsing for generated `mcdata`.
6. Use numeric sorting that supports scientific notation for frequency or UGF
   values.
7. Use plain `for` syntax and keep `do`/`done` on valid shell lines.

## 13. Retention and Cleanup

Keep:

1. Scalar `mcdata` and `mcparam` files
2. Latest reports, analysis files, and sample tables
3. Checksums, status files, audit logs, and `.complete` markers
4. Input schemas
5. Final runner/report scripts and this chapter

Do not retain large raw waveform files solely for convenience once scalar and
audit artifacts have been verified. Do not delete a result tree that is still
referenced by a correlation hash or report.

## 14. Next Chapter

After offset, performance, and correlated-transient Monte Carlo are verified,
continue with [Chapter 14](14-final-pre-simulation-signoff.md) to freeze the
handoff state and define the boundary before post-simulation work.
