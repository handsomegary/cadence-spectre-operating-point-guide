# 第 7 章：CMRR Automation

本章整理 five-transistor OTA 在 Cadence Virtuoso、Spectre 與 OCEAN 下的
common-mode rejection ratio，也就是 CMRR，自動化流程。

原始筆記包含本機路徑、project name、net name 與一次性的 debug history。公開版保留
工程方法，並用占位字替換可能涉及隱私的環境資訊。

## 1. 範圍

本流程包含：

1. Differential-mode 與 common-mode excitation
2. 建立完整 common-mode netlist copy
3. Common-mode AC OCEAN setup
4. Common-mode raw export 驗證
5. 由 differential gain 與 common-mode gain 後處理 CMRR
6. Bandwidth 與 spot-value 擷取
7. 工程判讀
8. 常見錯誤與安全復原
9. Working checkpoints

這些命令預設在遠端 Linux Cadence environment 執行，通常由 MobaXterm 或其他 SSH
terminal 貼上。

## 2. CMRR 定義

使用相同頻率下的 open-loop differential gain 與 common-mode gain：

```text
CMRR(f) = |Ad(f)| / |Acm(f)|
CMRR_dB(f) = 20 log10(CMRR(f))
CMRR_dB(f) = Ad_dB(f) - Acm_dB(f)
```

`Ad` 是 differential-mode gain。`Acm` 是 common-mode gain。

兩條曲線必須使用相同 frequency grid，才能相減或相除。

## 3. Differential 與 Common-Mode Excitation

既有 differential AC testbench 使用兩個反相 input sources：

```text
Vin+ DC value:       VCM + VID/2
Vin- DC value:       VCM - VID/2

Vin+ AC magnitude:   0.5
Vin+ AC phase:       0 deg

Vin- AC magnitude:   0.5
Vin- AC phase:       180 deg
```

因此：

```text
Vin,diff = V(vinp) - V(vinn) = 1 V
```

Common-mode AC 請建立 copied netlist，並只修改負端 input source 的 phase：

```text
Vin+ AC magnitude:   0.5
Vin+ AC phase:       0 deg

Vin- AC magnitude:   0.5
Vin- AC phase:       0 deg
```

Common-mode input 為：

```text
Vin,cm = (V(vinp) + V(vinn)) / 2 = 0.5 V
```

OCEAN script 中請直接用實際 common-mode input waveform 當分母，避免因 `0.5 V`
excitation amplitude 造成 gain normalization 錯誤。

## 4. 建立完整 Common-Mode Netlist Copy

不要只複製單一 `netlist` file。Cadence OCEAN design flow 可能也需要同一資料夾中的
`netlistHeader`、`amap` 與其他 generated files。

建立 common-mode netlist directory：

```bash
mkdir -p /home/<linux-user>/simulation/<ota-project>_cmrr/spectre/schematic/netlist
```

複製完整 differential netlist directory：

```bash
cp -a \
  /home/<linux-user>/simulation/<ota-project>/spectre/schematic/netlist/. \
  /home/<linux-user>/simulation/<ota-project>_cmrr/spectre/schematic/netlist/
```

只修改 copied negative-input source phase：

```bash
sed -i '/^VMINUS .* vsource / s/phase=180/phase=0/' \
  /home/<linux-user>/simulation/<ota-project>_cmrr/spectre/schematic/netlist/netlist
```

請依實際 netlist 中的 source name 調整 `sed` pattern。

驗證必要檔案：

```bash
test -f /home/<linux-user>/simulation/<ota-project>_cmrr/spectre/schematic/netlist/netlistHeader && \
echo "NETLIST_HEADER_VERIFIED"
```

```bash
test -d /home/<linux-user>/simulation/<ota-project>_cmrr/spectre/schematic/netlist/amap && \
echo "AMAP_VERIFIED"
```

驗證 copied input sources：

```bash
grep -nE '^V.* vsource ' \
  /home/<linux-user>/simulation/<ota-project>_cmrr/spectre/schematic/netlist/netlist
```

## 5. Common-Mode AC Setup

Nominal setup 示例：

```text
Process corner:          <process-corner>
Temperature:             27 deg C
VCM:                     800 mV
VID:                     0 V
Output node:             /vout
Load capacitance:        100 fF
Frequency start:         1 Hz
Frequency stop:          100 GHz
Sweep density:           100 points per decade
Expected numeric points: 1101
```

