# Security review notes

## Proxy: behavior reviewers should inspect

The shipped code uses `VirtualAlloc`, `VirtualProtect` and
`FlushInstructionCache` inside the current game process. These are needed for
native language table relocation and a constructor thunk; they may cause
heuristic detections. Allocation/protection flags are visible in the source.
No claim is made that an antivirus or Nexus reviewer will accept this technique.

The original six version exports are resolved from the absolute Windows system
`version.dll` via `LoadLibraryExW(..., LOAD_LIBRARY_SEARCH_SYSTEM32)`.
There is no network client, downloader, credential access, autostart registration,
privilege-elevation request, remote process handle or remote injection routine
in the published proxy source. It hashes the local host EXE and refuses other
builds. No game executable on disk is rewritten.

There are three exported `ThaiTest*` helpers for native profile tests. They are
also present in the released build; publishing their source does not remove or
hide them. Runtime initialization is performed in `DllMain`; the source is
published as-is, including this implementation choice.

The current shipped DLL still attempts optional diagnostic logging to this
developer-workspace path:
`E:\Mod_Workspace\UNCHARTED_Legacy_of_Thieves_Collection\05_Scripts_and_Tools\native_language_extension\runtime.log`.
Logging opens only that file and ignores failure. This is disclosed and kept in
the exact source snapshot. Removing or relocating it would produce a different
DLL and would require a new release, updated hashes and renewed testing.

## Installer: write scope and recovery

The entry script pins manifest and engine hashes; the manifest pins payload,
whole original/target archive hashes, executable profiles and original/target
range hashes. Neither manifest nor journal executes commands.

Paths are restricted beneath the selected game root; traversal, absolute paths,
duplicates, reparse points and invalid/overlapping ranges are rejected. A local
lock prevents concurrent installer instances. Original texture archives are
held exclusively while being checked and patched.

Before mutation, all backups and small staged files are flushed and rehashed.
Every changed unit has durable pending/dirty markers before writing, followed
by flush/readback and final whole target hash checks. Full small archives are
atomically replaced on the same volume. Saves and game profiles are untouched.

Recovery verifies backups, non-pending range hashes and a streamed normalized
original whole-file hash before restoration. It allows torn writes only for
known persisted dirty/pending IDs, including a second interruption during
recovery. It does not require the mod payload. Missing/corrupt backups or edits
outside mapped ranges cause a refusal; Steam verification may be needed.

Process-kill tests simulate interrupted software writes. They do not certify
hardware behavior during a physical power loss or disk/controller failure.

## Review this specific release

`review/release_hashes.json` records the shipped DLL, installer, engine, manifest,
payload, outer ZIP and supported executable hashes. Compare these against the
downloaded files. The payload and game data are intentionally absent here;
the shipped runtime scripts and manifest are present for inspection.

The local full-size install/repeat/uninstall tests and synthetic safety results
are included. Publishing source alone neither resolves a detection nor
constitutes approval from Nexus Mods. Obtain the actual review requirements
from the support response; the acknowledgement email is not an approval.
