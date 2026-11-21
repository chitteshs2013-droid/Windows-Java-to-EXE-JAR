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

if not exist "src\" (
    echo Error: Could not find a 'src' folder in %CD%.
    pause
    exit /b 1
)

for %%P in ("%CD%") do set "PROJECT_NAME=%%~nxP"

:: 1. Auto-detect Main-Class
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

for %%C in ("%MAIN_CLASS%") do set "JAR_BASE=%%~xC"
if defined JAR_BASE (
    set "JAR_BASE=%JAR_BASE:~1%"
) else (
    set "JAR_BASE=%MAIN_CLASS%"
)

set "JAR_PATH=JAR\!JAR_BASE!.jar"

:: 2. Check if JAR needs rebuilding
set "NEED_JAR=0"
if not exist "!JAR_PATH!" (
    echo !JAR_PATH! not found. Building Fat JAR first...
    set "NEED_JAR=1"
) else (
    for /f %%I in ('powershell -NoProfile -Command ^
      "$jarTime = (Get-Item '!JAR_PATH!').LastWriteTime; " ^
      "$newerCode = Get-ChildItem -Path 'src' -Filter *.java -Recurse | Where-Object { $_.LastWriteTime -gt $jarTime }; " ^
      "$newerRes = if (Test-Path 'res') { Get-ChildItem -Path 'res' -Recurse -File | Where-Object { $_.LastWriteTime -gt $jarTime } } else { $null }; " ^
      "$newerLib = if (Test-Path 'lib') { Get-ChildItem -Path 'lib' -Filter *.jar -Recurse | Where-Object { $_.LastWriteTime -gt $jarTime } } else { $null }; " ^
      "if ($newerCode -or $newerRes -or $newerLib) { Write-Output 1 } else { Write-Output 0 }"') do (
        set "NEED_JAR=%%I"
    )
    if "!NEED_JAR!"=="1" (
        echo Changes detected. Rebuilding Fat JAR first...
    ) else (
        echo !JAR_PATH! is up to date. Skipping compilation...
    )
)

if "!NEED_JAR!"=="1" (
    call "%~dp0build_jar.bat" --no-pause
    if not exist "!JAR_PATH!" (
        echo Failed to generate !JAR_PATH!.
        pause
        exit /b 1
    )
)

:: 3. Locate JDK root folder
set "JAVAC_EXE="
for /f "delims=" %%P in ('where javac 2^>nul') do (
    if not defined JAVAC_EXE set "JAVAC_EXE=%%P"
)
if not defined JAVAC_EXE (
    for /d %%D in ("%USERPROFILE%\.jdks\*") do (
        if exist "%%D\bin\javac.exe" set "JAVAC_EXE=%%D\bin\javac.exe"
    )
)
if not defined JAVAC_EXE (
    echo Could not find JDK in PATH or %USERPROFILE%\.jdks
    pause
    exit /b 1
)

for %%F in ("%JAVAC_EXE%") do set "JAVA_BIN=%%~dpF"
for %%F in ("%JAVA_BIN%..") do set "JDK_HOME=%%~fF"

:: 4. Build temporary staging folder
set "STAGE_DIR=%CD%\build_exe_temp"
if exist "!STAGE_DIR!\" rmdir /s /q "!STAGE_DIR!"
mkdir "!STAGE_DIR!"

if exist "%JAVA_BIN%jlink.exe" (
    echo Bundling compact Java runtime...
    "%JAVA_BIN%jlink.exe" --add-modules java.se,jdk.unsupported,jdk.crypto.ec --strip-debug --no-man-pages --no-header-files --compress=zip-6 --output "!STAGE_DIR!\runtime" 2>nul
    if not exist "!STAGE_DIR!\runtime\bin\javaw.exe" (
        "%JAVA_BIN%jlink.exe" --add-modules java.se,jdk.unsupported,jdk.crypto.ec --strip-debug --no-man-pages --no-header-files --output "!STAGE_DIR!\runtime"
    )
)
if not exist "!STAGE_DIR!\runtime\bin\javaw.exe" (
    echo Copying JDK runtime...
    xcopy /s /e /y /q "!JDK_HOME!\*" "!STAGE_DIR!\runtime\" >nul
)

echo Compressing runtime for single-file embedding...
set "STAGE_RT=!STAGE_DIR!\runtime"
set "STAGE_ZIP=!STAGE_DIR!\runtime.zip"
powershell -NoProfile -Command ^
  "Add-Type -AssemblyName System.IO.Compression.FileSystem; " ^
  "[System.IO.Compression.ZipFile]::CreateFromDirectory($env:STAGE_RT, $env:STAGE_ZIP, [System.IO.Compression.CompressionLevel]::Optimal, $false)"

if not exist "!STAGE_ZIP!" (
    echo Failed to compress runtime.zip.
    pause
    exit /b 1
)

for /f %%H in ('powershell -NoProfile -Command "[guid]::NewGuid().ToString('N')"') do set "BUILD_ID=%%H"

:: 5. Write self-extracting C# Launcher
set "CSC_EXE=%SystemRoot%\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
if not exist "!CSC_EXE!" set "CSC_EXE=%SystemRoot%\Microsoft.NET\Framework\v4.0.30319\csc.exe"

