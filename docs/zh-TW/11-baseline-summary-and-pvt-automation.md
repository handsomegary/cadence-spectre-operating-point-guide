# 第 11 章：Baseline Summary and PVT Automation

本章整合 five-transistor OTA 的 nominal baseline，並把下一階段 characterization
整理成可重用的 deterministic process-corner workflow。

原始筆記包含本機路徑、project name、process-file details、generated filenames 與
machine-specific script settings。公開版保留工程方法，並用占位字替換可能涉及隱私的
環境資訊。

## 1. 範圍

本章包含：

1. Frozen nominal baseline conditions
2. DC、AC、STB、transient、noise、CMRR 與 PSRR summary metrics
3. 跨分析一致性 cross-checks
4. Baseline strengths and limitations
5. Deterministic process-corner automation flow
6. Refined near-zero VID linearity workflow
7. Completed corners 的 transient metric extraction
8. Consolidated process-corner report generation
9. 發布前需要保留在私人筆記中的內容

Reusable shell-script templates 存在：

```text
scripts/pvt/run_process_corners.sh
scripts/pvt/refine_vid_linearity.sh
scripts/pvt/analyze_process_corner_transients.sh
scripts/pvt/build_process_corner_report.sh
```

## 2. Frozen Nominal Conditions

Nominal baseline 示例：

```text
Process corner:              TT
Temperature:                 27 deg C
VDD:                         1.2 V
Bias voltage:                550 mV
Input common-mode voltage:   800 mV
Differential DC input:       0 V
Load capacitance:            100 fF
```

Device dimensions 示例：

```text
NM0/NM1: W = 4 um,  L = 260 nm
NM2:     W = 8 um,  L = 260 nm
PM0/PM1: W = 10 um, L = 260 nm
```

已完成 nominal analyses：

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

任何 schematic sizing、bias、model、load 或 netlist 變更，都會使 frozen baseline 失效，
需要重跑受影響的 analyses。

## 3. DC Operating Point Summary

Current 與 power 示例：

```text
Estimated VDD current:       139.300253 uA
Estimated DC power:          167.160304 uW
Tail current:                139.299600 uA
Input-pair current sum:      139.300020 uA
Current-balance error:       0.420080 nA
```

Device operating points 示例：

| Device | Current | gm | gm/Id | ro | Saturation margin |
| --- | ---: | ---: | ---: | ---: | ---: |
| NM0 | 69.6500 uA | 0.789655 mS | 11.3375 1/V | 91.2000 kOhm | 353.913 mV |
| NM1 | 69.6500 uA | 0.789655 mS | 11.3375 1/V | 91.1998 kOhm | 353.912 mV |
| NM2 | 139.2996 uA | 1.497467 mS | 10.7500 1/V | 12.9244 kOhm | 67.113 mV |
| PM0 | 69.6501 uA | 0.736229 mS | 10.5704 1/V | 71.8353 kOhm | 322.662 mV |
| PM1 | 69.6501 uA | 0.736230 mS | 10.5704 1/V | 71.8354 kOhm | 322.663 mV |

Nominal operating point 下所有 MOS 都在 saturation。Tail device 的 saturation margin
最小、output resistance 最低，因此是 headroom、CMRR 與 negative-rail coupling 的重要
限制點。

## 4. DC Range Summary

VCM sweep 示例：

```text
Sweep range:                         0 V to 1.2 V
Step:                                10 mV
Point count:                         121
All-devices-saturated low sample:    0.720 V
All-devices-saturated high sample:   1.200 V
```

低端 transition 在 `0.710 V` 與 `0.720 V` 之間。高端碰到 sweep boundary，因此請寫成：

```text
VCM high >= 1.200 V within the tested sweep
```

除非用更寬的 sweep 證明，否則不要把 `1.200 V` 當成真正高端失效點。

VID sweep 示例：

```text
Sweep range:              -50 mV to +50 mV
Step:                     100 uV
Point count:              1001
VID saturation range:     -18.2 mV to +13.8 mV
VOUT at VID=0:            0.7039498 V
Center DC gain:           31.434502 V/V
Center DC gain:           29.948132 dB
```

以 center small-signal slope 為基準的 secant-gain deviation：

```text
0.1 percent VID range:       -0.1 mV to +0.1 mV
0.1 percent VID width:        0.2 mV
0.1 percent VOUT range:       0.7008088 V to 0.7070957 V

1 percent VID range:         -1.0 mV to +2.0 mV
1 percent VID width:          3.0 mV
1 percent VOUT range:         0.6727987 V to 0.7674419 V
```

Saturation range 與 linear range 是不同規格。元件仍在 saturation，不代表 transfer curve
仍符合 0.1 percent 或 1 percent linearity requirement。

## 5. AC and STB Summary

Open-loop differential AC：

```text
Low-frequency gain:             31.434620 V/V
Low-frequency gain:             29.948160 dB
Unity-gain frequency:           949.525439 MHz
Sweep:                          1 Hz to 100 GHz, 100 points/decade
```

