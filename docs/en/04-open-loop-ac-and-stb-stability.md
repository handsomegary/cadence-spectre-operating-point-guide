# Chapter 4: Open-Loop AC and STB Feedback Stability

This chapter documents a reusable Cadence Virtuoso, Spectre, and OCEAN workflow
for open-loop AC characterization and closed-loop STB stability analysis.

The source notes contained local paths, cell names, and one-run checkpoints.
This public version keeps the method and replaces private details with
placeholders.

## 1. Scope

This workflow covers:

1. The difference between feedback topology and analysis type
2. Open-loop AC gain, bandwidth, and unity-gain frequency
3. Differential AC source normalization
4. Confirming the intended load capacitor
5. Building a dedicated unity-feedback STB testbench
6. Running STB with an `iprobe`
7. Reading formal Spectre STB margins
8. Comparing open-loop AC estimates with formal STB results

Example nominal conditions:

```text
Circuit type:        five-transistor one-stage OTA
Process corner:      <process-corner>
Temperature:         27 deg C
Supply:              VDD = 1.2 V
Nominal VCM:         0.8 V
Nominal VID:         0 V
Load capacitance:    100 fF
```

These are example values. Recheck them for each design and PDK.

## 2. Feedback Is Not an Analysis Type

Feedback is a circuit topology. Transient, AC, DC, and STB are analysis types.
They are not mutually exclusive.

Typical flow:

```text
Open-loop AC:
  Keep the OTA open-loop and use differential AC sources to measure frequency response.

Closed-loop STB:
  Connect the OTA as a unity negative-feedback loop and use an iprobe to measure return ratio and formal phase margin.

Closed-loop transient:
  Keep the unity-feedback topology and apply a time-domain input step to measure settling, overshoot, and slew behavior.
```

Use separate testbenches when the topology is meaningfully different. This
reduces accidental cross-contamination between open-loop AC, STB, and transient
workflows.

## 3. Recommended Directory Layout

Example layout:

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

Useful scripts:

```text
ac_sweep.ocn
stb_sweep.ocn
inspect_stb_margin.ocn
```

Save a dated checkpoint after a script is proven:

```bash
cp -p ac_sweep.ocn ac_sweep.ocn.working_YYYYMMDD
cp -p stb_sweep.ocn stb_sweep.ocn.working_YYYYMMDD
```

## 4. Batch Simulation Checklist

Return to Virtuoso only when schematic topology, source properties, design
variables, or probe placement changes.

Recommended flow:

1. Modify the intended schematic.
2. Run **Check and Save**.
3. Use **Variables -> Copy From Cellview** in ADE when needed.
4. Use **Simulation -> Netlist -> Recreate**.
5. Do not press **Run** in ADE if the next step is OCEAN batch.
6. Make sure Virtuoso, Spectre, and OCEAN are not using the same result
   directory.
7. Run the OCEAN script from the Linux shell.

Check for leftover processes:

```bash
pgrep -af 'virtuoso|ocean|spectre|cdsMsgServer'
```

Keep GUI ADE and batch OCEAN result directories separate.

## 5. Confirm the Load Capacitor

Before trusting an AC or STB result, confirm the intended load exists in the
netlist. For example:

```text
Output node:       vout
Load capacitor:    CLOAD = <load-capacitance>
No unintended output resistor
No unintended leftover iprobe in the open-loop AC testbench
```

Quick inspection:

```bash
grep -nEi 'vout|capacitor|resistor|iprobe' \
/home/<linux-user>/simulation/<ota-project>/spectre/schematic/netlist/input.scs
```

An AC result with `CL = 100 fF` is not an unloaded result. The bandwidth,
unity-gain frequency, and phase are all affected by the load.

## 6. Open-Loop AC Source Setup

For differential AC normalization, use two input sources:

```text
Vin+ DC value:       VCM + VID/2
Vin- DC value:       VCM - VID/2

Vin+ AC magnitude:   0.5
Vin+ AC phase:       0 deg

Vin- AC magnitude:   0.5
Vin- AC phase:       180 deg
```

Then:

```text
Vin,diff = 0.5<0deg - 0.5<180deg = 1 V
```

With a 1 V differential AC input, `VOUT/Vin,diff` numerically equals voltage
gain.

Inspect the netlist:

```bash
grep -nE '^V[0-9]+ ' \
/home/<linux-user>/simulation/<ota-project>/spectre/schematic/netlist/input.scs
```

Expected pattern:

```text
V0 (...) vsource dc=VCM+VID/2 mag=500.0m phase=0 type=sine
V1 (...) vsource dc=VCM-VID/2 mag=500.0m phase=180 type=sine
```

## 7. Open-Loop AC OCEAN Pattern

Example script core:

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

Run:

```bash
cd /home/<linux-user>/cadence_projects/<ota-project>
ocean -nograph -restore ac_sweep.ocn 2>&1 | tee ac_sweep_run.log
```

Check errors and data count:

```bash
grep -nEi 'OCN-|ERROR|FATAL|SYNTAX|Segmentation|SPECTRE-' ac_sweep_run.log

awk 'NF==4 && $1 ~ /^[0-9]/ {n++}
END {print "AC_DATA_POINTS =",n}' \
/home/<linux-user>/simulation/<ota-project>_ocean/ac_openloop/ac_gain_raw.txt
```

For 1 Hz to 100 GHz at 100 points/decade:

```text
11 decades * 100 points/decade + start point = 1101 points
```

## 8. Calculate Bandwidth, UGF, and PM Estimate

The raw AC report columns are:

