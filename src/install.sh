#!/bin/bash
#
# eApp for Mac - Setup (free engine, no CrossOver)
#
# Builds a private Windows environment on this Mac using a free build of
# CrossOver's open-source Wine engine, installs Microsoft .NET Framework 4.8
# into it, then installs eApp from the file you downloaded from AIL.
# Safe to run more than once. It skips whatever is already done.
#
# Order matters and each step below was found the hard way:
#   - The engine tarball has no libraries. They come from the Sikarugir
#     Template and must sit beside wswine.bundle. The engine also loads
#     FreeType and GnuTLS by bare name, so DYLD_FALLBACK_LIBRARY_PATH must
#     point at them or fonts and HTTPS silently fail.
#   - .NET 4.0 goes in first (it installs the .NET loader), reporting Windows XP.
#     .NET 4.8 goes in second, reporting Windows 7. Then the reported version
#     is put back and the environment is told to use Microsoft's loader.
#   - This engine copies itself to a temp path at launch, so installer
#     processes never show their own names. Completion is detected by what
#     lands on disk and in the registry, never by process names.

set -u
umask 022

EAPP_HOME="${EAPP_HOME:-$HOME/Library/Application Support/eApp Mac}"
ENGINE_DIR="$EAPP_HOME/engine"
CXE="$ENGINE_DIR/wswine.bundle"
export WINEPREFIX="$EAPP_HOME/prefix"
export WINEDEBUG=-all
export DYLD_FALLBACK_LIBRARY_PATH="$ENGINE_DIR"
WINE="$CXE/bin/wine"; WINESERVER="$CXE/bin/wineserver"
C="$WINEPREFIX/drive_c"
CACHE="$HOME/Library/Caches/eApp-Mac-Setup"
LOG="$HOME/Library/Logs/eApp-Mac-Setup.log"
APPDIR="${EAPP_APPDIR:-/Applications/eApp.app}"

# Download locations are issued by the Tally server after sign-in (short-lived links).
ENGINE_URL=""; TEMPLATE_URL=""; DOTNET40_URL=""; DOTNET48_URL=""
GATE_VERSION="1.4"

B="\033[1m"; G="\033[32m"; Y="\033[33m"; R="\033[31m"; N="\033[0m"
mkdir -p "$CACHE" "$(dirname "$LOG")" "$EAPP_HOME"
: > "$LOG"
say()  { printf "%b\n" "$*"; }
step() { printf "\n${B}==> %s${N}\n" "$*"; echo "=== $* ===" >> "$LOG"; }
ok()   { printf "    ${G}OK${N}  %s\n" "$*"; }
warn() { printf "    ${Y}--${N}  %s\n" "$*"; }
die()  { printf "\n${R}STOPPED.${N} %s\n\n" "$*"; printf "Send this file to your administrator:\n  %s\n\n" "$LOG"
         printf "Press Return to close this window. "; read -r _; exit 1; }
run()  { echo "+ $*" >> "$LOG"; "$@" >> "$LOG" 2>&1; }
stop_engine() { "$WINESERVER" -k >> "$LOG" 2>&1; sleep 2; }

fetch() { # url dest label
  [ -s "$2" ] && return 0
  say "    Downloading $3"
  curl -fL --retry 3 --progress-bar -o "$2.part" "$1" || die "The download failed. Check your internet connection and run this again."
  mv "$2.part" "$2"
}
mscoree_size() { stat -f%z "$C/windows/system32/mscoree.dll" 2>/dev/null || echo 0; }
dotnet_size()  { du -sm "$C/windows/Microsoft.NET" 2>/dev/null | awk '{print $1+0}'; }
dotnet_release(){ grep -a -A14 'NDP\\\\v4\\\\Full\]' "$WINEPREFIX/system.reg" 2>/dev/null | grep -a '"Release"=dword' | head -1 | sed 's/.*dword://'; }
winver_set()   { stop_engine; run "$WINE" reg.exe add 'HKCU\Software\Wine' /v Version /d "$1" /f; }
winver_clear() { stop_engine; run "$WINE" reg.exe delete 'HKCU\Software\Wine' /v Version /f; }

# wait_for <label> <max_minutes> <done-check command...>
# Polls every 15 s. Done when the check passes AND the .NET folder size has
# stopped changing for four polls. Never looks at process names.
wait_for() {
  local label="$1" maxmin="$2"; shift 2
  local last=-1 stable=0 i
  for i in $(seq 1 $(( maxmin * 4 ))); do
    sleep 15
    local sz; sz=$(dotnet_size)
    if [ "$sz" -eq "$last" ]; then stable=$(( stable + 1 )); else stable=0; fi
    last=$sz
    printf "\r    %s... %s min, %s MB      " "$label" "$(( i / 4 ))" "$sz"
    if "$@" >/dev/null 2>&1 && [ "$stable" -ge 4 ]; then printf "\r%60s\r" ""; return 0; fi
  done
  printf "\r%60s\r" ""; return 1
}


# ------------------------------------------------- Tally subscription gate
# Written to disk so the eApp launcher can use the same code on every start.
cat > "$EAPP_HOME/tally-gate.sh" <<'GATE_EOF'
# Tally subscription gate for eApp for Mac. Sourced by the installer and by the eApp launcher.
# The decision is made by the Tally server (personal subscription OR active team). The server also
# issues the offline allowance: eApp keeps opening until "expiresAt", then needs to be online once.
TALLY_API="${TALLY_API:-https://api.callwithtally.com}"
GATE_SERVICE="eApp Mac (Tally)"
GATE_STATE="${GATE_STATE:-$EAPP_HOME/tally-gate.state}"   # non-secret: email|expires_epoch|via
GATE_VERSION="${GATE_VERSION:-1.4}"

