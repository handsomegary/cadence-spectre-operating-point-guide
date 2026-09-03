# Chapter 14: Final Pre-Simulation Sign-Off

This is the final chapter of the current pre-simulation automation manual. It
freezes the verified characterization state, records the evidence needed for
handoff, and defines the boundary before post-simulation. It does not start
another simulation and does not alter any canonical netlist.

The source notes contained real project paths, result roots, local bundle
names, and cleanup history. This public version keeps the sign-off method and
uses generic placeholders.

```text
Document version: 1
Date: 2026-09-03
Status: pre-simulation finale; post-simulation deferred
```

## 1. Final Source and Result Map

Use placeholders in public documentation:

```text
VM project directory:
/home/<linux-user>/cadence_projects/<ota-project>

Simulation result root:
/home/<linux-user>/simulation/<ota-project>_ocean

Canonical source netlists:
/home/<linux-user>/simulation/<ota-project>/spectre/schematic/netlist/netlist
/home/<linux-user>/simulation/<ota-project>_stb/spectre/schematic/netlist/netlist
```

Example final Monte Carlo result roots:

```text
/home/<linux-user>/simulation/<ota-project>_ocean/monte_carlo_performance/all_n200_seed20260902
/home/<linux-user>/simulation/<ota-project>_ocean/monte_carlo_performance/process_n200_seed20260902
/home/<linux-user>/simulation/<ota-project>_ocean/monte_carlo_performance/mismatch_n200_seed20260902
/home/<linux-user>/simulation/<ota-project>_ocean/monte_carlo_offset/all_n200_seed20260902
/home/<linux-user>/simulation/<ota-project>_ocean/monte_carlo_offset/process_n200_seed20260902
/home/<linux-user>/simulation/<ota-project>_ocean/monte_carlo_offset/mismatch_n200_seed20260902
/home/<linux-user>/simulation/<ota-project>_ocean/monte_carlo_transient_validation/all_n200_seed20260902
```

## 2. Frozen Nominal Baseline

The baseline conditions remain:

```text
Process:              TT
Temperature:          27 deg C
VDD:                  1.2 V
Bias:                 550 mV
VCM:                  0.8 V
Differential input:   0 V
Load:                 100 fF
Operating point:      UNITY_FEEDBACK
```

The verified topology includes the five MOS devices, feedback path, load
capacitor, supply, input source, bias source, and STB probe required by the
project. Any change to sizing, bias, model, load, source, or netlist invalidates
this sign-off and requires a new baseline comparison.

## 3. Characterization Coverage

The retained pre-simulation coverage is:

1. Nominal DC operating point
2. VCM and VID DC sweeps
3. Open-loop AC
4. Unity-feedback STB
5. Closed-loop transient and slew
6. Open-loop noise and contribution ranking
7. CMRR
8. PSRR+ and PSRR-
9. Deterministic process and PVT automation
10. Refined near-zero VID linearity
11. Completed-corner transient extraction and report generation
12. Offset Monte Carlo for all, process, and mismatch variations
13. Performance Monte Carlo for all, process, and mismatch variations
14. Correlated transient Monte Carlo

## 4. Verified Monte Carlo Evidence

Performance campaigns should show:

```text
all/process/mismatch production modes
Expected scalar row count met
Invalid numeric rows = 0
Failed Monte Carlo iterations = 0
Spectre exit status = 0
Formal phase margin uses corrected sign convention
UGF values are positive
```

Offset campaigns should show:

```text
all/process/mismatch production modes
Expected sample count met
Nominal centering voltage recorded
Nominal VOUT at VID=0 recorded
Reports, samples, worst-case tables, checksums, and completion markers present
```

Correlated transient campaigns should show:

```text
Expected scalar row count met
Invalid numeric rows = 0
Failed iterations = 0
Process random stream matches performance reference
Mismatch random stream matches performance reference
Stimulus definition recorded
Completion marker and report artifacts present
```

## 5. Value-Definition Corrections

Freeze these definitions at sign-off:

1. Formal STB phase margin must use the sign convention verified for the local
   loop-gain waveform.
2. The analysis instance name and PSF/OCEAN result name may differ; use the
   verified result name in `getData`.
3. `VDD_POWER_W` should be positive consumed supply power, while
   `VDD_CURRENT_A` may preserve Spectre terminal-current sign convention.
