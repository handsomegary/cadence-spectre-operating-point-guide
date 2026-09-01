# Chapter 2: Export and Read `oppoint.lis`

This SOP explains how to run a Spectre DC operating-point simulation in Cadence
Virtuoso ADE and export MOS operating-point data into an `oppoint.lis` file that
can be read from MobaXterm.

For the basic no-sweep DC operating-point setup in ADE L, start with
[Chapter 1: DC Operating-Point Simulation and Automation](01-dc-operating-point-simulation.md).

`oppoint.lis` in this guide is a Spectre-generated ASCII operating-point report.
It is not a native HSPICE `.lis` file.

## 1. Placeholder Paths

Use placeholders for private environment details:

```text
Linux user:              <linux-user>
VM IP address:           <vm-ip-address>
PDK root:                /home/<linux-user>/eda/pdk/<process-pdk>
Shared OP file:          /home/<linux-user>/eda/config/opdump.scs
Cadence project folder:  /home/<linux-user>/cadence_projects/<project-name>
ADE simulation root:     /home/<linux-user>/simulation/<project-name>
Library / cell:          <library-name> / <cell-name>
Netlist:                 /home/<linux-user>/simulation/<project-name>/<cell-name>/spectre/schematic/netlist/input.scs
OP report:               /home/<linux-user>/simulation/<project-name>/<cell-name>/spectre/schematic/psf/oppoint.lis
```

Keep design data and simulation output separate:

- `cadence_projects` stores schematics, libraries, and design data.
- `simulation` stores ADE/Spectre generated results.

## 2. Connect to the VM With MobaXterm

Open a MobaXterm terminal and connect to the Linux VM:

```bash
ssh <linux-user>@<vm-ip-address>
```

If the VM IP address is unknown, check it inside the VM:

```bash
hostname -I
```

## 3. Create a Shared `opdump.scs`

Create this file once and reuse it across projects:

```bash
nano /home/<linux-user>/eda/config/opdump.scs
```

File content:

```spectre
simulator lang=spectre
opDump info what=oppoint where=file file="../psf/oppoint.lis"
```

In `nano`, save with:

1. `Ctrl+O`
2. Press `Enter`
3. `Ctrl+X`

Verify the file:

```bash
sed -n '1,10p' /home/<linux-user>/eda/config/opdump.scs
```

The relative output path `../psf/oppoint.lis` is resolved from the generated
cell netlist directory, so each cell normally writes its own report under its own
`psf` folder.

## 4. Create a New Cadence Project Folder

Example:

```bash
mkdir -p /home/<linux-user>/cadence_projects/<project-name>
cd /home/<linux-user>/cadence_projects/<project-name>
nano cds.lib
```

Example `cds.lib` content:

```text
INCLUDE /home/<linux-user>/eda/pdk/<process-pdk>/cds.lib
```

Start Virtuoso from the project folder:

```bash
cd /home/<linux-user>/cadence_projects/<project-name>
virtuoso &
```

Use a separate design folder and simulation folder for each project:

```text
/home/<linux-user>/cadence_projects/<project-name>
/home/<linux-user>/simulation/<project-name>
```

This prevents different projects or cells from mixing simulation results.

## 5. Add `opdump.scs` in ADE

1. Open the schematic.
2. Select **Launch -> ADE L**.
3. Confirm the simulator is **spectre**.
4. Open **Setup -> Simulator/Directory/Host**.
5. Set **Project Directory** to:

   ```text
   /home/<linux-user>/simulation/<project-name>
   ```

6. Open **Setup -> Simulation Files**.
7. Add this file to **Definition Files**:

   ```text
   /home/<linux-user>/eda/config/opdump.scs
   ```

8. Set the analysis to **dc**. A DC operating point does not require a sweep.
9. Run the simulation.

Do not manually edit the ADE-generated `input.scs` as the long-term fix. Make
changes in ADE or in the schematic, then regenerate the netlist.

## 6. Verify `input.scs`

Find recent Spectre netlists:

```bash
find /home/<linux-user> -type f -name "input.scs" -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -10
```

Check the current netlist:

```bash
grep -n "opdump.scs" /home/<linux-user>/simulation/<project-name>/<cell-name>/spectre/schematic/netlist/input.scs
```

Expected result:

```spectre
include "/home/<linux-user>/eda/config/opdump.scs"
```

If this line is missing, the Definition Files entry was not added correctly, or
the design has not been netlisted and run again.

## 7. Run Spectre and Confirm `oppoint.lis`

After running ADE, inspect the Spectre log:

```bash
tail -n 50 /home/<linux-user>/simulation/<project-name>/<cell-name>/spectre/schematic/psf/spectre.out
```

Successful output usually includes:

```text
opDump: writing operating point information to file `../psf/oppoint.lis'.
DC Analysis `dcOp'
Convergence achieved
```

Find all operating-point reports:

```bash
find /home/<linux-user>/simulation -type f -name "oppoint.lis" -print
```

The report should be under:

```text
/home/<linux-user>/simulation/<project-name>/<cell-name>/spectre/schematic/psf/oppoint.lis
```

## 8. Read `oppoint.lis` in MobaXterm

Open the report:

```bash
less /home/<linux-user>/simulation/<project-name>/<cell-name>/spectre/schematic/psf/oppoint.lis
```

Useful `less` shortcuts:

- `/NM2` searches for `NM2`
- `/region` searches for `region`
- `n` jumps to the next match
- `Shift+N` jumps to the previous match
- `q` quits

Filter common MOS names and parameters:

```bash
grep -nE 'NM0|NM1|NM2|PM0|PM1|region|gm|gds|id|vgs|vds|vdsat' \
/home/<linux-user>/simulation/<project-name>/<cell-name>/spectre/schematic/psf/oppoint.lis | less
```

