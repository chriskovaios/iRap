@echo off
rem Starts the Lyrics app at http://localhost:8765/ and opens it in your browser.
rem Use this instead of double-clicking index.html when you want the browser to remember
rem folder permissions ("Allow on every visit"). Nothing is installed; the tiny server is
rem Windows' own PowerShell and stops by itself about 90 seconds after you close the tab.
start "" /min powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0serve.ps1"
