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
