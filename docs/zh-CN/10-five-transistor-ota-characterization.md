# 第 10 章：Five-Transistor OTA Characterization Workflow

本章整理一个通用的 five-transistor one-stage OTA characterization 流程，适用于
Cadence Virtuoso ADE 与 Spectre。

原始素材包含特定 project 名称、路径、device label 与示例数值。本公开版本保留工程方法，
但将可能涉及隐私或环境信息的内容改成通用占位符。

## 1. 范围

本流程包含：

1. Input common-mode range, ICMR
2. Output swing
3. DC differential gain 与 input linear range
4. Open-loop AC gain、bandwidth、unity-gain frequency
5. STB stability analysis
6. Unity-gain buffer large-signal transient response
7. Slew rate、rise/fall time、overshoot、1% settling time
8. Open-loop noise 与 input-referred noise
9. 为什么 AC magnitude normalization 不等于真实 large-signal input swing
10. Virtuoso、MobaXterm、VMware、Windows 的安全关闭流程
11. 后续建议 characterization 项目

最重要的观念：

```text
AC magnitude 是 small-signal normalization，不是真实加在 nonlinear transistor
circuit 上的 physical input swing。
```

## 2. 通用 Testbench

占位符示例：

```text
Circuit type:        five-transistor one-stage OTA
Process/PDK:         <process-pdk>
Library:             <library-name>
Cell:                <cell-name>
Supply:              VDD = <supply-voltage>
Nominal VCM:         <nominal-common-mode-voltage>
Load capacitance:    <load-capacitance>
Simulation root:     /home/<linux-user>/simulation/<project-name>
```

典型 five-transistor OTA device：

```text
NMOS differential pair:      <nmos-input-left>, <nmos-input-right>
PMOS current-mirror load:    <pmos-load-left>, <pmos-load-right>
NMOS tail current source:    <nmos-tail>
```

原始示例使用：

```text
VDD = 1.2 V
VCM = 0.8 V
CLOAD = 100 fF
```

这些是示例数值，不是所有设计都该采用的固定规格。

## 3. Input Common-Mode Range

目的：在 `Vin+ = VCM`、`Vin- = VCM` 时，找出关键 MOS 仍维持目标工作区的 `VCM`
范围。

在 ADE 建立 design variable：

```text
VCM
```

执行 DC sweep：

```text
Analysis:          dc
Sweep variable:    VCM
Start:             0 V
Stop:              VDD
Step:              10 mV, or a suitable resolution
```

保存并观察 OP parameters：

```text
tail device:       vds, vdsat, region
input device:      vds, vdsat, region
load device:       vds, vdsat, region
```

NMOS 饱和条件可用：

```text
VDS >= VDSAT
```

PMOS 饱和条件可用：

```text
|VDS| >= |VDSAT|
```

低端 ICMR 常由 tail current source 限制。高端 ICMR 可能由 input pair、active load，
或 supply rail 限制。

示例结果：

```text
Practical ICMR: about 0.711 V to 1.2 V
Nominal VCM selected for later tests: 0.8 V
```

## 4. Output Swing

目的：强迫 `Vout` 从低到高 sweep，找出上下两侧输出相关 MOS 何时离开 saturation。

设置：

```text
Vin+ = <nominal-vcm>
Vin- = <nominal-vcm>
```

在 `Vout` 与 ground 之间加一颗 ideal DC voltage source：

```text
Source name:       <vout-test-source>
DC value:          VOUT_TEST
Connection:        Vout to GND
```

Output load capacitor 也应接在 `Vout` 与 ground 之间。测试电压源和负载电容是并联，
不要误接成串联。

执行 DC sweep：

```text
Sweep variable:    VOUT_TEST
Start:             0 V
Stop:              VDD
```

观察：

```text
input-side output device:    vds, vdsat, region
active-load output device:   vds, vdsat, region
```

示例结果：

```text
Vout,min: about 0.346 V
Vout,max: about 1.03 V
Usable output swing: about 0.684 V
Open-loop quiescent output: about 0.704 V
Approximate symmetric swing around Q: about +/-0.326 V, or 0.652 Vpp
```

## 5. DC Differential Gain 与 Input Linear Range

目的：sweep differential input voltage，量 `Vout` 对 `VID` 的 local slope。

使用：

```text
VCM = <nominal-vcm>
Vin+ = VCM + VID/2
Vin- = VCM - VID/2
```

执行 DC sweep：

```text
Sweep variable:    VID
Start:             -10 mV
Stop:              +10 mV
Step:              0.1 mV, or suitable resolution
```

画：

```text
Vout vs VID
```

在 Calculator 使用 DC sweep waveform 的 derivative：

```text
deriv(VS("/vout"))
```

