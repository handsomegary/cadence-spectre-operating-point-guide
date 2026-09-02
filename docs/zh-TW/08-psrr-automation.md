# 第 8 章：PSRR Automation

本章整理 five-transistor OTA 在 Cadence Virtuoso、Spectre 與 OCEAN 下的
PSRR+ 與 PSRR- 自動化流程。

原始筆記包含本機路徑、project name、net name、一次性的 checkpoint name 與 script
hash。公開版保留工程方法，並用占位字替換可能涉及隱私的環境資訊。

## 1. 範圍

本流程包含：

1. PSRR definition choices
2. 共用 PSRR AC 條件
3. PSRR+ supply-injection setup
4. PSRR- local-VSS setup
5. OCEAN 執行與 raw export 驗證
6. Formal input-referred PSRR 與 direct rejection 後處理
7. PSRR+ 與 PSRR- 結果比較
8. 工程判讀
9. 常見錯誤與安全復原
10. Working checkpoints

這些命令預設在遠端 Linux Cadence environment 執行，通常由 MobaXterm 或其他 SSH
terminal 貼上。

## 2. PSRR 定義

報告 supply rejection 時，一定要說明使用哪一種定義。

本流程保存兩種表示法：

```text
Direct supply rejection = |Vsupply / Vout|
Formal input-referred PSRR = |Ad / (Vout / Vsupply)|
```

dB 表示：

```text
Direct rejection dB = -Supply-to-output gain dB
Formal PSRR dB = Differential gain dB - Supply-to-output gain dB
```

本章主要 PSRR 指標採用 formal input-referred definition。Direct rejection 仍保留，
因為它可以追蹤真實 supply-to-output coupling path。

## 3. 共用 AC 條件

Nominal setup 示例：

```text
Process corner:          <process-corner>
Temperature:             27 deg C
VDD:                     1.2 V
VCM:                     800 mV
VID:                     0 V
Load capacitance:        100 fF
Frequency start:         1 Hz
Frequency stop:          100 GHz
Sweep density:           100 points per decade
Expected numeric points: 1101
```

PSRR simulation 時，關閉所有 differential input AC excitation：

```text
Vin+ DC value:       VCM + VID/2
Vin+ AC magnitude:   0
Vin+ AC phase:       0 deg

Vin- DC value:       VCM - VID/2
Vin- AC magnitude:   0
Vin- AC phase:       180 deg
```

Formal PSRR 後處理使用已驗證的 differential open-loop AC result 作為 `Ad(f)`：

```text
/home/<linux-user>/simulation/<ota-project>_ocean/ac_openloop/ac_gain_raw.txt
```

## 4. PSRR+ Testbench

PSRR+ 在 positive supply 注入 `1 V` small-signal AC source：

```text
VDD source: DC = 1.2 V, AC magnitude = 1 V, phase = 0 deg
VSS:        global 0
Inputs:     DC bias only, AC magnitude = 0
Bias:       DC only
```

OCEAN expression 示例：

```lisp
vddWave = v("/vdd")
supplyGainWave = v("/vout") / vddWave
directPsrrPlusWave = vddWave / v("/vout")
```

建立 result directory：

```bash
mkdir -p /home/<linux-user>/simulation/<ota-project>_ocean/ac_psrr_plus
```

執行 PSRR+：

```bash
cd /home/<linux-user>/cadence_projects/<ota-project> || exit 1
set -o pipefail
ocean -nograph -restore psrr_plus_sweep.ocn 2>&1 | tee psrr_plus_sweep_run.log
run_status=${PIPESTATUS[0]}
echo "OCEAN_EXIT_STATUS=$run_status"
```

驗證 raw data：

```bash
if [ -s /home/<linux-user>/simulation/<ota-project>_ocean/ac_psrr_plus/psrr_plus_raw.txt ]; then
    echo "PSRR_PLUS_RAW_VERIFIED"
else
    echo "ERROR: PSRR_PLUS_RAW_MISSING"
fi
```

## 5. PSRR- Testbench

PSRR- 不要直接對 Spectre global node `0` 注入 AC。請建立 local VSS node，並把 OTA
本體的 negative-supply terminals 接到該節點。

本流程使用 fixed-absolute-input setup：

