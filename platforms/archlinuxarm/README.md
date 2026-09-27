# Arch Linux ARM in kmos

Arch Linux ARM is a separate port of Arch Linux with AArch64 and ARMv7
repositories; it does not use the official x86_64 Arch binary repositories.
Board boot media must be prepared with the matching board recipe. Once the
board boots, run its post-boot provisioner to apply kmos packages and defaults.
Do not run the x86_64 `platforms/archlinux/kmos-archlinux-install.sh` on ARM.

Currently implemented: [Quartz64 Model B](boards/quartz64b/README.md), using
Arch Linux ARM AArch64. Its SD-card preparation and post-boot provisioning
remain separate scripts while the common ARM workflow is developed. Raspberry
Pi and ODROID board preparation, a shared ARM provisioner, and an optional KDE
stage are not implemented yet.

Never run a media-preparation script against a disk holding data you need.
Back up the SD card, verify the exact target device, and read the board's
instructions before confirming any erase.
