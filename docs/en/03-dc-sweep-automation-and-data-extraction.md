# Chapter 3: DC Sweep Automation and Data Extraction

This chapter converts the VCM/VID sweep notes into a public, reusable workflow
for Cadence Virtuoso, Spectre, and OCEAN. The original notes included local
paths and project-specific names; this version uses placeholders.

## 1. Scope

This workflow covers:

1. Parameterizing `VCM` and `VID` in the schematic
2. Running DC operating point, VCM sweep, and VID sweep from OCEAN
3. Extracting swept device operating-point data
4. Checking MOS `region` and saturation margin
5. Calculating 1% DC linearity from a VID sweep

Example conditions:

```text
Circuit type:        five-transistor one-stage OTA
Supply:              VDD = 1.2 V
Nominal VCM:         0.8 V
Nominal VID:         0 V
Temperature:         27 deg C
Corner:              <process-corner>
```

These values are examples, not universal specifications.

## 2. Directory Layout

Keep scripts and batch results separate from GUI ADE results:

```text
OCEAN scripts:
/home/<linux-user>/cadence_projects/<ota-project>

ADE netlist:
/home/<linux-user>/simulation/<ota-project>/spectre/schematic/netlist/netlist

Quick netlist inspection file:
/home/<linux-user>/simulation/<ota-project>/spectre/schematic/netlist/input.scs

OCEAN result root:
/home/<linux-user>/simulation/<ota-project>_ocean

DC OP results:
/home/<linux-user>/simulation/<ota-project>_ocean/dcop

VCM sweep results:
/home/<linux-user>/simulation/<ota-project>_ocean/dc_vcm

VID sweep results:
/home/<linux-user>/simulation/<ota-project>_ocean/dc_vid
```

Useful script names:

```text
dcop.ocn
vcm_sweep.ocn
vid_sweep.ocn
inspect_vid_linearity.ocn
```

Save known-good checkpoints with dated names:

```bash
cp -p vid_sweep.ocn vid_sweep.ocn.working_YYYYMMDD
```

## 3. Stable GUI-to-Batch Flow

Return to Virtuoso only when schematic-level information changes:

1. Circuit topology changes.
2. Device sizes or source properties change in the schematic.
3. New design variables are added.
4. Instance names change.
5. An `iprobe` is added or removed for STB analysis.

Use this handoff:

1. Modify the schematic.
2. Run **Check and Save**.
3. In ADE, use **Variables -> Copy From Cellview**.
4. Confirm nominal values for all design variables.
5. Use **Simulation -> Netlist -> Recreate**.
6. Do not press **Run** in ADE if OCEAN batch will run next.
7. Make sure Virtuoso is not writing into the same result directory.
8. Run the OCEAN script from the Linux shell.

Before batch simulation:

```bash
pgrep -af 'virtuoso|ocean|spectre|cdsMsgServer'
```

Ideally this prints nothing. If another Cadence process is intentionally
running, make sure it uses a different result directory.

## 4. Parameterize VCM and VID

For a differential input pair, set both input source DC values from the same
variables:

```text
Vin+ DC value: VCM + VID/2
Vin- DC value: VCM - VID/2
```

Then:

```text
VCM = (Vin+ + Vin-) / 2
VID = Vin+ - Vin-
```

After editing the source properties, run **Check and Save**, copy variables
from cellview, set nominal values, and recreate the netlist.

Inspect the netlist:

```bash
grep -nE '^parameters|V[0-9]+.*vsource' \
/home/<linux-user>/simulation/<ota-project>/spectre/schematic/netlist/input.scs
```

Expected pattern:

```text
parameters VCM=<nominal-vcm> VID=0
V0 (...) vsource dc=VCM+VID/2 ...
V1 (...) vsource dc=VCM-VID/2 ...
```

## 5. DC OP Versus DC Sweep

Single operating point:

```lisp
desVar("VCM" 800m)
desVar("VID" 0)
analysis('dc ?saveOppoint t)
```

Parameter sweep:

```lisp
analysis('dc
    ?saveOppoint t
    ?param "VCM"
    ?start "0"
    ?stop "1.2"
    ?step "10m"
)
```

`saveOpPoint()` selects which device OP quantities are saved. It does not create
a DC analysis by itself.