set "LAUNCHER_CS=!STAGE_DIR!\Launcher.cs"
(
echo using System;
echo using System.Diagnostics;
echo using System.IO;
echo using System.IO.Compression;
echo using System.Reflection;
echo using System.Windows.Forms;
echo class Program {
echo     [STAThread]
echo     static void Main^(string[] args^) {
echo         try {
echo             string buildId = "!BUILD_ID!";
echo             string rootCache = Path.Combine^(Environment.GetFolderPath^(Environment.SpecialFolder.LocalApplicationData^), "!PROJECT_NAME!_Runtime"^);
echo             string appCache = Path.Combine^(rootCache, buildId^);
echo             string runtimeDir = Path.Combine^(appCache, "runtime"^);
echo             string jar = Path.Combine^(appCache, "app.jar"^);
echo             string flagFile = Path.Combine^(appCache, ".ready"^);
echo.
echo             // Always ensure base folders exist first before checking files
echo             Directory.CreateDirectory^(rootCache^);
echo             Directory.CreateDirectory^(appCache^);
echo             Directory.CreateDirectory^(runtimeDir^);
echo.
echo             string[] existingJavaw = Directory.GetFiles^(runtimeDir, "javaw.exe", SearchOption.AllDirectories^);
echo             if ^(!File.Exists^(flagFile^) ^|^| !File.Exists^(jar^) ^|^| existingJavaw.Length == 0^) {
echo                 // Clean up older build folders
echo                 foreach ^(string dir in Directory.GetDirectories^(rootCache^)^) {
echo                     if ^(!string.Equals^(dir, appCache, StringComparison.OrdinalIgnoreCase^)^) {
echo                         try { Directory.Delete^(dir, true^); } catch { }
echo                     }
echo                 }
echo.
echo                 // Reset current cache folder cleanly
echo                 if ^(Directory.Exists^(runtimeDir^)^) Directory.Delete^(runtimeDir, true^);
echo                 Directory.CreateDirectory^(appCache^);
echo.
echo                 Assembly asm = Assembly.GetExecutingAssembly^(^);
echo                 using ^(Stream s = asm.GetManifestResourceStream^("app.jar"^)^) {
echo                     if ^(s == null^) throw new Exception^("Embedded app.jar resource missing."^);
echo                     using ^(FileStream fs = File.Create^(jar^)^) { s.CopyTo^(fs^); }
echo                 }
echo.
echo                 string zipPath = Path.Combine^(appCache, "runtime.zip"^);
echo                 using ^(Stream s = asm.GetManifestResourceStream^("runtime.zip"^)^) {
echo                     if ^(s == null^) throw new Exception^("Embedded runtime.zip resource missing."^);
echo                     using ^(FileStream fs = File.Create^(zipPath^)^) { s.CopyTo^(fs^); }
echo                 }
echo.
echo                 // ExtractToDirectory creates runtimeDir itself
echo                 ZipFile.ExtractToDirectory^(zipPath, runtimeDir^);
echo                 File.Delete^(zipPath^);
echo                 File.WriteAllText^(flagFile, "ok"^);
echo             }
echo.
echo             string[] found = Directory.GetFiles^(runtimeDir, "javaw.exe", SearchOption.AllDirectories^);
echo             if ^(found.Length == 0^) throw new Exception^("javaw.exe not found inside: " + runtimeDir^);
echo             string javaw = found[0];
echo.
echo             string argLine = "-jar \"" + jar + "\"";
echo             if ^(args.Length ^> 0^) argLine += " " + string.Join^(" ", args^);
echo             ProcessStartInfo psi = new ProcessStartInfo^(javaw, argLine^);
echo             psi.WorkingDirectory = AppDomain.CurrentDomain.BaseDirectory;
echo             psi.UseShellExecute = false;
echo             Process.Start^(psi^);
echo         } catch ^(Exception ex^) {
echo             MessageBox.Show^("Failed to start application:\n" + ex.Message, "!PROJECT_NAME!", MessageBoxButtons.OK, MessageBoxIcon.Error^);
echo         }
echo     }
echo }
) > "!LAUNCHER_CS!"

set "ICON_OPT="
if exist "res\icon.ico" set "ICON_OPT=/win32icon:"res\icon.ico""

if not exist "EXE\" mkdir "EXE"
set "FINAL_EXE=EXE\!PROJECT_NAME!.exe"

echo Compiling single standalone EXE...
"!CSC_EXE!" /nologo /target:winexe ^
  /reference:System.Windows.Forms.dll ^
  /reference:System.IO.Compression.dll ^
  /reference:System.IO.Compression.FileSystem.dll ^
  /resource:"!JAR_PATH!",app.jar ^
  /resource:"!STAGE_ZIP!",runtime.zip ^
  /out:"!FINAL_EXE!" !ICON_OPT! "!LAUNCHER_CS!"

if %errorlevel% neq 0 (
    echo C# compiler failed!
    pause
    exit /b 1
)

rmdir /s /q "!STAGE_DIR!"

if not exist "!FINAL_EXE!" (
    echo Failed to compile standalone EXE.
    pause
    exit /b 1
)

echo.
echo Success! Single standalone EXE is ready:
echo - !FINAL_EXE!
pause
