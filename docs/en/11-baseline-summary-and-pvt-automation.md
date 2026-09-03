# Chapter 11: Baseline Summary and PVT Automation

This chapter consolidates the nominal five-transistor OTA baseline and turns the
next characterization stage into a reusable deterministic process-corner
workflow.

The source notes contained local paths, project names, process-file details,
generated filenames, and machine-specific script settings. This public version
keeps the engineering method and uses placeholders for private environment
details.

## 1. Scope

This chapter covers:

1. Frozen nominal baseline conditions
2. DC, AC, STB, transient, noise, CMRR, and PSRR summary metrics
3. Cross-checks that confirm consistency between analyses
4. Baseline strengths and limitations
5. Deterministic process-corner automation flow
6. Refined near-zero VID linearity workflow
7. Transient metric extraction for completed corners
8. Consolidated process-corner report generation
9. What to keep private before publishing results

The reusable shell-script templates are stored in:

```text
scripts/pvt/run_process_corners.sh
scripts/pvt/refine_vid_linearity.sh
scripts/pvt/analyze_process_corner_transients.sh
scripts/pvt/build_process_corner_report.sh
```

## 2. Frozen Nominal Conditions

Example nominal baseline:

```text
Process corner:              TT
Temperature:                 27 deg C
VDD:                         1.2 V
Bias voltage:                550 mV
Input common-mode voltage:   800 mV
Differential DC input:       0 V
Load capacitance:            100 fF
```

Example device dimensions:

```text
NM0/NM1: W = 4 um,  L = 260 nm
NM2:     W = 8 um,  L = 260 nm
PM0/PM1: W = 10 um, L = 260 nm
```

Completed nominal analyses:

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

Any schematic sizing, bias, model, load, or netlist change invalidates the
frozen baseline and requires the affected analyses to be rerun.

## 3. DC Operating Point Summary

Example current and power:

```text
Estimated VDD current:       139.300253 uA
Estimated DC power:          167.160304 uW
Tail current:                139.299600 uA
Input-pair current sum:      139.300020 uA
Current-balance error:       0.420080 nA
```

Example device operating points:

| Device | Current | gm | gm/Id | ro | Saturation margin |
| --- | ---: | ---: | ---: | ---: | ---: |
| NM0 | 69.6500 uA | 0.789655 mS | 11.3375 1/V | 91.2000 kOhm | 353.913 mV |
| NM1 | 69.6500 uA | 0.789655 mS | 11.3375 1/V | 91.1998 kOhm | 353.912 mV |
| NM2 | 139.2996 uA | 1.497467 mS | 10.7500 1/V | 12.9244 kOhm | 67.113 mV |
| PM0 | 69.6501 uA | 0.736229 mS | 10.5704 1/V | 71.8353 kOhm | 322.662 mV |
| PM1 | 69.6501 uA | 0.736230 mS | 10.5704 1/V | 71.8354 kOhm | 322.663 mV |

All MOS devices are in saturation for this nominal operating point. The tail
device has the smallest saturation margin and lowest output resistance, so it is
an important limit for headroom, CMRR, and negative-rail coupling.

## 4. DC Range Summary

Example VCM sweep:

```text
Sweep range:                         0 V to 1.2 V
Step:                                10 mV
Point count:                         121
All-devices-saturated low sample:    0.720 V
All-devices-saturated high sample:   1.200 V
```

The low-side transition is between `0.710 V` and `0.720 V`. The high side
reaches the sweep boundary, so report it as:

```text
VCM high >= 1.200 V within the tested sweep
```

Do not claim that `1.200 V` is the real high-side failure point unless a wider
sweep proves it.

Example VID sweep:

```text
Sweep range:              -50 mV to +50 mV
Step:                     100 uV
Point count:              1001
VID saturation range:     -18.2 mV to +13.8 mV
VOUT at VID=0:            0.7039498 V
Center DC gain:           31.434502 V/V
Center DC gain:           29.948132 dB
```

Linearity by secant-gain deviation from the center small-signal slope:

