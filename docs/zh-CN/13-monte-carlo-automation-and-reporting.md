# 第 13 章：Monte Carlo Automation and Reporting

本章延续第 12 章的 frozen baseline 与 deterministic PVT workflow，整理 Monte Carlo
preparation、random-stream correlation、scalar schemas、statistical report builders
与 acceptance gates。

原始笔记包含真实 result roots、PDK details、wrapper names 与 local filenames。公开版
保留方法，并把私密环境信息替换成 placeholders。

```text
Document version: 1
Date: 2026-09-03
Status: verified pre-simulation continuation
```

## 1. Monte Carlo Freeze Contract

Monte Carlo 必须使用与 frozen baseline 相同的 verified unity-feedback topology。

Production settings 示例：

```text
Input common-mode voltage:  0.8 V
VDD:                        1.2 V
Temperature:                27 deg C
Seed:                       20260902
Production run count:       200
Operating point:            UNITY_FEEDBACK
Load capacitance:           100 fF
```

Canonical netlists 保持 read-only。每个 runner 会把 source 复制到 private result/input
tree，验证 topology，只转换目标 MOS devices，并记录 input checksums。

## 2. Device-Wrapper and PDK Contract

Randomized MOS devices 应使用 installed PDK 提供的 wrapper models。

Public template variables：

```text
MC_NOMINAL_NMOS_MODEL
MC_NOMINAL_PMOS_MODEL
MC_NMOS_MISMATCH_WRAPPER
MC_PMOS_MISMATCH_WRAPPER
MC_MODEL_SECTION
```

Five-transistor OTA 示例中，generated netlist 应包含：

```text
Five wrapper devices
Five mismatch-enabled devices
Zero remaining nominal MOS model instances
One correctly connected STB probe
```

未确认 installed model library 与 generated netlist 前，不要替换成另一个 PDK installation
的 wrapper names、model sections 或 nominal model references。

## 3. Campaign Map

Offset Monte Carlo result roots 示例：

```text
/home/<linux-user>/simulation/<ota-project>_ocean/monte_carlo_offset/all_n200_seed20260902
/home/<linux-user>/simulation/<ota-project>_ocean/monte_carlo_offset/process_n200_seed20260902
/home/<linux-user>/simulation/<ota-project>_ocean/monte_carlo_offset/mismatch_n200_seed20260902
```

Performance Monte Carlo result roots 示例：

```text
/home/<linux-user>/simulation/<ota-project>_ocean/monte_carlo_performance/all_n200_seed20260902
/home/<linux-user>/simulation/<ota-project>_ocean/monte_carlo_performance/process_n200_seed20260902
/home/<linux-user>/simulation/<ota-project>_ocean/monte_carlo_performance/mismatch_n200_seed20260902
```

Correlated transient Monte Carlo result root 示例：

```text
/home/<linux-user>/simulation/<ota-project>_ocean/monte_carlo_transient_validation/all_n200_seed20260902
```

每个 production tree 都有自己的 `input`、`psf`、`logs`、`summary`、`report` 与
completion-marker structure。不要混用不同 run IDs 的文件。

## 4. Performance Monte Carlo Runner

Public template：

```text
scripts/monte-carlo/run_monte_carlo_performance_smoke.sh
```

先检查 syntax：

```bash
bash -n scripts/monte-carlo/run_monte_carlo_performance_smoke.sh
```

建议流程：

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

Smoke run 通过后，再执行 production：

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

Process-only 与 mismatch-only production runs 使用相同 seed 与 topology，分别设置
`MC_VARIATIONS=process` 与 `MC_VARIATIONS=mismatch`。

## 5. Performance Scalar Schema

Performance scalar file 每个 sample 有六个 numeric columns：

```text
1. VOUT_DC_V
2. VDD_CURRENT_A
3. VDD_POWER_W
4. LOOP_GAIN_DB_1HZ
5. UGF_HZ
6. PHASE_MARGIN_DEG
```

| Metric | Meaning |
| --- | --- |
| `VOUT_DC_V` | Unity-feedback operating point 的 closed-loop DC output voltage。 |
| `VDD_CURRENT_A` | 使用 Spectre terminal-current sign convention 的 VDD source current。 |
| `VDD_POWER_W` | Positive supply power；报告消耗功率时优先使用。 |
| `LOOP_GAIN_DB_1HZ` | 1 Hz 的 loop-gain magnitude，单位 dB。 |
| `UGF_HZ` | 从 loop-gain waveform 得到的 unity-gain frequency。 |
| `PHASE_MARGIN_DEG` | 使用修正后 sign convention 的 formal positive phase margin。 |

`VDD_CURRENT_A` 可能因 terminal-current sign convention 而为负值；`VDD_POWER_W` 才是建议
用来报告 consumed power 的正值 metric。

## 6. Performance Report Builder

Public templates：

```text
scripts/monte-carlo/build_monte_carlo_performance_report.sh
scripts/monte-carlo/analyze_monte_carlo_performance_v1.awk
```

示例：

