# 第 4 章：Open-Loop AC and STB Feedback Stability

本章整理 Cadence Virtuoso、Spectre 与 OCEAN 中 open-loop AC characterization
和 closed-loop STB stability analysis 的可重复流程。

原始笔记包含本机路径、cell name 与一次性的 checkpoint。公开版保留方法，并用占位符取代
可能涉及隐私的细节。

## 1. 范围

本流程包含：

1. Feedback topology 与 analysis type 的差别
2. Open-loop AC gain、bandwidth、unity-gain frequency
3. Differential AC source normalization
4. 确认指定 load capacitor
5. 建立专用 unity-feedback STB testbench
6. 用 `iprobe` 执行 STB
7. 读取 Spectre 正式 STB margins
8. 比较 open-loop AC estimate 与 formal STB result

示例 nominal conditions：

```text
Circuit type:        five-transistor one-stage OTA
Process corner:      <process-corner>
Temperature:         27 deg C
Supply:              VDD = 1.2 V
Nominal VCM:         0.8 V
Nominal VID:         0 V
Load capacitance:    100 fF
```

这些是示例值，每个设计与 PDK 都要重新确认。

## 2. Feedback 不是 Analysis Type

Feedback 是电路拓扑。Transient、AC、DC、STB 是 analysis type。它们不是二选一。

常见流程：

```text
Open-loop AC:
  OTA 保持 open-loop，用 differential AC sources 量 frequency response。

Closed-loop STB:
  OTA 接成 unity negative-feedback loop，用 iprobe 量 return ratio 与 formal phase margin。

Closed-loop transient:
  保持 unity-feedback topology，改用 time-domain input step 量 settling、overshoot 和 slew behavior。
```

当 topology 明显不同时，建议使用不同 testbench，避免 open-loop AC、STB 与 transient
彼此污染。

## 3. 建议目录结构

示例：

```text
Main open-loop testbench netlist:
/home/<linux-user>/simulation/<ota-project>/spectre/schematic/netlist/netlist

Main open-loop input.scs:
/home/<linux-user>/simulation/<ota-project>/spectre/schematic/netlist/input.scs

Dedicated STB testbench netlist:
/home/<linux-user>/simulation/<ota-project>_stb/spectre/schematic/netlist/netlist

Dedicated STB input.scs:
/home/<linux-user>/simulation/<ota-project>_stb/spectre/schematic/netlist/input.scs

Open-loop AC results:
/home/<linux-user>/simulation/<ota-project>_ocean/ac_openloop

Closed-loop STB results:
/home/<linux-user>/simulation/<ota-project>_ocean/stb_unity
```

常用脚本：

```text
ac_sweep.ocn
stb_sweep.ocn
inspect_stb_margin.ocn
```

确认脚本可用后，用日期保存 checkpoint：

```bash
cp -p ac_sweep.ocn ac_sweep.ocn.working_YYYYMMDD
cp -p stb_sweep.ocn stb_sweep.ocn.working_YYYYMMDD
```

## 4. Batch Simulation Checklist

只有 schematic topology、source property、design variable 或 probe placement 改变时，
才需要回 Virtuoso。

建议流程：

1. 修改目标 schematic。
2. 执行 **Check and Save**。
3. 需要时在 ADE 使用 **Variables -> Copy From Cellview**。
4. 使用 **Simulation -> Netlist -> Recreate**。
5. 若下一步要跑 OCEAN batch，不要在 ADE 点 **Run**。
6. 确认 Virtuoso、Spectre、OCEAN 没有使用同一个 result directory。
7. 从 Linux shell 执行 OCEAN script。

检查残留 process：

```bash
pgrep -af 'virtuoso|ocean|spectre|cdsMsgServer'
```

GUI ADE 和 batch OCEAN 的 result directory 要分开。

## 5. 确认 Load Capacitor

信任 AC 或 STB 结果前，先确认 netlist 中真的有指定负载：

```text
Output node:       vout
Load capacitor:    CLOAD = <load-capacitance>
No unintended output resistor
No unintended leftover iprobe in the open-loop AC testbench
```

快速检查：

```bash
grep -nEi 'vout|capacitor|resistor|iprobe' \
/home/<linux-user>/simulation/<ota-project>/spectre/schematic/netlist/input.scs
```