4. Fixed-time transient samples are the portable fallback when Monte Carlo
   `oceanEval` waveform reductions are unsupported.
5. A long transient pulse period prevents a second pulse before the final
   return-to-baseline sample.
6. Scientific-notation frequency sorting must use a numeric mode that supports
   exponent notation.

## 6. Final Acceptance Gates

The pre-simulation state is signed off only when:

1. Every required runner and report-builder script is present.
2. `bash -n` passes for every shell script in the execution package.
3. Each final Monte Carlo tree contains a `.complete` marker.
4. Report builders regenerate production-sample reports without schema errors.
5. Report analysis shows zero invalid rows.
6. Correlated transient hashes match their performance reference.
7. Required checksums and status files are present.
8. No explicit stale PID or stale shell artifact remains.
9. Generated corner directories are retained when they represent distinct
   combinations.
10. Handoff documents and final bundle artifacts are preserved privately.

Warnings and notices should be reviewed, but they are not automatic failures
unless they affect measured values or output validity.

## 7. Reproducibility-Only Verification

These checks do not rerun Spectre:

```bash
cd /home/<linux-user>/cadence_projects/<ota-project> || exit 1

for result_dir in \
  /home/<linux-user>/simulation/<ota-project>_ocean/monte_carlo_performance/all_n200_seed20260902 \
  /home/<linux-user>/simulation/<ota-project>_ocean/monte_carlo_performance/process_n200_seed20260902 \
  /home/<linux-user>/simulation/<ota-project>_ocean/monte_carlo_performance/mismatch_n200_seed20260902 \
  /home/<linux-user>/simulation/<ota-project>_ocean/monte_carlo_transient_validation/all_n200_seed20260902
do
    test -f "$result_dir/.complete" || printf 'MISSING_COMPLETE_MARKER %s\n' "$result_dir"
done
```

Project-root packaging archives should not be kept in the execution tree after
they are verified redundant and removed with explicit authorization. A separate
private Windows or workstation bundle may be preserved as the handoff artifact.

## 8. Cleanup and Storage State

Items that may be removed after explicit authorization and verification:

1. Redundant project-root packaging archives
2. Superseded temporary cleanup archives
3. Large raw waveform files no longer needed for audit
4. Temporary shell-error artifacts

Items that should not be removed:

1. Canonical netlists
2. Root OCEAN sources
3. Required shell runners and report builders
4. Generated corner directories that represent valid combinations
5. Formal simulation result trees
6. Scalar data, parameters, reports, checksums, status files, and markers
7. Final handoff and chapter documents

## 9. Handoff Package

Private handoff workspaces may preserve files such as:

```text
ota_pre_sim_handoff_<date>.txt
ota_automation_manual_chaptered_<date>.txt
ota_automation_chapter_12_deterministic_pvt_<date>.txt
ota_automation_chapter_13_monte_carlo_<date>.txt
ota_automation_chapter_14_final_signoff_<date>.txt
ota_pre_sim_cleanup_manifest_<date>.txt
ota_pre_sim_final_bundle.zip
```

The final bundle is a distribution artifact. The VM project is the execution
artifact. Do not copy private PDK or raw result data into a public documentation
bundle.

## 10. Post-Simulation Boundary

Post-simulation has not started. No post-simulation script, waveform reduction,
optimization, design change, or sign-off claim should be added to this
pre-simulation finale without explicit authorization.

When post-simulation is eventually authorized:

1. Begin from this frozen baseline.
2. Record a new run ID.
3. Preserve the pre-simulation checksums.
4. Document the new work as a separate chapter set.
5. Do not overwrite the current reports.

## 11. Final Checklist

```text
[x] Nominal baseline frozen.
[x] DC, AC, STB, transient, noise, CMRR, and PSRR covered.
[x] Deterministic PVT automation documented.
[x] Refined VID and process-corner transient post-processing documented.
[x] Offset Monte Carlo documented.
[x] Performance Monte Carlo documented.
[x] Correlated transient Monte Carlo documented.
[x] Report builders and statistical acceptance gates documented.
[x] Version, reference, filename, and Linux syntax corrections recorded.
[x] Required result markers and checksums retained.
[x] Redundant archives and project-root zip files handled privately.
[ ] Post-simulation started.
```

The unchecked post-simulation item is intentional.

This is the end of the pre-simulation manual.