## 6. VCM Sweep Pattern

Example:

```text
VCM:   0 V to VDD
Step:  10 mV
VID:   0 V
```

OCEAN core:

```lisp
resultsDir("/home/<linux-user>/simulation/<ota-project>_ocean/dc_vcm")

desVar("VCM" 800m)
desVar("VID" 0)

analysis('dc
    ?saveOppoint t
    ?param "VCM"
    ?start "0"
    ?stop "1.2"
    ?step "10m"
)

save('v "/vout")

saveOpPoint("/PM0" ?operatingPoints "ids gm gds vgs vds vdsat region")
saveOpPoint("/PM1" ?operatingPoints "ids gm gds vgs vds vdsat region")
saveOpPoint("/NM0" ?operatingPoints "ids gm gds vgs vds vdsat region")
saveOpPoint("/NM1" ?operatingPoints "ids gm gds vgs vds vdsat region")
saveOpPoint("/NM2" ?operatingPoints "ids gm gds vgs vds vdsat region")

temp(27)
run()

selectResult('dc)

ocnPrint(
    ?output "/home/<linux-user>/simulation/<ota-project>_ocean/dc_vcm/vcm_devices_raw.txt"
    v("/vout")
    getData("NM0:ids") getData("NM0:region")
    getData("NM1:ids") getData("NM1:region")
    getData("NM2:ids") getData("NM2:region")
    getData("PM0:ids") getData("PM0:region")
    getData("PM1:ids") getData("PM1:region")
)

exit()
```

Run and verify:

```bash
ocean -nograph -restore vcm_sweep.ocn 2>&1 | tee vcm_sweep_run.log
grep -nEi 'OCN-|ERROR|FATAL|SYNTAX|Segmentation' vcm_sweep_run.log
awk 'NF==12 {n++} END {print "VCM_DATA_POINTS =",n}' \
/home/<linux-user>/simulation/<ota-project>_ocean/dc_vcm/vcm_devices_raw.txt
```

For 0 V to 1.2 V with 10 mV steps, expect `121` data points.

## 7. VID Sweep Pattern

Example:

```text
VCM:   fixed at nominal common-mode voltage
VID:   -50 mV to +50 mV
Step:  100 uV
```

OCEAN core:

```lisp
resultsDir("/home/<linux-user>/simulation/<ota-project>_ocean/dc_vid")

desVar("VCM" 800m)
desVar("VID" 0)

analysis('dc
    ?saveOppoint t
    ?param "VID"
    ?start "-50m"
    ?stop "50m"
    ?step "100u"
)

save('v "/vout")
```

Use the same `saveOpPoint()` and `ocnPrint()` pattern as the VCM sweep, but
write to:

```text
/home/<linux-user>/simulation/<ota-project>_ocean/dc_vid/vid_devices_raw.txt
```

For -50 mV to +50 mV with 100 uV steps, expect `1001` data points.

## 8. Swept Device Data Access

Single-point DC OP:

```lisp
selectResult('dcOpInfo)
pv("/NM0" "ids")
```

Swept DC data:

```lisp
selectResult('dc)
getData("NM0:ids")
```

In the source IC618 environment, this was the key difference:

```text
Correct for swept device OP: getData("NM0:ids")
Wrong in that environment:   getData("/NM0:ids")
```

Node voltages still use schematic node names:

```lisp
v("/vout")
```

If `outputs()` shows `/NM0:ids` but `getData("/NM0:ids")` returns `nil`, test
`getData("NM0:ids")`.

## 9. Raw TXT Column Map

With `vout` plus five devices, each data row has 12 fields:

```text
$1  = sweep variable, VCM or VID
$2  = VOUT
$3  = NM0 ids
$4  = NM0 region
$5  = NM1 ids
$6  = NM1 region
$7  = NM2 ids
$8  = NM2 region
$9  = PM0 ids
$10 = PM0 region
$11 = PM1 ids
$12 = PM1 region
```

Find rows where every saved MOS reports `region = 2`:

```bash
awk 'NF==12 && $4==2 && $6==2 && $8==2 && $10==2 && $12==2 {
    if (!seen) { first=$1; seen=1 }
    last=$1
    count++
}
END {
    if (seen)
        print "FIRST_ALL_REGION2 =",first,
              "\nLAST_ALL_REGION2  =",last,
              "\nPOINTS =",count
    else
        print "No all-region-2 point found"
}' INPUT_FILE.txt
```

Example source checkpoints:

```text
VCM all-region-2 sampled range: 0.72 V to 1.2 V
VID all-region-2 sampled range: -18.2 mV to +13.8 mV
```

This is not the same as 1% linear input range.

## 10. Saturation Margin

Confirm `region` with `vds` and `vdsat`:

```text
SAT_MARGIN = abs(VDS) - abs(VDSAT)
```

Interpretation:

```text
SAT_MARGIN > 0: inside saturation condition
SAT_MARGIN = 0: boundary
SAT_MARGIN < 0: outside saturation condition
```

OCEAN pattern:

```lisp
openResults("/home/<linux-user>/simulation/<ota-project>_ocean/dc_vcm/psf")
selectResult('dc)

nm0Margin = abs(getData("NM0:vds")) - abs(getData("NM0:vdsat"))
nm1Margin = abs(getData("NM1:vds")) - abs(getData("NM1:vdsat"))
nm2Margin = abs(getData("NM2:vds")) - abs(getData("NM2:vdsat"))
pm0Margin = abs(getData("PM0:vds")) - abs(getData("PM0:vdsat"))
pm1Margin = abs(getData("PM1:vds")) - abs(getData("PM1:vdsat"))
```

The limiting device depends on the topology and bias point, so recheck this for
each design.

## 11. Scientific Notation Before Math

Raw `ocnPrint()` output can contain engineering suffixes such as `100u`, `1m`,
or `69.6u`. Plain AWK math does not automatically convert these suffixes.

Before calculating gain or percentage error, print the VID/VOUT waveform in
scientific notation:

```lisp
openResults("/home/<linux-user>/simulation/<ota-project>_ocean/dc_vid/psf")
selectResult('dc)

ocnPrint(
    ?output "/home/<linux-user>/simulation/<ota-project>_ocean/dc_vid/vid_vout_scientific.txt"
    ?numberNotation 'scientific
    ?precision 12
    v("/vout")
)

exit()
```

## 12. 1% DC Linearity

The source workflow used secant-gain error relative to the zero-bias
small-signal slope:

```text
A0 = [VOUT(+100 uV) - VOUT(-100 uV)] / 200 uV
Gsec(VID) = [VOUT(VID) - VOUT(0)] / VID
error_percent = 100 * abs[Gsec(VID)/A0 - 1]
```

Pass/fail rule:

```text
error_percent <= 1: pass
error_percent > 1: fail
```

Skip `VID = 0`, because the denominator is zero. This is static DC transfer
linearity, not THD, AC response, or large-signal transient distortion.

Example source checkpoint:

```text
A0 = 31.4345 V/V
A0 = 29.948 dB
Interpolated 1% input range: -1.094528 mV <= VID <= +2.046602 mV
```

The source workflow also found:

```text
Five-device all-region-2 sampled VID range: -18.2 mV to +13.8 mV
```

These two ranges answer different questions. A MOS still being in saturation
does not guarantee the OTA transfer curve is still within 1% linearity.

## 13. Minimum Verification Checklist

Before trusting the sweep:

1. Confirm no unintended Cadence process uses the same result directory.
2. Check the OCEAN log for `OCN-`, `ERROR`, `FATAL`, `SYNTAX`, and
   `Segmentation`.
3. Confirm the expected sweep-point count.
4. At `VID = 0`, confirm symmetric branch current in a symmetric testbench.
5. Confirm `region` boundaries with saturation margin.
6. Use scientific notation for percentage calculations.
7. Save a dated known-good script checkpoint.
8. Keep the main script, final log, and final data.

## 14. Key Takeaways

1. Parameterize `VCM` and `VID` once in the schematic, then sweep from OCEAN.
2. Use `pv()` for single-point `dcOpInfo`; use `getData()` for swept device
   waveforms.
3. `region = 2` range and 1% linear input range are different specifications.
4. Sanitize usernames, private paths, PDK names, VM IP addresses, and unpublished
   project names before publishing.
