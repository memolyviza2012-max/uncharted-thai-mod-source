# UNCHARTED Thai Mod — source for review

Creator: **หน๊ด หนวด translator** (Nod Nuat Translator).
Supported game: UNCHARTED: Legacy of Thieves Collection, Steam PC 1.4.21058.
Mod content version: 1.0; distribution: LowSpace offline installer.

This repository contains the shipped installer scripts and the C++ source of the
native Thai language proxy, provided so reviewers can inspect their behavior.
No game EXEs, archives, texture assets, translated CSV, DLL binaries or mod payload
are included. `profiles.h` contains only the build hashes, relocation metadata and
short expected instruction signatures required by the native guards.

## Contents

- `proxy/`: exact `thai_language.cpp`, `profiles.h` and `version.def` used by the
  released proxy, plus a portable build command. The source has not been changed
  to disguise behavior from reviewers.
- `installer/`: byte-identical scripts and manifest from the distributed ZIP.
  Install needs the separate mod release's `mod_data.zip`; it is not in this repo.
- `tests/test_installer.ps1`: synthetic test fixtures including real process kills
  during install/recovery. Fixtures are not game assets and are created locally.
- `review/`: release SHA-256 values, supported EXE hashes and recorded test results.

## Build the proxy

On Windows, install Visual Studio Build Tools 2022, Desktop development with C++
and the Windows SDK. Run `proxy\build.cmd`. Output is `proxy/out/version.dll`.
The build uses C++17, `/O2 /MT /GS /EHsc /W4`, `bcrypt.lib`, and the supplied DEF.
No downloads are performed by the build script. A game installation is not
required to compile: all four exact build profiles are included in the header.

The original DLL has no reproducible-build promise: toolchain version and PE
timestamps can change its whole-file hash. See `review/build_comparison.json`
for the local rebuild evidence: every byte matches after normalizing PE header,
export-directory and debug-directory timestamps. Always use the recorded released
DLL hash when comparing a downloaded release to this review snapshot.

## Test the installer

Run in Windows PowerShell 5.1:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests/test_installer.ps1
```

It creates a disposable synthetic folder beneath `tests/`, tests install,
rollback, recovery and uninstall, and never locates the user's real game.
Full-size tests were run separately against disposable original game copies.
All six target hashes match the mod previously accepted in-game by the creator;
the installer revision did not receive a new gameplay launch test.

## Runtime summary

The DLL forwards six version-information exports to the Windows system DLL.
It verifies the host EXE's exact hash and instruction signatures before changing
the language manager inside that same process, adding Thai ID 25 while keeping
the original IDs and sentinel 24. It does not patch EXEs on disk or other processes.

The installer validates the game build and payload, locks texture archives,
backs up and verifies every original range before writes, journals pending
mutations, and verifies the complete target hashes. It modifies only the six
listed mod files. Original ranges and small original files are retained for
uninstall/recovery. Required free game-drive space is 1 GB; measured retained
backup is about 284 MB. Players do not need Python, administrator elevation
requested by this code, or an internet connection for installation.

Read [SECURITY_REVIEW.md](SECURITY_REVIEW.md) for the memory patching, legacy log
path, recovery constraints and expected security-review questions.

This repository is review material, not a statement of Nexus Mods approval.
No software license has been selected for this source snapshot.

Creator website: https://www.nodnuattranslator.com/
Facebook: https://www.facebook.com/NodNuatTranslator/
