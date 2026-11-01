#!/bin/zsh
# vmx.sh <script.ps1 under build/vm or windows/> [args…]: resume the VM if it was suspended, run the script as the user.
st=$(prlctl list -o status "Windows 11" | tail -1 | tr -d ' ')
if [ "$st" != "running" ]; then prlctl resume "Windows 11" >/dev/null 2>&1 || prlctl start "Windows 11" >/dev/null; sleep 6; fi
f=$1; shift
prlctl exec "Windows 11" --current-user powershell -ExecutionPolicy Bypass -File "$f" "$@"
