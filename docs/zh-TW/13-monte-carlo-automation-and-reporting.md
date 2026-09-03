# 第 13 章：Monte Carlo Automation and Reporting

本章延續第 12 章的 frozen baseline 與 deterministic PVT workflow，整理 Monte Carlo
preparation、random-stream correlation、scalar schemas、statistical report builders
與 acceptance gates。

原始筆記包含真實 result roots、PDK details、wrapper names 與 local filenames。公開版
保留方法，並把私密環境資訊替換成 placeholders。

```text
Document version: 1
Date: 2026-09-03
Status: verified pre-simulation continuation
```

## 1. Monte Carlo Freeze Contract

Monte Carlo 必須使用與 frozen baseline 相同的 verified unity-feedback topology。

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

Canonical netlists 保持 read-only。每個 runner 會把 source 複製到 private result/input
tree，驗證 topology，只轉換目標 MOS devices，並記錄 input checksums。

## 2. Device-Wrapper and PDK Contract

Randomized MOS devices 應使用 installed PDK 提供的 wrapper models。

Public template variables：

```text
MC_NOMINAL_NMOS_MODEL
MC_NOMINAL_PMOS_MODEL
MC_NMOS_MISMATCH_WRAPPER
MC_PMOS_MISMATCH_WRAPPER
MC_MODEL_SECTION
```

Five-transistor OTA 示例中，generated netlist 應包含：

```text
Five wrapper devices
Five mismatch-enabled devices
Zero remaining nominal MOS model instances
One correctly connected STB probe
```

未確認 installed model library 與 generated netlist 前，不要替換成另一個 PDK installation
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

每個 production tree 都有自己的 `input`、`psf`、`logs`、`summary`、`report` 與
completion-marker structure。不要混用不同 run IDs 的檔案。

## 4. Performance Monte Carlo Runner

Public template：

```text
scripts/monte-carlo/run_monte_carlo_performance_smoke.sh
```

先檢查 syntax：

```bash
bash -n scripts/monte-carlo/run_monte_carlo_performance_smoke.sh
```

建議流程：

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

Smoke run 通過後，再執行 production：

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

Process-only 與 mismatch-only production runs 使用相同 seed 與 topology，分別設定
`MC_VARIATIONS=process` 與 `MC_VARIATIONS=mismatch`。

## 5. Performance Scalar Schema

Performance scalar file 每個 sample 有六個 numeric columns：

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
| `VDD_POWER_W` | Positive supply power；回報消耗功率時優先使用。 |
| `LOOP_GAIN_DB_1HZ` | 1 Hz 的 loop-gain magnitude，單位 dB。 |
| `UGF_HZ` | 從 loop-gain waveform 得到的 unity-gain frequency。 |
| `PHASE_MARGIN_DEG` | 使用修正後 sign convention 的 formal positive phase margin。 |

`VDD_CURRENT_A` 可能因 terminal-current sign convention 而為負值；`VDD_POWER_W` 才是建議
用來回報 consumed power 的正值 metric。

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

Builder 會拒絕以下 source run：

1. 未標記為 `PASSED`
2. Row count 錯誤
3. 包含 nonnumeric rows
4. 包含 column count 錯誤的 rows
5. 有 nonpositive UGF values

成功時會輸出 report、analysis、sample table 與 SHA-256 files。

## 7. Offset Monte Carlo

Offset Monte Carlo 應用相同 seed 與 topology，分別執行 `all`、`process`、`mismatch`
variations。

Offset report 應保留：

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
checksums、status files 與 completion markers 都驗證後再移除。

## 8. Correlated Transient Monte Carlo

Public template：

```text
scripts/monte-carlo/run_monte_carlo_transient_validation.sh
```

Transient run 刻意使用與 all-variation performance run 相同的 seed 與 random streams。
在用 sample IDs 做 correlation 前，必須 byte-for-byte 比對 process 與 mismatch stream
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

較長的 pulse period 可避免 30 ns observation window 內出現第二個 pulse。

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

Report builder 會由 fixed-time samples 推導 high-step amplitude、high-step error 與
return errors，不需要在 Monte Carlo `oceanEval` 裡做 waveform max/min reductions。

## 10. Statistical Report Convention

每份 report 包含：

| Field | Meaning |
| --- | --- |
| `N` | Valid samples 數量。 |
| `MEAN` | Valid samples 的 arithmetic mean。 |
| `SAMPLE_SIGMA` | Sample standard deviation。 |
| `MIN` | Minimum valid sample。 |
| `MAX` | Maximum valid sample。 |

Report 也保留完整 tab-separated sample table 與 SHA-256 checksums。

## 11. Acceptance Gates

Production campaign 只有在以下條件通過時才接受：

1. Spectre exit status 是 0。
2. Log error count 是 0。
3. Failed Monte Carlo iterations 是 0。
4. Expected row count 是 200，或文件明確指定的 production count。
5. 所有 scalar rows 都有正確 numeric column count。
6. 沒有 invalid numeric rows。
7. Performance rows 的 UGF 全部為正。
8. Formal phase margin 使用已驗證的 sign convention。
9. 必要 report、sample、analysis、checksum、status 與 `.complete` files 都存在。
10. Correlated transient 的 process 與 mismatch hashes 符合 reference run。

乾淨 Spectre log 裡的 warnings 與 notices 不會自動讓 campaign 失敗；但任何會改變量測值的
warning 都必須調查並記錄。

## 12. Version and Filename Notes

保留這些修正：

1. 某些 Spectre/OCEAN environments 在 Monte Carlo `oceanEval` 裡做 max/min waveform
   reductions 可能回傳 `nil`；fixed-time scalar samples 是較 portable 的 fallback。
2. `loopStb` 可能是 STB analysis instance，而 `stb` 可能是 PSF/OCEAN result name。
3. Formal phase margin 應使用 local loop-gain waveform 驗證過的 sign convention。
4. 使用精確 runner 與 report filenames；不要把下一個 command 接進 `tee` filename。
5. 對 generated `mcdata` 使用 whitespace-aware parsing。
6. 對 frequency 或 UGF values 使用支援 scientific notation 的 numeric sorting。
7. 使用普通 `for` syntax，並讓 `do`/`done` 位在有效 shell lines。

## 13. Retention and Cleanup

保留：

1. Scalar `mcdata` 與 `mcparam` files
2. Latest reports、analysis files 與 sample tables
3. Checksums、status files、audit logs 與 `.complete` markers
4. Input schemas
5. Final runner/report scripts 與本章

當 scalar 與 audit artifacts 已驗證後，不要只為了方便而保留大型 raw waveform files。
仍被 correlation hash 或 report 引用的 result tree 不可刪除。

## 14. Next Chapter

Offset、performance 與 correlated-transient Monte Carlo 驗證後，接著看
[第 14 章](14-final-pre-simulation-signoff.md)，凍結 handoff state，並定義
post-simulation 前的邊界。
