# 第 12 章：Deterministic PVT Automation

本章把第 11 章的 frozen baseline 擴展成 deterministic process-corner PVT campaign。
重點放在 pre-simulation workflow：產生 corner-specific OCEAN scripts、執行 core
與 full matrices、細化 near-zero VID linearity、擷取 transient metrics，最後建立
consolidated report。

原始筆記包含真實 Linux username、project path、simulation root 與本機 project naming。
公開版只保留工程流程，並將私密環境資訊替換成 placeholders。

```text
Document version: 1
Date: 2026-09-03
Status: verified pre-simulation continuation
```

## 1. Scope and Freeze Rule

Deterministic PVT campaign 必須在 nominal baseline frozen 之後才開始。

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

任何 schematic sizing、bias、model、load 或 netlist 變更，都會使 frozen baseline
失效，需要重跑受影響的 analyses。

## 2. Public Path Convention

撰寫或分享流程時使用 placeholders：

```bash
cd /home/<linux-user>/cadence_projects/<ota-project> || exit 1

PROJECT_DIR="$PWD"
RESULT_ROOT="/home/<linux-user>/simulation/<ota-project>_ocean"
PVT_ROOT="$RESULT_ROOT/pvt_process"
GENERATED_ROOT="$PROJECT_DIR/generated_pvt"
PVT_CORNERS="ff ss fnsp snfp"
```

不要公開真實 Linux usernames、VM addresses、PDK roots、foundry model files、raw PSF
trees、netlists 或未清理過的 logs。

上面的 corner names 是 reusable template 的示例。實際執行或修改公開 script 前，一定要
先確認 installed PDK 中真正支援的 model-section names。

## 3. Runner Modes

Process-corner runner 是：

```text
scripts/pvt/run_process_corners.sh
```

它支援三個分開的 modes：

| Mode | Purpose |
| --- | --- |
| `prepare` | 產生並驗證 corner-specific OCEAN scripts，不啟動 OCEAN 或 Spectre。 |
| `core` | 執行最小 process matrix：DCOP、open-loop AC、unity-feedback STB。 |
| `full` | Core matrix 乾淨後，執行完整 deterministic set。 |

這三個 modes 要保持分開。乾淨的 `prepare` step 代表 generated paths 與 model-section
rewrite 合理，之後再花 simulation time。

## 4. Exact Execution Sequence

請從 project directory 執行。行尾的 backslash 是 shell line-continuation character。

先檢查 shell syntax：

```bash
bash -n scripts/pvt/run_process_corners.sh
```

產生 corner-specific OCEAN scripts：

```bash
PROJECT_DIR="$PWD" \
RESULT_ROOT="/home/<linux-user>/simulation/<ota-project>_ocean" \
PVT_CORNERS="ff ss fnsp snfp" \
bash scripts/pvt/run_process_corners.sh prepare
```

執行 core matrix：

```bash
PROJECT_DIR="$PWD" \
RESULT_ROOT="/home/<linux-user>/simulation/<ota-project>_ocean" \
PVT_CORNERS="ff ss fnsp snfp" \
bash scripts/pvt/run_process_corners.sh core
```

Core matrix 乾淨後，才執行 full deterministic matrix：

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

每個 corner 都會產生一份 private generated OCEAN copy。Canonical root-level OCEAN
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

Runner 會把 nominal model section 改寫成 selected corner。不要安靜地拿另一個 Cadence
或 PDK installation 的 model section 來替代。

## 6. Reuse and Rerun Policy

只有在 expected artifacts 有效時，才使用 existing results。

```text
PVT_ADOPT_EXISTING=1
```

這允許 runner 在驗證後採用 existing result。Verified completion marker 可以安全略過。

```text
PVT_FORCE=1
```

這會刻意重跑 corner/test，即使 marker 已存在也一樣。只有在 source script、model
section、simulator setup 或 measurement definition 改變時才使用。

Runner 會把每個 corner/test 的 status 記錄在 timestamped TSV，並使用 per-test
completion markers。Crash retries 與 startup delays 會寫入 log；retry 不是 final artifact
validation 的替代品。

## 7. Refined Near-Zero VID Linearity

Coarse VID sweep 用來找 usable range，但不一定足夠證明嚴格 near-zero linearity。

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

Refined export 會記錄 `VOUT` versus `VID`，以及相關 MOS devices 的 saturation margins。
最終 0.1 percent 或 1 percent linearity table 請使用 refined output。

