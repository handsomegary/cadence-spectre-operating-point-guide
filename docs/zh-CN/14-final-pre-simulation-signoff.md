# 第 14 章：Final Pre-Simulation Sign-Off

这是目前 pre-simulation automation manual 的最后一章。本章冻结已验证的
characterization state，记录 handoff 需要的 evidence，并定义进入 post-simulation 前的
边界。它不启动新 simulation，也不修改任何 canonical netlist。

原始笔记包含真实 project paths、result roots、local bundle names 与 cleanup history。
公开版保留 sign-off 方法，并使用 generic placeholders。

```text
Document version: 1
Date: 2026-09-03
Status: pre-simulation finale; post-simulation deferred
```

## 1. Final Source and Result Map

公开文件使用 placeholders：

```text
VM project directory:
/home/<linux-user>/cadence_projects/<ota-project>

Simulation result root:
/home/<linux-user>/simulation/<ota-project>_ocean

Canonical source netlists:
/home/<linux-user>/simulation/<ota-project>/spectre/schematic/netlist/netlist
/home/<linux-user>/simulation/<ota-project>_stb/spectre/schematic/netlist/netlist
```

Final Monte Carlo result roots 示例：

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

Baseline conditions 维持：

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

Verified topology 包含 project 需要的 five MOS devices、feedback path、load
capacitor、supply、input source、bias source 与 STB probe。任何 sizing、bias、model、
load、source 或 netlist 变更都会使本 sign-off 失效，必须重新做 baseline comparison。

## 3. Characterization Coverage

保留的 pre-simulation coverage：

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

Performance campaigns 应显示：

```text
all/process/mismatch production modes
Expected scalar row count met
Invalid numeric rows = 0
Failed Monte Carlo iterations = 0
Spectre exit status = 0
Formal phase margin uses corrected sign convention
UGF values are positive
```

Offset campaigns 应显示：

```text
all/process/mismatch production modes
Expected sample count met
Nominal centering voltage recorded
Nominal VOUT at VID=0 recorded
Reports, samples, worst-case tables, checksums, and completion markers present
```

Correlated transient campaigns 应显示：

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

Sign-off 时冻结这些 definitions：

1. Formal STB phase margin 必须使用 local loop-gain waveform 验证过的 sign convention。
2. Analysis instance name 与 PSF/OCEAN result name 可能不同；`getData` 要使用已验证的
   result name。
3. `VDD_POWER_W` 应是 positive consumed supply power，而 `VDD_CURRENT_A` 可以保留
   Spectre terminal-current sign convention。
4. 当 Monte Carlo `oceanEval` waveform reductions 不支持时，fixed-time transient samples
   是 portable fallback。
5. 较长 transient pulse period 可避免 final return-to-baseline sample 前出现第二个 pulse。
6. Scientific-notation frequency sorting 必须使用支持 exponent notation 的 numeric mode。

## 6. Final Acceptance Gates

只有符合以下条件，pre-simulation state 才能 sign off：

1. 每个 required runner 与 report-builder script 都存在。
2. Execution package 中每个 shell script 都通过 `bash -n`。
3. 每个 final Monte Carlo tree 都有 `.complete` marker。
4. Report builders 能无 schema errors 地重新生成 production-sample reports。
5. Report analysis 显示 zero invalid rows。
6. Correlated transient hashes 符合 performance reference。
7. Required checksums 与 status files 存在。
8. 没有明确 stale PID 或 stale shell artifact。
9. Generated corner directories 若代表 distinct combinations，需保留。
10. Handoff documents 与 final bundle artifacts 保持 private 保存。

Warnings 与 notices 需要 review，但除非影响 measured values 或 output validity，否则不是
automatic failures。

## 7. Reproducibility-Only Verification

这些 checks 不会重跑 Spectre：

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

Project-root packaging archives 在确认 redundant 并经明确授权移除后，不应留在 execution
tree。独立的 private Windows 或 workstation bundle 可以作为 handoff artifact 保存。

## 8. Cleanup and Storage State

经明确授权与验证后可移除：

1. Redundant project-root packaging archives
2. Superseded temporary cleanup archives
3. Audit 不再需要的大型 raw waveform files
4. Temporary shell-error artifacts

不应移除：

1. Canonical netlists
2. Root OCEAN sources
3. Required shell runners and report builders
4. 代表 valid combinations 的 generated corner directories
5. Formal simulation result trees
6. Scalar data、parameters、reports、checksums、status files 与 markers
7. Final handoff and chapter documents

## 9. Handoff Package

Private handoff workspaces 可保存类似以下文件：

```text
ota_pre_sim_handoff_<date>.txt
ota_automation_manual_chaptered_<date>.txt
ota_automation_chapter_12_deterministic_pvt_<date>.txt
ota_automation_chapter_13_monte_carlo_<date>.txt
ota_automation_chapter_14_final_signoff_<date>.txt
ota_pre_sim_cleanup_manifest_<date>.txt
ota_pre_sim_final_bundle.zip
```

Final bundle 是 distribution artifact；VM project 是 execution artifact。不要把 private
PDK 或 raw result data 复制进 public documentation bundle。

## 10. Post-Simulation Boundary

Post-simulation 尚未开始。没有 explicit authorization 前，不要把 post-simulation script、
waveform reduction、optimization、design change 或 sign-off claim 加进这份
pre-simulation finale。

未来若授权开始 post-simulation：

1. 从本 frozen baseline 开始。
2. 记录新的 run ID。
3. 保留 pre-simulation checksums。
4. 将新工作写成独立 chapter set。
5. 不要覆盖目前 reports。

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

Post-simulation 这一项维持未勾选是刻意的。

这是 pre-simulation manual 的结尾。
