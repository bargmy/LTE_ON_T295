# LTE_ON_T295
Get simcard working on your Galaxy Tab A 8.0 2019 LineageOS 22.2! 

# Works
- Calls
- Internet
- SMS
- Call audio
- SIMCARD settings

## Install

Download the module ZIP from GitHub Releases, install it in Magisk, and reboot.
Call audio uses VoiceMMode1 PCM 34 and its RX/TX mixer controls, with multi-session
voice disabled. Live call audio was confirmed; persistence after reboot still
needs confirmation.

## Build and release

Run `python scripts/build_module.py` to create a ZIP in `dist/`. The builder uses
forward-slash archive paths on Windows and Linux, LF text files, and executable
permissions for Android scripts and binaries.

In GitHub Actions, run **Build and release Magisk module** to publish a release.
The optional tag defaults to the version in `module.prop`. Pushing a `v*` tag
also builds and publishes a release automatically.