Do not run the report as a program:

```bash
/home/<linux-user>/simulation/<project-name>/<cell-name>/spectre/schematic/psf/oppoint.lis
```

That causes `Permission denied` because the shell tries to execute a text file.
Use `less`, `more`, `nano`, `grep`, or `vi` instead.

## 9. Check MOS Saturation

For many BSIM-based model reports, `region` values are commonly interpreted as:

```text
region = 0: off
region = 1: triode / linear
region = 2: saturation
region = 3: subthreshold
region = 4: breakdown
```

Always confirm the exact meaning with your PDK/model documentation.

Do not rely on `region` alone. Also check saturation margin:

```text
NMOS margin = VDS - VDSAT
PMOS margin = |VDS| - |VDSAT|
```

A positive margin means the device has saturation margin. A value close to zero
means the device is close to the triode boundary.

Recommended parameters:

- `region`: model-reported operating region
- `gm`: transconductance
- `gds`: output conductance
- `id`: drain current
- `vgs`: gate-source voltage
- `vds`: drain-source voltage
- `vdsat`: model-computed saturation voltage
- `gm/id`: useful for inversion and efficiency checks

`VGS` alone cannot prove that a MOS device is saturated. Saturation also depends
on whether `VDS` is large enough.

## 10. View DC Operating Point in Virtuoso

After a successful simulation, use:

```text
Results -> Print -> DC Operating Point
```

Or annotate values back onto the schematic:

```text
Results -> Annotate -> DC Operating Points
```

For annotation settings, try:

```text
View -> Annotations -> Setup
```

The GUI is convenient for quick inspection. `oppoint.lis` is better for saving,
searching, comparing, and version tracking.

For a dedicated schematic annotation workflow, see
[Chapter 3: Schematic DC OP Annotation](03-schematic-op-annotation.md).

## 11. Save One Simulation Result

Enter the cell `psf` directory:

```bash
cd /home/<linux-user>/simulation/<project-name>/<cell-name>/spectre/schematic/psf
```

Copy the report with a condition-specific name:

```bash
cp oppoint.lis oppoint_tt_27C_VDD1p2.lis
```

Example naming patterns:

```text
oppoint_tt_27C_VDD1p2.lis
oppoint_ss_125C_VDD1p08.lis
oppoint_ff_m40C_VDD1p32.lis
```

## 12. Save and Reload ADE State

In ADE L:

```text
Session -> Save State -> Cellview
```

Example state name:

```text
spectre_op_export
```

Next time:

```text
Session -> Load State
```

If a reopened window shows `(1)`, `(2)`, or `(3)`, it is usually just a repeated
window number in the same session, not a new design version.

## 13. Troubleshooting

### `oppoint.lis` Not Found

Check these:

```bash
grep -n "opdump.scs" /home/<linux-user>/simulation/<project-name>/<cell-name>/spectre/schematic/netlist/input.scs
tail -n 80 /home/<linux-user>/simulation/<project-name>/<cell-name>/spectre/schematic/psf/spectre.out
find /home/<linux-user>/simulation -type f -name "oppoint.lis" -print
```

If `input.scs` includes `opdump.scs` and the log says `opDump` is writing the
file, `oppoint.lis` should be in that cell's `psf` folder.

### Undefined Model Errors

Errors such as `undefined model <model-name>` usually mean Spectre did not load
the correct model library or model section.

Check that `input.scs` points to the expected PDK model file and that the
correct process corner section, such as `tt`, `ss`, or `ff`, is selected.

### `CDS.log is already locked`

This usually means another Virtuoso process is running, or a previous session
left a lock behind.

Check running processes:

```bash
pgrep -af -u <linux-user> 'virtuoso|icfb|cdsMsgServer|libManager|libSelect'
```

Check log files:

```bash
ls -la /home/<linux-user>/CDS.log*
```

The safest action is to exit from the original Virtuoso CIW with:

```text
File -> Exit
```

If you confirm a process is an old unwanted session:

```bash
kill -TERM <pid>
ps -o pid,ppid,stat,etime,cmd -p <pid>
```

Use `kill -KILL <pid>` only after confirming that the process must be terminated
and `TERM` does not work.

Closing the MobaXterm window does not always close a background Virtuoso
process. Exit from Virtuoso first when possible.

### Simulation Runs but Operating Points Look Wrong

Check both biasing and connectivity:

- Diode-connected current mirror devices should have gate and drain connected.
- Bulk terminals should be connected correctly.
- Supply voltage, input common-mode voltage, tail current bias, and output nodes
  should match the intended circuit.

Fix the schematic, then **Check and Save**, netlist again, and rerun simulation.

## 14. Short Checklist for a New Circuit

1. Create separate design and simulation folders for each project.
2. Start `virtuoso &` from the project design folder.
3. Select the correct Spectre simulator, model library, and process corner.
4. Set the ADE Project Directory to the project simulation folder.
5. Add shared `opdump.scs` to Definition Files.
6. Run DC operating-point analysis.
7. Confirm convergence and `opDump` writing in `spectre.out`.
8. Find `oppoint.lis`.
9. Open it with `less`.
10. Review `region`, `gm`, `gds`, `id`, `vgs`, `vds`, and `vdsat`.
11. Copy important results to condition-specific filenames.
12. Save the ADE state.

## Success Criteria

The flow is working when:

1. `input.scs` includes the shared `opdump.scs`.
2. `spectre.out` shows DC convergence.
3. `spectre.out` shows `opDump` writing `../psf/oppoint.lis`.
4. The cell `psf` folder contains `oppoint.lis`.
5. `less` can display MOS operating-point data such as `gm`, `gds`, `vgs`,
   `vds`, `vdsat`, and `region`.
