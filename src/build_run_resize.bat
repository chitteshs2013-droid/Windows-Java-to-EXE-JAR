@echo off
setlocal EnableDelayedExpansion

:: Determine project root (handles running from inside src\ OR from the parent project folder)
set "SCRIPT_DIR=%~dp0"
if "%SCRIPT_DIR:~-1%"=="\" set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"
for %%I in ("%SCRIPT_DIR%") do set "CUR_NAME=%%~nxI"

if /i "%CUR_NAME%"=="src" (
    cd /d "%SCRIPT_DIR%\.."
) else (
    cd /d "%SCRIPT_DIR%"
)

:: Verify that a 'src' folder exists in the project root
if not exist "src\" (
    echo Error: Could not find a 'src' folder in %CD%.
    pause
    exit /b 1
)

:: 1. Locate JDK (Global PATH first, then IntelliJ's .jdks folder)
set "JAVAC_EXE="
for /f "delims=" %%P in ('where javac 2^>nul') do (
    if not defined JAVAC_EXE set "JAVAC_EXE=%%P"
)
if not defined JAVAC_EXE (
    for /d %%D in ("%USERPROFILE%\.jdks\*") do (
        if exist "%%D\bin\javac.exe" (
            set "JAVAC_EXE=%%D\bin\javac.exe"
        )
    )
)

if not defined JAVAC_EXE (
    echo Could not find JDK in PATH or %USERPROFILE%\.jdks
    pause
    exit /b 1
)

for %%F in ("%JAVAC_EXE%") do set "JAVA_BIN=%%~dpF"

:detect_main
:: 2. Find the .java file containing psvm strictly inside 'src\'
set "MAIN_CLASS="
for /f "usebackq delims=" %%M in (`powershell -NoProfile -Command ^
  "$files = Get-ChildItem -Path 'src' -Filter *.java -Recurse; " ^
  "foreach ($f in $files) { " ^
  "  $txt = Get-Content $f.FullName -Raw; " ^
  "  if ($txt -match 'public\s+static\s+void\s+main\s*\(') { " ^
  "    $pkg = ''; " ^
  "    if ($txt -match '(?m)^\s*package\s+([\w\.]+)\s*;') { $pkg = $matches[1] + '.' } " ^
  "    Write-Output ($pkg + $f.BaseName); break " ^
  "  } " ^
  "}"`) do (
    set "MAIN_CLASS=%%M"
)

if not defined MAIN_CLASS (
    echo Error: Could not find any .java file with 'public static void main' inside src\.
    pause
    exit /b 1
)

:: 3. Build dynamic classpath (includes lib\*.jar if a lib folder exists)
set "APP_CP=build;."
if exist "lib\" (
    for %%J in ("lib\*.jar") do (
        set "APP_CP=!APP_CP!;%%J"
    )
)

:: 4. Prepare clean build folder and collect .java files strictly from 'src\'
if exist "build\" rmdir /s /q "build"
mkdir "build"

powershell -NoProfile -Command ^
  "Get-ChildItem -Path 'src' -Filter *.java -Recurse | " ^
  "ForEach-Object { '\"' + ($_.FullName -replace '\\', '/') + '\"' } | " ^
  "Set-Content -Path 'build\sources.txt' -Encoding ASCII"

echo Detected Main-Class: !MAIN_CLASS!
echo Compiling source files from src\...
"%JAVA_BIN%javac.exe" --release 21 -cp "!APP_CP!" -d "build" @"build\sources.txt"
if %errorlevel% neq 0 (
    echo Compilation failed.
    rmdir /s /q "build"
    pause
    exit /b 1
)
del "build\sources.txt"

:: 5. Copy entire res\ folder contents into build\ classpath root
if exist "res\" (
    xcopy /s /e /y /q "res\*" "build\" >nul
)

:: If called from build_jar.bat, export MAIN_CLASS and stop here
if /i "%~1"=="--compile-only" (
    endlocal & set "MAIN_CLASS=%MAIN_CLASS%" & set "APP_CP=%APP_CP%" & set "JAVA_BIN=%JAVA_BIN%"
    exit /b 0
)

:: Otherwise, launch app in background and clean up build\ when closed
start /b "" cmd /c ""%JAVA_BIN%javaw.exe" -cp "!APP_CP!" !MAIN_CLASS! & rmdir /s /q "build""