# 第 6 章：Open-Loop Noise Automation

本章整理 five-transistor OTA 在 Cadence Virtuoso、Spectre 與 OCEAN 下的
open-loop noise 自動化流程。

原始筆記包含本機路徑、project name、script checkpoint name 與一次性的 debug history。
公開版保留工程方法，並用占位字替換可能涉及隱私的環境資訊。

## 1. 範圍

本流程包含：

1. Open-loop noise testbench 檢查
2. OCEAN noise simulation setup
3. Output-noise raw export 驗證
4. Differential input-referred noise 計算
5. White-noise floor 估算
6. 1/f noise corner 擷取
7. Integrated RMS output 與 input-referred noise
8. Working checkpoints
9. Device noise contribution ranking
10. Noise optimization priority
11. 常見錯誤與安全判讀

這些命令預設在遠端 Linux Cadence environment 執行，通常由 MobaXterm 或其他 SSH
terminal 貼上。

## 2. Testbench 與 Differential Input

Open-loop AC/noise testbench 使用兩個 input sources：

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

對這種 differential source setup，不建議只把其中一個 input source 當成完整 input
probe。請使用：

```text
Input-referred noise density =
Output noise density / differential open-loop gain magnitude
```

Differential gain 來自相同 frequency grid 的 open-loop AC result。

## 3. 何時需要重新開 Schematic

如果 schematic、device size、接線、load、supply、bias 和 source property 都沒有改，
可直接使用已驗證的既有 netlist。

以下情況要回 Virtuoso：

1. 修改 MOS width、length 或 multiplier
2. 修改 load capacitor 或任何 output loading
3. 修改 supply、bias 或 input source
4. 修改 feedback 或其他接線
5. 新增 noise probe、port 或其他元件

修改 schematic 後，先 **Check and Save**，重新產生 netlist，再執行 OCEAN。

## 4. Noise Analysis Setup

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
Output noise unit:       V/sqrt(Hz)
```

Noise analysis block：

```lisp
analysis('noise
    ?start "1"
    ?stop "100G"
    ?dec "100"
    ?p "/vout"
    ?n ""
    ?oprobe ""
    ?iprobe ""
)
```

讀取 output-noise waveform：

```lisp
outNoise = getData("out" ?result "noise")
```

## 5. 標準執行流程

進入 Cadence project directory：

```bash
cd /home/<linux-user>/cadence_projects/<ota-project> || exit 1
```

確認 scripts 存在：

```bash
ls -lh noise_openloop.ocn analyze_noise_v2.awk
```

檢查重要 OCEAN settings：

```bash
grep -nE 'simulator|design|resultsDir|modelFile|desVar|analysis|start|stop|dec|iprobe|getData' \
noise_openloop.ocn
```

確認沒有非預期 Cadence 或 Spectre process：

```bash
pgrep -af 'virtuoso|ocean|spectre|cdsMsgServer'
```

執行 noise simulation：

```bash
set -o pipefail
ocean -nograph -restore noise_openloop.ocn 2>&1 | tee noise_openloop_run.log
run_status=${PIPESTATUS[0]}
echo "OCEAN_EXIT_STATUS=$run_status"
```

## 6. 成功判定

不要只依賴 OCEAN exit status 或 completion message。必須驗證 raw file 存在且有資料：

```bash
grep -nEi 'ERROR|FATAL|SYNTAX|Segmentation|SPECTRE-|noise analysis completed' \
noise_openloop_run.log
```

```bash
if [ -s /home/<linux-user>/simulation/<ota-project>_ocean/noise_openloop/output_noise_raw.txt ]; then
    echo "NOISE_RAW_VERIFIED"
else
    echo "ERROR: NOISE_RAW_MISSING"
fi
```

```bash
wc -l /home/<linux-user>/simulation/<ota-project>_ocean/noise_openloop/output_noise_raw.txt
head -8 /home/<linux-user>/simulation/<ota-project>_ocean/noise_openloop/output_noise_raw.txt
tail -5 /home/<linux-user>/simulation/<ota-project>_ocean/noise_openloop/output_noise_raw.txt
```

示例 checkpoint：

```text
OCEAN_EXIT_STATUS=0
NOISE_RAW_VERIFIED
File lines=1104
Numeric points=1101
Frequency start=1 Hz
Frequency stop=100 GHz
```

多出來的行通常是 header 或空白格式列。

## 7. Post-Processing Inputs

Analyzer 使用：

```text
Open-loop AC gain:
/home/<linux-user>/simulation/<ota-project>_ocean/ac_openloop/ac_gain_raw.txt

