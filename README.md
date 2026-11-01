# ThinkPad T14 Gen 2 touchpad

Debian and Ubuntu. Intel T14 Gen 2, i5-1145G7, Synaptics TM3471-030.

Linux boots this pad as PS/2. The script adds `psmouse.synaptics_intertouch=1` so it comes up on RMI4. Flashing the touchpad firmware does not choose the bus.

Fork of [debzar/thinkpad-t14-gen2-touchpad-fix](https://github.com/debzar/thinkpad-t14-gen2-touchpad-fix). That copy calls `mkinitcpio`, which Debian does not have, and it has no menu.

```bash
git clone https://github.com/Birdabo404/thinkpad-t14-gen2-touchpad-fix
cd thinkpad-t14-gen2-touchpad-fix
chmod +x t14_touchpad_manager.sh
sudo ./t14_touchpad_manager.sh
```

The `./` matters. Without it the shell says command not found and the menu never starts.

Choose 1, reboot, then choose 3.

Working: `Synaptics TM3471-030`.
Still on PS/2: `SynPS/2 Synaptics TouchPad`.

Leave the TrackPoint enabled in BIOS. The buttons above the pad need it.

If the pad is fine and only turns bad after the lid has been shut for hours, that is suspend. Set `ENABLE_RESUME=1` near the top of the script and run it again.