```bash
MC_PERFORMANCE_RESULT_ROOT="/home/<linux-user>/simulation/<ota-project>_ocean/monte_carlo_performance/all_n200_seed20260902" \
MC_EXPECTED_COUNT=200 \
bash scripts/monte-carlo/build_monte_carlo_performance_report.sh
```

Builder 会拒绝以下 source run：

1. 未标记为 `PASSED`
2. Row count 错误
3. 包含 nonnumeric rows
4. 包含 column count 错误的 rows
5. 有 nonpositive UGF values

成功时会输出 report、analysis、sample table 与 SHA-256 files。

## 7. Offset Monte Carlo

Offset Monte Carlo 应用相同 seed 与 topology，分别执行 `all`、`process`、`mismatch`
variations。

Offset report 应保留：

```text
Valid sample count
Nominal centering voltage
Nominal VOUT at VID=0
Worst-case offset table
Checksums
Status files
Completion markers
```

Large raw offset waveform files 只能在 `offset.mcdata`、`offset.mcparam`、reports、
checksums、status files 与 completion markers 都验证后再移除。

## 8. Correlated Transient Monte Carlo

Public template：

```text
scripts/monte-carlo/run_monte_carlo_transient_validation.sh
```

Transient run 刻意使用与 all-variation performance run 相同的 seed 与 random streams。
在用 sample IDs 做 correlation 前，必须 byte-for-byte 比对 process 与 mismatch stream
hashes。

Verified stimulus pattern：

```text
Step amplitude:      +10 mV
Step delay:          1 ns
Rise/fall time:      10 ps
Pulse width:         10 ns
Pulse period:        1 us
Transient stop:      30 ns
Maximum step:        20 ps
```

较长的 pulse period 可避免 30 ns observation window 内出现第二个 pulse。

Required transient scalar columns：

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

Public templates：

```text
scripts/monte-carlo/build_monte_carlo_transient_report.sh
scripts/monte-carlo/analyze_monte_carlo_transient_v1.awk
```

示例：

```bash
MC_TRANSIENT_RESULT_ROOT="/home/<linux-user>/simulation/<ota-project>_ocean/monte_carlo_transient_validation/all_n200_seed20260902" \
MC_EXPECTED_COUNT=200 \
bash scripts/monte-carlo/build_monte_carlo_transient_report.sh
```

Report builder 会由 fixed-time samples 推导 high-step amplitude、high-step error 与
return errors，不需要在 Monte Carlo `oceanEval` 里做 waveform max/min reductions。

## 10. Statistical Report Convention

每份 report 包含：

| Field | Meaning |
| --- | --- |
| `N` | Valid samples 数量。 |
| `MEAN` | Valid samples 的 arithmetic mean。 |
| `SAMPLE_SIGMA` | Sample standard deviation。 |
| `MIN` | Minimum valid sample。 |
| `MAX` | Maximum valid sample。 |

Report 也保留完整 tab-separated sample table 与 SHA-256 checksums。

## 11. Acceptance Gates

Production campaign 只有在以下条件通过时才接受：

1. Spectre exit status 是 0。
2. Log error count 是 0。
3. Failed Monte Carlo iterations 是 0。
4. Expected row count 是 200，或文件明确指定的 production count。
5. 所有 scalar rows 都有正确 numeric column count。
6. 没有 invalid numeric rows。
7. Performance rows 的 UGF 全部为正。
8. Formal phase margin 使用已验证的 sign convention。
9. 必要 report、sample、analysis、checksum、status 与 `.complete` files 都存在。
10. Correlated transient 的 process 与 mismatch hashes 符合 reference run。

干净 Spectre log 里的 warnings 与 notices 不会自动让 campaign 失败；但任何会改变量测值的
warning 都必须调查并记录。

## 12. Version and Filename Notes

保留这些修正：

1. 某些 Spectre/OCEAN environments 在 Monte Carlo `oceanEval` 里做 max/min waveform
   reductions 可能返回 `nil`；fixed-time scalar samples 是较 portable 的 fallback。
2. `loopStb` 可能是 STB analysis instance，而 `stb` 可能是 PSF/OCEAN result name。
3. Formal phase margin 应使用 local loop-gain waveform 验证过的 sign convention。
4. 使用精确 runner 与 report filenames；不要把下一个 command 接进 `tee` filename。
5. 对 generated `mcdata` 使用 whitespace-aware parsing。
6. 对 frequency 或 UGF values 使用支持 scientific notation 的 numeric sorting。
7. 使用普通 `for` syntax，并让 `do`/`done` 位在有效 shell lines。

## 13. Retention and Cleanup

保留：

1. Scalar `mcdata` 与 `mcparam` files
2. Latest reports、analysis files 与 sample tables
3. Checksums、status files、audit logs 与 `.complete` markers
4. Input schemas
5. Final runner/report scripts 与本章

当 scalar 与 audit artifacts 已验证后，不要只为了方便而保留大型 raw waveform files。
仍被 correlation hash 或 report 引用的 result tree 不可删除。

## 14. Next Chapter

Offset、performance 与 correlated-transient Monte Carlo 验证后，接着看
[第 14 章](14-final-pre-simulation-signoff.md)，冻结 handoff state，并定义
post-simulation 前的边界。