Unity-feedback STB：

```text
Low-frequency loop gain:        31.77780 V/V
Low-frequency loop gain:        30.04247 dB
Phase margin:                   79.63017 deg
Phase-margin frequency:         894.2901 MHz
Gain margin:                    NOT_FOUND_WITHIN_1HZ_TO_100GHZ
```

STB phase 在 sweep 範圍內沒有到達 Cadence gain-margin calculation 需要的 crossing。
這種情況下 `nan` gain margin 本身不代表 simulation failure 或 instability。

STB crossover 與 open-loop differential UGF 使用不同 testbench/result definition，
所以 `894.29 MHz` 與 `949.53 MHz` 不必完全相同。Unity-feedback stability 請採 formal
STB phase margin。

## 6. Transient Summary

100 mV input step 示例：

```text
Closed-loop gain:               0.965503 V/V
Rise time, 10 percent to 90:    300.718 ps
Fall time, 90 percent to 10:    308.805 ps
Max positive slope, 20 ps:      380.875 V/us
Max negative slope, 20 ps:     -349.280 V/us
Rise settling, 1 percent:       0.509337 ns
Rise settling, 0.1 percent:     0.929337 ns
Fall settling, 1 percent:       0.497341 ns
Fall settling, 0.1 percent:     0.979341 ns
```

140 mV input step 示例：

```text
Closed-loop gain:               0.965297 V/V
Rise time, 10 percent to 90:    304.686 ps
Fall time, 90 percent to 10:    316.884 ps
Max positive slope, 20 ps:      527.820 V/us
Max negative slope, 20 ps:     -467.490 V/us
Rise settling, 1 percent:       0.520061 ns
Rise settling, 0.1 percent:     0.924061 ns
Fall settling, 1 percent:       0.506299 ns
Fall settling, 0.1 percent:     0.996299 ns
Rise overshoot:                 0.21355 percent
Fall undershoot:                0.50229 percent
```

從 100 mV 到 140 mV，output step 幾乎同比增加，rise/fall time 與 settling time 接近，
maximum slope 仍增加：

```text
HARD_SLEW_RATE_CEILING=NO
POSITIVE_PATH_COMPRESSION=MINIMAL
NEGATIVE_PATH_COMPRESSION=MILD
LARGE_SIGNAL_OPERATION_AT_140MV=ACCEPTABLE
```

## 7. Noise、CMRR and PSRR Summary

Open-loop input-referred noise：

```text
White-noise floor:       7.4005 nV/sqrt(Hz)
Flicker-noise corner:    13.8629 MHz

1 Hz to 1 kHz:           123.936 uV RMS
1 Hz to 1 MHz:           150.133 uV RMS
1 Hz to 10 MHz:          157.775 uV RMS
1 Hz to 100 MHz:         176.956 uV RMS
1 Hz to UGF:             276.975 uV RMS
```

Noise contribution summary：

```text
Low-frequency flicker noise:    dominated by PM current-mirror devices
Corner-region noise:            NM input pair and PM mirror both contribute
White/high-frequency noise:     dominated by NM input pair
Tail-device contribution:       negligible under nominal conditions
```

CMRR：

```text
Low-frequency CMRR:         57.850270 dB
CMRR 3 dB bandwidth:        58.853855 MHz
CMRR >= 40 dB bandwidth:    414.847335 MHz
CMRR >= 20 dB bandwidth:    2.049543 GHz
CMRR at 100 MHz:            51.942680 dB
CMRR near differential UGF: 30.465873 dB
```

Formal input-referred PSRR：

| Metric | PSRR+ | PSRR- |
| --- | ---: | ---: |
| Low-frequency PSRR | 29.953 dB | 29.955 dB |
| 3 dB bandwidth | 185.697 MHz | 59.132 MHz |
| 20 dB bandwidth | 553.848 MHz | 176.984 MHz |
| 10 dB bandwidth | 1.802 GHz | 594.338 MHz |
| 0 dB crossing | 5.392 GHz | 2.186 GHz |
| PSRR at 100 MHz | 28.852 dB | 24.106 dB |
| PSRR near differential UGF | 15.531 dB | 6.082 dB |
| PSRR at 1 GHz | 15.139 dB | 5.711 dB |

本文件的 PSRR- fixture 使用 local VSS node，而 VDD、inputs、bias 與 load 仍參考
global `0`。VSS-tracking bias system 需要另做獨立 PSRR- analysis。

## 8. Cross-Checks

實用 consistency checks：

1. VID center DC gain 是 `29.948132 dB`。
2. Open-loop low-frequency AC gain 是 `29.948160 dB`。
3. 差異約 `0.000028 dB`。
4. Differential AC、noise、CMRR、PSRR+ 與 PSRR- 都有 `1101` 個 numeric frequency
   points，範圍為 1 Hz 到 100 GHz。