Output noise:
/home/<linux-user>/simulation/<ota-project>_ocean/noise_openloop/output_noise_raw.txt
```

兩個檔案應該有相同的 numeric frequency grid。做 output noise 除以 gain 前，先確認格點一致。

執行 analyzer，並保存 combined per-frequency data 和 final report：

```bash
cd /home/<linux-user>/cadence_projects/<ota-project> || exit 1
awk \
  -v combined="/home/<linux-user>/simulation/<ota-project>_ocean/noise_openloop/noise_combined_raw.txt" \
  -f analyze_noise_v2.awk \
  /home/<linux-user>/simulation/<ota-project>_ocean/ac_openloop/ac_gain_raw.txt \
  /home/<linux-user>/simulation/<ota-project>_ocean/noise_openloop/output_noise_raw.txt \
  | tee /home/<linux-user>/simulation/<ota-project>_ocean/noise_openloop/noise_analysis_final.txt
```

檢查關鍵行：

```bash
grep -E 'FREQUENCY_GRID|UNITY_GAIN|WHITE_NOISE|FLICKER_NOISE' \
/home/<linux-user>/simulation/<ota-project>_ocean/noise_openloop/noise_analysis_final.txt
```

## 8. White-Noise Floor 與 1/f Corner

White-noise estimation band 要從 input-referred noise curve 的平坦區域選。太低頻的區間
可能仍受 flicker noise 主導，導致 white floor 被高估。

原始流程示例：

```text
Bad first estimate band:       1 MHz to 10 MHz
Reason:                        noise was still falling with frequency
Refined white-noise band:      100 MHz to 400 MHz
Points in refined band:        61
```

精修結果示例：

```text
Input-referred white-noise floor: 7.4005 nV/sqrt(Hz)
1/f noise corner:                 13.8629 MHz
```

本流程的 corner 定義：

```text
Input-referred noise amplitude reaches sqrt(2) times the white-noise floor.
```

這等價於 total noise PSD 是 white-noise PSD 的兩倍。

## 9. Noise Results 示例

原始 checkpoint 示例：

```text
AC_NUMERIC_POINTS=1101
NOISE_NUMERIC_POINTS=1101
FREQUENCY_GRID=VERIFIED
FREQUENCY_START=1 Hz
FREQUENCY_STOP=100 GHz
DC_GAIN=31.434620 V/V
DC_GAIN=29.948160 dB
UNITY_GAIN_FREQUENCY=949.525439 MHz
INPUT_REFERRED_WHITE_NOISE_FLOOR=7.4005 nV/sqrt(Hz)
FLICKER_NOISE_CORNER=13.8629 MHz
```

Input-referred spot noise 示例：

```text
1 Hz:      58.9052 uV/sqrt(Hz)
10 Hz:     15.7811 uV/sqrt(Hz)
100 Hz:    4.27035 uV/sqrt(Hz)
1 kHz:     1.17402 uV/sqrt(Hz)
10 kHz:    330.507 nV/sqrt(Hz)
100 kHz:   96.2628 nV/sqrt(Hz)
1 MHz:     29.8152 nV/sqrt(Hz)
10 MHz:    11.5036 nV/sqrt(Hz)
100 MHz:   7.64716 nV/sqrt(Hz)
1 GHz:     7.37774 nV/sqrt(Hz)
```

Integrated output noise 示例：

```text
1 Hz to 1 kHz:    3.89587 mV RMS
1 Hz to 10 kHz:   4.23829 mV RMS
1 Hz to 100 kHz:  4.49883 mV RMS
1 Hz to 1 MHz:    4.71934 mV RMS
1 Hz to 10 MHz:   4.95443 mV RMS
1 Hz to 100 MHz:  5.20139 mV RMS
1 Hz to UGF:      5.24821 mV RMS
1 Hz to 100 GHz:  5.25221 mV RMS
```

Integrated input-referred noise 示例：

```text
1 Hz to 1 kHz:    123.936 uV RMS
1 Hz to 10 kHz:   134.829 uV RMS
1 Hz to 100 kHz:  143.117 uV RMS
1 Hz to 1 MHz:    150.133 uV RMS
1 Hz to 10 MHz:   157.775 uV RMS
1 Hz to 100 MHz:  176.956 uV RMS
1 Hz to UGF:      276.975 uV RMS
```

## 10. 工程判讀

示例判讀：

1. 100 MHz 到 400 MHz 形成穩定 input-referred white-noise plateau，約
   `7.4 nV/sqrt(Hz)`。
2. 1 GHz spot noise 接近精修 white-noise floor，支持 floor estimate。
3. 1/f corner 約 `13.86 MHz`，代表很寬的低頻區域仍受 flicker noise 主導。
4. 若應用是 low-frequency、DC 或 precision amplifier，flicker noise 可能是主要限制。
5. 若真實系統有 high-pass response，請依實際 signal bandwidth 計算 band-limited
   integrated noise。
6. Open-loop output-referred integrated noise 不會自動等於最終 closed-loop system output
   noise。Closed-loop noise 還需要 noise gain、feedback network 與實際 signal bandwidth。
7. Device contribution ranking 可以判斷不同頻率區間由哪些元件主導。本例中，低頻
   integrated noise 主要由 PM current-mirror flicker noise 主導；高頻 spot noise
   與 band-limited noise 則主要由 NM input-pair channel noise 主導。

## 11. Working Checkpoints

OCEAN script 和 analyzer 都要建立並驗證 checkpoint：

```bash
cd /home/<linux-user>/cadence_projects/<ota-project> || exit 1
cp -p noise_openloop.ocn noise_openloop.ocn.working_YYYYMMDD_HHMMSS
cp -p analyze_noise_v2.awk analyze_noise_v2.awk.working_YYYYMMDD_HHMMSS
```

逐位元組驗證：

```bash
cmp -s -- noise_openloop.ocn noise_openloop.ocn.working_YYYYMMDD_HHMMSS && \
echo "OCEAN_CHECKPOINT_VERIFIED"
```

```bash
cmp -s -- analyze_noise_v2.awk analyze_noise_v2.awk.working_YYYYMMDD_HHMMSS && \
echo "ANALYZER_CHECKPOINT_VERIFIED"
```

## 12. 常見錯誤與修正

`OCN-6004: ocean session was not created`：

```text
可能原因：OCEAN script 只有 analysis tail，缺少 simulator、design、resultsDir、
modelFile 和 desVar setup。

