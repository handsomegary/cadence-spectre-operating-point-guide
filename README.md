# Spectre OP LIS Guide for Virtuoso and MobaXterm

Privacy-safe, reusable guides for generating and reading Spectre operating-point
reports from Cadence Virtuoso ADE with MobaXterm.

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

## Available Guides

- [English guide](docs/guide.en.md)
- [Traditional Chinese guide](docs/guide.zh-TW.md)
- [Simplified Chinese guide](docs/guide.zh-CN.md)
- [AI customization prompt](prompts/customize-this-guide.md)

## What This Guide Covers

- Connecting to a Linux VM with MobaXterm
- Creating a shared `opdump.scs`
- Adding that file to Virtuoso ADE simulation files
- Running Spectre DC operating-point analysis
- Finding and reading `oppoint.lis`
- Checking MOS operating regions and saturation margin
- Saving simulation results safely
- Troubleshooting common Spectre/ADE issues

## Privacy Notes

Do not publish real usernames, server IPs, private PDK paths, lab directory
names, customer names, or unpublished circuit names. Replace them with generic
placeholders before uploading documentation to a public repository.

