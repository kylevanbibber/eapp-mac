# Form fix for eApp for Mac. Sourced by the installer and by the eApp launcher.
#
# On this engine a form page that was scrolled keeps its fields a few units too high, on screen and
# in the pages that go to DocuSign and to the home office. A small add-in that runs inside eApp
# (AtlasEappAddin) puts the fields back. The add-in is copied into the .NET assembly cache of
# eApp's environment and named in EappMain.exe.config, which is how .NET loads it.
#
# eApp's own update can replace that config file, so the launcher runs apply_form_fix on every
# start. If the add-in files are not in place, the config is put back to plain, so eApp always starts.
#
# Needs: EAPP_HOME.
FORM_FIX_VER="0.1.43"
FORM_FIX_TOKEN="6ff452385eecd907"

# apply_form_fix -> 0 the add-in is wired in, 1 it is not (eApp still starts, without the fix)
apply_form_fix() {
  local C="$EAPP_HOME/prefix/drive_c"
  local SRC="$EAPP_HOME/addin"
  local NET="$C/windows/Microsoft.NET/assembly"
  local G32="$NET/GAC_32/AtlasEappAddin/v4.0_${FORM_FIX_VER}.0__${FORM_FIX_TOKEN}"
  local GH="$NET/GAC_MSIL/0Harmony/v4.0_2.2.2.0__${FORM_FIX_TOKEN}"
  local CFG="$C/Program Files (x86)/AIL/eApp/EappMain.exe.config"
  [ -f "$CFG" ] || return 1
  if [ -s "$SRC/AtlasEappAddin.dll" ] && [ -s "$SRC/0Harmony.dll" ] && [ -d "$NET" ]; then
    mkdir -p "$G32" "$GH" 2>/dev/null
    cmp -s "$SRC/AtlasEappAddin.dll" "$G32/AtlasEappAddin.dll" || cp -f "$SRC/AtlasEappAddin.dll" "$G32/AtlasEappAddin.dll"
    cmp -s "$SRC/0Harmony.dll" "$GH/0Harmony.dll" || cp -f "$SRC/0Harmony.dll" "$GH/0Harmony.dll"
    if [ -s "$SRC/atlas-toolbar-icons.ttf" ] && [ -d "$C/windows/Fonts" ]; then
      cmp -s "$SRC/atlas-toolbar-icons.ttf" "$C/windows/Fonts/atlas-toolbar-icons.ttf" || cp -f "$SRC/atlas-toolbar-icons.ttf" "$C/windows/Fonts/atlas-toolbar-icons.ttf"
    fi
  fi
  local WANT="AtlasEappAddin, Version=${FORM_FIX_VER}.0, Culture=neutral, PublicKeyToken=${FORM_FIX_TOKEN}"
  if [ -s "$G32/AtlasEappAddin.dll" ] && [ -s "$GH/0Harmony.dll" ]; then
    grep -q "$WANT" "$CFG" 2>/dev/null && return 0
    cp -f "$CFG" "$CFG.form-fix.tmp" || return 1
    FF_WANT="$WANT" /usr/bin/perl -0pi -e '
      s/[ \t]*<appDomainManager(?:Assembly|Type)\b[^>]*>[ \t]*\r?\n//g;
      s/(<runtime>[^\n]*\n)/$1 . "    <appDomainManagerAssembly value=\"$ENV{FF_WANT}\" \/>\n    <appDomainManagerType value=\"AtlasEappAddin.AtlasAppDomainManager\" \/>\n"/e;
    ' "$CFG.form-fix.tmp" 2>/dev/null
    if grep -q "$WANT" "$CFG.form-fix.tmp" 2>/dev/null && grep -q "</configuration>" "$CFG.form-fix.tmp" 2>/dev/null; then
      mv -f "$CFG.form-fix.tmp" "$CFG" && return 0
    fi
    rm -f "$CFG.form-fix.tmp"
    return 1
  fi
  # The add-in is not in place: a config that names it would stop eApp from starting.
  if grep -q "appDomainManager" "$CFG" 2>/dev/null; then
    /usr/bin/perl -0pi -e 's/[ \t]*<appDomainManager(?:Assembly|Type)\b[^>]*>[ \t]*\r?\n//g' "$CFG" 2>/dev/null
  fi
  return 1
}