```text
$1 = frequency, Hz
$2 = gain magnitude, V/V
$3 = gain, dB
$4 = phase, degrees
```

Use log-frequency interpolation for -3 dB bandwidth and 0 dB crossing:

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

Example source checkpoint:

```text
Low-frequency gain: 31.434620 V/V, or 29.948160 dB
-3 dB bandwidth:    32.525935 MHz
Open-loop AC UGF:   949.525439 MHz
Phase at UGF:       -101.049136 deg
PM estimate:        78.950864 deg
```

This phase-margin estimate assumes unity negative feedback. It is useful for a
sanity check, but formal stability should come from STB.

## 9. Why Use a Dedicated STB Testbench

Keep the original DC/AC testbench free of `iprobe` unless it is specifically
needed. A dedicated STB cell avoids:

```text
Leftover iprobe changing the circuit inventory
DC/AC and STB topology contamination
Manual delete-and-reinsert steps before each analysis
Confusion after recreating the netlist
```

Recommended split:

```text
<ota-project>:       DC OP, VCM sweep, VID sweep, open-loop AC
<ota-project>_stb:   unity-feedback STB with permanent iprobe
<ota-project>_tran:  unity-feedback transient, if needed
```

## 10. Closed-Loop STB Topology

Example unity-feedback STB schematic:

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

Remove the second independent input source in the STB testbench. The inverting
input should be driven by the feedback path.

The `iprobe` is electrically similar to a 0 V source for DC, so the feedback
loop remains closed for biasing. Spectre injects the small-signal STB
perturbation through the probe.

Inspect the STB netlist:

```bash
grep -nEi 'parameters|iprobe|vsource|capacitor|vout' \
/home/<linux-user>/simulation/<ota-project>_stb/spectre/schematic/netlist/input.scs
```

Expected pattern:

```text
parameters VCM
IPRB0 (...) iprobe
CLOAD (...) capacitor c=<load-capacitance>
VBIAS (...) vsource dc=<bias-voltage>
VDD (...) vsource dc=<supply-voltage>
VINP (...) vsource dc=VCM type=sine
```

## 11. Closed-Loop STB OCEAN Pattern

Example script core:

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

Run:

```bash
ocean -nograph -restore stb_sweep.ocn 2>&1 | tee stb_sweep_run.log
```

Check data count:

```bash
awk 'NF==4 && $1 ~ /^[0-9]/ {n++}
END {print "STB_DATA_POINTS =",n}' \
/home/<linux-user>/simulation/<ota-project>_ocean/stb_unity/stb_loopgain_raw.txt
```

For the same 1 Hz to 100 GHz sweep at 100 points/decade, expect `1101` points.

## 12. STB Phase May Start Near 180 Degrees

Open-loop AC gain is usually plotted as `VOUT/VID`, so the low-frequency phase
may be near 0 degrees.

STB `loopGain` is a closed-loop return-ratio quantity and includes feedback
sign conventions. A stable negative-feedback loop may therefore report a
low-frequency phase near +180 degrees or -180 degrees.

This does not automatically mean the loop is positive feedback, and it does not
automatically mean the `iprobe` direction is wrong. Read formal margins from
`stb_margin`.

## 13. Read Formal STB Margins

Use a report-only script after the STB run:

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

Run:

```bash
ocean -nograph -restore inspect_stb_margin.ocn \
2>&1 | tee inspect_stb_margin.log
```

Check:

```bash
grep -nEi 'OCN-|ERROR|FATAL|SYNTAX|phaseMargin|gainMargin' \
inspect_stb_margin.log
```

Example source checkpoint:

```text
phaseMargin     = 79.63017 deg
phaseMarginFreq = 8.942901e+08 Hz
gainMargin      = nan
gainMarginFreq  = nan
```

`gainMargin = nan` is not automatically a simulation error. It can mean no
phase crossover was found inside the sweep range. In that case, report gain
margin as `N/A` with the sweep range and reason, rather than converting `nan` to
zero.

## 14. Compare AC Estimate and STB Result

Example comparison:

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

Small differences are expected because:

```text
The open-loop AC and unity-feedback STB bias points may differ.
STB measures return ratio with the feedback loop closed.
The probe preserves the actual impedance and loading around the loop.
```

Use STB as the formal stability specification. Use open-loop AC as a
cross-check and design intuition.

## 15. SPECTRE-17101 Warning

If the log shows:

```text
WARNING (SPECTRE-17101): The value 'psf' specified using the
'checklimitdest' option will no longer be supported in future releases.
```

Interpretation:

```text
This is a future-compatibility warning.
It is not a convergence error.
It does not mean the PSF data is corrupt.
It does not invalidate the AC or STB result by itself.
```

Errors that deserve immediate attention include:

```text
ERROR
FATAL
SYNTAX
Segmentation
Analysis terminated prematurely
Invalid probe instance
```

## 16. Nominal Stability Summary

Example source checkpoint:

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

This is a nominal checkpoint, not a worst-case PVT conclusion. Continue with
corner, temperature, supply, load, and mismatch checks before signing off.

## 17. Next Step: Closed-Loop Transient

After nominal AC and STB are complete, move to closed-loop transient analysis.

Measure:

```text
Small-signal settling time
Large-signal settling time
Overshoot
Undershoot
Positive slew rate
Negative slew rate
```

Choose these before comparing results:

```text
Step amplitude
Pulse rise and fall time
Settling-error criterion, such as 1% or 0.1%
Simulation stop time
Load capacitance
```

Different transient conditions produce different settling and slew-rate
numbers, so keep the setup documented with the result.
