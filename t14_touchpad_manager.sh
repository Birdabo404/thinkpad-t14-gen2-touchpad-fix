#!/usr/bin/env bash
# ThinkPad T14 Gen 2 (Intel) touchpad manager — Debian and Ubuntu only.
#
# The pad on the i5-1145G7 (PNP LEN2072, board id 3471) is a Synaptics
# TM3471-030. Linux boots it in PS/2 compatibility mode unless told not to.
# The kernel's own hint, and the change Ubuntu users actually feel, is:
#
#   psmouse.synaptics_intertouch=1
#
# That brings the pad up on RMI4 over SMBus. Firmware upgrades and downgrades
# do not select the bus. This script does not call mkinitcpio (Arch only),
# does not invent i2c_designware.disable_ps, does not enable Elan SMBus,
# does not write libinput pressure quirks, and does not disable the TrackPoint.
#
# Choices baked in by the page that generated this file:
#   CLEAN_UPSTREAM  remove leftovers from debzar/thinkpad-t14-gen2-touchpad-fix
#   ENABLE_RESUME   reload psmouse after wake (off unless you asked for it)

set -uo pipefail
umask 022

ROOT_DIR="${T14_ROOT_DIR:-}"
TOKEN="psmouse.synaptics_intertouch=1"
CLEAN_UPSTREAM=1
ENABLE_RESUME=0
YES=0
DRY=0
ACTION=""
STAMP="$(date +%Y%m%d%H%M%S)"

rp() { printf '%s%s' "$ROOT_DIR" "$1"; }
BACKUP_DIR="$(rp /var/backups/t14-touchpad-fix)/${STAMP}"

say() { printf '%s\n' "$*"; }
info() { printf '  %s\n' "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

have() { command -v "$1" >/dev/null 2>&1; }

usage() {
  cat <<EOF
Usage: sudo ./t14_touchpad_manager.sh [install|uninstall|status] [--yes]

With no arguments, a menu is shown.
  install     add psmouse.synaptics_intertouch=1 and rebuild GRUB
  uninstall   remove it
  status      say whether this boot is on RMI4 or still on PS/2
  --yes       do not ask for confirmation
  --dry-run   print what would change

The leading ./ matters. "sudo t14_touchpad_manager.sh" without ./ is
"command not found" before this script can show a menu.
EOF
}

confirm() {
  local reply
  if [[ "$YES" == "1" || "$DRY" == "1" ]]; then
    return 0
  fi
  if [[ ! -t 0 ]]; then
    die "No terminal to confirm. Re-run with --yes."
  fi
  printf '%s [y/N] ' "$1"
  read -r reply || return 1
  [[ "$reply" == "y" || "$reply" == "Y" ]]
}

backup_file() {
  local f="$1" flat
  [[ -f "$f" ]] || return 0
  if [[ "$DRY" == "1" ]]; then
    info "backup ${f#"$ROOT_DIR"}"
    return 0
  fi
  mkdir -p "$BACKUP_DIR"
  flat="$(printf '%s' "${f#"$ROOT_DIR"}" | tr '/' '_')"
  cp -a "$f" "$BACKUP_DIR/$flat"
  info "backup ${f#"$ROOT_DIR"} -> ${BACKUP_DIR#"$ROOT_DIR"}/$flat"
}

write_file() {
  local path="$1" mode="$2" tmp
  tmp="$(mktemp)"
  cat > "$tmp"
  if [[ "$DRY" == "1" ]]; then
    printf 'would write %s (mode %s)\n' "${path#"$ROOT_DIR"}" "$mode"
    sed 's/^/  | /' "$tmp"
    rm -f "$tmp"
    return 0
  fi
  mkdir -p "$(dirname "$path")"
  backup_file "$path"
  cat "$tmp" > "$path"
  chmod "$mode" "$path"
  rm -f "$tmp"
}

run() {
  if [[ "$DRY" == "1" || -n "$ROOT_DIR" ]]; then
    printf 'run: %s\n' "$*"
    if [[ -n "$ROOT_DIR" ]]; then
      mkdir -p "$(rp /var)"
      printf '%s\n' "$*" >> "$(rp /var/t14-ran.log)"
    fi
    return 0
  fi
  "$@"
}

require_debian() {
  if [[ ! -f "$(rp /etc/debian_version)" ]]; then
    die "This build is for Debian and Ubuntu only ($(rp /etc/debian_version) is missing). It will not call mkinitcpio."
  fi
}

require_intel() {
  [[ -n "$ROOT_DIR" ]] && return 0
  if ! grep -q 'GenuineIntel' /proc/cpuinfo; then
    die "This build is for the Intel T14 Gen 2 (i5-1145G7). This CPU is not GenuineIntel."
  fi
}

check_machine() {
  local name="" family="" blob
  [[ -n "$ROOT_DIR" ]] && return 0
  [[ -r /sys/class/dmi/id/product_name ]] && name="$(< /sys/class/dmi/id/product_name)"
  [[ -r /sys/class/dmi/id/product_family ]] && family="$(< /sys/class/dmi/id/product_family)"
  blob="$family $name"
  case "$blob" in
    *T14*Gen\ 2*|*T14*G2*|*20W0*|*20W1*)
      info "Machine looks like an Intel T14 Gen 2 (${blob# })."
      ;;
    *[Tt]hink[Pp]ad*)
      warn "ThinkPad detected (${blob# }) but the name is not a T14 Gen 2."
      warn "Continue only if dmesg mentions PNP LEN2072 or board id 3471."
      confirm "Continue on this ThinkPad?" || exit 1
      ;;
    *)
      warn "This machine does not look like a ThinkPad (${blob:-unknown})."
      confirm "Continue anyway?" || exit 1
      ;;
  esac
}