DC sweep waveform 建议使用 `VS("/vout")`。某些 ADE 环境中，`VDC("/vout")` 可能只取回
scalar，无法正确做 `deriv`。

在 `VID = 0`，示例结果：

```text
DC gain: about 31.4 V/V, or 29.9 dB
```

若要量 5% linearity range：

```text
Allowed gain = 0.95 * A0
```

找 `deriv(VS("/vout"))` 和该数值的左右交点。

示例：

```text
A0 = 31.4 V/V
5% threshold = 29.83 V/V
5% linear differential input range: about -2.1 mV to +5.2 mV
Total width: about 7.3 mV
```

single-ended five-transistor OTA 出现不对称是正常的，current mirror、finite output
resistance、bias point 都会影响 transfer curve。

## 6. Open-Loop AC Analysis

目的：量 small-signal gain、bandwidth、unity-gain frequency。

DC bias：

```text
Vin+ DC = <nominal-vcm>
Vin- DC = <nominal-vcm>
```

差动 AC normalization：

```text
Vin+ AC magnitude = 0.5
Vin+ AC phase     = 0 deg

Vin- AC magnitude = 0.5
Vin- AC phase     = 180 deg
```

因此：

```text
Vid,ac = +0.5 - (-0.5) = 1 V
```

执行 AC sweep：

```text
Analysis:           ac
Sweep type:         log
Start:              1 Hz
Stop:               1e10 Hz
Points/decade:      100
```

当 `Vid,ac = 1`，gain 可直接画：

```text
dB20(VF("/vout"))
```

示例结果：

```text
Low-frequency gain:    about 31.43 V/V, or 29.95 dB
-3 dB bandwidth:       about 32.59 MHz
One-pole GBW estimate: about 1.024 GHz
Open-loop UGF:         about 949.6 MHz
Open-loop phase at UGF: about -101.05 deg
Rough open-loop PM estimate: about 78.95 deg
```

正式 closed-loop stability 请用 STB。

## 7. AC Magnitude 不是真实 Input Swing

如果真实 5% linear input range 只有几 mV，看到 `AC magnitude = 0.5` 很容易觉得奇怪。
但这不冲突。

Spectre AC analysis 大致分成两步：

1. 求 DC operating point。
2. 在该 operating point 附近线性化 nonlinear transistor network。

AC analysis 解的是由下列 local quantities 组成的 small-signal network：

```text
gm
gmb
gds
ro
Cgs
Cgd
operating region
```

它不是用 `1 V` 差动大信号去真正驱动 nonlinear circuit。

在线性化系统中，振幅可以选成方便的 normalization：

```text
If Vid,ac = 1 V, then Vout numerically equals Vout/Vid.
If Vid,ac = 1 mV, then gain is VF("/vout") / 1e-3.
```

经过 scaling 后，transfer function 应该相同。

真实 input swing 必须用以下方式验证：

```text
DC differential sweep
transient large-signal simulation
distortion analysis, if needed
```

精准说法：

```text
AC magnitude 是 small-signal linear-model normalization，不是 physical large-signal input swing。
```

## 8. STB Stability Analysis

目的：在 unity-feedback configuration 下，正式量 loop gain、crossover frequency、phase
margin。

Unity-gain buffer 设置示例：

```text
Non-inverting input:    Vin+ = <nominal-vcm>
Feedback path:          Vout -> iprobe -> Vin-
Load:                   <load-capacitance>
```

使用：

```text
analogLib / iprobe
```

不要再加另一颗 ideal DC source 强迫 feedback input。反相端应该由 feedback loop 决定。

在 ADE：

```text
Analyses -> Choose -> stb
Probe instance: <iprobe-instance>
Sweep: 1 Hz to 10 GHz, 100 points/decade
```

Calculator expressions：

```text
db20(getData("loopGain" ?result "stb"))
phase(getData("loopGain" ?result "stb"))
getData("phaseMargin" ?result "stb_margin")
getData("phaseMarginFreq" ?result "stb_margin")
```

正式示例结果：

```text
Loop crossover: about 894.3 MHz
Phase margin:   about 79.63 deg
```

Open-loop AC UGF 和 STB loop crossover 不必完全相同，因为 bias point、loop loading、
return-ratio definition 可能不同。正式 stability specification 以 STB 为主。

## 9. Unity-Gain Buffer Large-Signal Transient

目的：测 large-signal tracking、slew behavior、overshoot、settling time、rise/fall time。

Topology：

```text
Vout -> iprobe -> Vin-
Vin+ uses a pulse source
CLOAD from Vout to GND
```

Input step 示例：

```text
Low level:       0.75 V
High level:      0.95 V
Rise time:       100 ps
Fall time:       100 ps
Pulse width:     20 ns
Period:          40 ns
```

示例量测输出：

