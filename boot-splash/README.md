# Boot splash (Serpantinum theme)

Optional. These touch system files, so `install.sh` never installs them for you.

- `plymouth/serpantinum/` -> `/usr/share/plymouth/themes/serpantinum/`
  then: `sudo plymouth-set-default-theme -R serpantinum`
- `grub/default-grub` -> `/etc/default/grub` (quiet splash, CachyOS menu visible for 3s)
- `grub/10_linux` -> `/etc/grub.d/10_linux` (without the "Loading Linux/initial ramdisk" lines).
  A grub update may overwrite it: re-apply and run `sudo grub-mkconfig -o /boot/grub/grub.cfg`.
- `grub/01_fastboot` -> `/etc/grub.d/01_fastboot` (SUPER+Power skips the menu once).
  Needs a sudoers rule: `YOUR_USER ALL=(root) NOPASSWD: /usr/bin/grub-editenv /boot/grub/grubenv set fastboot=1`
- `90-power-hold.conf` -> `/etc/systemd/logind.conf.d/` (the physical power button no longer powers off by itself; the wave animation handles it)
- `sync-theme.sh` repaints Plymouth + the SDDM theme with the active Serpantinum colors.