gate_dialog_text()   { osascript -e 'on run argv' -e 'tell application "System Events"' -e 'activate' -e 'set r to display dialog (item 1 of argv) default answer (item 2 of argv) with title "eApp for Mac" buttons {"Cancel", "OK"} default button "OK"' -e 'return text returned of r' -e 'end tell' -e 'end run' "$1" "$2" 2>/dev/null; }
gate_dialog_secret() { osascript -e 'on run argv' -e 'tell application "System Events"' -e 'activate' -e 'set r to display dialog (item 1 of argv) default answer "" with hidden answer with title "eApp for Mac" buttons {"Cancel", "OK"} default button "OK"' -e 'return text returned of r' -e 'end tell' -e 'end run' "$1" 2>/dev/null; }
gate_tell()          { osascript -e 'on run argv' -e 'tell application "System Events"' -e 'activate' -e 'display dialog (item 1 of argv) with title "eApp for Mac" buttons {"OK"} default button "OK"' -e 'end tell' -e 'end run' "$1" >/dev/null 2>&1; }

gate_json_str() { sed -nE "s/.*\"$1\" *: *\"([^\"]*)\".*/\1/p" | head -1; }
gate_json_num() { sed -nE "s/.*\"$1\" *: *([0-9]+).*/\1/p" | head -1; }
gate_json_esc() { printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'; }

gate_token_get() { security find-generic-password -s "$GATE_SERVICE" -w 2>/dev/null; }
gate_token_set() { security add-generic-password -U -s "$GATE_SERVICE" -a "$1" -w "$2" >/dev/null 2>&1; }
gate_state_get() { cat "$GATE_STATE" 2>/dev/null; }
gate_state_set() { printf '%s|%s|%s\n' "$1" "$2" "$3" > "$GATE_STATE"; }

# Device identity: a hash of the machine's platform UUID. The UUID itself never leaves the Mac.
gate_device_hash() { ioreg -rd1 -c IOPlatformExpertDevice 2>/dev/null | awk -F'"' '/IOPlatformUUID/{print $4}' | tr -d '\n' | shasum -a 256 | cut -c1-64; }
gate_device_headers() {   # fills the array GATE_DEV_HDRS (bash arrays: no word-splitting surprises)
  GATE_DEV_HDRS=( -H "X-EApp-Device: $(gate_device_hash)"
                  -H "X-EApp-Name: $(scutil --get ComputerName 2>/dev/null | LC_ALL=C tr -cd 'A-Za-z0-9 ._-' | cut -c1-80)"
                  -H "X-EApp-Model: $(sysctl -n hw.model 2>/dev/null)"
                  -H "X-EApp-OS: $(sw_vers -productVersion 2>/dev/null)"
                  -H "X-EApp-Version: $GATE_VERSION" )
}

# gate_http <curl args...>  -> sets GATE_CODE and GATE_BODY
gate_http() {
  local out; out=$(curl -sS --max-time 20 -w '\n%{http_code}' "$@" 2>/dev/null)
  GATE_CODE=$(printf '%s' "$out" | tail -n1); GATE_BODY=$(printf '%s' "$out" | sed '$d')
  [ -z "$GATE_CODE" ] && GATE_CODE=000
}

# gate_entitle <token> -> 0 active (state + token stored), 1 inactive, 2 token rejected, 3 network
gate_entitle() {
  local token="$1"; gate_device_headers
  gate_http "${GATE_DEV_HDRS[@]}" -H "Authorization: Bearer $token" "$TALLY_API/api/eapp-mac/entitlement"
  case "$GATE_CODE" in
    000) return 3;;
    401) return 2;;
    403) return 1;;
    200) ;;
    *)   return 3;;
  esac
  local email via exp
  email=$(printf '%s' "$GATE_BODY" | gate_json_str email); via=$(printf '%s' "$GATE_BODY" | gate_json_str via)
  exp=$(printf '%s' "$GATE_BODY" | gate_json_num expiresAt)
  [ -n "$exp" ] || return 3
  gate_token_set "${email:-tally}" "$token"; gate_state_set "${email:-tally}" "$exp" "${via:-personal}"; GATE_VIA="$via"; return 0
}

# gate_login <email> <password> -> 0 active, 1 inactive, 2 bad credentials, 3 network
gate_login() {
  local body; body=$(printf '{"email":"%s","password":"%s"}' "$(gate_json_esc "$1")" "$(gate_json_esc "$2")")
  gate_http -H 'Content-Type: application/json' -d "$body" "$TALLY_API/api/login"
  case "$GATE_CODE" in 000) return 3;; 200) ;; *) return 2;; esac
  local token; token=$(printf '%s' "$GATE_BODY" | gate_json_str token); [ -n "$token" ] || return 2
  gate_entitle "$token"; local rc=$?
  [ $rc -eq 2 ] && return 3   # a token we were just given cannot be "rejected" unless the server is confused
  return $rc
}

