@echo off
setlocal EnableDelayedExpansion

set "SCRIPT_DIR=%~dp0"
if "%SCRIPT_DIR:~-1%"=="\" set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"
for %%I in ("%SCRIPT_DIR%") do set "CUR_NAME=%%~nxI"

if /i "%CUR_NAME%"=="src" (
    cd /d "%SCRIPT_DIR%\.."
) else (
    cd /d "%SCRIPT_DIR%"
)

:: 1. Compile source files
call "%~dp0build_run_resize.bat" --compile-only
if %errorlevel% neq 0 exit /b 1

for %%C in ("%MAIN_CLASS%") do set "APP_NAME=%%~xC"
if defined APP_NAME (
    set "APP_NAME=%APP_NAME:~1%"
) else (
    set "APP_NAME=%MAIN_CLASS%"
)

:: 2. Locate jar.exe
where jar >nul 2>&1
if %errorlevel% equ 0 (
    set "JAVA_BIN="
    goto :merge_libs
)

set "JAVA_BIN="
for /d %%D in ("%USERPROFILE%\.jdks\*") do (
    if exist "%%D\bin\jar.exe" set "JAVA_BIN=%%D\bin\"
)

:merge_libs
:: Extract all external JARs from lib\ into build\ to create a Fat JAR
if exist "lib\" (
    echo Merging external libraries from lib\...
    pushd "build"
    for %%J in ("..\lib\*.jar") do (
        "%JAVA_BIN%jar.exe" xf "%%J"
    )
    :: Remove signature files from merged JARs to prevent SecurityException
    if exist "META-INF\*.SF" del /q "META-INF\*.SF"
    if exist "META-INF\*.DSA" del /q "META-INF\*.DSA"
    if exist "META-INF\*.RSA" del /q "META-INF\*.RSA"
    popd
)

echo Creating manifest for !MAIN_CLASS!...
(
echo Main-Class: !MAIN_CLASS!
echo.
) > "build\manifest.txt"

echo Packaging Fat JAR: JAR\!APP_NAME!.jar...
if not exist "JAR\" mkdir "JAR"
"%JAVA_BIN%jar.exe" cfm "JAR\!APP_NAME!.jar" "build\manifest.txt" -C "build" .

rmdir /s /q "build"

echo Success - JAR\!APP_NAME!.jar is ready.

if /i "%~1"=="--no-pause" (
    endlocal & set "MAIN_CLASS=%MAIN_CLASS%" & set "APP_NAME=%APP_NAME%"
    exit /b 0
)
pause
