# Chapter 7: Five-Transistor OTA Characterization Workflow

This chapter describes a practical characterization flow for a generic
five-transistor, one-stage OTA in Cadence Virtuoso ADE with Spectre.

The source workflow included specific project names, paths, device labels, and
example numerical results. This public version keeps the engineering method but
uses generic placeholders where environment details may be private.

## 1. Scope

This workflow covers:

1. Input common-mode range, or ICMR
2. Output swing
3. DC differential gain and input linear range
4. Open-loop AC gain, bandwidth, and unity-gain frequency
5. STB stability analysis
6. Unity-gain buffer large-signal transient response
7. Slew rate, rise/fall time, overshoot, and 1% settling time
8. Why AC magnitude normalization does not equal real large-signal input swing
9. Safe shutdown steps for Virtuoso, MobaXterm, VMware, and Windows
10. Suggested next characterization items

The most important idea:

```text
AC magnitude is small-signal normalization. It is not the real physical input
swing applied to the nonlinear transistor circuit.
```

## 2. Generic Testbench

Example placeholders:

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

Typical five-transistor OTA devices:

```text
NMOS differential pair:      <nmos-input-left>, <nmos-input-right>
PMOS current-mirror load:    <pmos-load-left>, <pmos-load-right>
NMOS tail current source:    <nmos-tail>
```

The example source used:

```text
VDD = 1.2 V
VCM = 0.8 V
CLOAD = 100 fF
```

These values are examples, not universal design targets.

## 3. Input Common-Mode Range

Goal: find the range of `VCM` where key MOS devices remain in the intended
operating region when:

```text
Vin+ = VCM
Vin- = VCM
```

In ADE, create the design variable:

```text
VCM
```

Run a DC sweep:

```text
Analysis:          dc
Sweep variable:    VCM
Start:             0 V
Stop:              VDD
Step:              10 mV, or a suitable resolution
```

Save and inspect OP parameters:

```text
tail device:       vds, vdsat, region
input device:      vds, vdsat, region
load device:       vds, vdsat, region
```

For NMOS saturation, use:

```text
VDS >= VDSAT
```

For PMOS saturation, use:

```text
|VDS| >= |VDSAT|
```

The lower ICMR is often limited by the tail current source. The upper ICMR may
be limited by the input pair, active load, or the supply rail.

Example result from the source workflow:

```text
Practical ICMR: about 0.711 V to 1.2 V
Nominal VCM selected for later tests: 0.8 V
```

## 4. Output Swing

Goal: force `Vout` across the output range and find where upper or lower output
devices leave saturation.

Set:

```text
Vin+ = <nominal-vcm>
Vin- = <nominal-vcm>
```

Add an ideal DC voltage source from `Vout` to ground:

```text
Source name:       <vout-test-source>
DC value:          VOUT_TEST
Connection:        Vout to GND
```

The output load capacitor should also connect from `Vout` to ground. The test
source and load capacitor are in parallel. Do not accidentally put them in
series.

Run a DC sweep:

```text
Sweep variable:    VOUT_TEST
Start:             0 V
Stop:              VDD
```

Inspect:

```text
input-side output device:    vds, vdsat, region
active-load output device:   vds, vdsat, region
```

Example result:

```text
Vout,min: about 0.346 V
Vout,max: about 1.03 V
Usable output swing: about 0.684 V
Open-loop quiescent output: about 0.704 V
Approximate symmetric swing around Q: about +/-0.326 V, or 0.652 Vpp
```

## 5. DC Differential Gain and Input Linear Range

Goal: sweep differential input voltage and measure the local slope of
`Vout` versus `VID`.

Use:

```text
VCM = <nominal-vcm>
Vin+ = VCM + VID/2
Vin- = VCM - VID/2
```

Run a DC sweep:

```text
Sweep variable:    VID
Start:             -10 mV
Stop:              +10 mV
Step:              0.1 mV, or suitable resolution
```

Plot:

```text
Vout vs VID
```

In the Calculator, use the derivative of the DC sweep waveform:

```text
deriv(VS("/vout"))
```