5. 每個 paired post-processor 都會先驗證 frequency grid 再合併曲線。
6. Input-pair current sum 與 tail current 只差 `0.420 nA`。

這些檢查讓 baseline 足夠 coherent，可以先 freeze 再進入 process-corner automation。

## 9. Engineering Assessment

Strengths：

1. Nominal power 低，`1.2 V` 下約 `167.2 uW`。
2. 相對 current 的 bandwidth 高，`139.3 uA` 下約 `949.5 MHz` UGF。
3. Nominal unity-feedback stability 強，phase margin 為 `79.63 deg`。
4. Sub-nanosecond transient response 快，overshoot 低。
5. 到測試的 `140 mV` input step 為止，未觀察到 hard slew-rate ceiling。
6. Nominal device matching 與 current balance 良好。

Primary limitations：

1. Open-loop gain 偏低，約 `29.95 dB`。
2. Low-frequency CMRR 只有約 `57.85 dB`。
3. Low-frequency formal PSRR 只有約 `29.95 dB`。
4. PSRR- 在高頻比 PSRR+ 更快惡化。
5. Flicker-noise corner 偏高，約 `13.86 MHz`。
6. Tail device nominal saturation margin 只有約 `67.1 mV`，且 output resistance 低。
7. 嚴格 0.1 percent open-loop VID linearity 只有約 `+/-0.1 mV`。

## 10. PVT Automation Flow

執行大型 matrix 前：

1. Freeze and hash golden nominal netlist 與所有 baseline scripts。
2. 從 PDK documentation 確認支援的 process-section names。
3. 依 design specification 定義 voltage 與 temperature ranges。
4. 先對 process matrix 跑 DC operating point、open-loop AC 與 STB。
5. 再選 worst corners 重跑 transient、noise、CMRR 與 PSRR。
6. Deterministic PVT 穩定後，再做 load sweep 與 Monte Carlo mismatch。

使用 process-corner runner template：

```bash
cd /home/<linux-user>/cadence_projects/<ota-project> || exit 1
PROJECT_DIR="$PWD" \
RESULT_ROOT="/home/<linux-user>/simulation/<ota-project>_ocean" \
PVT_CORNERS="ff ss fnsp snfp" \
bash scripts/pvt/run_process_corners.sh prepare
```

檢查 generated scripts 後：

```bash
PROJECT_DIR="$PWD" \
RESULT_ROOT="/home/<linux-user>/simulation/<ota-project>_ocean" \
PVT_CORNERS="ff ss fnsp snfp" \
bash scripts/pvt/run_process_corners.sh core
```

Core matrix 乾淨後才跑 `full`：

```bash
PVT_FORCE=0 \
PROJECT_DIR="$PWD" \
RESULT_ROOT="/home/<linux-user>/simulation/<ota-project>_ocean" \
bash scripts/pvt/run_process_corners.sh full
```

## 11. Refined VID Linearity

Coarse VID sweep 適合找範圍；near-zero linearity 可能需要更細 step：

```bash
PROJECT_DIR="$PWD" \
RESULT_ROOT="/home/<linux-user>/simulation/<ota-project>_ocean" \
PVT_CORNERS="ss fnsp" \
VID_REFINED_START="-5m" \
VID_REFINED_STOP="5m" \
VID_REFINED_STEP="10u" \
bash scripts/pvt/refine_vid_linearity.sh
```

當 coarse step 太大時，請用 refined results 建立最終 0.1 percent 或 1 percent VID
linearity table。

## 12. Transient and Report Post-Processing

從 completed corner raw files 擷取 transient metrics：

```bash
PROJECT_DIR="$PWD" \
RESULT_ROOT="/home/<linux-user>/simulation/<ota-project>_ocean" \
PVT_CORNERS="ff ss fnsp snfp" \
bash scripts/pvt/analyze_process_corner_transients.sh
```

建立 consolidated process-corner report：

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

Generated reports 在發布前必須保留為 private，直到 paths、PDK names、machine names 與
unpublished circuit names 都完成 sanitization。

## 13. Completion Checklist

```text
[x] Nominal DC operating point summarized.
[x] Nominal VCM and VID ranges summarized.
[x] Nominal AC and STB summarized.
[x] Nominal transient response summarized.
[x] Nominal noise, CMRR, and PSRR summarized.
[x] Cross-checks documented.
[x] Deterministic process-corner runner template added.
[x] Refined VID linearity template added.
[x] Process-corner transient analyzer template added.
[x] Process-corner report builder template added.
[ ] Voltage and temperature matrix finalized from the specification.
[ ] PVT reports generated and reviewed.
[ ] Load sweep and Monte Carlo mismatch completed.
```

## 14. 下一步

Baseline 已準備好進入 deterministic PVT。先用 `prepare` mode 檢查 generated OCEAN
scripts，再跑 `core` process matrix，最後才擴展到 full analysis set。