# gate_recheck -> 0 active, 1 inactive, 2 must sign in again, 3 offline
gate_recheck() {
  local token; token=$(gate_token_get); [ -n "$token" ] || return 2
  gate_http -X POST -H "Authorization: Bearer $token" "$TALLY_API/api/refresh-token"
  [ "$GATE_CODE" = "000" ] && return 3
  [ "$GATE_CODE" = "200" ] || return 2
  local new; new=$(printf '%s' "$GATE_BODY" | gate_json_str token); [ -n "$new" ] && token="$new"
  gate_entitle "$token"
}

# Server-issued offline allowance.
gate_within_grace() {
  local exp; exp=$(gate_state_get | cut -d'|' -f2)
  [ -n "$exp" ] && [ "$(date +%s)" -lt "$exp" ]
}

# gate_downloads -> exports DL_ENGINE DL_TEMPLATE DL_DOTNET40 DL_DOTNET48 (short-lived links); 0 ok, else fail
gate_downloads() {
  local token; token=$(gate_token_get); [ -n "$token" ] || return 1
  gate_http -H "Authorization: Bearer $token" "$TALLY_API/api/eapp-mac/downloads"
  [ "$GATE_CODE" = "200" ] || return 1
  DL_ENGINE=$(printf '%s' "$GATE_BODY" | gate_json_str engine); DL_TEMPLATE=$(printf '%s' "$GATE_BODY" | gate_json_str template)
  DL_DOTNET40=$(printf '%s' "$GATE_BODY" | gate_json_str dotnet40); DL_DOTNET48=$(printf '%s' "$GATE_BODY" | gate_json_str dotnet48)
  DL_WIC=$(printf '%s' "$GATE_BODY" | gate_json_str wic)
  [ -n "$DL_ENGINE" ] && [ -n "$DL_TEMPLATE" ] && [ -n "$DL_DOTNET40" ] && [ -n "$DL_DOTNET48" ]
}

gate_signin_interactive() {
  local last; last=$(gate_state_get | cut -d'|' -f1)
  local email pass rc
  email=$(gate_dialog_text "Sign in with your Tally account to use eApp on this Mac.

Email:" "$last") || return 1
  [ -n "$email" ] || return 1
  pass=$(gate_dialog_secret "Tally password for $email:") || return 1
  gate_login "$email" "$pass"; rc=$?
  case $rc in
    0) return 0;;
    1) gate_tell "This Tally account does not have an active subscription.

eApp for Mac is included with Tally. Subscribe or renew at callwithtally.com, then try again."; return 1;;
    2) gate_tell "That email or password is not right. Try again."; gate_signin_interactive; return $?;;
    *) gate_tell "Could not reach Tally. Check your internet connection and try again."; return 1;;
  esac
}

# gate_check_or_signin -> 0 allowed to run, 1 blocked (user already told why)
gate_check_or_signin() {
  gate_recheck; local rc=$?
  case $rc in
    0) return 0;;
    1) gate_tell "Your Tally subscription is no longer active.

eApp for Mac is included with Tally. Renew at callwithtally.com, then open eApp again."; return 1;;
    3) gate_within_grace && return 0
       gate_tell "eApp needs to confirm your Tally subscription, and this Mac is offline. Connect to the internet and open eApp again."; return 1;;
    *) gate_signin_interactive; return $?;;
  esac
}
GATE_EOF
. "$EAPP_HOME/tally-gate.sh"

clear
cat <<'BANNER'
--------------------------------------------------
  eApp for Mac - Setup
--------------------------------------------------
This takes about 20 to 40 minutes. Most of that is
waiting. You can leave it running.

Do not close this window until it says FINISHED.
--------------------------------------------------
BANNER

# ------------------------------------------------------------------ 1. Mac
step "Step 1 of 8  Checking this Mac"
MACOS=$(sw_vers -productVersion)
case "$MACOS" in 1[2-9].*|2[0-9].*) ok "macOS $MACOS" ;; *) die "eApp needs macOS 12 or newer. This Mac has macOS $MACOS." ;; esac
if [ "$(uname -m)" = "arm64" ]; then
  ok "Apple Silicon Mac"
  if /usr/bin/arch -x86_64 /usr/bin/true 2>/dev/null; then ok "Rosetta 2 is installed"
  else
    warn "Rosetta 2 is missing. Installing it now. You may be asked for your Mac password."
    softwareupdate --install-rosetta --agree-to-license || die "Rosetta 2 did not install. Install any pending macOS updates, then run this again."
    ok "Rosetta 2 installed"
  fi
else ok "Intel Mac"; fi
FREE=$(df -g "$HOME" | awk 'NR==2 {print $4+0}')
# A fresh install needs room for the engine, .NET, eApp and its 3 GB update. A re-run over an
# existing environment only needs working space.
if [ -d "$EAPP_HOME/prefix/drive_c/windows" ]; then NEED=3; else NEED=20; fi
[ "$FREE" -ge "$NEED" ] || die "Not enough free disk space. This needs about ${NEED} GB free. This Mac has ${FREE} GB free."
ok "${FREE} GB free disk space"


# ---------------------------------------------------------------- 2. Tally
step "Step 2 of 8  Signing in to Tally"
say "    eApp for Mac is included with an active Tally subscription."
say "    A sign-in window will open."
if gate_signin_interactive; then
  ok "Signed in as $(cut -d'|' -f1 "$GATE_STATE")  (subscription: $(cut -d'|' -f3 "$GATE_STATE"))"
else
  die "eApp for Mac needs an active Tally subscription. Subscribe or renew at callwithtally.com, then run this again."