Use `VS("/vout")` for a DC sweep waveform. In some ADE setups, `VDC("/vout")`
may return only a scalar and will not work correctly with `deriv`.

At `VID = 0`, the example result was:

```text
DC gain: about 31.4 V/V, or 29.9 dB
```

For a 5% linearity range:

```text
Allowed gain = 0.95 * A0
```

Find where `deriv(VS("/vout"))` crosses that value.

Example:

```text
A0 = 31.4 V/V
5% threshold = 29.83 V/V
5% linear differential input range: about -2.1 mV to +5.2 mV
Total width: about 7.3 mV
```

Asymmetry is normal in a single-ended five-transistor OTA because current
mirrors, finite output resistance, and bias point all affect the transfer curve.

## 6. Open-Loop AC Analysis

Goal: measure small-signal gain, bandwidth, and unity-gain frequency.

Set the DC bias:

```text
Vin+ DC = <nominal-vcm>
Vin- DC = <nominal-vcm>
```

For differential AC normalization:

```text
Vin+ AC magnitude = 0.5
Vin+ AC phase     = 0 deg

Vin- AC magnitude = 0.5
Vin- AC phase     = 180 deg
```

Then:

```text
Vid,ac = +0.5 - (-0.5) = 1 V
```

Run an AC sweep:

```text
Analysis:           ac
Sweep type:         log
Start:              1 Hz
Stop:               1e10 Hz
Points/decade:      100
```

When `Vid,ac = 1`, gain can be plotted directly as:

```text
dB20(VF("/vout"))
```

Example result:

```text
Low-frequency gain:    about 31.43 V/V, or 29.95 dB
-3 dB bandwidth:       about 32.59 MHz
One-pole GBW estimate: about 1.024 GHz
Open-loop UGF:         about 949.6 MHz
Open-loop phase at UGF: about -101.05 deg
Rough open-loop PM estimate: about 78.95 deg
```

Use STB for formal closed-loop stability.

## 7. AC Magnitude Is Not Real Input Swing

If the true 5% linear input range is only a few millivolts, seeing `AC
magnitude = 0.5` can feel wrong. It is not wrong.

Spectre AC analysis works in two steps:

1. Solve the DC operating point.
2. Linearize the nonlinear transistor network around that operating point.

The AC analysis solves a small-signal network made from local quantities such as:

```text
gm
gmb
gds
ro
Cgs
Cgd
operating region
```

It does not physically drive the nonlinear circuit with a large differential
input of `1 V`.

In a linearized system, amplitude can be chosen for convenient normalization:

```text
If Vid,ac = 1 V, then Vout numerically equals Vout/Vid.
If Vid,ac = 1 mV, then gain is VF("/vout") / 1e-3.
```

The transfer function should be the same after scaling.

The real input swing must be verified by:

```text
DC differential sweep
transient large-signal simulation
distortion analysis, if needed
```

Precise statement:

```text
AC magnitude is small-signal linear-model normalization, not physical large-signal input swing.
```

## 8. STB Stability Analysis

Goal: formally measure loop gain, crossover frequency, and phase margin in a
unity-feedback configuration.

Example unity-gain buffer setup:

```text
Non-inverting input:    Vin+ = <nominal-vcm>
Feedback path:          Vout -> iprobe -> Vin-
Load:                   <load-capacitance>
```

Use:

```text
analogLib / iprobe
```

Do not add another ideal DC source that forces the feedback input. The inverting
input should be determined by the feedback loop.

In ADE:

```text
Analyses -> Choose -> stb
Probe instance: <iprobe-instance>
Sweep: 1 Hz to 10 GHz, 100 points/decade
```

Calculator expressions:

```text
db20(getData("loopGain" ?result "stb"))
phase(getData("loopGain" ?result "stb"))
getData("phaseMargin" ?result "stb_margin")
getData("phaseMarginFreq" ?result "stb_margin")
```

Example formal result:

```text
Loop crossover: about 894.3 MHz
Phase margin:   about 79.63 deg
```

