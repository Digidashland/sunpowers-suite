@echo off
chcp 65001 >nul
title Sunpowers - GitHub upload
cd /d "%~dp0"
echo ============================================
echo   SUNPOWERS  -  GitHub par upload
echo   Repo: github.com/Suraj4048/sunpowers-suite
echo ============================================
echo.
where git >nul 2>nul
if errorlevel 1 (
  echo [X] Git install nahi hai.
  echo     https://git-scm.com/download/win  se install karein, phir is file par dobara double-click karein.
  pause
  exit /b 1
)
if not exist ".git" git init -b main
git config user.name "Suraj Anand"
git config user.email "surajanandpbh@gmail.com"
git checkout -B main >nul 2>nul
git add -A
git commit -q -m "Sunpowers update %date% %time%"
git remote remove origin >nul 2>nul
git remote add origin https://github.com/Suraj4048/sunpowers-suite.git
echo.
echo GitHub par bhej rahe hain... (pehli baar GitHub login ki window khul sakti hai - login karein)
git push -u origin main
if errorlevel 1 (
  echo.
  echo [X] Upload nahi hua. Upar ka laal / error wala hissa ka screenshot Claude ko bhejein.
  echo     Aam wajah: GitHub par "sunpowers-suite" naam ka KHAALI private repo pehle nahi bana.
  pause
  exit /b 1
)
echo.
echo [OK] Upload ho gaya!  https://github.com/Suraj4048/sunpowers-suite
echo      Ab Vercel me 4 project banane hain (Claude ke steps).
pause