rewrite_grub() {
  local mode="$1" file tmp prog
  file="$(rp /etc/default/grub)"
  [[ -f "$file" ]] || die "No ${file}. This script only edits GRUB, which Debian and Ubuntu desktop use."
  if grep -qE "^GRUB_CMDLINE_LINUX(_DEFAULT)?='" "$file"; then
    die "A GRUB command line uses single quotes. Change it to double quotes and re-run."
  fi
  backup_file "$file"
  tmp="$(mktemp)"
  prog="$(mktemp)"
  cat > "$prog" <<'AWK'
function strip(s) {
  gsub(/(^| )psmouse\.synaptics_intertouch=[^ ]+/, "", s)
  gsub(/(^| )psmouse\.elantech_smbus=[^ ]+/, "", s)
  gsub(/(^| )i2c_designware\.disable_ps=[^ ]+/, "", s)
  gsub(/(^| )psmouse\.resetafter=[^ ]+/, "", s)
  gsub(/  +/, " ", s)
  gsub(/^ /, "", s)
  gsub(/ $/, "", s)
  return s
}
function unwrap(v,    q) {
  q = substr(v, 1, 1)
  if (q == "\"" && substr(v, length(v), 1) == "\"") {
    return substr(v, 2, length(v) - 2)
  }
  return v
}
BEGIN { seen = 0 }
$0 ~ /^GRUB_CMDLINE_LINUX_DEFAULT=/ || $0 ~ /^GRUB_CMDLINE_LINUX=/ {
  key = $0
  sub(/=.*/, "", key)
  val = $0
  sub(/^[^=]*=/, "", val)
  inner = strip(unwrap(val))
  if (mode == "add" && key == "GRUB_CMDLINE_LINUX_DEFAULT") {
    if (inner == "") inner = token
    else inner = token " " inner
  }
  if (key == "GRUB_CMDLINE_LINUX_DEFAULT") seen = 1
  print key "=\"" inner "\""
  next
}
{ print }
END {
  if (!seen && mode == "add") print "GRUB_CMDLINE_LINUX_DEFAULT=\"" token "\""
}
AWK
  if ! awk -v mode="$mode" -v token="$TOKEN" -f "$prog" "$file" > "$tmp"; then
    rm -f "$tmp" "$prog"
    die "Could not rewrite ${file}. The original was left in place."
  fi
  rm -f "$prog"
  if [[ ! -s "$tmp" ]]; then
    rm -f "$tmp"
    die "Refusing to replace ${file} with an empty file."
  fi
  if [[ "$DRY" == "1" ]]; then
    printf 'would update %s:\n' "${file#"$ROOT_DIR"}"
    sed 's/^/  | /' "$tmp"
    rm -f "$tmp"
    return 0
  fi
  cat "$tmp" > "$file"
  rm -f "$tmp"
  info "Updated ${file#"$ROOT_DIR"}."
}