不要把 MOS saturation range 和 linearity range 混在一起。元件可以仍在 saturation，但
transfer curve 已經不符合指定的 linearity criterion。

## 8. Completed-Corner Transient Extraction

Required corners 都有有效 transient raw files 後，執行：

```bash
PROJECT_DIR="$PWD" \
RESULT_ROOT="/home/<linux-user>/simulation/<ota-project>_ocean" \
PVT_CORNERS="ff ss fnsp snfp" \
bash scripts/pvt/analyze_process_corner_transients.sh
```

Analyzer 應拒絕 missing 或 malformed waveform files。它應該為每個 corner 寫出一筆
metric record，並保留：

```text
Stimulus definition
Sample times
Rise and fall measurements
Settling criterion
Slew rate
Overshoot
Undershoot
```

Process run 完成但沒有 transient extraction，不能算 complete corner characterization。

## 9. Consolidated Report

只有在 status TSV 與 transient metric files 完整後，才建立 process-corner report：

```bash
RESULT_ROOT="/home/<linux-user>/simulation/<ota-project>_ocean" \
PVT_CORNERS="ff ss fnsp snfp" \
bash scripts/pvt/build_process_corner_report.sh
```

預期 report artifacts：

```text
process_corner_report_<run-id>.txt
process_corner_metrics_long_<run-id>.tsv
process_corner_comparison_<run-id>.tsv
process_corner_report_<run-id>.sha256
```

每份 report 都應標示 source result root、corner list、model section、simulator status、
warning count 與 generated-file checksums。Reports 在 paths、PDK names、machine names
與 unpublished circuit names 清理前，都應保持 private。

## 10. Acceptance Gates

只有符合以下條件，才接受 deterministic PVT campaign：

1. Nominal baseline hash 與 conditions 沒變。
2. 每個 requested corner 都有 expected generated OCEAN files。
3. 每個 requested core/full test 都有 valid result directory。
4. 每個 test status 是 `PASSED`，或是明確記錄的 adopted result。
5. supposedly passed log 中沒有 hard Spectre/OCEAN error。
6. Refined VID analysis 沒有 parser 或 numeric errors。
7. Transient extraction 有 expected metric rows。
8. Consolidated report 與 SHA-256 file 存在。
9. Corner names 與 model sections 確實符合預期。

Warnings 與 notices 是需要 review 的證據，不是自動 failure。Process exit 成功但缺少必要
output artifacts，仍然是 failure。

## 11. Filename and Shell Notes

將這些實務 notes 跟 automation workflow 放在一起：

1. `loopStb` 可能是 generated STB analysis instance，而 `stb` 可能是 PSF/OCEAN result
   name。`getData` 要使用實際需要的 result name。
2. 某些較舊的 Spectre/OCEAN environments 在 scripted exports 中做 waveform reductions
   時可能回傳 `nil`。Fixed-time samples 是較 portable 的 fallback。
3. `run_process_corners.sh`、`refine_vid_linearity.sh`、
   `analyze_process_corner_transients.sh` 與 `build_process_corner_report.sh` 維持為獨立檔名。
4. 執行前先跑 `bash -n`。
5. Pipe 到 `tee` 時使用 `set -o pipefail`。
6. 比較 frequency values 時，使用支援 scientific notation 的 numeric sorting。
7. 不要只因為 generated corner directories 的 timestamps 較舊就刪除；每個 corner 都是一個
   distinct valid combination。

## 12. Privacy and Retention

保持 private：

1. 真實 Linux usernames 與 machine addresses
2. PDK root paths 與 foundry model files
3. Raw PSF and netlist trees
4. Path sanitization 前的 generated reports
5. 會暴露 private infrastructure 的 logs

為了 reproducibility 保留：

1. Final runner and report-builder scripts
2. Exact generated-file and result-root naming scheme
3. Status TSVs、report checksums 與 completion markers
4. Frozen baseline summary 與本章

## 13. Completion State and Next Chapter

本階段記錄 deterministic pre-Monte-Carlo characterization workflow。Deterministic
PVT campaign accepted 之後，接著看
[第 13 章](13-monte-carlo-automation-and-reporting.md)，整理 offset、performance 與
correlated-transient Monte Carlo automation，包含 random-stream correlation checks。

Post-simulation review 會等到有真正且已清理過的 PVT reports 後再進行。
