# Java Build & Standalone EXE Packaging Scripts

A lightweight, zero-dependency Windows batch build system for Java desktop applications. It compiles Java 21 source code, merges external libraries into a Fat JAR, and packages a self-extracting standalone Windows `.exe` bundled with a stripped-down Java runtime—without requiring Maven, Gradle, or third-party wrapper tools.

---

## 📁 Expected Project Structure

Place the batch scripts either in the **project root** or inside the **`src\`** directory. The scripts automatically resolve the project root.

```text
YourProjectName/
├── src/                  # (Required) Java source files (.java)
│   └── com/example/
│       └── Main.java     # Must contain 'public static void main'
├── res/                  # (Optional) Assets copied to classpath root
│   └── icon.ico          # (Optional) Custom icon for the generated .exe
├── lib/                  # (Optional) External dependency .jar files
├── JAR/                  # (Generated) Output Fat JAR directory
├── EXE/                  # (Generated) Output standalone EXE directory
├── build_run.bat         # Compiles and launches the app
├── build_jar.bat         # Builds a runnable Fat JAR
└── build_exe.bat         # Builds a standalone Windows EXE with bundled JRE
```

---

## 🛠️ Prerequisites

* **Operating System:** Windows (uses Batch, PowerShell, and built-in .NET `csc.exe`)
* **JDK 21+:** Must be available in the system `PATH` or installed under `%USERPROFILE%\.jdks\` (standard IntelliJ IDEA JDK location).
* **.NET Framework 4.0+:** Pre-installed on modern Windows versions (used to compile the native C# launcher wrapper).

---

## 🚀 Usage

### 1. Compile & Run (`build_run.bat`)
Compiles all `.java` files inside `src\`, copies `res\` into the classpath, and runs the application in the background without a console window.
```cmd
build_run.bat
```
* **Arguments:** Pass `--compile-only` to compile into `build\` without launching the app.
* **Auto-cleanup:** Automatically deletes the temporary `build\` folder after the application closes.

---

### 2. Build a Fat JAR (`build_jar.bat`)
Compiles the project and packages your code, resources, and all `lib\*.jar` dependencies into a single executable JAR at `JAR\<MainClassName>.jar`.
```cmd
build_jar.bat
```
* **Signature Stripping:** Automatically removes `META-INF\*.SF`, `*.DSA`, and `*.RSA` files from merged libraries to prevent `SecurityException` errors at runtime.
* **Arguments:** Pass `--no-pause` when calling from automated workflows.

---

### 3. Build a Standalone Windows EXE (`build_exe.bat`)
Creates a completely portable single-file executable at `EXE\<ProjectFolderName>.exe` that runs on machines without Java installed.
```cmd
build_exe.bat
```
**How it works under the hood:**
1. **Smart Rebuild Check:** Checks timestamps on `src\`, `res\`, and `lib\` and rebuilds the Fat JAR only if changes are detected.
2. **Minimal JRE Bundling:** Uses `jlink` (with fallback to full JDK copy) to build a stripped, compressed Java runtime (`java.se`, `jdk.unsupported`, `jdk.crypto.ec`).
3. **C# Wrapper Compilation:** Generates and compiles a native WinForms C# launcher embedding both `app.jar` and `runtime.zip` as resources.
4. **First-Run Caching:** On end-user machines, the `.exe` extracts the runtime to `%LocalAppData%\<ProjectName>_Runtime\<BuildID>` on first launch, cleans up older build caches, and launches `javaw.exe`.

---

## ⚙️ Customization Notes

* **Java Target Version:** Currently hardcoded to `--release 21` in `build_run.bat`. Edit that flag if targeting a different JDK version.
* **Custom EXE Icon:** Place an `.ico` file at `res\icon.ico` to automatically embed it into the generated executable.
* **Jlink Modules:** If your app uses additional JDK modules (e.g., `java.sql` or `java.desktop`), append them to the `--add-modules` list in `build_exe.bat`.
