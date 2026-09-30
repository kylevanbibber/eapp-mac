-- Install eApp: opens Terminal and runs the bundled installer script.
-- The script runs through bash inside Terminal, so Launch Services never
-- opens it directly and Gatekeeper judges only this signed, notarized app.
set scriptPath to POSIX path of (path to resource "install.sh")
tell application "Terminal"
	activate
	do script "clear; exec /bin/bash " & quoted form of scriptPath
end tell
