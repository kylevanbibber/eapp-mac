# Tally subscription gate for eApp for Mac. Sourced by the installer and by the eApp launcher.
# The decision is made by the Tally server (personal subscription OR active team). The server also
# issues the offline allowance: eApp keeps opening until "expiresAt", then needs to be online once.
TALLY_API="${TALLY_API:-https://api.callwithtally.com}"
GATE_SERVICE="eApp Mac (Tally)"
GATE_STATE="${GATE_STATE:-$EAPP_HOME/tally-gate.state}"   # non-secret: email|expires_epoch|via
GATE_VERSION="${GATE_VERSION:-1.2}"

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
