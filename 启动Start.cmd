@echo off
setlocal
chcp 65001 >nul
set "branchShell=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if not exist "%branchShell%" (
  echo Windows PowerShell 5.1 is required. See README.md.
  pause
  exit /b 1
)
set "branchAction=%~1"
if not defined branchAction set "branchAction=Enable"
"%branchShell%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0branch-switch.ps1" -Action "%branchAction%" -PauseAtEnd
set "branchExit=%errorlevel%"
exit /b %branchExit%
