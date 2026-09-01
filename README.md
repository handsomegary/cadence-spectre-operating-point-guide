# Cadence Spectre Operating Point Guide

Privacy-safe, reusable tutorials for Cadence Virtuoso ADE and Spectre DC
operating-point workflows.

This repository is a sanitized tutorial. It intentionally replaces personal
Linux usernames, VM IP addresses, project names, cell names, and local directory
paths with placeholders such as:

- `<linux-user>`
- `<vm-ip-address>`
- `<project-name>`
- `<library-name>`
- `<cell-name>`
- `<pdk-root>`
- `<simulation-root>`

## Chapters

- English:
  - [Chapter 1: DC operating-point simulation and automation](docs/en/01-dc-operating-point-simulation.md)
  - [Chapter 2: Export and read `oppoint.lis`](docs/en/02-export-and-read-oppoint-lis.md)
  - [Chapter 3: Schematic DC OP annotation](docs/en/03-schematic-op-annotation.md)
  - [Chapter 4: Five-transistor OTA characterization](docs/en/04-five-transistor-ota-characterization.md)
- Traditional Chinese:
  - [Chapter 1: DC operating-point simulation and automation](docs/zh-TW/01-dc-operating-point-simulation.md)
  - [Chapter 2: Export and read `oppoint.lis`](docs/zh-TW/02-export-and-read-oppoint-lis.md)
  - [Chapter 3: Schematic DC OP annotation](docs/zh-TW/03-schematic-op-annotation.md)
  - [Chapter 4: Five-transistor OTA characterization](docs/zh-TW/04-five-transistor-ota-characterization.md)
- Simplified Chinese:
  - [Chapter 1: DC operating-point simulation and automation](docs/zh-CN/01-dc-operating-point-simulation.md)
  - [Chapter 2: Export and read `oppoint.lis`](docs/zh-CN/02-export-and-read-oppoint-lis.md)
  - [Chapter 3: Schematic DC OP annotation](docs/zh-CN/03-schematic-op-annotation.md)
  - [Chapter 4: Five-transistor OTA characterization](docs/zh-CN/04-five-transistor-ota-characterization.md)
- Template:
  - [`templates/opdump.scs`](templates/opdump.scs)
- AI customization:
  - [AI customization prompt](prompts/customize-this-guide.md)

## What This Guide Covers

- Connecting to a Linux VM with MobaXterm
- Creating a shared `opdump.scs`
- Adding that file to Virtuoso ADE simulation files
- Running Spectre DC operating-point analysis
- Distinguishing pure DC operating point from DC sweep characterization
- Finding and reading `oppoint.lis`
- Annotating MOS `region`, `gm`, `vgs`, `vds`, and `vdsat` on schematics
- Saving and reloading Virtuoso annotation setup
- Characterizing a five-transistor OTA with ICMR, output swing, DC gain,
  linear input range, AC response, STB stability, transient settling, slew rate,
  and safe shutdown steps
- Checking MOS operating regions and saturation margin
- Saving simulation results safely
- Troubleshooting common Spectre/ADE issues

## Privacy Notes

Do not publish real usernames, server IPs, private PDK paths, lab directory
names, customer names, or unpublished circuit names. Replace them with generic
placeholders before uploading documentation to a public repository.

Do not commit foundry PDKs, model files, generated `psf` folders, netlists,
simulation outputs, lock files, or screenshots that reveal private paths.
