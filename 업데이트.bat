@echo off
cd /d "%~dp0"

echo ============================================
echo    AuhHeung deploy to GitHub Pages
echo ============================================
echo.

git add .
git commit -m "update %date% %time%"
git push

echo.
echo --------------------------------------------
echo  Done. Live in 2-4 min at:
echo  https://ppyojog.github.io/auh-heung/
echo --------------------------------------------
pause