1. Tail-device source 與 body 接到 local `vss`。
2. NM input-pair bodies 接到 local `vss`。
3. VSS source 在 local `vss` 與 global `0` 之間提供 `DC = 0 V` 與 `AC = 1 V`。
4. VDD、input sources、tail-bias voltage source 與 external load capacitor 仍參考
   global `0`。

這是 fixed-absolute-input 與 fixed-absolute-bias PSRR- 測試。若真實系統的 bias
voltage 由 VSS-referenced circuit 產生，請另建 tracking-bias PSRR- variant，不要與
本曲線混用。

建立完整 PSRR- netlist directory copy：

```bash
mkdir -p /home/<linux-user>/simulation/<ota-project>_psrr_minus/spectre/schematic/netlist
cp -a \
  /home/<linux-user>/simulation/<ota-project>_psrr_plus/spectre/schematic/netlist/. \
  /home/<linux-user>/simulation/<ota-project>_psrr_minus/spectre/schematic/netlist/
```

只修改 copied netlist。實際 device 與 source name 取決於你的 schematic，所以請先用
`grep` 檢查相關行，再只做以下邏輯修改：

```text
Tail device source/body:      0 -> vss
Input-pair bodies:            0 -> vss
VDD source:                   AC=1 -> DC-only
Added local VSS source:       VSS (vss 0) vsource dc=0 mag=1 phase=0 type=sine
```

若要用 `sed` 自動化，請匹配你自己的 netlist exact names，並保留 `.pre_psrr_minus`
backup。

OCEAN expression 示例：

```lisp
vssWave = v("/vss")
supplyGainWave = v("/vout") / vssWave
directPsrrMinusWave = vssWave / v("/vout")
```

執行 PSRR-：

```bash
set -o pipefail
ocean -nograph -restore psrr_minus_sweep.ocn 2>&1 | tee psrr_minus_sweep_run.log
run_status=${PIPESTATUS[0]}
echo "OCEAN_EXIT_STATUS=$run_status"
```

檢查 log 與 raw data：

```bash
grep -nEi 'ERROR|FATAL|SYNTAX|Segmentation|SPECTRE-|PSRR- AC sweep completed' \
psrr_minus_sweep_run.log
```

```bash
if [ -s /home/<linux-user>/simulation/<ota-project>_ocean/ac_psrr_minus/psrr_minus_raw.txt ]; then
    echo "PSRR_MINUS_RAW_VERIFIED"
else
    echo "ERROR: PSRR_MINUS_RAW_MISSING"
fi
```

## 6. PSRR Post-Processing

執行 PSRR+ analyzer：

```bash
awk \
  -v combined="/home/<linux-user>/simulation/<ota-project>_ocean/ac_psrr_plus/psrr_plus_combined_raw.txt" \
  -f analyze_psrr_plus_v1.awk \
  /home/<linux-user>/simulation/<ota-project>_ocean/ac_openloop/ac_gain_raw.txt \
  /home/<linux-user>/simulation/<ota-project>_ocean/ac_psrr_plus/psrr_plus_raw.txt \
  | tee /home/<linux-user>/simulation/<ota-project>_ocean/ac_psrr_plus/psrr_plus_analysis.txt
```

執行 PSRR- analyzer：

```bash
awk \
  -v combined="/home/<linux-user>/simulation/<ota-project>_ocean/ac_psrr_minus/psrr_minus_combined_raw.txt" \
  -f analyze_psrr_minus_v1.awk \
  /home/<linux-user>/simulation/<ota-project>_ocean/ac_openloop/ac_gain_raw.txt \
  /home/<linux-user>/simulation/<ota-project>_ocean/ac_psrr_minus/psrr_minus_raw.txt \
  | tee /home/<linux-user>/simulation/<ota-project>_ocean/ac_psrr_minus/psrr_minus_analysis.txt
```

兩個 analyzer 都應確認：

```text
DIFFERENTIAL_NUMERIC_POINTS=1101
PSRR_*_NUMERIC_POINTS=1101
FREQUENCY_GRID=VERIFIED
```

## 7. PSRR+ Results 示例

Formal input-referred PSRR+ 結果示例：