影響：Spectre 沒有執行，raw file 沒有生成。既有 AC、STB 或 transient 結果不會因此損壞。

修正：從已驗證的 AC script 複製完整 header，再接上 noise analysis block。
```

`OCEAN_EXIT_STATUS=0` 但 raw file 不存在：

```text
Script 可能在前面命令失敗後仍印出 completion message 並 exit。
請用 test -s、line count、frequency start、frequency stop 驗證成功。
```

AWK function parameter 使用 `index`：

```text
index 是 AWK built-in function name。請把自訂參數改名，例如 spotIndex。
```

`FLICKER_NOISE_CORNER=NOT_FOUND`：

```text
White-noise estimation band 可能沒有選在真正平坦的 white-noise region。
請把 estimation band 移到已確認的 plateau 後重跑 analyzer。
```

`SPECTRE-17101`：

```text
這是 checklimitdest=psf 的 future-compatibility warning。它不是 noise convergence error，
也不會單獨使 raw data 失效。
```

## 13. 完成清單

```text
[x] Differential source and input normalization confirmed.
[x] Output node and load capacitance confirmed.
[x] Independent noise results directory created.
[x] Noise OCEAN script created and verified.
[x] Noise simulation completed over the intended frequency range.
[x] Output noise raw file saved.
[x] Numeric point count and frequency range verified.
[x] AC/noise frequency grid verified.
[x] Input-referred spot noise calculated.
[x] Integrated RMS noise calculated.
[x] White-noise floor refined from a flat band.
[x] 1/f noise corner extracted.
[x] Final analysis report saved.
[x] OCEAN working checkpoint created.
[x] Analyzer working checkpoint created.
[x] Device noise contribution summary collected.
[ ] Closed-loop integrated noise calculated for the real application bandwidth.
```

## 14. Device Noise Contribution Ranking

正式 contribution ranking 檔建議存放在 noise result directory：

```text
/home/<linux-user>/simulation/<ota-project>_ocean/noise_openloop/noise_contributor_ranking.txt
```

以下示例 ranking summary 均正規化為 100 percent。

Spot noise at 1 kHz：

```text
PM1: 42.391068 percent
PM0: 39.645138 percent
NM1: 8.991841 percent
NM0: 8.968841 percent
NM2: 0.003113 percent

PM current mirror total: 82.036206 percent
NM input-pair total:    17.960682 percent
Flicker noise:          99.996394 percent
```

在 1 kHz，spot noise 幾乎完全是 flicker noise，PM current mirror 是主因。

Integrated noise from 1 Hz to 1 kHz：

```text
PM1: 47.367632 percent
PM0: 44.299339 percent
NM1: 4.171127 percent
NM0: 4.160458 percent
NM2: 0.001444 percent

