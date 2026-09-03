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
  - [Chapter 3: DC sweep automation and data extraction](docs/en/03-dc-sweep-automation-and-data-extraction.md)
  - [Chapter 4: Open-loop AC and STB feedback stability](docs/en/04-open-loop-ac-and-stb-stability.md)
  - [Chapter 5: Closed-loop transient automation](docs/en/05-closed-loop-transient-automation.md)
  - [Chapter 6: Open-loop noise automation](docs/en/06-open-loop-noise-automation.md)
  - [Chapter 7: CMRR automation](docs/en/07-cmrr-automation.md)
  - [Chapter 8: PSRR automation](docs/en/08-psrr-automation.md)
  - [Chapter 9: Schematic DC OP annotation](docs/en/09-schematic-op-annotation.md)
  - [Chapter 10: Five-transistor OTA characterization](docs/en/10-five-transistor-ota-characterization.md)
  - [Chapter 11: Baseline summary and PVT automation](docs/en/11-baseline-summary-and-pvt-automation.md)
  - [Chapter 12: Deterministic PVT automation](docs/en/12-deterministic-pvt-automation.md)
- Traditional Chinese:
  - [Chapter 1: DC operating-point simulation and automation](docs/zh-TW/01-dc-operating-point-simulation.md)
  - [Chapter 2: Export and read `oppoint.lis`](docs/zh-TW/02-export-and-read-oppoint-lis.md)
  - [Chapter 3: DC sweep automation and data extraction](docs/zh-TW/03-dc-sweep-automation-and-data-extraction.md)
  - [Chapter 4: Open-loop AC and STB feedback stability](docs/zh-TW/04-open-loop-ac-and-stb-stability.md)
  - [Chapter 5: Closed-loop transient automation](docs/zh-TW/05-closed-loop-transient-automation.md)
  - [Chapter 6: Open-loop noise automation](docs/zh-TW/06-open-loop-noise-automation.md)
  - [Chapter 7: CMRR automation](docs/zh-TW/07-cmrr-automation.md)
  - [Chapter 8: PSRR automation](docs/zh-TW/08-psrr-automation.md)
  - [Chapter 9: Schematic DC OP annotation](docs/zh-TW/09-schematic-op-annotation.md)
  - [Chapter 10: Five-transistor OTA characterization](docs/zh-TW/10-five-transistor-ota-characterization.md)
  - [Chapter 11: Baseline summary and PVT automation](docs/zh-TW/11-baseline-summary-and-pvt-automation.md)
  - [Chapter 12: Deterministic PVT automation](docs/zh-TW/12-deterministic-pvt-automation.md)
- Simplified Chinese:
  - [Chapter 1: DC operating-point simulation and automation](docs/zh-CN/01-dc-operating-point-simulation.md)
  - [Chapter 2: Export and read `oppoint.lis`](docs/zh-CN/02-export-and-read-oppoint-lis.md)
  - [Chapter 3: DC sweep automation and data extraction](docs/zh-CN/03-dc-sweep-automation-and-data-extraction.md)
  - [Chapter 4: Open-loop AC and STB feedback stability](docs/zh-CN/04-open-loop-ac-and-stb-stability.md)
  - [Chapter 5: Closed-loop transient automation](docs/zh-CN/05-closed-loop-transient-automation.md)
  - [Chapter 6: Open-loop noise automation](docs/zh-CN/06-open-loop-noise-automation.md)
  - [Chapter 7: CMRR automation](docs/zh-CN/07-cmrr-automation.md)
  - [Chapter 8: PSRR automation](docs/zh-CN/08-psrr-automation.md)
  - [Chapter 9: Schematic DC OP annotation](docs/zh-CN/09-schematic-op-annotation.md)
  - [Chapter 10: Five-transistor OTA characterization](docs/zh-CN/10-five-transistor-ota-characterization.md)
  - [Chapter 11: Baseline summary and PVT automation](docs/zh-CN/11-baseline-summary-and-pvt-automation.md)
  - [Chapter 12: Deterministic PVT automation](docs/zh-CN/12-deterministic-pvt-automation.md)
- Template:
  - [`templates/opdump.scs`](templates/opdump.scs)
- Script templates:
  - [`scripts/pvt/run_process_corners.sh`](scripts/pvt/run_process_corners.sh)
  - [`scripts/pvt/refine_vid_linearity.sh`](scripts/pvt/refine_vid_linearity.sh)
  - [`scripts/pvt/analyze_process_corner_transients.sh`](scripts/pvt/analyze_process_corner_transients.sh)
  - [`scripts/pvt/build_process_corner_report.sh`](scripts/pvt/build_process_corner_report.sh)
- AI customization:
  - [AI customization prompt](prompts/customize-this-guide.md)

## What This Guide Covers

- Connecting to a Linux VM with MobaXterm
- Creating a shared `opdump.scs`
- Adding that file to Virtuoso ADE simulation files
- Running Spectre DC operating-point analysis
- Distinguishing pure DC operating point from DC sweep characterization
- Finding and reading `oppoint.lis`
- Automating VCM and VID DC sweeps with OCEAN
- Extracting swept device operating-point waveforms
- Calculating 1% DC linearity from a differential-input sweep
- Running open-loop AC gain and bandwidth characterization
- Running closed-loop STB feedback stability analysis
- Reading formal phase margin and gain margin results from `stb_margin`
- Automating closed-loop transient step response simulations
- Measuring rise/fall time, slew rate, settling time, overshoot, and undershoot
- Automating open-loop noise simulations
- Calculating input-referred noise, white-noise floor, 1/f corner, and integrated RMS noise
- Interpreting device noise contribution ranking and optimization priority
- Automating CMRR simulations and extracting common-mode rejection bandwidth
- Automating PSRR+ and PSRR- simulations and comparing supply rejection
- Building a frozen baseline summary for DC, AC, STB, transient, noise, CMRR, and PSRR
- Running deterministic process-corner automation with reusable shell templates
- Separating deterministic PVT automation into `prepare`, `core`, and `full` modes
- Validating generated OCEAN scripts, adopted results, transient extraction, and report checksums
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
