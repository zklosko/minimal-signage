# Pi Zero 2W Signage Build — Checklist

Stack: Raspberry Pi OS Lite (Bookworm) → Weston (minimal Wayland compositor) →
Cog + WPE WebKit (kiosk browser) → Node/Express (local admin panel).

Cog and wpewebkit are official Debian packages (confirmed present in bookworm
for arm64/armhf), so everything installs via `apt` — no compiling WebKit from
source, no third-party images.

---

## 1. Flash the OS

- [ ] Use Raspberry Pi Imager → **Raspberry Pi OS Lite (64-bit)**, Bookworm.
- [ ] In Imager's advanced settings (gear icon / Ctrl+Shift+X): set hostname,
      enable SSH, set username/password, configure Wi-Fi. This gets you
      headless from first boot — no monitor/keyboard needed for setup.
- [ ] Boot the Pi, `ssh` in, confirm network:
      `ping -c 3 8.8.8.8`

## 2. Base system

- [ ] `sudo apt update && sudo apt full-upgrade -y`
- [ ] Enable the KMS display driver (needed for Cog/Weston to draw to the
      screen) by confirming this line exists in `/boot/firmware/config.txt`:
      `dtoverlay=vc4-kms-v3d`
      (Usually present by default on Bookworm — the setup script checks and
      adds it if missing.)
- [ ] Reboot after any config.txt change.

## 3. Install the kiosk stack

- [ ] `sudo apt install -y weston cog wpewebkit-driver jq`
- [ ] Add your user to the groups needed for GPU/display access:
      `sudo usermod -aG video,render,input pi`
- [ ] Log out and back in (or reboot) for group membership to take effect.

## 4. Test Weston + Cog manually before automating

- [ ] From a console (not over SSH, or SSH with the right env — see script),
      start Weston: `weston --backend=drm-backend.so &`
- [ ] In another session with `WAYLAND_DISPLAY=wayland-1` set, run:
      `cog https://example.com`
- [ ] Confirm the page renders on the connected display. If it doesn't,
      check `journalctl` for weston/cog errors before moving on — debugging
      this manually is much easier than debugging it inside systemd.

## 5. Wire it into systemd

- [ ] Create a Weston service that starts on boot under your user.
- [ ] Create a Cog service that starts after Weston and loads a URL from a
      config file (not hardcoded), so the admin panel can change it.
- [ ] Confirm both come up cleanly after a full `sudo reboot`.

## 6. Admin panel (Express)

- [ ] Install Node via NodeSource (see prior steps in this conversation).
- [ ] Deploy the single-file Express app (`fs` + `child_process`, one
      dependency) to read/write the config file and restart the Cog service.
- [ ] Add a narrow sudoers rule so Express can restart *only* the Cog
      service, not run arbitrary commands as root.
- [ ] Add basic auth in front of it.
- [ ] Create a systemd service for the Express app too.

## 7. Lock it down and verify

- [ ] `free -h` — confirm total resident memory is comfortably under 512MB
      with everything running.
- [ ] Bind the admin panel to `127.0.0.1` unless you specifically need LAN
      access; if you do, firewall it (`ufw allow from <your-subnet>`).
- [ ] Disable services you don't need to reclaim a little more RAM/CPU:
      `sudo systemctl disable bluetooth avahi-daemon` (skip avahi if you rely
      on `.local` hostnames).
- [ ] Do a full power-cycle test (not just reboot) to make sure everything
      comes back up unattended — this is the real test for signage, since
      it'll likely lose power at some point in the field.

## 8. Optional hardening (do later, not required to get running)

- [ ] Mount the root filesystem read-only or use overlayfs, so power loss
      mid-write doesn't corrupt the SD card — common failure mode for
      always-on Pi signage.
- [ ] Add a hardware or software watchdog to reboot if Cog/Weston hang.
- [ ] Set up automatic screenshots or a health-check endpoint in Express so
      you can tell remotely if the display is actually showing the page.

---

Run `setup.sh` (as root, on a freshly booted Pi) to automate steps 2–5.
Steps 6 onward still need your Express app code and a couple of manual
choices (LAN exposure, auth password), so they're not in the script.