```text
Vout low:         748.731 mV
Vout high:        941.105 mV
Output step:      192.374 mV
Input step:       200 mV
Average large-signal closed-loop gain: about 0.962
```

有限 open-loop gain 造成 tracking error 是正常的：

```text
Acl = A / (1 + A)
```

若 `A = 31.4 V/V`，small-signal follower gain 约 `0.969`。large-signal 实测接近
`0.962` 合理，因为大信号过程中 gain 会随 operating point 改变。

## 10. Overshoot 与 1% Settling Time

若 finite closed-loop DC gain 造成 static tracking error，settling target 应使用实际 final
output value，而不是 commanded input value。

示例：

```text
Final high output:  941.105 mV
Peak output:        941.4912 mV
Output step:        192.374 mV
Overshoot:          about 0.20%
```

1% settling：

```text
1% band = 0.01 * output step
```

示例：

```text
1% band:            1.924 mV
Lower bound:        939.181 mV
Upper bound:        943.029 mV
1% settling time:   about 0.581 ns
```

## 11. Rise Time、Fall Time 与 Effective Slew Rate

10-90% rise time：

```text
V10 = VL + 0.1 * (VH - VL)
V90 = VL + 0.9 * (VH - VL)
tr = t90 - t10
```

示例：

```text
10-90% rise time: about 0.3305 ns, or 331 ps
90-10% fall time: about 0.3346 ns, or 335 ps
```

10-90% effective slew rate：

```text
SRrise = (V90 - V10) / tr
SRfall = (V90 - V10) / tf
```

示例：

```text
Effective rising slew:  about 465.6 V/us
Effective falling slew: about 460.0 V/us
```

如果 waveform 没有明显 slew-limited linear ramp 或稳定 derivative plateau，不要只把很窄的
derivative spike 当成正式 slew rate。尖峰可能来自 input-edge feedthrough、Cgd coupling，
或 numerical derivative artifact。

## 12. 示例 Characterization Summary

以下是一组示例量测结果：

```text
Supply:                                  1.2 V
Nominal common-mode:                     0.8 V
Load:                                    100 fF
ICMR:                                    about 0.711 V to 1.2 V
Output swing:                            about 0.346 V to 1.03 V
Open-loop DC gain:                       about 31.4 V/V, 29.9 dB
5% linear differential input range:      about -2.1 mV to +5.2 mV
AC low-frequency gain:                   about 31.43 V/V, 29.95 dB
-3 dB bandwidth:                         about 32.59 MHz
Open-loop AC UGF:                        about 949.6 MHz
Formal STB loop crossover:               about 894.3 MHz
Phase margin:                            about 79.63 deg
Large-signal output step:                about 192.374 mV
Large-signal closed-loop gain:           about 0.962
Overshoot:                               about 0.20%
1% settling time:                        about 0.581 ns
10-90% rise time:                        about 0.3305 ns
90-10% fall time:                        about 0.3346 ns
Effective rising slew:                   about 465.6 V/us
Effective falling slew:                  about 460.0 V/us
```

## 13. 安全关闭流程

如果要换地方、稍后继续：

```text
Virtuoso normal exit
MobaXterm SSH exit
VMware suspend
Windows hibernate
```

Virtuoso 建议流程：

1. 执行 **Check and Save**。
2. 若需要保存 ADE 设置，使用 **Session -> Save State**。
3. 正常关闭 ADE、ViVA、Calculator。
4. 从 CIW 使用 **File -> Exit**。

MobaXterm：

```bash
exit
```

VMware Workstation：

```text
VM -> Power -> Suspend
```

若笔记本要放进包里移动，建议先 suspend VM，再 hibernate Windows。如果 Virtuoso 是通过
MobaXterm X11 forwarding 打开，不要在 Virtuoso 还活着时先关闭 X11 session。

## 14. 下一步建议

完成以上项目后，可继续：

```text
Power consumption
PVT corners
Temperature sweep
Monte Carlo / mismatch
```

Open-loop noise、CMRR automation 与 PSRR automation 都已有独立章节。请接着看
[第 11 章：Baseline Summary and PVT Automation](11-baseline-summary-and-pvt-automation.md)，
用于 corners 与 variation planning。

CMRR：

```text
CMRR = 20 log10(|Ad / Acm|)
```

其中 `Ad` 是 differential-mode gain，`Acm` 是 common-mode gain。

## 15. 三个重点

1. AC source 的 `+0.5` 与 `-0.5` 是 small-signal normalization，不是 physical
   large-signal input swing。
2. 真实 input swing 必须用 DC 或 transient nonlinear simulation 验证。
3. AC analysis 给的是 bias point 附近的 local transfer function；只有真实信号仍在
   small-signal region 时，才能线性缩放到真实小信号电路。