write_modprobe() {
  write_file "$(rp /etc/modprobe.d/t14-psmouse.conf)" 644 <<EOF
# ThinkPad T14 Gen 2 Intel — Synaptics TM3471-030 on RMI4/SMBus.
# i2c_i801 is the Intel SMBus host. rmi_smbus is the pad's alternate bus.
# Loading both before psmouse avoids a PS/2 fallback when the host is late.
softdep psmouse pre: i2c_i801 rmi_smbus
options psmouse synaptics_intertouch=1
EOF
}

write_resume() {
  local hook
  hook="$(rp /usr/lib/systemd/system-sleep/t14-touchpad-resume)"
  if [[ "$ENABLE_RESUME" != "1" ]]; then
    if [[ -f "$hook" ]]; then
      backup_file "$hook"
      if [[ "$DRY" != "1" ]]; then
        rm -f "$hook"
      fi
      info "Removed the post-resume hook."
    fi
    return 0
  fi
  info "Installing a hook that runs after wake, not when sleep starts."
  write_file "$hook" 755 <<'EOF'
#!/bin/sh
# t14-touchpad-manager — optional. $1 is "pre" or "post".
case "$1" in
  post)
    modprobe -r psmouse 2>/dev/null || true
    modprobe psmouse synaptics_intertouch=1 2>/dev/null || true
    ;;
esac
exit 0
EOF
}

cleanup_upstream() {
  local f legacy quirks other
  [[ "$CLEAN_UPSTREAM" == "1" ]] || return 0
  for f in \
    "$(rp /etc/udev/rules.d/99-thinkpad-performance.rules)" \
    "$(rp /etc/udev/rules.d/99-touchpad-no-sleep.rules)" \
    "$(rp /usr/local/bin/touchpad-resume-fix.sh)" \
    "$(rp /etc/systemd/system/touchpad-resume.service)"
  do
    if [[ -f "$f" ]]; then
      info "Removing old-script file ${f#"$ROOT_DIR"}"
      backup_file "$f"
      if [[ "$DRY" != "1" ]]; then
        rm -f "$f"
      fi
    fi
  done
  legacy="$(rp /etc/modprobe.d/psmouse.conf)"
  if [[ -f "$legacy" ]] && grep -qE 'synaptics_intertouch|elantech_smbus' "$legacy"; then
    info "Moving aside ${legacy#"$ROOT_DIR"} so it does not fight t14-psmouse.conf."
    backup_file "$legacy"
    if [[ "$DRY" != "1" ]]; then
      rm -f "$legacy"
    fi
  fi
  quirks="$(rp /etc/libinput/local-overrides.quirks)"
  if [[ -f "$quirks" ]] && grep -q 'ThinkPad T14 Gen 2' "$quirks"; then
    other="$(grep -E '^\[' "$quirks" | grep -v 'ThinkPad T14' || true)"
    if [[ -n "$other" ]]; then
      warn "Left ${quirks#"$ROOT_DIR"} in place; it has other sections."
    else
      info "Moving aside ${quirks#"$ROOT_DIR"} (upstream quirks can fail to parse)."
      backup_file "$quirks"
      if [[ "$DRY" != "1" ]]; then
        rm -f "$quirks"
      fi
    fi
  fi
  if [[ -z "$ROOT_DIR" && "$DRY" != "1" ]] && have systemctl; then
    systemctl disable touchpad-resume.service >/dev/null 2>&1 || true
    systemctl daemon-reload >/dev/null 2>&1 || true
  fi
}

