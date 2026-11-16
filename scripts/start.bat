@echo off
rem Cangmo launcher for Windows. Adjust CANGJIE_HOME if your SDK is elsewhere.
setlocal
set "CANGJIE_HOME=C:\Program Files (x86)\Cangjie"
if not exist "%CANGJIE_HOME%\bin\cjc.exe" (
  echo Cangjie SDK not found at %CANGJIE_HOME%.
  echo Edit %~f0 and set CANGJIE_HOME to your installation.
  exit /b 1
)
set "PATH=%CANGJIE_HOME%\runtime\lib\windows_x86_64_cjnative;%CANGJIE_HOME%\lib\windows_x86_64_cjnative;%CANGJIE_HOME%\bin;%CANGJIE_HOME%\tools\bin;%CANGJIE_HOME%\tools\lib;%PATH%"
cd /d "%~dp0.."
if not exist "target\release\bin\main.exe" (
  echo Building Cangmo...
  call cjpm build || exit /b 1
)
"target\release\bin\main.exe" serve %*