Common-mode gain expression：

```lisp
vcmWave = (v("/vinp") + v("/vinn")) / 2
cmGainWave = v("/vout") / vcmWave
```

將 common-mode gain raw data 存到：

```text
/home/<linux-user>/simulation/<ota-project>_ocean/ac_commonmode/cm_gain_raw.txt
```

## 6. 標準執行流程

進入 Cadence project directory：

```bash
cd /home/<linux-user>/cadence_projects/<ota-project> || exit 1
```

執行 common-mode AC sweep：

```bash
set -o pipefail
ocean -nograph -restore cmrr_sweep.ocn 2>&1 | tee cmrr_sweep_run.log
run_status=${PIPESTATUS[0]}
echo "OCEAN_EXIT_STATUS=$run_status"
```

只有回到 Linux shell prompt 後，才讀取 `PIPESTATUS`。

驗證 raw file：

```bash
if [ -s /home/<linux-user>/simulation/<ota-project>_ocean/ac_commonmode/cm_gain_raw.txt ]; then
    echo "COMMON_MODE_RAW_VERIFIED"
else
    echo "ERROR: COMMON_MODE_RAW_MISSING"
fi
```

```bash
wc -l /home/<linux-user>/simulation/<ota-project>_ocean/ac_commonmode/cm_gain_raw.txt
```

示例 checkpoint：

```text
OCEAN_EXIT_STATUS=0
COMMON_MODE_RAW_VERIFIED
File lines=1104
Numeric points=1101
```

## 7. CMRR Post-Processing

Analyzer inputs：

```text
Differential open-loop gain:
/home/<linux-user>/simulation/<ota-project>_ocean/ac_openloop/ac_gain_raw.txt

Common-mode gain:
/home/<linux-user>/simulation/<ota-project>_ocean/ac_commonmode/cm_gain_raw.txt
```

執行 analyzer：

```bash
awk \
  -v combined="/home/<linux-user>/simulation/<ota-project>_ocean/ac_commonmode/cmrr_combined_raw.txt" \
  -f analyze_cmrr_v1.awk \
  /home/<linux-user>/simulation/<ota-project>_ocean/ac_openloop/ac_gain_raw.txt \
  /home/<linux-user>/simulation/<ota-project>_ocean/ac_commonmode/cm_gain_raw.txt \
  | tee /home/<linux-user>/simulation/<ota-project>_ocean/ac_commonmode/cmrr_analysis.txt
```

驗證 output files：

```bash
ls -lh \
  /home/<linux-user>/simulation/<ota-project>_ocean/ac_commonmode/cmrr_analysis.txt \
  /home/<linux-user>/simulation/<ota-project>_ocean/ac_commonmode/cmrr_combined_raw.txt
```

## 8. CMRR Results 示例

原始 checkpoint 示例：

```text
DIFFERENTIAL_NUMERIC_POINTS=1101
COMMON_MODE_NUMERIC_POINTS=1101
FREQUENCY_GRID=VERIFIED
FREQUENCY_START=1 Hz
FREQUENCY_STOP=100 GHz

LOW_FREQUENCY_DIFFERENTIAL_GAIN=31.434620 V/V
LOW_FREQUENCY_DIFFERENTIAL_GAIN=29.948160 dB
LOW_FREQUENCY_COMMON_MODE_GAIN=0.04026189 V/V
LOW_FREQUENCY_COMMON_MODE_GAIN=-27.902110 dB
LOW_FREQUENCY_CMRR=780.753710 V/V
LOW_FREQUENCY_CMRR=57.850270 dB

DIFFERENTIAL_UNITY_GAIN_FREQUENCY=949.525439 MHz
CMRR_3DB_BANDWIDTH=58.853855 MHz
CMRR_40DB_BANDWIDTH=414.847335 MHz
CMRR_20DB_BANDWIDTH=2.049543 GHz
CMRR_0DB_CROSSING=24.755596 GHz

MINIMUM_CMRR_1HZ_TO_UGF=30.762290 dB
MINIMUM_CMRR_FREQUENCY=933.254300 MHz
MAXIMUM_CMRR_1HZ_TO_UGF=57.850270 dB
MAXIMUM_CMRR_FREQUENCY=1 Hz
CMRR_AT_NEAREST_UGF=30.465873 dB
```