```text
0.1 percent VID range:       -0.1 mV to +0.1 mV
0.1 percent VID width:        0.2 mV
0.1 percent VOUT range:       0.7008088 V to 0.7070957 V

1 percent VID range:         -1.0 mV to +2.0 mV
1 percent VID width:          3.0 mV
1 percent VOUT range:         0.6727987 V to 0.7674419 V
```

The saturation range and linear range are different specifications. Devices can
remain saturated even when the transfer curve no longer meets a 0.1 percent or
1 percent linearity requirement.

## 5. AC and STB Summary

Open-loop differential AC:

```text
Low-frequency gain:             31.434620 V/V
Low-frequency gain:             29.948160 dB
Unity-gain frequency:           949.525439 MHz
Sweep:                          1 Hz to 100 GHz, 100 points/decade
```

Unity-feedback STB:

```text
Low-frequency loop gain:        31.77780 V/V
Low-frequency loop gain:        30.04247 dB
Phase margin:                   79.63017 deg
Phase-margin frequency:         894.2901 MHz
Gain margin:                    NOT_FOUND_WITHIN_1HZ_TO_100GHZ
```

The STB phase never reaches the crossing needed for a finite Cadence gain-margin
calculation within the sweep range. A `nan` gain margin in this context is not
by itself a simulation failure or instability proof.

The STB crossover and open-loop differential UGF use different testbench/result
definitions, so `894.29 MHz` and `949.53 MHz` do not need to be identical. Use
the formal STB phase margin as the unity-feedback stability metric.

## 6. Transient Summary

Example 100 mV input step:

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

Example 140 mV input step:

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

From 100 mV to 140 mV, the output step scales nearly proportionally. Rise/fall
time and settling time stay close, while maximum slope still increases:

```text
HARD_SLEW_RATE_CEILING=NO
POSITIVE_PATH_COMPRESSION=MINIMAL
NEGATIVE_PATH_COMPRESSION=MILD
LARGE_SIGNAL_OPERATION_AT_140MV=ACCEPTABLE
```

## 7. Noise, CMRR, and PSRR Summary

Open-loop input-referred noise:

```text
White-noise floor:       7.4005 nV/sqrt(Hz)
Flicker-noise corner:    13.8629 MHz

1 Hz to 1 kHz:           123.936 uV RMS
1 Hz to 1 MHz:           150.133 uV RMS
1 Hz to 10 MHz:          157.775 uV RMS
1 Hz to 100 MHz:         176.956 uV RMS
1 Hz to UGF:             276.975 uV RMS
```

Noise contribution summary:

```text
Low-frequency flicker noise:    dominated by PM current-mirror devices
Corner-region noise:            NM input pair and PM mirror both contribute
White/high-frequency noise:     dominated by NM input pair
Tail-device contribution:       negligible under nominal conditions
```

CMRR:

```text
Low-frequency CMRR:         57.850270 dB
CMRR 3 dB bandwidth:        58.853855 MHz
CMRR >= 40 dB bandwidth:    414.847335 MHz
CMRR >= 20 dB bandwidth:    2.049543 GHz
CMRR at 100 MHz:            51.942680 dB
CMRR near differential UGF: 30.465873 dB
```

Formal input-referred PSRR:

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

The documented PSRR- fixture uses a local VSS node while VDD, inputs, bias, and
load remain referenced to global `0`. A VSS-tracking bias system requires a
separate PSRR- analysis.

## 8. Cross-Checks

Useful baseline consistency checks:

1. VID center DC gain is `29.948132 dB`.
2. Open-loop low-frequency AC gain is `29.948160 dB`.
3. The difference is about `0.000028 dB`.
4. Differential AC, noise, CMRR, PSRR+, and PSRR- each contain `1101` numeric
   frequency points from 1 Hz to 100 GHz.
5. Each paired post-processor verifies the frequency grid before combining
   curves.
6. Input-pair current sum and tail current differ by only `0.420 nA`.

These checks make the baseline coherent enough to freeze before process-corner
automation.

## 9. Engineering Assessment

Strengths:

1. Low nominal power, about `167.2 uW` at `1.2 V`.
2. High bandwidth relative to current, about `949.5 MHz` UGF at `139.3 uA`.
3. Strong nominal unity-feedback stability, with `79.63 deg` phase margin.
4. Fast sub-nanosecond transient response with low overshoot.
5. No hard slew-rate ceiling observed up to the tested `140 mV` input step.
6. Good nominal device matching and current balance.

Primary limitations:

1. Low open-loop gain, about `29.95 dB`.
2. Low-frequency CMRR is only about `57.85 dB`.
3. Low-frequency formal PSRR is only about `29.95 dB`.
4. PSRR- degrades substantially faster than PSRR+ at high frequency.
5. Flicker-noise corner is high, about `13.86 MHz`.
6. The tail device has only about `67.1 mV` nominal saturation margin and low
   output resistance.
7. Strict 0.1 percent open-loop VID linearity is limited to about `+/-0.1 mV`.

## 10. PVT Automation Flow

Before running a large matrix:

1. Freeze and hash the golden nominal netlist and all baseline scripts.
2. Inspect the PDK documentation for exact supported process-section names.
3. Define voltage and temperature ranges from the design specification.
4. Run DC operating point, open-loop AC, and STB across the process matrix first.
5. Select worst corners for transient, noise, CMRR, and PSRR reruns.
6. Run load sweep and Monte Carlo mismatch only after deterministic PVT is
   stable.

Use the process-corner runner template:

```bash
cd /home/<linux-user>/cadence_projects/<ota-project> || exit 1
PROJECT_DIR="$PWD" \
RESULT_ROOT="/home/<linux-user>/simulation/<ota-project>_ocean" \
PVT_CORNERS="ff ss fnsp snfp" \
bash scripts/pvt/run_process_corners.sh prepare
```

After inspecting generated scripts:

```bash
PROJECT_DIR="$PWD" \
RESULT_ROOT="/home/<linux-user>/simulation/<ota-project>_ocean" \
PVT_CORNERS="ff ss fnsp snfp" \
bash scripts/pvt/run_process_corners.sh core
```

Run `full` only after the core matrix is clean:

```bash
PVT_FORCE=0 \
PROJECT_DIR="$PWD" \
RESULT_ROOT="/home/<linux-user>/simulation/<ota-project>_ocean" \
bash scripts/pvt/run_process_corners.sh full
```

## 11. Refined VID Linearity

The coarse VID sweep is useful for range discovery. Near-zero linearity may need
a finer step:

```bash
PROJECT_DIR="$PWD" \
RESULT_ROOT="/home/<linux-user>/simulation/<ota-project>_ocean" \
PVT_CORNERS="ss fnsp" \
VID_REFINED_START="-5m" \
VID_REFINED_STOP="5m" \
VID_REFINED_STEP="10u" \
bash scripts/pvt/refine_vid_linearity.sh
```

Use refined results for the final 0.1 percent or 1 percent VID linearity table
when the coarse step is too large.

## 12. Transient and Report Post-Processing

Extract transient metrics from completed corner raw files:

```bash
PROJECT_DIR="$PWD" \
RESULT_ROOT="/home/<linux-user>/simulation/<ota-project>_ocean" \
PVT_CORNERS="ff ss fnsp snfp" \
bash scripts/pvt/analyze_process_corner_transients.sh
```

Build the consolidated process-corner report:

```bash
RESULT_ROOT="/home/<linux-user>/simulation/<ota-project>_ocean" \
PVT_CORNERS="ff ss fnsp snfp" \
bash scripts/pvt/build_process_corner_report.sh
```

Expected report artifacts:

```text
process_corner_report_<run-id>.txt
process_corner_metrics_long_<run-id>.tsv
process_corner_comparison_<run-id>.tsv
process_corner_report_<run-id>.sha256
```

Keep the generated reports private until all paths, PDK names, machine names,
and unpublished circuit names are sanitized.

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

## 14. Next Step

The baseline is ready for deterministic PVT. Continue with
[Chapter 12](12-deterministic-pvt-automation.md) to run the `prepare`, `core`,
and `full` modes, validate generated OCEAN scripts, refine VID linearity,
extract transient metrics, and build the consolidated process-corner report.