```text
LOW_FREQUENCY_FORMAL_PSRR_PLUS=31.452236 V/V
LOW_FREQUENCY_FORMAL_PSRR_PLUS=29.953026 dB
PSRR_PLUS_3DB_BANDWIDTH=185.697346 MHz
PSRR_PLUS_20DB_BANDWIDTH=553.847737 MHz
PSRR_PLUS_10DB_BANDWIDTH=1.802096 GHz
PSRR_PLUS_0DB_CROSSING=5.392464 GHz
MINIMUM_PSRR_PLUS_1HZ_TO_UGF=15.725680 dB
PSRR_PLUS_AT_NEAREST_UGF=15.530523 dB
```

Spot values：

```text
1 Hz:       29.953026 dB
1 kHz:      29.953026 dB
1 MHz:      29.952903 dB
10 MHz:     29.940518 dB
100 MHz:    28.852231 dB
1 GHz:      15.138914 dB
10 GHz:     -5.574950 dB
100 GHz:   -22.029000 dB
```

## 8. PSRR- Results 示例

Formal input-referred PSRR- 結果示例：

```text
LOW_FREQUENCY_FORMAL_PSRR_MINUS=31.458994 V/V
LOW_FREQUENCY_FORMAL_PSRR_MINUS=29.954892 dB
PSRR_MINUS_3DB_BANDWIDTH=59.132436 MHz
PSRR_MINUS_20DB_BANDWIDTH=176.984285 MHz
PSRR_MINUS_10DB_BANDWIDTH=594.338332 MHz
PSRR_MINUS_0DB_CROSSING=2.186329 GHz
MINIMUM_PSRR_MINUS_1HZ_TO_UGF=6.268900 dB
PSRR_MINUS_AT_NEAREST_UGF=6.082411 dB
```

Spot values：

```text
1 Hz:       29.954892 dB
1 kHz:      29.954892 dB
1 MHz:      29.953658 dB
10 MHz:     29.832983 dB
100 MHz:    24.106233 dB
1 GHz:       5.711071 dB
10 GHz:     -2.456120 dB
100 GHz:   -11.361810 dB
```

## 9. PSRR+ 與 PSRR- 比較

示例比較：

| Metric | PSRR+ | PSRR- |
| --- | ---: | ---: |
| Low-frequency formal PSRR | 29.953 dB | 29.955 dB |
| 3 dB bandwidth | 185.697 MHz | 59.132 MHz |
| 20 dB bandwidth | 553.848 MHz | 176.984 MHz |
| 10 dB bandwidth | 1.802 GHz | 594.338 MHz |
| 0 dB crossing | 5.392 GHz | 2.186 GHz |
| Formal PSRR at 100 MHz | 28.852 dB | 24.106 dB |
| Formal PSRR near UGF | 15.531 dB | 6.082 dB |
| Formal PSRR at 1 GHz | 15.139 dB | 5.711 dB |

## 10. 工程判讀

示例判讀：

1. 低頻 PSRR+ 與 PSRR- 幾乎完全相同，差異只有約 `0.0019 dB`。
2. 兩側低頻 supply-to-output gain 都接近 `1 V/V`。輸出幾乎完整跟隨低頻 supply
   ripple，因此約 `30 dB` formal PSRR 主要來自 differential open-loop gain，而不是
   supply path 本身有很強的隔離。
3. PSRR- 的 3 dB bandwidth 只有 PSRR+ 約三分之一，表示 negative-rail coupling 在
   中高頻更早惡化。
4. 100 MHz 時，PSRR- 比 PSRR+ 低約 `4.75 dB`。UGF 附近，PSRR- 低約 `9.45 dB`。
5. 對高速 operation，本例中 negative-rail cleanliness 比 positive-rail cleanliness
   更關鍵。
6. Formal PSRR 在 UGF 以上變成負值。這些 very-high-frequency values 可用來確認曲線
   連續性，但不應當成正常 closed-loop operating-range specification。
7. 若要求 precision-grade supply rejection，約 `30 dB` 的低頻 PSRR 不足。若是基本
   high-speed OTA，仍需依實際 supply ripple、closed-loop noise gain 與 signal
   bandwidth 評估是否可接受。

## 11. 改善方向

常見 PSRR 改善方向：