Spot values：

```text
1 Hz:     57.850270 dB
1 kHz:    57.850270 dB
1 MHz:    57.849030 dB
10 MHz:   57.727760 dB
100 MHz:  51.942680 dB
1 GHz:    29.867804 dB
10 GHz:    3.725720 dB
```

## 9. 工程判讀

示例判讀：

1. CMRR 從 1 Hz 到約 10 MHz 幾乎完全平坦，低頻 common-mode rejection 穩定。
2. 低頻 CMRR 為 `57.85 dB`，約等於 `780.8 V/V`。對基本 five-transistor OTA 屬合理
   結果，但不屬於 precision high-CMRR amplifier 等級。
3. CMRR 的 3 dB bandwidth 約為 `58.85 MHz`。
4. 100 MHz 仍有 `51.94 dB` CMRR，代表中頻 common-mode rejection 仍有用。
5. CMRR 維持高於 `40 dB` 到約 `414.85 MHz`。
6. Differential unity-gain frequency 約為 `949.5 MHz`；UGF 附近 CMRR 約 `30.5 dB`，
   約等於 33 倍 rejection。
7. 高頻 CMRR 下降主要來自 differential-gain roll-off，不是 common-mode gain 突然
   失控。
8. UGF 以上很遠的結果不應當成正常 closed-loop operating region，但可用來確認曲線
   連續性。
9. 是否符合需求要看 specification。若是一般 high-speed OTA 可能可接受；若是低頻
   precision 用途，約 `57.85 dB` 通常仍需要提升。

## 10. CMRR 改善方向

常見改善方向：

1. 提高 NM tail current source 的 output resistance。
2. 增加 tail-device channel length，再重新確認 headroom、bias current 與速度。
3. 改善 NM input-pair matching 與 layout symmetry。
4. 改善 PM current-mirror matching。
5. 若 topology 允許，可使用 cascoded tail source 或其他較高 output-resistance 的
   bias structure。
6. 所有尺寸或 topology 修改後，都要重跑 DC VCM、VID、AC、STB、transient、noise 與
   CMRR。

## 11. 常見錯誤與修正

錯誤示例：

```text
netlistHeader file not found
amap directory is missing
```

可能原因：

```text
只複製了單一 netlist file，沒有複製完整 Cadence netlist directory。
```

影響：

```text
Spectre 沒有真的執行。既有 AC、noise、transient 與其他結果不會被這次失敗的
common-mode attempt 損壞。
```

修正：

```bash
cp -a source_netlist_directory/. destination_netlist_directory/
```

之後只修改 copied input-source phase。

若 script error 後停在 OCEAN prompt：

```text
>
```

請先離開 OCEAN：

```lisp
exit()
```

回到 Linux shell prompt 後，才能執行 `PIPESTATUS`、`grep`、`awk` 等 shell command。

## 12. Working Checkpoints

保存 OCEAN script、analyzer 與 common-mode netlist copy：

```bash
cd /home/<linux-user>/cadence_projects/<ota-project> || exit 1
stamp=$(date +%Y%m%d_%H%M%S)

cp -p -- cmrr_sweep.ocn "cmrr_sweep.ocn.working_$stamp"
cp -p -- analyze_cmrr_v1.awk "analyze_cmrr_v1.awk.working_$stamp"
cp -p -- \
  /home/<linux-user>/simulation/<ota-project>_cmrr/spectre/schematic/netlist/netlist \
  "/home/<linux-user>/simulation/<ota-project>_cmrr/spectre/schematic/netlist/netlist.working_$stamp"
```

## 13. 完成狀態

```text
[x] Independent common-mode netlist directory created.
[x] Original differential netlist preserved.
[x] Vin+ and Vin- common-mode phase verified.
[x] Common-mode AC sweep completed.
[x] 1101 numeric points verified.
[x] Differential/common-mode frequency grid verified.
[x] Full CMRR curve calculated.
[x] Low-frequency CMRR calculated.
[x] 3 dB, 40 dB, 20 dB, and 0 dB bandwidths calculated.
[x] CMRR near UGF calculated.
[x] Formal analysis and combined raw files saved.
[ ] Working checkpoints created and verified.
```

## 14. 下一步

CMRR baseline characterization 已完成。建立並驗證 checkpoints 後，請接著看
[第 8 章：PSRR Automation](08-psrr-automation.md)。
