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

## Guides

- Full workflow:
  - [English](docs/guide.en.md)
  - [Traditional Chinese](docs/guide.zh-TW.md)
  - [Simplified Chinese](docs/guide.zh-CN.md)
- Schematic annotation workflow:
  - [English](docs/annotate-region.en.md)
  - [Traditional Chinese](docs/annotate-region.zh-TW.md)
  - [Simplified Chinese](docs/annotate-region.zh-CN.md)
- Chapter 3, OTA characterization workflow:
  - [English](docs/03-five-transistor-ota-characterization.en.md)
  - [Traditional Chinese](docs/03-five-transistor-ota-characterization.zh-TW.md)
  - [Simplified Chinese](docs/03-five-transistor-ota-characterization.zh-CN.md)
- Template:
  - [`templates/opdump.scs`](templates/opdump.scs)
- AI customization:
  - [AI customization prompt](prompts/customize-this-guide.md)

## What This Guide Covers

- Connecting to a Linux VM with MobaXterm
- Creating a shared `opdump.scs`
- Adding that file to Virtuoso ADE simulation files
- Running Spectre DC operating-point analysis
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
