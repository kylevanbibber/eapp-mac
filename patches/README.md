# patches

## wine-9.0-wmp-pause.patch

Why: eApp plays its recruiting and product videos through a WPF `MediaElement`.
WPF drives the Windows Media Player control (`wmp.dll`) like this: play, wait
for the playing state, pause, seek to 0, wait for a `PositionChange` event,
then play again. Wine 9.0's `wmp.dll` (the engine the installer uses is
CrossOver 24.0.7's engine, Wine 9.0 based) returns `E_NOTIMPL` for `pause()`
and for `isAvailable("pause")`, and never sends `PositionChange`. WPF therefore
stops after opening the file. The video never starts, and eApp never shows the
Continue button, because that button appears only when the slider reaches the
end of the video.

What the patch does (dlls/wmp/player.c, wmp_private.h):

- `IWMPControls::pause` pauses the DirectShow graph and reports `wmppsPaused`.
- `IWMPControls::get_isAvailable` answers true for `pause`, `play` and `stop`
  once a graph exists.
- `IWMPControls::put_currentPosition` sends `PositionChange(old, new)` after a
  successful seek.
- `IWMPPlayer4::get_playState` / `get_openState` return the last reported state
  (were `E_NOTIMPL`).

Verified with a WPF `MediaElement` test program on the real recruiting video:
opens in 9 s, pause and resume hold the position, seek works, `MediaEnded`
fires, and `Position` equals `NaturalDuration` at the end.

## Rebuilding bin/wmp.dll

Tools: Xcode command line tools, Rosetta 2, Homebrew `mingw-w64` and `bison`.

```sh
curl -LO https://dl.winehq.org/wine/source/9.0/wine-9.0.tar.xz
tar xJf wine-9.0.tar.xz && cd wine-9.0
patch -p1 < ../patches/wine-9.0-wmp-pause.patch
export PATH="/opt/homebrew/opt/bison/bin:/opt/homebrew/bin:$PATH"
arch -x86_64 ./configure CC="clang -arch x86_64" CXX="clang++ -arch x86_64" \
  --enable-archs=i386 --without-x --without-freetype --disable-tests \
  --without-cups --without-opencl --without-gstreamer --without-vulkan --without-sdl \
  --without-gphoto --without-usb --without-pcap --without-netapi --without-krb5 \
  --without-gssapi --without-pulse --without-dbus --without-unwind --without-coreaudio \
  --without-opengl --without-gnutls --without-fontconfig --without-xml --without-xslt
arch -x86_64 make -j8 dlls/wmp/i386-windows/wmp.dll
i686-w64-mingw32-strip dlls/wmp/i386-windows/wmp.dll
arch -x86_64 tools/winebuild/winebuild --builtin dlls/wmp/i386-windows/wmp.dll
cp dlls/wmp/i386-windows/wmp.dll ../bin/wmp.dll
shasum -a 256 ../bin/wmp.dll   # put this value in WMP_SHA in both install.sh files
```

The installer copies the file over `engine/wswine.bundle/lib/wine/i386-windows/wmp.dll`
and keeps the original as `wmp.dll.orig`.

## shell32-autocomplete-reentry.py

Why: eApp's text boxes use Windows auto-complete (append + suggest) with the values typed
before. When a typed key matches a saved value, Wine's `display_matching_strs()`
(dlls/shell32/autocomplete.c) appends the suggestion with `WM_SETTEXT`. eApp's masked text
boxes (dates, phone numbers) set the text again while they handle that change. The second
`WM_SETTEXT` reaches the auto-complete subclass, which frees the string list. Back in
`display_matching_strs()`, `find_matching_enum_str()` reads the freed list and the whole
program stops with a page fault at shell32+0x894c. Users saw eApp close while typing a date.

What the patch does: the second `find_matching_enum_str()` call goes through a 22-byte stub
placed in alignment padding. The stub checks that `ac->enum_strs` is still the list saved
before the text was set. If not, it leaves the function with TRUE and shows no list.

It is a binary patch of the engine's own `lib/wine/i386-windows/shell32.dll` (26 bytes), so
no modified Wine file is shipped. The installer applies the same bytes in place, only when
the file's SHA-256 is the expected one, and keeps the original as `shell32.dll.orig`.
The script documents the change and reproduces the patched file.

Verified with a WinForms test (text box with SuggestAppend and a TextChanged handler that
sets Text): page fault before, clean after, suggestions still shown. Verified in eApp on
the Diabetic Questionnaire date field.

## Default font (no patch, a registry setting)

eApp's form windows use the old WinForms `AutoScaleBaseSize` (5, 13) and scale their
contents by the default font's height. Wine maps `MS Shell Dlg` to Tahoma (height 14);
Windows uses Microsoft Sans Serif (height 13). A form that eApp opens without a parent
window was stretched by about 16% vertically, so fields sat below their boxes. The
installer sets `FontSubstitutes` `MS Shell Dlg` and `MS Shell Dlg 2` to
`Microsoft Sans Serif` (the font file is part of macOS).