regenerate() {
  if [[ -n "$ROOT_DIR" ]]; then
    run update-grub
    run update-initramfs -u
    return 0
  fi
  if have update-grub; then
    run update-grub
  elif have grub-mkconfig; then
    run grub-mkconfig -o /boot/grub/grub.cfg
  else
    die "update-grub is not installed (package grub2-common). Refusing to call mkinitcpio; that is the Arch command Debian does not have."
  fi
  if ! have update-initramfs; then
    die "update-initramfs is not installed (package initramfs-tools)."
  fi
  run update-initramfs -u
}

remove_managed_files() {
  local f
  for f in \
    "$(rp /etc/modprobe.d/t14-psmouse.conf)" \
    "$(rp /usr/lib/systemd/system-sleep/t14-touchpad-resume)"
  do
    if [[ -f "$f" ]]; then
      backup_file "$f"
      if [[ "$DRY" != "1" ]]; then
        rm -f "$f"
      fi
      info "Removed ${f#"$ROOT_DIR"}."
    fi
  done
}

install_fix() {
  require_debian
  require_intel
  check_machine
  say ""
  say "Install InterTouch for the Synaptics TM3471-030."
  info "Add ${TOKEN} to GRUB."
  info "Write /etc/modprobe.d/t14-psmouse.conf (option + Intel SMBus softdep)."
  if [[ "$CLEAN_UPSTREAM" == "1" ]]; then
    info "Remove leftovers from the GitHub script, if they are present."
  fi
  if [[ "$ENABLE_RESUME" == "1" ]]; then
    info "Reload psmouse after resume."
  else
    info "No resume hook. Add one later only if the pad dies after suspend."
  fi
  info "Run update-grub and update-initramfs -u. mkinitcpio is not used."
  info "The pad will not change until you reboot."
  confirm "Apply this?" || return 0
  cleanup_upstream
  rewrite_grub add
  write_modprobe
  write_resume
  regenerate
  say ""
  say "Installed. Reboot, then run: sudo ./t14_touchpad_manager.sh status"
  say "You want: Synaptics TM3471-030 on rmi4."
  say "Still broken if you see: SynPS/2 Synaptics TouchPad."
  say "Leave the TrackPoint enabled in BIOS. The buttons above the pad need it."
  say "Do not write AttrTapping or AttrPressureRange=1:0. Neither fixes this lag."
}

uninstall_fix() {
  require_debian
  say ""
  say "Remove InterTouch and the files this script owns."
  confirm "Remove the fix?" || return 0
  rewrite_grub del
  remove_managed_files
  cleanup_upstream
  regenerate
  say ""
  say "Removed. Reboot to go back to PS/2."
}

report_tool() {
  local name="$1"
  if have "$name"; then
    info "found    $name ($(command -v "$name"))"
  else
    info "missing  $name"
  fi
}

