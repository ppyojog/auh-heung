@echo off
setlocal enabledelayedexpansion
cd /d "%~dp0"
set "LOG=%~dp0deploy_log.txt"

echo ============================================
echo    AuhHeung deploy to GitHub Pages
echo ============================================
echo.

REM ---- write log header (overwrite each run) ----
echo ================================================== > "%LOG%"
echo  AuhHeung deploy log  %date% %time% >> "%LOG%"
echo  folder: %~dp0 >> "%LOG%"
echo ================================================== >> "%LOG%"

REM ---- 0) git installed? ----
where git >nul 2>&1
if errorlevel 1 (
  echo [ERROR] 'git' not found in PATH.
  echo [ERROR] git not found in PATH >> "%LOG%"
  echo Fix: install git ^(winget install --id Git.Git -e^) then reopen terminal.
  echo Fix: install git, reopen terminal >> "%LOG%"
  goto :end_fail
)
for /f "delims=" %%v in ('git --version') do echo [git] %%v >> "%LOG%"

REM ---- is this a git repo? ----
git rev-parse --is-inside-work-tree >nul 2>&1
if errorlevel 1 (
  echo [ERROR] This folder is not a git repository yet.
  echo [ERROR] not a git repo - run first-time setup >> "%LOG%"
  echo Run first-time setup once ^(git init / remote add / push^).
  goto :end_fail
)

REM ---- 1) add ----
echo [1/3] git add .
echo. >> "%LOG%"
echo ----- [1/3] git add . ----- >> "%LOG%"
git add . >> "%LOG%" 2>&1

REM ---- 2) commit ----
echo [2/3] git commit
echo. >> "%LOG%"
echo ----- [2/3] git commit ----- >> "%LOG%"
git commit -m "update %date% %time%" >> "%LOG%" 2>&1
set "COMMIT_CODE=%errorlevel%"
echo [commit exit code] %COMMIT_CODE% >> "%LOG%"

REM ---- 3) push ----
echo [3/3] git push
echo. >> "%LOG%"
echo ----- [3/3] git push ----- >> "%LOG%"
git push >> "%LOG%" 2>&1
set "PUSH_CODE=%errorlevel%"
echo [push exit code] %PUSH_CODE% >> "%LOG%"

REM ---- status snapshot ----
echo. >> "%LOG%"
echo ----- git status ----- >> "%LOG%"
git status >> "%LOG%" 2>&1
echo. >> "%LOG%"
echo ----- last commit ----- >> "%LOG%"
git log -1 --oneline >> "%LOG%" 2>&1

echo.
if not "%PUSH_CODE%"=="0" (
  echo [FAILED] git push failed ^(exit code %PUSH_CODE%^).
  echo --------------------------------------------
  echo  Showing log below. Full file: deploy_log.txt
  echo --------------------------------------------
  type "%LOG%"
  goto :end_fail
)

echo --------------------------------------------
echo  [OK] Pushed to GitHub.
echo  GitHub now builds in the cloud ^(2-4 min^).
echo  Live link:  https://ppyojog.github.io/auh-heung/
echo  Build status: Actions tab on github.com
echo  ^(If the site does not update, the CLOUD BUILD may
echo   have failed - open Actions, click the red run,
echo   open the 'build' step, copy the red error.^)
echo --------------------------------------------
echo  Log saved: %LOG%
echo.
pause
exit /b 0

:end_fail
echo.
echo  Log saved: %LOG%
echo  ^(Send deploy_log.txt if you need help.^)
echo.
pause
exit /b 1
