# Chapter 9: Schematic DC OP Annotation

This guide explains how to display MOS DC operating-point parameters such as
`region`, `gm`, `vgs`, `vds`, and `vdsat` directly on a Cadence Virtuoso
schematic, then save the annotation setup for reuse.

This is related to, but separate from, generating `oppoint.lis`. The `.lis`
report can contain complete operating-point data even when the schematic does
not show every parameter.

## 1. Placeholder Environment

Use placeholders in public documentation:

```text
Cadence Virtuoso:        <virtuoso-version>
Simulator:               Spectre <spectre-version>
Process/PDK:             <process-pdk>
Library:                 <library-name>
Cell:                    <cell-name>
ADE simulation root:     /home/<linux-user>/simulation/<project-name>
Shared OP file:          /home/<linux-user>/eda/config/opdump.scs
Annotation setup file:   /home/<linux-user>/cadence_projects/<project-name>/dc_op_region.as
```

Do not publish real usernames, private PDK paths, VM IP addresses, customer
names, or unpublished circuit names.

## 2. Why `region` May Disappear

`region` disappearing from the schematic does not always mean Spectre failed to
calculate it. Common causes include:

- Annotation Setup returned to its default display list.
- The MOS symbol has a limited number of visible `cdsParam` labels.
- ADE state was loaded, but schematic annotation setup was not loaded.

If values such as `id`, `vgs`, `vds`, `gm`, or `vdsat` are already visible, DC
operating-point data is probably available. The display slots may simply be
occupied by other parameters.

## 3. Reload DC Operating-Point Results

Use the ADE L window first:

1. Confirm that DC analysis is selected.
2. Run the simulation and confirm convergence.
3. Select **Results -> Annotate -> DC Operating Points**.
4. Return to the schematic window.

This tells Virtuoso where the latest operating-point data is and which
parameters are available.

## 4. Add `region` to NMOS Devices

In the schematic window:

1. Open **View -> Annotations -> Setup**.
2. Click one NMOS instance.
3. Set **Instance Name** to:

   ```text
   *
   ```

4. Confirm **Display Mode** is:

   ```text
   DC Operating Point
   ```

5. Change one visible `cdsParam` field to:

   ```text
   region
   ```

6. Click **Apply**.

Using `*` applies the setting to the same device type instead of only the
clicked instance.

## 5. Configure PMOS Separately

NMOS and PMOS devices are different component types. Repeat the same process for
one PMOS instance:

1. Click one PMOS instance.
2. Set **Instance Name** to `*`.
3. Confirm **Display Mode = DC Operating Point**.
4. Change one visible field to `region`.
5. Click **Apply**.

If only NMOS is configured, PMOS devices may still not show `region`, and vice
versa.

## 6. Choose the Visible Fields

Some MOS symbols can show only a limited number of OP fields directly on the
schematic. If only five fields are convenient, choose based on the task.

For saturation checks:

```text
vgs
vds
vdsat
gm
region
```

For bias-current and small-signal checks:

```text
id
vds
vdsat
gm
region
```

Use `oppoint.lis` for additional values that do not fit on the schematic. Avoid
modifying foundry PDK symbols or Base CDF just to add more visible fields.

## 7. If `region` Is Missing or Greyed Out

Check these in order:

1. Return to ADE L and rerun the DC simulation.
2. Select **Results -> Annotate -> DC Operating Points** again.
3. Open **View -> Annotations -> Setup**.
4. Confirm **Simulation Data Directory** is not blank.
5. Confirm **Display Mode** is `DC Operating Point`, not `Component Parameter`.

From MobaXterm, you can also check whether `region` exists in `oppoint.lis`:

```bash
grep -n "region" \
/home/<linux-user>/simulation/<project-name>/<cell-name>/spectre/schematic/psf/oppoint.lis | head
```

If `oppoint.lis` contains `region`, the issue is probably schematic display
setup. If `oppoint.lis` is missing or incomplete, check the model, PDK CDF, or
operating-point save settings.

## 8. Save Annotation Setup

ADE saved state and schematic annotation setup are not always the same thing.
Save annotation settings separately.

In **View -> Annotations -> Setup**:

1. Click **Save**.
2. Choose **Save at Absolute Path**.
3. Save to:

   ```text
   /home/<linux-user>/cadence_projects/<project-name>/dc_op_region.as
   ```

Next time:

1. Run DC simulation.
2. Select **Results -> Annotate -> DC Operating Points**.
3. Open **View -> Annotations -> Setup**.
4. Choose **Load -> Load from Absolute Path**.
5. Load the `.as` file.

If the GUI Save/Load buttons are unavailable, use SKILL commands in CIW while
the schematic window is active:

```lisp
annSaveAnnotationData(hiGetCurrentWindow() "/home/<linux-user>/cadence_projects/<project-name>/dc_op_region.as")
```

```lisp
annLoadAnnotationData(hiGetCurrentWindow() "/home/<linux-user>/cadence_projects/<project-name>/dc_op_region.as")
```

## 9. Interpret `region`

Many BSIM-based model reports commonly use:

```text
region = 0: off
region = 1: triode / linear
region = 2: saturation
region = 3: subthreshold
region = 4: breakdown
```

Always confirm the exact coding in your PDK/model documentation.

Do not rely only on `region`. Also check saturation margin:

```text
NMOS margin = VDS - VDSAT
PMOS margin = |VDS| - |VDSAT|
```

Positive margin indicates saturation margin. Values close to zero indicate the
device is close to the triode boundary.

## 10. Fast Recovery Checklist

When `region` disappears:

```text
ADE L: Run
ADE L: Results -> Annotate -> DC Operating Points
Schematic: View -> Annotations -> Setup
Annotation Setup: Load -> Load from Absolute Path
Select dc_op_region.as
```

If no `.as` file exists yet:

```text
Click NMOS -> Instance Name = * -> set one field to region -> Apply
Click PMOS -> Instance Name = * -> set one field to region -> Apply
Save at Absolute Path
```