若 AC 结果是在 `CL = 100 fF` 下得到，它就不是空载结果。Bandwidth、UGF、phase 都会受
load 影响。

## 6. Open-Loop AC Source Setup

Differential AC normalization 可用两个 input sources：

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
Vin,diff = 0.5<0deg - 0.5<180deg = 1 V
```

当 differential AC input 是 1 V 时，`VOUT/Vin,diff` 的数值可直接当成 voltage gain。

检查 netlist：

```bash
grep -nE '^V[0-9]+ ' \
/home/<linux-user>/simulation/<ota-project>/spectre/schematic/netlist/input.scs
```

预期形式：

```text
V0 (...) vsource dc=VCM+VID/2 mag=500.0m phase=0 type=sine
V1 (...) vsource dc=VCM-VID/2 mag=500.0m phase=180 type=sine
```

## 7. Open-Loop AC OCEAN Pattern

示例 script 核心：

```lisp
resultsDir("/home/<linux-user>/simulation/<ota-project>_ocean/ac_openloop")

desVar("VCM" 800m)
desVar("VID" 0)

analysis('ac
    ?start "1"
    ?stop "100G"
    ?dec "100"
)

save('v "/vout")
save('v "/vinp")
save('v "/vinn")

temp(27)
run()

selectResult('ac)

vinDiff = v("/vinp") - v("/vinn")
gainWave = v("/vout") / vinDiff

gainMag = mag(gainWave)
gainDb = db20(gainWave)
gainPhase = phase(gainWave)

ocnPrint(
    ?output "/home/<linux-user>/simulation/<ota-project>_ocean/ac_openloop/ac_gain_raw.txt"
    ?numberNotation 'scientific
    ?precision 12
    gainMag
    gainDb
    gainPhase
)

exit()
```

执行：

```bash
cd /home/<linux-user>/cadence_projects/<ota-project>
ocean -nograph -restore ac_sweep.ocn 2>&1 | tee ac_sweep_run.log
```

检查错误与数据点：

```bash
grep -nEi 'OCN-|ERROR|FATAL|SYNTAX|Segmentation|SPECTRE-' ac_sweep_run.log

awk 'NF==4 && $1 ~ /^[0-9]/ {n++}
END {print "AC_DATA_POINTS =",n}' \
/home/<linux-user>/simulation/<ota-project>_ocean/ac_openloop/ac_gain_raw.txt
```

1 Hz 到 100 GHz、100 points/decade 时：

```text
11 decades * 100 points/decade + start point = 1101 points
```

## 8. 计算 Bandwidth、UGF 与 PM Estimate

AC raw report 字段：

```text
$1 = frequency, Hz
$2 = gain magnitude, V/V
$3 = gain, dB
$4 = phase, degrees
```

用 log-frequency interpolation 找 -3 dB bandwidth 与 0 dB crossing：

```bash
awk '
NF==4 && $1 ~ /^[0-9]/ {
    f=$1+0; mag=$2+0; db=$3+0; ph=$4+0

    if (!seen) {
        seen=1
        lowMag=mag
        lowDb=db
        target3dB=lowDb-3
        previousF=f
        previousDb=db
        previousPhase=ph
        next
    }

    if (!found3dB && previousDb>=target3dB && db<target3dB) {
        ratio=(target3dB-previousDb)/(db-previousDb)
        bandwidth=exp(log(previousF)+ratio*(log(f)-log(previousF)))
        found3dB=1
    }

    if (!foundUnity && previousDb>=0 && db<0) {
        ratio=(0-previousDb)/(db-previousDb)
        ugf=exp(log(previousF)+ratio*(log(f)-log(previousF)))
        phaseAtUgf=previousPhase+ratio*(ph-previousPhase)
        phaseMargin=180+phaseAtUgf
        foundUnity=1
    }

    previousF=f
    previousDb=db
    previousPhase=ph
}

END {
    printf "LOW_FREQUENCY_GAIN = %.6f V/V\n",lowMag
    printf "LOW_FREQUENCY_GAIN = %.6f dB\n",lowDb
    printf "MINUS_3DB_TARGET   = %.6f dB\n",target3dB

    if (found3dB) {
        printf "BANDWIDTH_3DB      = %.9e Hz\n",bandwidth
        printf "BANDWIDTH_3DB      = %.6f MHz\n",bandwidth/1e6
    }
    else {
        print "BANDWIDTH_3DB crossing not found"
    }

    if (foundUnity) {
        printf "UGF                = %.9e Hz\n",ugf
        printf "UGF                = %.6f MHz\n",ugf/1e6
        printf "PHASE_AT_UGF       = %.6f deg\n",phaseAtUgf
        printf "PHASE_MARGIN_EST   = %.6f deg\n",phaseMargin
    }
    else {
        print "UNITY_GAIN crossing not found"
    }
}
' /home/<linux-user>/simulation/<ota-project>_ocean/ac_openloop/ac_gain_raw.txt
```

示例 checkpoint：

```text
Low-frequency gain: 31.434620 V/V, or 29.948160 dB
-3 dB bandwidth:    32.525935 MHz
Open-loop AC UGF:   949.525439 MHz
Phase at UGF:       -101.049136 deg
PM estimate:        78.950864 deg
```

这个 PM estimate 假设 unity negative feedback。它适合做 sanity check，但正式 stability
请以 STB 为准。

## 9. 为什么要用 STB 专用 Testbench

原始 DC/AC testbench 建议不要留下 `iprobe`，除非该分析需要它。独立 STB cell 可避免：

```text
Leftover iprobe changing the circuit inventory
DC/AC and STB topology contamination
Manual delete-and-reinsert steps before each analysis
Confusion after recreating the netlist
```

建议分工：

```text
<ota-project>:       DC OP, VCM sweep, VID sweep, open-loop AC
<ota-project>_stb:   unity-feedback STB with permanent iprobe
<ota-project>_tran:  unity-feedback transient, if needed
```

## 10. Closed-Loop STB Topology

Unity-feedback STB schematic 示例：

```text
Vin+ source:
  DC value = VCM
  AC magnitude = 0
  AC phase = 0

Feedback path:
  vout -> iprobe -> Vin-

Load:
  CLOAD from vout to ground
```

在 STB testbench 中移除第二个 independent input source。反相端应由 feedback path 决定。

`iprobe` 在 DC 上近似 0 V source，因此 bias 时 feedback loop 仍是闭合的。Spectre 会通过
probe 注入 STB small-signal perturbation。

检查 STB netlist：

```bash
grep -nEi 'parameters|iprobe|vsource|capacitor|vout' \
/home/<linux-user>/simulation/<ota-project>_stb/spectre/schematic/netlist/input.scs
```

预期形式：

```text
parameters VCM
IPRB0 (...) iprobe
CLOAD (...) capacitor c=<load-capacitance>
VBIAS (...) vsource dc=<bias-voltage>
VDD (...) vsource dc=<supply-voltage>
VINP (...) vsource dc=VCM type=sine
```

## 11. Closed-Loop STB OCEAN Pattern

示例 script 核心：

```lisp
design("/home/<linux-user>/simulation/<ota-project>_stb/spectre/schematic/netlist/netlist")

resultsDir("/home/<linux-user>/simulation/<ota-project>_ocean/stb_unity")

desVar("VCM" 800m)

analysis('stb
    ?start "1"
    ?stop "100G"
    ?dec "100"
    ?probe "/IPRB0"
)

temp(27)
run()

selectResult('stb)

loopGainWave = getData("loopGain")

loopGainMag = mag(loopGainWave)
loopGainDb = db20(loopGainWave)
loopGainPhase = phase(loopGainWave)

ocnPrint(
    ?output "/home/<linux-user>/simulation/<ota-project>_ocean/stb_unity/stb_loopgain_raw.txt"
    ?numberNotation 'scientific
    ?precision 12
    loopGainMag
    loopGainDb
    loopGainPhase
)

exit()
```

执行：

```bash
ocean -nograph -restore stb_sweep.ocn 2>&1 | tee stb_sweep_run.log
```

检查数据点：

```bash
awk 'NF==4 && $1 ~ /^[0-9]/ {n++}
END {print "STB_DATA_POINTS =",n}' \
/home/<linux-user>/simulation/<ota-project>_ocean/stb_unity/stb_loopgain_raw.txt
```

同样 1 Hz 到 100 GHz、100 points/decade 时，预期是 `1101` points。

## 12. STB Phase 可能从 180 Degrees 附近开始

Open-loop AC gain 常画成 `VOUT/VID`，所以低频 phase 可能接近 0 degrees。

STB `loopGain` 是 closed-loop return-ratio quantity，包含 feedback sign convention。
稳定的 negative-feedback loop 可能回报低频 phase 接近 +180 degrees 或 -180 degrees。

这不自动代表接成 positive feedback，也不自动代表 `iprobe` 方向错。正式结果请读
`stb_margin`。

## 13. 读取 Formal STB Margins

STB 跑完后，用 report-only script：

```lisp
openResults("/home/<linux-user>/simulation/<ota-project>_ocean/stb_unity/psf")

pm = getData("phaseMargin" ?result "stb_margin")
pmFreq = getData("phaseMarginFreq" ?result "stb_margin")
gm = getData("gainMargin" ?result "stb_margin")
gmFreq = getData("gainMarginFreq" ?result "stb_margin")

printf("phaseMargin     = %L\n" pm)
printf("phaseMarginFreq = %L\n" pmFreq)
printf("gainMargin      = %L\n" gm)
printf("gainMarginFreq  = %L\n" gmFreq)

exit()
```

执行：

```bash
ocean -nograph -restore inspect_stb_margin.ocn \
2>&1 | tee inspect_stb_margin.log
```

检查：

```bash
grep -nEi 'OCN-|ERROR|FATAL|SYNTAX|phaseMargin|gainMargin' \
inspect_stb_margin.log
```

示例 checkpoint：

```text
phaseMargin     = 79.63017 deg
phaseMarginFreq = 8.942901e+08 Hz
gainMargin      = nan
gainMarginFreq  = nan
```

`gainMargin = nan` 不一定是 simulation error。它可能代表 sweep 范围内没有 phase
crossover。此时可把 gain margin 记成 `N/A`，并写明 sweep range 与原因，不要把 `nan`
改成零。

## 14. 比较 AC Estimate 与 STB Result

示例比较：

```text
Open-loop AC:
  Low-frequency gain = 29.94816 dB
  UGF                = 949.52544 MHz
  PM estimate        = 78.95086 deg

Closed-loop STB:
  Low-frequency loop gain = 30.04247 dB
  PM frequency            = 894.29010 MHz
  Formal PM               = 79.63017 deg
```

小差异是合理的，原因包括：

```text
Open-loop AC 与 unity-feedback STB 的 bias point 可能不同。
STB 量的是 feedback loop closed 时的 return ratio。
Probe 保留 loop 周围实际 impedance 与 loading。
```

正式 stability specification 以 STB 为准；open-loop AC 用来交叉验证与建立设计直觉。

## 15. SPECTRE-17101 Warning

如果 log 出现：

```text
WARNING (SPECTRE-17101): The value 'psf' specified using the
'checklimitdest' option will no longer be supported in future releases.
```

判读：

```text
这是 future-compatibility warning。
它不是 convergence error。
它不代表 PSF data 损坏。
它本身不会让 AC 或 STB 结果失效。
```

真正需要停下来检查的错误包括：

```text
ERROR
FATAL
SYNTAX
Segmentation
Analysis terminated prematurely
Invalid probe instance
```

## 16. Nominal Stability Summary

示例 checkpoint：

```text
Corner:                  <process-corner>
Temperature:             27 deg C
VDD:                     1.2 V
VCM:                     0.8 V
CL:                      100 fF

Low-frequency gain:      31.43462 V/V
Low-frequency gain:      29.94816 dB
-3 dB bandwidth:         32.52594 MHz
Open-loop AC UGF:        949.52544 MHz

STB phase margin:        79.63017 deg
STB PM frequency:        894.29010 MHz
Gain margin:             N/A, no phase crossover found in the sweep range
```

这是 nominal checkpoint，不是 worst-case PVT 结论。Sign-off 前仍需做 corner、
temperature、supply、load 与 mismatch checks。

## 17. 下一步：Closed-Loop Transient

Nominal AC 与 STB 完成后，可以进入
[第 5 章：Closed-Loop Transient Automation](05-closed-loop-transient-automation.md)。

量测项目：

```text
Small-signal settling time
Large-signal settling time
Overshoot
Undershoot
Positive slew rate
Negative slew rate
```

比较结果前先固定：

```text
Step amplitude
Pulse rise and fall time
Settling-error criterion, such as 1% or 0.1%
Simulation stop time
Load capacitance
```

不同 transient 条件会得到不同 settling 与 slew-rate 数字，因此 setup 要和结果一起保存。