show_status() {
  local n name found grub
  say "T14 Gen 2 Intel — Debian/Ubuntu status"
  say ""
  say "Tools (mkinitcpio is intentionally unused):"
  report_tool update-grub
  report_tool grub-mkconfig
  report_tool update-initramfs
  if have mkinitcpio; then
    info "present  mkinitcpio (not called)"
  else
    info "missing  mkinitcpio (expected on Debian; the old script called it anyway)"
  fi
  say ""
  grub="$(rp /etc/default/grub)"
  if [[ -f "$grub" ]] && grep -q 'psmouse.synaptics_intertouch=1' "$grub"; then
    say "GRUB file: token is staged."
  elif [[ -f "$grub" ]]; then
    say "GRUB file: token is not staged."
  else
    say "GRUB file: ${grub#"$ROOT_DIR"} not found."
  fi
  if [[ -f "$(rp /etc/modprobe.d/t14-psmouse.conf)" ]]; then
    say "modprobe: /etc/modprobe.d/t14-psmouse.conf is installed."
  else
    say "modprobe: t14-psmouse.conf is not installed."
  fi
  say ""
  if [[ -n "$ROOT_DIR" ]]; then
    say "Boot state was not read (test root)."
    return 0
  fi
  if [[ -r /proc/cmdline ]] && grep -q 'psmouse.synaptics_intertouch=1' /proc/cmdline; then
    say "This boot: InterTouch is on the kernel command line."
  else
    say "This boot: InterTouch is NOT on the kernel command line."
  fi
  if [[ -r /proc/cmdline ]] && grep -q 'i2c_designware.disable_ps' /proc/cmdline; then
    warn "i2c_designware.disable_ps is on the command line. It is not how this pad switches buses. Re-run install to strip it."
  fi
  say ""
  say "Input devices:"
  found=0
  shopt -s nullglob
  for n in /sys/class/input/input*/name; do
    [[ -r "$n" ]] || continue
    name="$(< "$n")"
    case "$name" in
      *TM3471-030*)
        info "RMI4  $name"
        found=2
        ;;
      *SynPS/2\ Synaptics*|*Synaptics\ TouchPad*)
        info "PS/2  $name"
        [[ "$found" -lt 2 ]] && found=1
        ;;
      *[Tt]rack[Pp]oint*)
        info "stick $name"
        ;;
    esac
  done
  shopt -u nullglob
  say ""
  if [[ "$found" == "2" ]]; then
    say "Verdict: RMI4 is active. The bus change worked."
    say "If touches still ghost, measure before any quirk:"
    say "  sudo libinput measure touchpad-pressure"
  elif [[ "$found" == "1" ]]; then
    say "Verdict: still on PS/2."
    say "If the command line has the parameter, the SMBus probe failed and the kernel fell back."
    say "Check: sudo dmesg | grep -E 'rmi4|TM3471|intertouch|SMBus'"
  else
    say "Verdict: no Synaptics touchpad node was found."
  fi
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      install|uninstall|status) ACTION="$1" ;;
      --yes|-y) YES=1 ;;
      --dry-run) DRY=1 ;;
      -h|--help) usage; exit 0 ;;
      *) die "Unknown argument: $1 (try --help)" ;;
    esac
    shift
  done
}

main() {
  if [[ -f "$0" ]] && grep -q $'\r' "$0"; then
    die "This file has Windows line endings. Run: sed -i 's/\\r$//' $0"
  fi
  parse_args "$@"
  if [[ -z "$ROOT_DIR" && "$DRY" != "1" && "$(id -u)" -ne 0 ]]; then
    die "Not root. From the directory that contains this file, run: sudo ./t14_touchpad_manager.sh"
  fi
  if [[ -n "$ACTION" ]]; then
    case "$ACTION" in
      install) install_fix ;;
      uninstall) uninstall_fix ;;
      status) show_status ;;
    esac
    exit 0
  fi
  while true; do
    cat <<EOF

ThinkPad T14 Gen 2 touchpad manager
Debian / Ubuntu, Intel only

  1) Install InterTouch
  2) Remove InterTouch
  3) Show whether RMI4 bound
  4) Exit

EOF
    printf 'Choose [1-4]: '
    if ! read -r choice; then
      printf '\n'
      exit 0
    fi
    case "$choice" in
      1) install_fix ;;
      2) uninstall_fix ;;
      3) show_status ;;
      4|q|Q) exit 0 ;;
      *) say "Not an option. Choose 1, 2, 3, or 4." ;;
    esac
  done
}

main "$@"
