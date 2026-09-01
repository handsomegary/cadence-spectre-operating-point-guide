# 第 6 章：Open-Loop Noise Automation

本章整理 five-transistor OTA 在 Cadence Virtuoso、Spectre 与 OCEAN 下的
open-loop noise 自动化流程。

原始笔记包含本机路径、project name、script checkpoint name 与一次性的 debug history。
公开版保留工程方法，并用占位符替换可能涉及隐私的环境信息。

## 1. 范围

本流程包含：

1. Open-loop noise testbench 检查
2. OCEAN noise simulation setup
3. Output-noise raw export 验证
4. Differential input-referred noise 计算
5. White-noise floor 估算
6. 1/f noise corner 提取
7. Integrated RMS output 与 input-referred noise
8. Working checkpoints
9. 常见错误与安全判读

这些命令默认在远端 Linux Cadence environment 执行，通常由 MobaXterm 或其他 SSH
terminal 贴上。

## 2. Testbench 与 Differential Input

Open-loop AC/noise testbench 使用两个 input sources：

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

对这种 differential source setup，不建议只把其中一个 input source 当成完整 input
probe。请使用：

```text
Input-referred noise density =
Output noise density / differential open-loop gain magnitude
```

Differential gain 来自相同 frequency grid 的 open-loop AC result。

## 3. 何时需要重新开 Schematic

如果 schematic、device size、接线、load、supply、bias 和 source property 都没有改，
可直接使用已验证的既有 netlist。

以下情况要回 Virtuoso：

1. 修改 MOS width、length 或 multiplier
2. 修改 load capacitor 或任何 output loading
3. 修改 supply、bias 或 input source
4. 修改 feedback 或其他接线
5. 新增 noise probe、port 或其他元件

修改 schematic 后，先 **Check and Save**，重新生成 netlist，再执行 OCEAN。

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

读取 output-noise waveform：

```lisp
outNoise = getData("out" ?result "noise")
```

## 5. 标准执行流程

进入 Cadence project directory：

```bash
cd /home/<linux-user>/cadence_projects/<ota-project> || exit 1
```

确认 scripts 存在：

```bash
ls -lh noise_openloop.ocn analyze_noise_v2.awk
```

检查重要 OCEAN settings：

```bash
grep -nE 'simulator|design|resultsDir|modelFile|desVar|analysis|start|stop|dec|iprobe|getData' \
noise_openloop.ocn
```

确认没有非预期 Cadence 或 Spectre process：

```bash
pgrep -af 'virtuoso|ocean|spectre|cdsMsgServer'
```

执行 noise simulation：

```bash
set -o pipefail
ocean -nograph -restore noise_openloop.ocn 2>&1 | tee noise_openloop_run.log
run_status=${PIPESTATUS[0]}
echo "OCEAN_EXIT_STATUS=$run_status"
```

## 6. 成功判定

不要只依赖 OCEAN exit status 或 completion message。必须验证 raw file 存在且有数据：

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

多出来的行通常是 header 或空白格式行。

## 7. Post-Processing Inputs

Analyzer 使用：

```text
Open-loop AC gain:
/home/<linux-user>/simulation/<ota-project>_ocean/ac_openloop/ac_gain_raw.txt

Output noise:
/home/<linux-user>/simulation/<ota-project>_ocean/noise_openloop/output_noise_raw.txt
```

两个文件应该有相同的 numeric frequency grid。做 output noise 除以 gain 前，先确认格点一致。

执行 analyzer，并保存 combined per-frequency data 和 final report：

```bash
cd /home/<linux-user>/cadence_projects/<ota-project> || exit 1
awk \
  -v combined="/home/<linux-user>/simulation/<ota-project>_ocean/noise_openloop/noise_combined_raw.txt" \
  -f analyze_noise_v2.awk \
  /home/<linux-user>/simulation/<ota-project>_ocean/ac_openloop/ac_gain_raw.txt \
  /home/<linux-user>/simulation/<ota-project>_ocean/noise_openloop/output_noise_raw.txt \
  | tee /home/<linux-user>/simulation/<ota-project>_ocean/noise_openloop/noise_analysis_final.txt
```

检查关键行：

```bash
grep -E 'FREQUENCY_GRID|UNITY_GAIN|WHITE_NOISE|FLICKER_NOISE' \
/home/<linux-user>/simulation/<ota-project>_ocean/noise_openloop/noise_analysis_final.txt
```

## 8. White-Noise Floor 与 1/f Corner

White-noise estimation band 要从 input-referred noise curve 的平坦区域选。太低频的区间
可能仍受 flicker noise 主导，导致 white floor 被高估。

原始流程示例：