1. 提高 PM active load 與 NM tail-current source 的 output resistance。
2. 若 headroom 允許，使用 cascodes 或 regulated-cascode bias structures。
3. 對 VDD、VSS 與 bias node 增加適當 decoupling，並在 system-level evaluation 中納入
   實際 package 與 PCB impedance。
4. 若 bias voltage 由 VSS-referenced circuit 產生，另做 tracking-bias PSRR- analysis。
5. 改善 supply routing、guarding、substrate isolation 與 layout symmetry。
6. 修改 sizing 或 topology 後，必須重跑 DC operating point、VCM、VID、AC、STB、
   transient、noise、CMRR 與兩側 PSRR。

## 12. 常見錯誤與防呆

不要只複製單一 netlist file：

```text
OCEAN design flow 可能還需要 netlistHeader、amap 與其他 Cadence netlist-directory files。
```

若 OCEAN 顯示這個 prompt：

```text
>
```

代表你仍在 OCEAN parser。請先離開：

```lisp
exit()
```

之後才能執行 `PIPESTATUS`、`grep`、`awk` 等 shell commands。

Pipeline 結束並回到 shell prompt 後，必須立刻保存 `PIPESTATUS`。

OCEAN completion `printf` 不是成功證明。真正成功條件是：

```text
Raw file exists
Raw file is not empty
Numeric point count is correct
Frequency grid matches the differential AC run
Log has no fatal error
```

檢查 PSRR- analyzer 是否誤含 PSRR+ 變數時，不要用 `grep -E 'plus|\+'` 這種過寬
pattern，因為它也會匹配正常 AWK arithmetic operator。請用精確名稱：

```bash
grep -nE 'psrr_plus|psrrPlus|PSRR_PLUS|PSRR\+' analyze_psrr_minus_v1.awk
```

預期結果是完全沒有輸出。

## 13. Working Checkpoints

驗證後保存 PSRR+ artifacts：

```bash
cd /home/<linux-user>/cadence_projects/<ota-project> || exit 1
stamp=$(date +%Y%m%d_%H%M%S)

cp -p -- psrr_plus_sweep.ocn "psrr_plus_sweep.ocn.working_$stamp"
cp -p -- analyze_psrr_plus_v1.awk "analyze_psrr_plus_v1.awk.working_$stamp"
cp -p -- \
  /home/<linux-user>/simulation/<ota-project>_psrr_plus/spectre/schematic/netlist/netlist \
  "/home/<linux-user>/simulation/<ota-project>_psrr_plus/spectre/schematic/netlist/netlist.working_$stamp"
```

驗證後保存 PSRR- artifacts：

```bash
cp -p -- psrr_minus_sweep.ocn "psrr_minus_sweep.ocn.working_$stamp"
cp -p -- analyze_psrr_minus_v1.awk "analyze_psrr_minus_v1.awk.working_$stamp"
cp -p -- \
  /home/<linux-user>/simulation/<ota-project>_psrr_minus/spectre/schematic/netlist/netlist \
  "/home/<linux-user>/simulation/<ota-project>_psrr_minus/spectre/schematic/netlist/netlist.working_$stamp"
```

請用 `sha256sum` 或 `cmp -s` 驗證，並把 matching hashes 保存在私人 lab notes，不要放進
公開 tutorial。

## 14. 完成狀態

```text
[x] Independent PSRR+ netlist directory created and verified.
[x] PSRR+ AC sweep completed.
[x] PSRR+ 1101 numeric points verified.
[x] Formal and direct PSRR+ analysis completed.
[x] PSRR+ working checkpoints created and verified.
[x] Independent PSRR- local-VSS netlist directory created and verified.
[x] PSRR- AC sweep completed.
[x] PSRR- 1101 numeric points verified.
[x] PSRR- and differential AC frequency grids verified.
[x] Formal and direct PSRR- analysis completed.
[x] PSRR+ and PSRR- analysis and combined raw data saved.
[x] PSRR- working checkpoints created and verified.
```

## 15. 下一步

PSRR baseline characterization 已完成。下一個有用的 artifact 是整合 DC、AC、STB、
transient、noise、CMRR 與 PSRR 的 baseline summary table，再用該表規劃 PVT corners、
load sweep、VCM-dependent PSRR 與 Monte Carlo analysis。
