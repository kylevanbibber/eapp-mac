# eApp for Mac

Run AIL eApp on a Mac. No Windows, no Boot Camp, nothing to buy.
Included with an active [Tally](https://callwithtally.com) subscription.

## Install

**[Download Install-eApp.dmg](https://github.com/kylevanbibber/eapp-mac/releases/latest/download/Install-eApp.dmg)**

1. Download `eAppSetup.msi` from AIL, the same way you would on Windows. Leave it in your Downloads folder.
2. Open the DMG and double-click **Install eApp**.
3. A Terminal window opens. First it asks you to sign in to Tally. Then it does the rest by itself. It takes 20 to 40 minutes. Leave it alone until it says FINISHED.
4. Open **eApp** from your Applications folder.

The first time you sign in to eApp, it downloads a 3 GB update and reopens itself. That takes 10 to 20 minutes. It is normal.

## Requirements

- macOS 12 or newer, Apple Silicon or Intel
- About 20 GB of free disk space
- An active Tally subscription (your own, or your team's)
- Internet during install and for the first eApp sign-in. After that, eApp works offline for up to 7 days at a time.

## If something goes wrong

The log is at `~/Library/Logs/eApp-Mac-Setup.log`. Send it to your administrator.
You can run **Install eApp** again at any time. It skips the steps that are already done.

## How it works

The installer builds a private Windows environment using a free build of the open-source Wine engine
that CrossOver publishes (LGPL, via the [Sikarugir](https://github.com/Sikarugir-App) project), installs
Microsoft .NET Framework 4.0 and 4.8 into it from Microsoft's own download servers, verifies that a 32-bit
.NET program can draw a window, then installs eApp from the MSI you downloaded from AIL. Nothing from AIL or
Microsoft is redistributed here.

Two parts of the engine are adjusted after it is unpacked. About one in ten eApp form pages is a
Deflate-compressed TIFF the engine cannot read, so a small tool rewrites those pages pixel-identically
(see `src/FormRepair.cs`). And the engine's Windows Media Player control cannot pause or report a finished
seek, which left eApp's recruiting video stuck with no Continue button; a rebuilt copy of that control
(`bin/wmp.dll`, Wine 9.0 plus the patch in `patches/`) replaces it.

The subscription check is done by the Tally server on every start (your own subscription or your team's).
Download links for the engine are issued by Tally only to active accounts and expire after 15 minutes.
The sign-in token lives in your keychain; your password is never stored. If this Mac is offline, eApp keeps
opening until the allowance Tally issued last time runs out (7 days), then it needs to be online once.

## Building this installer

```
./build.sh 1.0      # signs with Developer ID
./notarize.sh       # notarizes + staples app and DMG (needs a notarytool keychain profile)
```

## License

All rights reserved for the installer and its scripts. The source is visible for review and support; it may not be copied, modified, or redistributed. Wine is LGPL 2.1 or later and is downloaded at install time from its publishers; the one Wine component shipped here, `bin/wmp.dll`, stays under the LGPL, with its source in `patches/`. Nothing from AIL or Microsoft is redistributed here.