PM current mirror total: 91.666971 percent
NM input-pair total:     8.331585 percent
Flicker noise:           99.999677 percent
```

超低頻 integrated noise 更強烈地由 PM current-mirror flicker noise 主導。

Spot noise at the 13.8629 MHz flicker corner：

```text
NM1: 34.421709 percent
NM0: 34.334388 percent
PM1: 16.137037 percent
PM0: 15.090972 percent
NM2: 0.015895 percent

NM input-pair total:     68.756097 percent
PM current mirror total: 31.228009 percent
Flicker noise:           54.608014 percent
Channel noise:           45.232433 percent
```

在 corner frequency，主導元件轉為 NM input pair。Flicker 與 channel noise 接近交接，
符合 corner definition。

Integrated noise from 1 Hz to the flicker corner：

```text
PM1: 40.654056 percent
PM0: 38.020624 percent
NM1: 10.674357 percent
NM0: 10.647070 percent
NM2: 0.003892 percent

PM current mirror total: 78.674680 percent
NM input-pair total:    21.321427 percent
Flicker noise:          97.418715 percent
```

雖然 corner spot noise 已由 NM input pair 主導，但從 1 Hz 積分到 corner 的總 noise
energy 仍由低頻 PM current-mirror flicker noise 主導。

Spot noise at 200 MHz：

```text
NM0: 34.490932 percent
NM1: 34.426387 percent
PM1: 16.026814 percent
PM0: 14.829783 percent
NM2: 0.226083 percent

NM input-pair total:     68.917319 percent
PM current mirror total: 30.856597 percent
Channel noise:           91.422744 percent
Flicker noise:            8.254806 percent
```

在 200 MHz，white-noise spot behavior 由 NM input-pair channel noise 主導。

Integrated noise from 100 MHz to 400 MHz：

```text
NM0: 34.549672 percent
NM1: 34.487746 percent
PM1: 15.965238 percent
PM0: 14.773962 percent
NM2: 0.223383 percent

NM input-pair total:     69.037418 percent
PM current mirror total: 30.739200 percent
Channel noise:           89.743673 percent
Flicker noise:            9.939800 percent
```

整個 white-noise estimation band 也由 NM input pair 主導。

Integrated noise from 1 Hz to UGF：

```text
PM1: 38.308080 percent
PM0: 35.819782 percent
NM1: 12.942433 percent
NM0: 12.915737 percent
NM2: 0.013968 percent

PM current mirror total: 74.127862 percent
NM input-pair total:    25.858170 percent
Flicker noise:          91.079408 percent
Channel noise:           8.889238 percent
```

即使積分到 949.5 MHz unity-gain frequency，從 1 Hz 起算的總 noise energy 仍由
PM current-mirror flicker noise 主導。Integration lower bound 會強烈影響最後結論。

## 15. Noise Optimization Priority

低頻、DC 或 precision-amplifier application：

1. 優先處理 PM0/PM1 current-mirror flicker noise。
2. 可評估增加 PM0/PM1 gate area、增加 channel length，或調整 current density。
3. 修改 PM mirror 後必須重跑 AC、STB、transient 與 noise，因為 PM mirror sizing 也會
   影響 output-node capacitance、gain、UGF、phase margin 與 settling behavior。

高頻或 broadband application：

1. 優先處理 NM0/NM1 input-pair channel noise。
2. 可評估提高 input-pair transconductance、重新選擇 gm/Id operating point，或調整
   bias current。
3. 增加 input-pair width 可能降低部分 noise，但也會增加 input capacitance 並影響速度。

NM2 tail device：

1. 在所有 spot 與 integrated cases 中，NM2 都低於約 `0.23 percent`。
2. 如果唯一目標是降低 noise，不應優先把面積或功耗花在 NM2。

對稱性檢查：

1. NM0 與 NM1 幾乎相等，代表 input-pair symmetry 良好。
2. PM0 與 PM1 也很接近，本例中 PM1 通常略高於 PM0，但沒有看到單一 PM device 異常。

## 16. 下一步

Baseline open-loop noise 與 device contribution characterization 已完成。

若已知實際 signal bandwidth 與 low-frequency cutoff，下一步是 closed-loop
band-limited integrated noise。若目標是完整 OTA characterization，下一個獨立分析是
CMRR，之後是 PSRR+ 與 PSRR-。
