#!/usr/bin/env bash
# SUPER+Power: reboot that skips the GRUB menu (boots straight into CachyOS).
# Needs the sudoers rule /etc/sudoers.d/90-fast-reboot (grub-editenv).
sudo -n /usr/bin/grub-editenv /boot/grub/grubenv set fastboot=1 \
  || notify-send -u critical "Fast reboot" "Missing the 90-fast-reboot sudoers rule; normal reboot"
systemctl reboot
