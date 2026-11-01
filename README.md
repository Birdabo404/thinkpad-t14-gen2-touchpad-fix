# ThinkPad T14 Gen 2 touchpad fix

Debian and Ubuntu, Intel only. Fork of [debzar/thinkpad-t14-gen2-touchpad-fix](https://github.com/debzar/thinkpad-t14-gen2-touchpad-fix).

The useful change in the original is `psmouse.synaptics_intertouch=1`. On this machine (i5-1145G7, Synaptics TM3471-030, PNP LEN2072, board id 3471) that moves the pad off PS/2 and onto RMI4. Firmware upgrades and downgrades do not select the bus.

The script that was on `main` had deleted its menu and always ran `mkinitcpio`. That command does not exist on Debian or Ubuntu, so the run ended with `command not found`.

## Install

```bash
git clone https://github.com/Birdabo404/thinkpad-t14-gen2-touchpad-fix
cd thinkpad-t14-gen2-touchpad-fix
chmod +x t14_touchpad_manager.sh
sudo ./t14_touchpad_manager.sh
```

The `./` is required. Without it the shell says `command not found` and the menu never starts.

1. Choose **1** (Install InterTouch).
2. Reboot.
3. Run the script again and choose **3**.

You want a device named `Synaptics TM3471-030`. It is still on the old bus if the name is `SynPS/2 Synaptics TouchPad`. Leave the TrackPoint enabled in BIOS. The buttons above the pad need it.

## Lid closed for hours

That is suspend, which the original repo did try to handle. Its unit ran as the machine went to sleep, and it reloaded the driver at the wrong time.

This install does not add a resume hook. Try the bus change first. If the pad is smooth and turns junk again only after the lid has been shut for a long time, set `ENABLE_RESUME=0` to `ENABLE_RESUME=1` near the top of `t14_touchpad_manager.sh` and install again. The hook runs after wake.

## What was removed

- `mkinitcpio` (Arch only)
- `elantech_smbus` (this pad is Synaptics, not Elan)
- `i2c_designware.disable_ps` (not how this pad changes buses)
- libinput `AttrTapping` and pressure `1:0` (not valid fixes for this lag; `AttrTapping` is not a libinput quirk)
- forcing the TrackPoint multiplier to zero
- turning runtime power management off for every PCI device
