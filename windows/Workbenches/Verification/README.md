# Workbench verification

`Logic/WorkbenchLogic.csproj` exercises production arithmetic, formula grammar and 3D scene codec logic using documented WPF/colour/symbol substitutes. Run it with the .NET 10 SDK; it writes a current receipt. Results do not verify native 3D rendering or physical input.

The packaged `RUN-CHECKS.cmd` opens an isolated synthetic Windows app and native workbench windows. Inspect its screenshots, add/edit primitives and strokes, test undo, save/reopen and exports with your own PC. Verify input with your actual tablet. A Mac-side Windows-targeted compile is separate from native Windows execution.

The release report records which machine and architecture ran the current checks, including any x64-on-ARM emulation.
