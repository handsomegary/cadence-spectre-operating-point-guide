# 第 12 章：Deterministic PVT Automation

本章把第 11 章的 frozen baseline 扩展成 deterministic process-corner PVT campaign。
重点放在 pre-simulation workflow：生成 corner-specific OCEAN scripts、执行 core 与
full matrices、细化 near-zero VID linearity、提取 transient metrics，最后建立
consolidated report。

原始笔记包含真实 Linux username、project path、simulation root 与本机 project naming。
公开版只保留工程流程，并将私密环境信息替换成 placeholders。

```text
Document version: 1
Date: 2026-09-03
Status: verified pre-simulation continuation
```

## 1. Scope and Freeze Rule

Deterministic PVT campaign 必须在 nominal baseline frozen 之后才开始。

Frozen nominal baseline 示例：

```text
Process corner:              TT
Temperature:                 27 deg C
VDD:                         1.2 V
Bias voltage:                550 mV
Input common-mode voltage:   800 mV
Differential DC input:       0 V
Load capacitance:            100 fF
```

Frozen baseline 包含：

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

任何 schematic sizing、bias、model、load 或 netlist 变更，都会使 frozen baseline
失效，需要重跑受影响的 analyses。

## 2. Public Path Convention

撰写或分享流程时使用 placeholders：

```bash
cd /home/<linux-user>/cadence_projects/<ota-project> || exit 1

PROJECT_DIR="$PWD"
RESULT_ROOT="/home/<linux-user>/simulation/<ota-project>_ocean"
PVT_ROOT="$RESULT_ROOT/pvt_process"
GENERATED_ROOT="$PROJECT_DIR/generated_pvt"
PVT_CORNERS="ff ss fnsp snfp"
```

不要公开真实 Linux usernames、VM addresses、PDK roots、foundry model files、raw PSF
trees、netlists 或未清理过的 logs。

上面的 corner names 是 reusable template 的示例。实际执行或修改公开 script 前，一定要
先确认 installed PDK 中真正支持的 model-section names。

## 3. Runner Modes

Process-corner runner 是：

```text
scripts/pvt/run_process_corners.sh
```

它支持三个分开的 modes：

| Mode | Purpose |
| --- | --- |
| `prepare` | 生成并验证 corner-specific OCEAN scripts，不启动 OCEAN 或 Spectre。 |
| `core` | 执行最小 process matrix：DCOP、open-loop AC、unity-feedback STB。 |
| `full` | Core matrix 干净后，执行完整 deterministic set。 |

这三个 modes 要保持分开。干净的 `prepare` step 代表 generated paths 与 model-section
rewrite 合理，之后再花 simulation time。

## 4. Exact Execution Sequence

请从 project directory 执行。行尾的 backslash 是 shell line-continuation character。

先检查 shell syntax：

```bash
bash -n scripts/pvt/run_process_corners.sh
```

生成 corner-specific OCEAN scripts：

```bash
PROJECT_DIR="$PWD" \
RESULT_ROOT="/home/<linux-user>/simulation/<ota-project>_ocean" \
PVT_CORNERS="ff ss fnsp snfp" \
bash scripts/pvt/run_process_corners.sh prepare
```

执行 core matrix：

```bash
PROJECT_DIR="$PWD" \
RESULT_ROOT="/home/<linux-user>/simulation/<ota-project>_ocean" \
PVT_CORNERS="ff ss fnsp snfp" \
bash scripts/pvt/run_process_corners.sh core
```

Core matrix 干净后，才执行 full deterministic matrix：

```bash
PVT_FORCE=0 \
PROJECT_DIR="$PWD" \
RESULT_ROOT="/home/<linux-user>/simulation/<ota-project>_ocean" \
PVT_CORNERS="ff ss fnsp snfp" \
bash scripts/pvt/run_process_corners.sh full
```

若用 `tee` 存 log，保留 failure propagation：

```bash
set -o pipefail
```

## 5. Generated-Script Contract

每个 corner 都会生成一份 private generated OCEAN copy。Canonical root-level OCEAN
sources 不直接修改。

Core source mapping：

```text
dcop        -> dcop.ocn
ac_openloop -> ac_sweep.ocn
stb_unity   -> stb_sweep.ocn
```

Full source mapping 另外加入：

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

Generated filenames 使用 corner-specific convention：

```text
generated_pvt/<corner>/<base-script>_<corner>.ocn
```

示例：

```text
generated_pvt/ff/ac_sweep_ff.ocn
```

Runner 会把 nominal model section 改写成 selected corner。不要安静地拿另一个 Cadence
或 PDK installation 的 model section 来替代。

## 6. Reuse and Rerun Policy

只有在 expected artifacts 有效时，才使用 existing results。

```text
PVT_ADOPT_EXISTING=1
```

这允许 runner 在验证后采用 existing result。Verified completion marker 可以安全略过。

```text
PVT_FORCE=1
```

这会刻意重跑 corner/test，即使 marker 已存在也一样。只有在 source script、model
section、simulator setup 或 measurement definition 改变时才使用。

Runner 会把每个 corner/test 的 status 记录在 timestamped TSV，并使用 per-test
completion markers。Crash retries 与 startup delays 会写入 log；retry 不是 final artifact
validation 的替代品。

