# Chapter 1: DC Operating-Point Simulation and Automation

This chapter explains the basic DC operating-point, or DCOP, workflow in
Cadence Virtuoso ADE L with Spectre. It focuses on the no-sweep operating point
case first, then shows how to automate a text report with a shared `opdump.scs`.

## 1. What DCOP Means

A DC operating-point simulation solves the circuit at one bias condition. It
answers questions such as:

- Which MOS devices are on, off, triode, saturation, or subthreshold?
- What are `id`, `gm`, `gds`, `vgs`, `vds`, and `vdsat` at the chosen bias?
- Is the nominal bias point reasonable before AC, STB, or transient analysis?

Do not confuse these two operations:

```text
Pure DC operating point: one bias point, no sweep variable.
DC sweep: many bias points while sweeping VCM, VID, VOUT_TEST, VDD, etc.
```

Use pure DCOP first. Use DC sweep later for ICMR, output swing, and input
linearity.

## 2. Prepare the Testbench

Use placeholders in public notes:

```text
Project:            <project-name>
Library:            <library-name>
Cell:               <cell-name>
Supply:             VDD = <supply-voltage>
Common-mode input:  VCM = <nominal-common-mode-voltage>
Simulation root:    /home/<linux-user>/simulation/<project-name>
Shared OP file:     /home/<linux-user>/eda/config/opdump.scs
```

For a differential amplifier or OTA nominal DCOP:

```text
Vin+ DC = VCM
Vin- DC = VCM
```

For a single-ended or biased block, set every independent source to the nominal
DC value you want to verify.

## 3. Run a Pure DC Operating Point in ADE L

In ADE L:

1. Open **Analyses -> Choose**.
2. Keep **`dc`** selected.
3. Check **`Save DC Operating Point`**.
4. In the lower **Sweep Variable** area, leave every sweep option unchecked.
5. Click **OK**.
6. Return to ADE L and click **Run**.

This is the important no-sweep setup:

```text
dc selected
Save DC Operating Point checked
Sweep Variable unchecked
```

If a sweep variable is checked, ADE will run a DC sweep instead of only the
nominal operating point.

## 4. Save Useful OP Parameters

To make key device values easier to plot or inspect:

```text
Outputs -> To Be Saved -> Select OP Parameters
```

Recommended MOS parameters:

```text
id
gm
gds
vgs
vds
vdsat
region
```

For saturation checks:

```text
NMOS margin = VDS - VDSAT
PMOS margin = |VDS| - |VDSAT|
```

Positive margin means the device has saturation headroom. Margin close to zero
means the device is near the triode boundary.

## 5. Automate Text Output With `opdump.scs`

Create a shared Spectre definition file:

```bash
nano /home/<linux-user>/eda/config/opdump.scs
```

Use the template:

```spectre
simulator lang=spectre
opDump info what=oppoint where=file file="../psf/oppoint.lis"
```

The repository also includes:

```text
templates/opdump.scs
```

Add the shared file in ADE L:

1. Open **Setup -> Simulation Files**.
2. In **Definition Files**, add:

   ```text
   /home/<linux-user>/eda/config/opdump.scs
   ```

3. Click **OK**.
4. Run the DC operating point again.

Do not manually edit the ADE-generated `input.scs` as the permanent fix. Add
the shared file through ADE so it survives netlist regeneration.

## 6. Verify the Automation

Check that the generated netlist includes the shared file:

```bash
grep -n "opdump.scs" \
/home/<linux-user>/simulation/<project-name>/<cell-name>/spectre/schematic/netlist/input.scs
```

Expected:

```spectre
include "/home/<linux-user>/eda/config/opdump.scs"
```

Check the Spectre log:

```bash
tail -n 80 \
/home/<linux-user>/simulation/<project-name>/<cell-name>/spectre/schematic/psf/spectre.out
```

Successful output usually includes:

```text
DC Analysis `dcOp'
Convergence achieved
opDump: writing operating point information to file `../psf/oppoint.lis'.
```

Find the report:

```bash
find /home/<linux-user>/simulation -type f -name "oppoint.lis" -print
```

## 7. Read Results

In Virtuoso:

```text
Results -> Print -> DC Operating Point
Results -> Annotate -> DC Operating Points
```

In MobaXterm:

```bash
less /home/<linux-user>/simulation/<project-name>/<cell-name>/spectre/schematic/psf/oppoint.lis
```

Quick filter:

```bash
grep -nE 'region|gm|gds|id|vgs|vds|vdsat' \
/home/<linux-user>/simulation/<project-name>/<cell-name>/spectre/schematic/psf/oppoint.lis | less
```

## 8. When to Use DC Sweep Instead

Switch from pure DCOP to DC sweep only when you intentionally want a curve:

```text
ICMR:              sweep VCM
Output swing:      sweep VOUT_TEST
Input linearity:   sweep VID
Supply sensitivity: sweep VDD
Bias sensitivity:  sweep a bias voltage or current
```

For those cases, enable the correct sweep variable and choose a start, stop, and
step. For nominal DCOP, keep Sweep Variable unchecked.

## 9. Common Mistakes

- Accidentally checking a Sweep Variable when only nominal DCOP is needed.
- Forgetting to rerun simulation after adding `opdump.scs`.
- Editing `input.scs` directly and losing the change at the next netlist.
- Trying to execute `oppoint.lis` as a program instead of opening it with
  `less`, `more`, `grep`, `nano`, or `vi`.
- Publishing real Linux home paths, private PDK names, IP addresses, library
  names, or unpublished cell names.

## 10. DCOP Checklist

The DCOP setup is correct when:

1. ADE L has `dc` selected.
2. `Save DC Operating Point` is checked.
3. No Sweep Variable option is checked for nominal DCOP.
4. The testbench sources use the intended DC bias values.
5. `input.scs` includes the shared `opdump.scs`, if text output is used.
6. `spectre.out` reports convergence.
7. `oppoint.lis` exists, if `opDump` automation is enabled.
8. The MOS OP data includes `id`, `gm`, `gds`, `vgs`, `vds`, `vdsat`, and
   `region`, when available from the model.