```text
Bad first estimate band:       1 MHz to 10 MHz
Reason:                        noise was still falling with frequency
Refined white-noise band:      100 MHz to 400 MHz
Points in refined band:        61
```

精修结果示例：

```text
Input-referred white-noise floor: 7.4005 nV/sqrt(Hz)
1/f noise corner:                 13.8629 MHz
```

本流程的 corner 定义：

```text
Input-referred noise amplitude reaches sqrt(2) times the white-noise floor.
```

这等价于 total noise PSD 是 white-noise PSD 的两倍。

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

## 10. 工程判读

示例判读：

1. 100 MHz 到 400 MHz 形成稳定 input-referred white-noise plateau，约
   `7.4 nV/sqrt(Hz)`。
2. 1 GHz spot noise 接近精修 white-noise floor，支持 floor estimate。
3. 1/f corner 约 `13.86 MHz`，代表很宽的低频区域仍受 flicker noise 主导。
4. 若应用是 low-frequency、DC 或 precision amplifier，flicker noise 可能是主要限制。
5. 若真实系统有 high-pass response，请依实际 signal bandwidth 计算 band-limited
   integrated noise。
6. Open-loop output-referred integrated noise 不会自动等于最终 closed-loop system output
   noise。Closed-loop noise 还需要 noise gain、feedback network 与实际 signal bandwidth。
7. 在取得 device noise contribution summary 前，不要断言哪一颗 device 主导 noise。

## 11. Working Checkpoints

OCEAN script 和 analyzer 都要建立并验证 checkpoint：

```bash
cd /home/<linux-user>/cadence_projects/<ota-project> || exit 1
cp -p noise_openloop.ocn noise_openloop.ocn.working_YYYYMMDD_HHMMSS
cp -p analyze_noise_v2.awk analyze_noise_v2.awk.working_YYYYMMDD_HHMMSS
```

逐字节验证：

```bash
cmp -s -- noise_openloop.ocn noise_openloop.ocn.working_YYYYMMDD_HHMMSS && \
echo "OCEAN_CHECKPOINT_VERIFIED"
```

```bash
cmp -s -- analyze_noise_v2.awk analyze_noise_v2.awk.working_YYYYMMDD_HHMMSS && \
echo "ANALYZER_CHECKPOINT_VERIFIED"
```

## 12. 常见错误与修正

`OCN-6004: ocean session was not created`：

```text
可能原因：OCEAN script 只有 analysis tail，缺少 simulator、design、resultsDir、
modelFile 和 desVar setup。

影响：Spectre 没有执行，raw file 没有生成。既有 AC、STB 或 transient 结果不会因此损坏。

修正：从已验证的 AC script 复制完整 header，再接上 noise analysis block。
```

`OCEAN_EXIT_STATUS=0` 但 raw file 不存在：

```text
Script 可能在前面命令失败后仍印出 completion message 并 exit。
请用 test -s、line count、frequency start、frequency stop 验证成功。
```

AWK function parameter 使用 `index`：

```text
index 是 AWK built-in function name。请把自定义参数改名，例如 spotIndex。
```

`FLICKER_NOISE_CORNER=NOT_FOUND`：

```text
White-noise estimation band 可能没有选在真正平坦的 white-noise region。
请把 estimation band 移到已确认的 plateau 后重跑 analyzer。
```

`SPECTRE-17101`：

```text
这是 checklimitdest=psf 的 future-compatibility warning。它不是 noise convergence error，
也不会单独使 raw data 失效。
```

## 13. 完成清单

```text
[ ] Differential source and input normalization confirmed.
[ ] Output node and load capacitance confirmed.
[ ] Independent noise results directory created.
[ ] Noise OCEAN script created and verified.
[ ] Noise simulation completed over the intended frequency range.
[ ] Output noise raw file saved.
[ ] Numeric point count and frequency range verified.
[ ] AC/noise frequency grid verified.
[ ] Input-referred spot noise calculated.
[ ] Integrated RMS noise calculated.
[ ] White-noise floor refined from a flat band.
[ ] 1/f noise corner extracted.
[ ] Final analysis report saved.
[ ] OCEAN working checkpoint created.
[ ] Analyzer working checkpoint created.
[ ] Device noise contribution summary collected.
[ ] Closed-loop integrated noise calculated for the real application bandwidth.
```

## 14. 下一步

下一个 noise 子分析是 device noise contribution ranking：

```text
Input pair contribution
Current mirror load contribution
Tail device contribution
Other bias or load contribution
```

完成 device contribution ranking 后，才能判断要优先增加 input-pair area、调整 current
mirror、修改 bias device，或改变 operating current。Noise 之后可继续整理 CMRR 与 PSRR
自动化。