Open-loop AC UGF and STB loop crossover do not need to match exactly because
bias point, loop loading, and return-ratio definition can differ. Use STB for
the formal stability specification.

## 9. Unity-Gain Buffer Large-Signal Transient

Goal: test large-signal tracking, slew behavior, overshoot, settling time, and
rise/fall time.

Topology:

```text
Vout -> iprobe -> Vin-
Vin+ uses a pulse source
CLOAD from Vout to GND
```

Example input step:

```text
Low level:       0.75 V
High level:      0.95 V
Rise time:       100 ps
Fall time:       100 ps
Pulse width:     20 ns
Period:          40 ns
```

Example measured output:

```text
Vout low:         748.731 mV
Vout high:        941.105 mV
Output step:      192.374 mV
Input step:       200 mV
Average large-signal closed-loop gain: about 0.962
```

This tracking error is expected when open-loop gain is finite:

```text
Acl = A / (1 + A)
```

For `A = 31.4 V/V`, the small-signal follower gain estimate is about `0.969`.
A measured large-signal value near `0.962` is plausible because gain changes
with operating point during a large step.

## 10. Overshoot and 1% Settling Time

Use the actual final output value, not the commanded input value, as the
settling target when finite closed-loop DC gain creates static tracking error.

Example:

```text
Final high output:  941.105 mV
Peak output:        941.4912 mV
Output step:        192.374 mV
Overshoot:          about 0.20%
```

For 1% settling:

```text
1% band = 0.01 * output step
```

Example:

```text
1% band:            1.924 mV
Lower bound:        939.181 mV
Upper bound:        943.029 mV
1% settling time:   about 0.581 ns
```

## 11. Rise Time, Fall Time, and Effective Slew Rate

For 10-90% rise time:

```text
V10 = VL + 0.1 * (VH - VL)
V90 = VL + 0.9 * (VH - VL)
tr = t90 - t10
```

Example:

```text
10-90% rise time: about 0.3305 ns, or 331 ps
90-10% fall time: about 0.3346 ns, or 335 ps
```

Effective slew rate from 10-90%:

```text
SRrise = (V90 - V10) / tr
SRfall = (V90 - V10) / tf
```

Example:

```text
Effective rising slew:  about 465.6 V/us
Effective falling slew: about 460.0 V/us
```

Do not report a narrow derivative spike as the only formal slew rate unless the
waveform clearly has a slew-limited linear ramp or a stable derivative plateau.
Narrow derivative peaks may include input-edge feedthrough, Cgd coupling, or
numerical derivative artifacts.

## 12. Example Summary Table

These are example results from one characterization run:

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

## 13. Safe Shutdown

If you plan to move locations and continue later:

```text
Virtuoso normal exit
MobaXterm SSH exit
VMware suspend
Windows hibernate
```

Recommended Virtuoso sequence:

1. Run **Check and Save**.
2. Save ADE state if needed with **Session -> Save State**.
3. Close ADE, ViVA, and Calculator windows normally.
4. Exit from CIW with **File -> Exit**.

For MobaXterm:

```bash
exit
```

For VMware Workstation:

```text
VM -> Power -> Suspend
```

For a laptop that will be carried around, hibernate Windows after suspending the
VM. Avoid closing the MobaXterm X11 session before Virtuoso exits if Virtuoso
was launched through X11 forwarding.

## 14. Suggested Next Characterization Items

After the items above, continue with:

```text
CMRR
PSRR+
PSRR-
Noise
Input-referred noise
Power consumption
PVT corners
Temperature sweep
Monte Carlo / mismatch
```

CMRR uses:

```text
CMRR = 20 log10(|Ad / Acm|)
```

where `Ad` is differential-mode gain and `Acm` is common-mode gain.

## 15. Three Key Takeaways

1. AC source values such as `+0.5` and `-0.5` are small-signal normalization,
   not physical large-signal input swing.
2. Real input swing must be verified with DC or transient nonlinear simulation.
3. AC analysis gives the local transfer function around the bias point; it can
   be scaled to real small signals only while the real signal stays in the
   small-signal region.