## 7. Refined Near-Zero VID Linearity

Coarse VID sweep 用来找 usable range，但不一定足够证明严格 near-zero linearity。

使用：

```text
scripts/pvt/refine_vid_linearity.sh
```

Sensitive corners 的 refined run 示例：

```bash
PROJECT_DIR="$PWD" \
RESULT_ROOT="/home/<linux-user>/simulation/<ota-project>_ocean" \
PVT_CORNERS="ss fnsp" \
VID_REFINED_START="-5m" \
VID_REFINED_STOP="5m" \
VID_REFINED_STEP="10u" \
bash scripts/pvt/refine_vid_linearity.sh
```

Refined export 会记录 `VOUT` versus `VID`，以及相关 MOS devices 的 saturation margins。
最终 0.1 percent 或 1 percent linearity table 请使用 refined output。

不要把 MOS saturation range 和 linearity range 混在一起。元件可以仍在 saturation，但
transfer curve 已经不符合指定的 linearity criterion。

## 8. Completed-Corner Transient Extraction

Required corners 都有有效 transient raw files 后，执行：

```bash
PROJECT_DIR="$PWD" \
RESULT_ROOT="/home/<linux-user>/simulation/<ota-project>_ocean" \
PVT_CORNERS="ff ss fnsp snfp" \
bash scripts/pvt/analyze_process_corner_transients.sh
```

Analyzer 应拒绝 missing 或 malformed waveform files。它应该为每个 corner 写出一笔
metric record，并保留：

```text
Stimulus definition
Sample times
Rise and fall measurements
Settling criterion
Slew rate
Overshoot
Undershoot
```

Process run 完成但没有 transient extraction，不能算 complete corner characterization。

## 9. Consolidated Report

只有在 status TSV 与 transient metric files 完整后，才建立 process-corner report：

```bash
RESULT_ROOT="/home/<linux-user>/simulation/<ota-project>_ocean" \
PVT_CORNERS="ff ss fnsp snfp" \
bash scripts/pvt/build_process_corner_report.sh
```

预期 report artifacts：

```text
process_corner_report_<run-id>.txt
process_corner_metrics_long_<run-id>.tsv
process_corner_comparison_<run-id>.tsv
process_corner_report_<run-id>.sha256
```

每份 report 都应标示 source result root、corner list、model section、simulator status、
warning count 与 generated-file checksums。Reports 在 paths、PDK names、machine names
与 unpublished circuit names 清理前，都应保持 private。

## 10. Acceptance Gates

只有符合以下条件，才接受 deterministic PVT campaign：

1. Nominal baseline hash 与 conditions 没变。
2. 每个 requested corner 都有 expected generated OCEAN files。
3. 每个 requested core/full test 都有 valid result directory。
4. 每个 test status 是 `PASSED`，或是明确记录的 adopted result。
5. supposedly passed log 中没有 hard Spectre/OCEAN error。
6. Refined VID analysis 没有 parser 或 numeric errors。
7. Transient extraction 有 expected metric rows。
8. Consolidated report 与 SHA-256 file 存在。
9. Corner names 与 model sections 确实符合预期。

Warnings 与 notices 是需要 review 的证据，不是自动 failure。Process exit 成功但缺少必要
output artifacts，仍然是 failure。

## 11. Filename and Shell Notes

将这些实务 notes 跟 automation workflow 放在一起：

1. `loopStb` 可能是 generated STB analysis instance，而 `stb` 可能是 PSF/OCEAN result
   name。`getData` 要使用实际需要的 result name。
2. 某些较旧的 Spectre/OCEAN environments 在 scripted exports 中做 waveform reductions
   时可能返回 `nil`。Fixed-time samples 是较 portable 的 fallback。
3. `run_process_corners.sh`、`refine_vid_linearity.sh`、
   `analyze_process_corner_transients.sh` 与 `build_process_corner_report.sh` 维持为独立文件名。
4. 执行前先跑 `bash -n`。
5. Pipe 到 `tee` 时使用 `set -o pipefail`。
6. 比较 frequency values 时，使用支持 scientific notation 的 numeric sorting。
7. 不要只因为 generated corner directories 的 timestamps 较旧就删除；每个 corner 都是一个
   distinct valid combination。

## 12. Privacy and Retention

保持 private：

1. 真实 Linux usernames 与 machine addresses
2. PDK root paths 与 foundry model files
3. Raw PSF and netlist trees
4. Path sanitization 前的 generated reports
5. 会暴露 private infrastructure 的 logs

为了 reproducibility 保留：

1. Final runner and report-builder scripts
2. Exact generated-file and result-root naming scheme
3. Status TSVs、report checksums 与 completion markers
4. Frozen baseline summary 与本章

## 13. Completion State and Next Chapter

本阶段记录 deterministic pre-Monte-Carlo characterization workflow。Deterministic
PVT campaign accepted 之后，接着看
[第 13 章](13-monte-carlo-automation-and-reporting.md)，整理 offset、performance 与
correlated-transient Monte Carlo automation，包含 random-stream correlation checks。

Post-simulation review 会等到有真正且已清理过的 PVT reports 后再进行。