fi
gate_downloads || die "Tally did not provide the download links. Run this again in a few minutes."
ENGINE_URL="$DL_ENGINE"; TEMPLATE_URL="$DL_TEMPLATE"; DOTNET40_URL="$DL_DOTNET40"; DOTNET48_URL="$DL_DOTNET48"
ok "Download links issued"

# --------------------------------------------------------------- 2. Engine
step "Step 3 of 8  Installing the Windows engine"
if [ -x "$WINE" ] && [ -e "$ENGINE_DIR/libfreetype.6.dylib" ] && [ -e "$ENGINE_DIR/libgstreamer-1.0.0.dylib" ]; then
  ok "Engine already installed"
else
  fetch "$ENGINE_URL"   "$CACHE/engine.tar.xz"   "the Windows engine (164 MB)"
  fetch "$TEMPLATE_URL" "$CACHE/template.tar.xz" "its support libraries (82 MB)"
  mkdir -p "$ENGINE_DIR" "$CACHE/template"
  say "    Unpacking."
  tar xJf "$CACHE/engine.tar.xz" -C "$ENGINE_DIR" || die "Could not unpack the engine."
  tar xJf "$CACHE/template.tar.xz" -C "$CACHE/template" || die "Could not unpack the support libraries."
  FW=$(find "$CACHE/template" -maxdepth 3 -type d -name Frameworks | head -1)
  [ -n "$FW" ] || die "Support libraries were not where expected."
  # Libraries must sit beside wswine.bundle. GStreamer keeps its own inside a framework.
  cp -f "$FW"/*.dylib "$ENGINE_DIR"/ 2>/dev/null
  cp -Rf "$FW/GStreamer.framework" "$ENGINE_DIR"/ 2>/dev/null
  for f in "$ENGINE_DIR"/GStreamer.framework/Versions/1.0/lib/*.dylib; do
    [ -e "$ENGINE_DIR/$(basename "$f")" ] || ln -sf "$f" "$ENGINE_DIR/$(basename "$f")"
  done
  xattr -dr com.apple.quarantine "$ENGINE_DIR" 2>/dev/null
  [ -x "$WINE" ] || die "The engine did not unpack correctly."
  ok "Engine ready: $("$WINE" --version 2>/dev/null | head -1)"
fi

# --------------------------------------------------------------- 3. Prefix
step "Step 4 of 8  Preparing the Windows environment"
if [ -d "$C/windows" ]; then ok "Environment already exists"
else
  say "    Creating it. This takes a minute."
  WINEDLLOVERRIDES="mscoree=d;mshtml=d" run "$WINE" wineboot -i
  stop_engine
  [ -d "$C/windows" ] || die "Could not create the Windows environment."
  ok "Created"
fi
V=$("$WINE" cmd.exe /c ver 2>/dev/null | tr -d '\r' | grep -i microsoft)
echo "$V" | grep -q "Windows" || die "The engine does not run on this Mac. Send the log file to your administrator."
V32=$("$WINE" "$C/windows/syswow64/cmd.exe" /c ver 2>/dev/null | tr -d '\r' | grep -ci microsoft)
[ "$V32" -ge 1 ] || die "32-bit Windows support is not working. Send the log file to your administrator."
ok "Environment runs 64-bit and 32-bit Windows code"
stop_engine

# ----------------------------------------------------------------- 4. .NET
step "Step 5 of 8  Installing Microsoft .NET Framework"
if [ "$(mscoree_size)" -gt 400000 ] && [ "$(dotnet_release)" = "00080eb1" ]; then
  ok ".NET Framework 4.8 is already installed"
else
  gate_downloads && { DOTNET40_URL="$DL_DOTNET40"; DOTNET48_URL="$DL_DOTNET48"; }
  fetch "$DOTNET40_URL" "$CACHE/dotnetfx40.exe" "Microsoft .NET 4.0 (48 MB)"
  fetch "$DOTNET48_URL" "$CACHE/ndp48.exe"      "Microsoft .NET 4.8 (69 MB)"
  ok "Installers ready"
  stop_engine
  for K in 'HKLM\Software\Microsoft\NET Framework Setup\NDP\v4' 'HKLM\Software\Wow6432Node\Microsoft\NET Framework Setup\NDP\v4'; do
    run "$WINE" reg.exe delete "$K" /f
  done
  if [ "$(mscoree_size)" -gt 400000 ]; then ok ".NET 4.0 already installed"
  else
    winver_set winxp
    cp -f "$CACHE/dotnetfx40.exe" "$C/dotnetfx40.exe"
    say "    Installing .NET 4.0. Nothing will appear on screen. Please wait."
    "$WINE" 'C:\dotnetfx40.exe' /q /norestart >> "$LOG" 2>&1 &
    wait_for "Installing .NET 4.0" 20 sh -c "[ \$(stat -f%z '$C/windows/system32/mscoree.dll' 2>/dev/null || echo 0) -gt 400000 ]" \
      || die ".NET 4.0 did not install. Send the log file to your administrator."
    stop_engine; rm -f "$C/dotnetfx40.exe"
    ok ".NET 4.0 installed"
  fi
  winver_set win7
  cp -f "$CACHE/ndp48.exe" "$C/ndp48.exe"
  say "    Installing .NET 4.8. This is the long one. Nothing will appear on screen. Please wait."
  "$WINE" 'C:\ndp48.exe' /q /norestart >> "$LOG" 2>&1 &
  wait_for "Installing .NET 4.8" 45 sh -c "grep -a -A14 'NDP\\\\\\\\v4\\\\\\\\Full\\]' '$WINEPREFIX/system.reg' 2>/dev/null | grep -aq '\"Release\"=dword:00080eb1'" \
    || die ".NET 4.8 did not install. Send the log file to your administrator."
  stop_engine; rm -f "$C/ndp48.exe"
  winver_clear
  run "$WINE" reg.exe add 'HKCU\Software\Wine\DllOverrides' /v mscoree /d native /f
  stop_engine
  [ "$(mscoree_size)" -gt 400000 ] || die ".NET installed but did not take over correctly. Send the log file to your administrator."
  ok ".NET Framework 4.8 installed ($(dotnet_size) MB)"
fi

# ---------------------------------------------------- 6. Form page repair
step "Step 6 of 8  Repairing form pages"
# About one in ten eApp form pages is a Deflate-compressed TIFF, which the engine's image codec
# cannot read; opening such a form fails with "A generic error occurred in GDI+". A small tool
# rewrites those pages as PackBits TIFF (pixel-identical) and keeps the originals in
# forms\_deflate-original. eApp's self-update can bring Deflate pages back, so the eApp icon
# runs the same tool before each start and again after an update.
# Earlier versions of this installer replaced the codec itself; that broke image saving and
# could stop eApp from opening. Undo that here if it is present.
stop_engine
cp -f "$CXE/lib/wine/i386-windows/windowscodecs.dll" "$C/windows/syswow64/windowscodecs.dll" 2>/dev/null
cp -f "$CXE/lib/wine/i386-windows/windowscodecsext.dll" "$C/windows/syswow64/windowscodecsext.dll" 2>/dev/null
run "$WINE" reg.exe delete 'HKCU\Software\Wine\DllOverrides' /v windowscodecs /f
run "$WINE" reg.exe delete 'HKCU\Software\Wine\DllOverrides' /v windowscodecsext /f
stop_engine
mkdir -p "$C/eapp-mac/repair"
cat > "$C/eapp-mac/repair/FormRepair.cs" <<'CSEOF'
// FormRepair: rewrites Deflate-compressed eApp form pages as PackBits TIFF, which Wine's image codec reads.
// Decodes the Deflate data itself (.NET inflater). No other decoder is involved.
//   FormRepair.exe <formsDir>            repair in place; originals kept in <formsDir>\_deflate-original
//   FormRepair.exe --list <formsDir>     only list the pages it would repair
//   FormRepair.exe --dump <tif> <out>    raw 32bpp render of every frame through GDI+ (verification)
using System; using System.IO; using System.IO.Compression; using System.Collections.Generic; using System.Drawing; using System.Drawing.Imaging; using System.Runtime.InteropServices;
class FormRepair {
  class Page { public uint W, H, Rps; public int Bps = 1, Spp = 1, Comp = 1, Photo = 1, Fill = 1, Pred = 1, Planar = 1, ResUnit = 2, PageNo = -1, PageTot = -1; public uint[] SOff, SCnt; public uint XrN = 300, XrD = 1, YrN = 300, YrD = 1; }
  static int Main(string[] a) {
    if (a.Length >= 3 && a[0] == "--dump") { Dump(a[1], a[2]); return 0; }
    bool list = a.Length >= 2 && a[0] == "--list"; string dir = list ? a[1] : a[0];
    string orig = Path.Combine(dir, "_deflate-original"); int fixedN = 0, skipped = 0, failed = 0;
    foreach (var f in Directory.GetFiles(dir)) {
      string ext = Path.GetExtension(f).ToLowerInvariant(); if (ext != ".tif" && ext != ".tiff") continue;
      byte[] t; List<Page> pages; try { t = File.ReadAllBytes(f); pages = ReadPages(t); } catch { skipped++; continue; }
      bool deflate = pages.Count > 0; foreach (var p in pages) if (p.Comp != 8 && p.Comp != 32946) deflate = false;
      if (!deflate) { skipped++; continue; }
      if (list) { Console.WriteLine("DEFLATE " + Path.GetFileName(f) + " pages=" + pages.Count + " bps=" + pages[0].Bps); continue; }
      string tmp = f + ".repair.tmp";
      try {
        Write(t, pages, tmp);
        int frames; using (var chk = Image.FromFile(tmp)) frames = chk.GetFrameCount(FrameDimension.Page);
        if (frames != pages.Count) throw new Exception("verify: " + frames + " frames, expected " + pages.Count);
        Directory.CreateDirectory(orig); string keep = Path.Combine(orig, Path.GetFileName(f));
        if (File.Exists(keep)) keep = Path.Combine(orig, Path.GetFileNameWithoutExtension(f) + "." + DateTime.Now.ToString("yyyyMMddHHmmss") + ext);
        File.Move(f, keep); File.Move(tmp, f); fixedN++; Console.WriteLine("FIXED " + Path.GetFileName(f) + " pages=" + pages.Count);
      } catch (Exception e) { failed++; Console.WriteLine("FAIL  " + Path.GetFileName(f) + "  " + e.Message); try { if (File.Exists(tmp)) File.Delete(tmp); } catch { } }
    }
    Console.WriteLine("done fixed=" + fixedN + " skipped=" + skipped + " failed=" + failed); return failed == 0 ? 0 : 1;
  }
  static List<Page> ReadPages(byte[] t) {
    bool le = t[0] == (byte)'I'; if ((le ? t[2] : t[3]) != 42) throw new Exception("not a TIFF");
    Func<int, int> u16 = o => le ? t[o] | (t[o + 1] << 8) : (t[o] << 8) | t[o + 1];
    Func<int, uint> u32 = o => le ? (uint)(t[o] | (t[o + 1] << 8) | (t[o + 2] << 16) | (t[o + 3] << 24)) : (uint)((t[o] << 24) | (t[o + 1] << 16) | (t[o + 2] << 8) | t[o + 3]);
    var pages = new List<Page>(); uint ifd = u32(4); int guard = 0;
    while (ifd != 0 && ifd + 2 <= t.Length && guard++ < 500) {
      int n = u16((int)ifd); var p = new Page();
      for (int i = 0; i < n; i++) {
        int e = (int)ifd + 2 + 12 * i; int tag = u16(e), typ = u16(e + 2); uint cnt = u32(e + 4);
        int tsz = typ == 3 ? 2 : typ == 4 ? 4 : typ == 5 ? 8 : 1; int vo = cnt * (uint)tsz <= 4 ? e + 8 : (int)u32(e + 8);
        Func<int, uint> val = k => typ == 3 ? (uint)u16(vo + 2 * k) : typ == 1 ? t[vo + k] : u32(vo + 4 * k);
        switch (tag) {
          case 256: p.W = val(0); break; case 257: p.H = val(0); break; case 258: p.Bps = (int)val(0); break; case 259: p.Comp = (int)val(0); break;
          case 262: p.Photo = (int)val(0); break; case 266: p.Fill = (int)val(0); break; case 277: p.Spp = (int)val(0); break; case 278: p.Rps = val(0); break;
          case 273: p.SOff = new uint[cnt]; for (int k = 0; k < cnt; k++) p.SOff[k] = val(k); break;
          case 279: p.SCnt = new uint[cnt]; for (int k = 0; k < cnt; k++) p.SCnt[k] = val(k); break;
          case 282: p.XrN = u32(vo); p.XrD = u32(vo + 4); break; case 283: p.YrN = u32(vo); p.YrD = u32(vo + 4); break;
          case 284: p.Planar = (int)val(0); break; case 296: p.ResUnit = (int)val(0); break; case 317: p.Pred = (int)val(0); break;
          case 297: p.PageNo = (int)val(0); if (cnt > 1) p.PageTot = (int)val(1); break;
        }
      }
      if (p.Rps == 0 || p.Rps > p.H) p.Rps = p.H; pages.Add(p); ifd = u32((int)ifd + 2 + 12 * n);
    }
    return pages;
  }
  static byte[] Inflate(byte[] t, uint off, uint cnt, int expect) {
    int skip = (cnt >= 2 && (t[off] & 0x0F) == 8 && (((t[off] << 8) | t[off + 1]) % 31) == 0) ? 2 : 0;
    using (var ms = new MemoryStream(t, (int)(off + skip), (int)(cnt - skip))) using (var ds = new DeflateStream(ms, CompressionMode.Decompress)) {
      var buf = new byte[expect]; int got = 0; while (got < expect) { int r = ds.Read(buf, got, expect - got); if (r <= 0) break; got += r; }
      if (got < expect) throw new Exception("short inflate " + got + "/" + expect); return buf;
    }
  }
  static void Write(byte[] t, List<Page> pages, string path) {
    using (var fs = new FileStream(path, FileMode.Create)) using (var w = new BinaryWriter(fs)) {
      w.Write((byte)'I'); w.Write((byte)'I'); w.Write((ushort)42); w.Write((uint)0); long prevNext = 4;
      for (int pi = 0; pi < pages.Count; pi++) {
        var p = pages[pi];
        if (p.Spp != 1 || (p.Bps != 1 && p.Bps != 8) || p.Planar != 1 || (p.Pred != 1 && p.Bps != 8) || p.SOff == null || p.SCnt == null) throw new Exception("unsupported layout on page " + pi);
        int rowBytes = (int)((p.W * (uint)p.Bps + 7) / 8); long stripOff = fs.Position; var packed = new MemoryStream(); uint rowsDone = 0;
        for (int s = 0; s < p.SOff.Length && rowsDone < p.H; s++) {
          uint rows = Math.Min(p.Rps, p.H - rowsDone); var raw = Inflate(t, p.SOff[s], p.SCnt[s], (int)(rows * rowBytes));
          for (uint y = 0; y < rows; y++) {
            int o = (int)(y * rowBytes);
            if (p.Fill == 2) for (int x = 0; x < rowBytes; x++) { byte b = raw[o + x]; b = (byte)(((b * 0x0802u & 0x22110u) | (b * 0x8020u & 0x88440u)) * 0x10101u >> 16); raw[o + x] = b; }
            if (p.Pred == 2) for (int x = 1; x < rowBytes; x++) raw[o + x] += raw[o + x - 1];
            PackRow(raw, o, rowBytes, packed);
          }
          rowsDone += rows;
        }
        packed.Position = 0; packed.CopyTo(fs); long stripLen = fs.Position - stripOff; if ((fs.Position & 1) == 1) w.Write((byte)0);
        long xr = fs.Position; w.Write(p.XrN); w.Write(p.XrD); long yr = fs.Position; w.Write(p.YrN); w.Write(p.YrD);
        long ifd = fs.Position; fs.Position = prevNext; w.Write((uint)ifd); fs.Position = ifd;
        int entries = 14 + (p.PageNo >= 0 ? 1 : 0); w.Write((ushort)entries);
        En(w, 256, 4, 1, p.W); En(w, 257, 4, 1, p.H); En(w, 258, 3, 1, (uint)p.Bps); En(w, 259, 3, 1, 32773); En(w, 262, 3, 1, (uint)p.Photo); En(w, 266, 3, 1, 1);
        En(w, 273, 4, 1, (uint)stripOff); En(w, 277, 3, 1, 1); En(w, 278, 4, 1, p.H); En(w, 279, 4, 1, (uint)stripLen); En(w, 282, 5, 1, (uint)xr); En(w, 283, 5, 1, (uint)yr); En(w, 284, 3, 1, 1); En(w, 296, 3, 1, (uint)p.ResUnit);
        if (p.PageNo >= 0) { w.Write((ushort)297); w.Write((ushort)3); w.Write((uint)2); w.Write((ushort)p.PageNo); w.Write((ushort)(p.PageTot >= 0 ? p.PageTot : pages.Count)); }
        prevNext = fs.Position; w.Write((uint)0);
      }
    }
  }
  static void En(BinaryWriter w, int tag, int type, uint count, uint val) { w.Write((ushort)tag); w.Write((ushort)type); w.Write(count); if (type == 3 && count == 1) { w.Write((ushort)val); w.Write((ushort)0); } else w.Write(val); }
  static void PackRow(byte[] b, int off, int len, Stream o) {
    int i = 0; while (i < len) {
      int run = 1; while (i + run < len && b[off + i + run] == b[off + i] && run < 128) run++;
      if (run >= 2) { o.WriteByte((byte)(257 - run)); o.WriteByte(b[off + i]); i += run; continue; }
      int lit = 1; while (i + lit < len && lit < 128 && !(i + lit + 1 < len && b[off + i + lit] == b[off + i + lit + 1])) lit++;
      o.WriteByte((byte)(lit - 1)); o.Write(b, off + i, lit); i += lit;
    }
  }
  static void Dump(string tif, string outPath) {
    using (var img = Image.FromFile(tif)) using (var o = new FileStream(outPath, FileMode.Create)) {
      int frames = 1; try { frames = img.GetFrameCount(FrameDimension.Page); } catch { }
      for (int p = 0; p < frames; p++) { if (frames > 1) img.SelectActiveFrame(FrameDimension.Page, p);
        using (var n = new Bitmap(img.Width, img.Height, PixelFormat.Format32bppArgb)) { using (var g = Graphics.FromImage(n)) g.DrawImage(img, 0, 0, img.Width, img.Height);
          var bd = n.LockBits(new Rectangle(0, 0, n.Width, n.Height), ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb); var buf = new byte[bd.Stride * n.Height]; Marshal.Copy(bd.Scan0, buf, 0, buf.Length); n.UnlockBits(bd); o.Write(buf, 0, buf.Length); } }
      Console.WriteLine("dumped frames=" + frames + " " + img.Width + "x" + img.Height);
    }
  }
}
CSEOF
if [ ! -f "$C/eapp-mac/repair/FormRepair.exe" ] || ! cmp -s "$C/eapp-mac/repair/FormRepair.cs" "$C/eapp-mac/repair/FormRepair.built" 2>/dev/null; then
  run "$WINE" 'C:\windows\Microsoft.NET\Framework\v4.0.30319\csc.exe' /nologo /platform:x86 /target:exe '/out:C:\eapp-mac\repair\FormRepair.exe' /r:System.Drawing.dll 'C:\eapp-mac\repair\FormRepair.cs'
  [ -f "$C/eapp-mac/repair/FormRepair.exe" ] || die "The page repair tool did not build. Send the log file to your administrator."
  cp -f "$C/eapp-mac/repair/FormRepair.cs" "$C/eapp-mac/repair/FormRepair.built"
fi
ok "Repair tool ready"
if [ -d "$C/Program Files (x86)/AIL/eApp/forms" ]; then
  say "    Checking form pages. This can take a few minutes the first time."
  "$WINE" 'C:\eapp-mac\repair\FormRepair.exe' 'C:\Program Files (x86)\AIL\eApp\forms' >> "$LOG" 2>&1
  ok "$(grep -E '^done' "$LOG" | tail -1 | sed 's/done //')"
else
  ok "No form pages yet (they arrive with eApp's first update)"
fi
stop_engine

# ------------------------------------------------------------- 5. Self-test
step "Step 7 of 8  Testing that Windows programs like eApp can run"
cat > "$C/SelfTest.cs" <<'CS'
using System; using System.IO; using System.Windows.Forms;
class T { [STAThread] static void Main() {
  File.WriteAllText(@"C:\selftest.txt", "started\n");
  var f = new Form { Text = "eApp self-test", Width = 320, Height = 120, StartPosition = FormStartPosition.CenterScreen };
  f.Controls.Add(new Label { Text = "Checking... this closes by itself.", Dock = DockStyle.Fill });
  var t = new Timer { Interval = 3000 }; t.Tick += (s, e) => { File.AppendAllText(@"C:\selftest.txt", "ok\n"); Application.Exit(); }; t.Start();
  Application.Run(f); } }
CS
rm -f "$C/selftest.txt" "$C/SelfTest.exe"
run "$WINE" 'C:\windows\Microsoft.NET\Framework\v4.0.30319\csc.exe' /nologo /target:winexe /platform:x86 '/out:C:\SelfTest.exe' /r:System.Windows.Forms.dll /r:System.Drawing.dll 'C:\SelfTest.cs'
[ -f "$C/SelfTest.exe" ] || die "The .NET compiler did not run. Send the log file to your administrator."
"$WINE" 'C:\SelfTest.exe' >> "$LOG" 2>&1 &
for i in $(seq 1 12); do sleep 5; grep -q ok "$C/selftest.txt" 2>/dev/null && break; done
grep -q ok "$C/selftest.txt" 2>/dev/null || die "A test Windows program could not start. eApp will not run on this setup. Send the log file to your administrator."
stop_engine; rm -f "$C/SelfTest.cs" "$C/SelfTest.exe" "$C/selftest.txt"
ok "A 32-bit Windows program started, drew a window, and exited"

# ----------------------------------------------------------------- 6. eApp
step "Step 8 of 8  Installing eApp"
if [ -f "$C/Program Files (x86)/AIL/eApp/eAPP.exe" ]; then ok "eApp is already installed"
else
  MSI=""
  for c in "$HOME/Downloads"/eAppSetup*.msi "$HOME/Downloads"/eappSetup*.msi "$HOME/Downloads"/*eapp*.msi "$HOME/Desktop"/eAppSetup*.msi; do
    [ -f "$c" ] && MSI="$c" && break
  done
  if [ -z "$MSI" ]; then
    say ""; say "  I could not find the eApp installer."; say ""
    say "  1. Download eAppSetup.msi from AIL, the same way you would on a Windows computer."
    say "  2. Leave it in your Downloads folder."
    say "  3. Run this installer again."; say ""
    printf "Press Return to close this window. "; read -r _; exit 0
  fi
  ok "Found $(basename "$MSI")"
  cp -f "$MSI" "$C/eappSetup.msi" || die "Could not copy the eApp installer."
  say "    Installing eApp. Follow any windows that appear."
  stop_engine
  "$WINE" msiexec.exe /i 'C:\eappSetup.msi' /qb >> "$LOG" 2>&1
  rm -f "$C/eappSetup.msi"
  [ -f "$C/Program Files (x86)/AIL/eApp/eAPP.exe" ] || die "eApp did not install. Send the log file to your administrator."
  ok "eApp installed"
fi
stop_engine

# -------------------------------------------------------------- Launcher
step "Creating the eApp icon"
rm -rf "$APPDIR" 2>/dev/null
mkdir -p "$APPDIR/Contents/MacOS"
cat > "$APPDIR/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>eApp</string>
  <key>CFBundleDisplayName</key><string>eApp</string>
  <key>CFBundleIdentifier</key><string>com.ail.eapp.mac</string>
  <key>CFBundleVersion</key><string>2.0</string>
  <key>CFBundleExecutable</key><string>eApp</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSMinimumSystemVersion</key><string>12.0</string>
</dict></plist>
PLIST
cat > "$APPDIR/Contents/MacOS/eApp" <<LAUNCH
#!/bin/bash
EAPP_HOME="$EAPP_HOME"
export WINEPREFIX="\$EAPP_HOME/prefix"
export WINEDEBUG=-all
export DYLD_FALLBACK_LIBRARY_PATH="\$EAPP_HOME/engine"
CXE="\$EAPP_HOME/engine/wswine.bundle"
# eApp for Mac is included with Tally. Confirm the subscription on every start.
# Offline is fine for 7 days after the last successful check.
. "\$EAPP_HOME/tally-gate.sh"
gate_check_or_signin || exit 1
# eApp leaves background processes behind. Clearing them first prevents an
# "AbandonedMutexException" error on the next start. Scoped to eApp's own
# environment by WINEPREFIX, so nothing else is touched.
"\$CXE/bin/wineserver" -k 2>/dev/null
sleep 2
cd "\$WINEPREFIX/drive_c"
# Rewrite any Deflate-compressed form pages the engine cannot read. Fast when there is nothing to do.
repair_pages() {
  [ -f "\$WINEPREFIX/drive_c/eapp-mac/repair/FormRepair.exe" ] && [ -d "\$WINEPREFIX/drive_c/Program Files (x86)/AIL/eApp/forms" ] \\
    && "\$CXE/bin/wine" 'C:\\eapp-mac\\repair\\FormRepair.exe' 'C:\\Program Files (x86)\\AIL\\eApp\\forms' >> "\$HOME/Library/Logs/eApp-Mac-Repair.log" 2>&1
}
repair_pages
# eApp's self-update replaces form pages after sign-in. Keep checking for the first 40 minutes.
( for i in \$(seq 1 40); do sleep 60; repair_pages; done ) >/dev/null 2>&1 &
exec "\$CXE/bin/wine" 'C:\\Program Files (x86)\\AIL\\eApp\\eAPP.exe'
LAUNCH
chmod +x "$APPDIR/Contents/MacOS/eApp"
ok "eApp is now in your Applications folder"

cat <<'DONE'

--------------------------------------------------
  FINISHED
--------------------------------------------------
Open eApp from your Applications folder, or from
Launchpad, the same as any other Mac app.

The first time you sign in, eApp downloads a 3 GB
update, then closes and reopens itself. That takes
10 to 20 minutes. It is normal. Leave it alone.
--------------------------------------------------

DONE
printf "Press Return to close this window. "; read -r _
