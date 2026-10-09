Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem
Add-Type -AssemblyName System.IO.Compression

function Get-Sha([string]$Path) { return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() }
function Get-BytesSha([byte[]]$Bytes) {
    $h=[Security.Cryptography.SHA256Cng]::new()
    try { return ([BitConverter]::ToString($h.ComputeHash($Bytes))).Replace('-','').ToLowerInvariant() } finally {$h.Dispose()}
}
function Get-StreamSha($Stream) {
    $h=[Security.Cryptography.SHA256Cng]::new();$Stream.Position=0
    try { return ([BitConverter]::ToString($h.ComputeHash($Stream))).Replace('-','').ToLowerInvariant() } finally {$h.Dispose();$Stream.Position=0}
}
function Get-CheckedPath([string]$Root,[string]$Relative) {
    if([string]::IsNullOrWhiteSpace($Relative) -or $Relative -match '(^[/\\])|(:)|(^|[/\\])\.\.([/\\]|$)') {throw "Unsafe path: $Relative"}
    $base=[IO.Path]::GetFullPath($Root).TrimEnd('\')+'\';$full=[IO.Path]::GetFullPath((Join-Path $Root $Relative))
    if(-not $full.StartsWith($base,[StringComparison]::OrdinalIgnoreCase)) {throw 'Path outside game directory'}
    $part=$full
    while($part -and $part.Length -ge $base.TrimEnd('\').Length) {
        if((Test-Path -LiteralPath $part) -and ((Get-Item -LiteralPath $part -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {throw "Linked path is not supported: $part"}
        $part=[IO.Path]::GetDirectoryName($part)
    }
    return $full
}
function Assert-GameClosed {
    if(@(Get-Process -ErrorAction SilentlyContinue|Where-Object {$_.ProcessName -in @('u4','tll','u4-l','tll-l')}).Count) {throw 'Close UNCHARTED before installing or uninstalling.'}
}
function Assert-Manifest($M,[string]$Root) {
    if($M.schema -ne 2 -or $M.backup_directory -ne '_NodNuatThai_v1.0_LowSpace_Backup') {throw 'Unsupported manifest format'}
    $seen=@{};[long]$needed=256MB
    foreach($f in $M.files) {
        $p=Get-CheckedPath $Root $f.path
        if($seen.ContainsKey($p.ToLowerInvariant())) {throw 'Duplicate destination'};$seen[$p.ToLowerInvariant()]=$true
        if($f.kind -notin @('full','ranges') -or $f.size -lt 1 -or $f.target_sha256 -notmatch '^[a-f0-9]{64}$') {throw 'Invalid file metadata'}
        if($null -eq $f.source_sha256 -and ($f.path -ne 'version.dll' -or $f.kind -ne 'full')) {throw 'Only the added language DLL may have no source'}
        if($null -ne $f.source_sha256 -and $f.source_sha256 -notmatch '^[a-f0-9]{64}$') {throw 'Invalid source hash'}
        if($f.kind -eq 'ranges') {
            [long]$last=0
            foreach($r in $f.ranges) {
                if($r.archive -ne $f.path -or $r.physical_offset -lt $last -or $r.size -lt 1 -or $r.size -gt [int]::MaxValue -or $r.physical_offset -gt ($f.size-$r.size)) {throw 'Invalid or overlapping texture range'}
                if($r.target_sha256 -notmatch '^[a-f0-9]{64}$' -or $r.original_sha256 -notmatch '^[a-f0-9]{64}$' -or $r.payload -ne ('Textures/'+$r.target_sha256+'.bin')) {throw 'Invalid payload metadata'}
                $last=$r.physical_offset+$r.size;$needed+=$r.size
            }
        } else {
            if($f.payload -ne ('FullFiles/'+$f.path) -or $f.source_size -lt 0) {throw 'Invalid full-file metadata'}
            $needed+=$f.size+$f.source_size
        }
    }
    if($M.temporary_bytes -lt $needed) {throw 'Incorrect free-space requirement'}
    foreach($e in $M.executables) { $null=Get-CheckedPath $Root $e.path;if($e.sha256 -notmatch '^[a-f0-9]{64}$') {throw 'Invalid executable hash'} }
}
function Save-Journal($J,[string]$Path) {
    $tmp=$Path+'.new';[IO.File]::WriteAllText($tmp,($J|ConvertTo-Json -Depth 12),[Text.UTF8Encoding]::new($false))
    $s=[IO.File]::Open($tmp,[IO.FileMode]::Open,[IO.FileAccess]::Write,[IO.FileShare]::None)
    try {$s.Flush($true)} finally {$s.Dispose()}
    if(Test-Path -LiteralPath $Path) {[IO.File]::Replace($tmp,$Path,($Path+'.previous'))} else {[IO.File]::Move($tmp,$Path)}
}
function Write-Durable([string]$Path,[byte[]]$Bytes) {
    $null=[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path))
    $s=[IO.File]::Open($Path,[IO.FileMode]::Create,[IO.FileAccess]::Write,[IO.FileShare]::None)
    try {$s.Write($Bytes,0,$Bytes.Length);$s.Flush($true)} finally {$s.Dispose()}
}
function Read-ZipBytes($Zip,[string]$Name,[long]$Length,[string]$Hash) {
    $e=$Zip.GetEntry($Name);if($null -eq $e -or $e.Length -ne $Length) {throw "Missing or wrong-size payload: $Name"}
    $s=$e.Open();$mem=[IO.MemoryStream]::new()
    try {$s.CopyTo($mem);$b=$mem.ToArray()} finally {$s.Dispose();$mem.Dispose()}
    if((Get-BytesSha $b) -ne $Hash) {throw "Corrupt payload: $Name"};return ,$b
}
function Read-Range($Stream,[long]$Offset,[int]$Size) {
    $b=New-Object byte[] $Size;$Stream.Position=$Offset;$done=0
    while($done -lt $Size) {$n=$Stream.Read($b,$done,$Size-$done);if($n -le 0) {throw 'Unexpected end of archive'};$done+=$n};return ,$b
}
# No-op checkpoints allow process-kill tests without exposing fault switches to players.
function Invoke-Checkpoint([string]$Name) {}
function Write-Range($S,[long]$Offset,[byte[]]$Bytes,[string]$Phase) {
    $S.Position=$Offset;[int]$half=[Math]::Max(1,[Math]::Floor($Bytes.Length/2))
    $S.Write($Bytes,0,$half);$S.Flush($true);Invoke-Checkpoint ($Phase+'-mid-write')
    $S.Write($Bytes,$half,$Bytes.Length-$half);$S.Flush($true);Invoke-Checkpoint ($Phase+'-after-write')
}
function Get-Units($M) {
    $units=[Collections.Generic.List[object]]::new();$n=0
    foreach($f in $M.files) {
        if($f.kind -eq 'ranges') {foreach($r in $f.ranges) {$units.Add([pscustomobject]@{id=('r'+$n.ToString('D6'));file=$f;range=$r});$n++}}
        else {$units.Add([pscustomobject]@{id=('f'+$n.ToString('D6'));file=$f;range=$null});$n++}
    };return ,$units
}
function Get-OriginalRange([string]$Backup,$R) {return Get-CheckedPath $Backup ('Ranges/'+$R.original_sha256+'.bin')}
function Get-MaskedSourceSha($S,$F,[string]$Backup) {
    # Reconstruct the original in a streaming hash, without creating a full-size file.
    $h=[Security.Cryptography.SHA256Cng]::new();$buf=New-Object byte[] (8MB);[long]$pos=0
    try {
        $S.Position=0
        while(($n=$S.Read($buf,0,$buf.Length)) -gt 0) {
            foreach($r in $F.ranges) {
                [long]$lo=[Math]::Max($pos,[long]$r.physical_offset);[long]$hi=[Math]::Min($pos+$n,[long]($r.physical_offset+$r.size))
                if($lo -lt $hi) {
                    $p=Get-OriginalRange $Backup $r;$b=[IO.File]::ReadAllBytes($p)
                    [Array]::Copy($b,[int]($lo-$r.physical_offset),$buf,[int]($lo-$pos),[int]($hi-$lo))
                }
            }
            $null=$h.TransformBlock($buf,0,$n,$buf,0);$pos+=$n
        }
        $null=$h.TransformFinalBlock([byte[]]@(),0,0);return ([BitConverter]::ToString($h.Hash)).Replace('-','').ToLowerInvariant()
    } finally {$h.Dispose();$S.Position=0}
}
function Clear-PreparedFiles($M,[string]$Backup) {
    foreach($f in $M.files) {
        foreach($prefix in @('Staged/','Discard/')) {$p=Get-CheckedPath $Backup ($prefix+$f.path);if(Test-Path -LiteralPath $p) {[IO.File]::Delete($p)}}
    }
}
function Restore-InPlace($M,[string]$Root,[string]$Backup,$J,[string]$JP,$Streams,$Units) {
    $preparing=$J.status -eq 'preparing'
    # Validate ALL originals and untouched bytes before any restoration write.
    foreach($u in $Units) {
        $f=$u.file;$p=Get-CheckedPath $Root $f.path
        if($f.kind -eq 'ranges') {
            if($preparing) {continue}
            $r=$u.range;$old=Get-OriginalRange $Backup $r
            if(-not (Test-Path -LiteralPath $old) -or (Get-Item -LiteralPath $old).Length -ne $r.size -or (Get-Sha $old) -ne $r.original_sha256) {throw 'Missing or corrupt original range backup; restore stopped'}
            $actual=Get-BytesSha (Read-Range $Streams[$f.path] $r.physical_offset $r.size)
            if($actual -notin @($r.original_sha256,$r.target_sha256) -and $u.id -notin @($J.pending,$J.dirty)) {throw 'Range changed outside pending transaction; restore stopped'}
        } else {
            $old=Get-CheckedPath $Backup ('Original/'+$f.path)
            if($null -ne $f.source_sha256 -and -not $preparing) {
                if(-not (Test-Path -LiteralPath $old) -or (Get-Sha $old) -ne $f.source_sha256) {throw 'Missing or corrupt original file backup; restore stopped'}
            }
            if(Test-Path -LiteralPath $p) {
                $actual=Get-Sha $p
                if($actual -notin @($f.source_sha256,$f.target_sha256)) {throw 'File changed since installation; restore stopped'}
                if($preparing -and $actual -ne $f.source_sha256) {throw 'Original file changed during preparation'}
            } elseif($null -ne $f.source_sha256) {throw 'Missing game file; restore stopped'}
        }
    }
    foreach($f in $M.files) {if($f.kind -eq 'ranges') {
        Write-Output ('Checking recovery baseline: '+$f.path)
        $actual=if($preparing) {Get-StreamSha $Streams[$f.path]} else {Get-MaskedSourceSha $Streams[$f.path] $f $Backup}
        if($actual -ne $f.source_sha256) {throw 'Archive changed outside mod ranges; restore stopped'}
    }}
    if($preparing) {Clear-PreparedFiles $M $Backup;$J.status='rolled_back';$J.pending=$null;$J.dirty=$null;Save-Journal $J $JP;return}
    $J.status='restoring';Save-Journal $J $JP
    foreach($u in $Units) {
        Assert-GameClosed
        $f=$u.file;$p=Get-CheckedPath $Root $f.path;$J.pending=$u.id;Save-Journal $J $JP;Invoke-Checkpoint 'restore-pending'
        if($f.kind -eq 'ranges') {
            $r=$u.range;$s=$Streams[$f.path];$b=[IO.File]::ReadAllBytes((Get-OriginalRange $Backup $r))
            if((Get-BytesSha (Read-Range $s $r.physical_offset $r.size)) -ne $r.original_sha256) {Write-Range $s $r.physical_offset $b 'restore'}
            if((Get-BytesSha (Read-Range $s $r.physical_offset $r.size)) -ne $r.original_sha256) {throw 'Restore readback failed'}
        } elseif($null -eq $f.source_sha256) {if(Test-Path -LiteralPath $p) {[IO.File]::Delete($p)}}
        elseif((Get-Sha $p) -ne $f.source_sha256) {
            $tmp=Get-CheckedPath $Backup ('Staged/'+$f.path);$old=Get-CheckedPath $Backup ('Original/'+$f.path);$discard=Get-CheckedPath $Backup ('Discard/'+$f.path)
            Write-Durable $tmp ([IO.File]::ReadAllBytes($old));$null=[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($discard));[IO.File]::Replace($tmp,$p,$discard);[IO.File]::Delete($discard)
        }
        Invoke-Checkpoint 'restore-after-unit'
        if($J.dirty -eq $u.id) {$J.dirty=$null};$J.pending=$null;Save-Journal $J $JP
    }
    foreach($f in $M.files) {if($f.kind -eq 'ranges') {Write-Output ('Verifying original: '+$f.path);if((Get-StreamSha $Streams[$f.path]) -ne $f.source_sha256) {throw 'Restored archive hash mismatch'}} elseif($f.source_sha256 -and (Get-Sha (Get-CheckedPath $Root $f.path)) -ne $f.source_sha256) {throw 'Restored file hash mismatch'}}
    Clear-PreparedFiles $M $Backup;$J.status='uninstalled';$J.pending=$null;$J.dirty=$null;Save-Journal $J $JP
}
function Invoke-ThaiPatch($Manifest,[string]$Root,[string]$Payload,[ValidateSet('Install','Uninstall','Recover')]$Action='Install') {
    $Root=[IO.Path]::GetFullPath($Root).TrimEnd('\');$M=$Manifest
    Assert-GameClosed;Assert-Manifest $M $Root
    foreach($e in $M.executables) {$p=Get-CheckedPath $Root $e.path;if(-not (Test-Path -LiteralPath $p) -or (Get-Sha $p) -ne $e.sha256) {throw "Unsupported or incomplete game build: $($e.path). Requires Steam PC 1.4.21058."}}
    $backup=Get-CheckedPath $Root $M.backup_directory;$jp=Get-CheckedPath $backup 'journal.json'
    $units=Get-Units $M;$identity=Get-BytesSha ([Text.Encoding]::UTF8.GetBytes(($M|ConvertTo-Json -Depth 16 -Compress)))
    $null=[IO.Directory]::CreateDirectory($backup)
    $lockPath=Get-CheckedPath $backup 'installer.lock';$lock=$null;$streams=@{};$zip=$null;$j=$null
    try {
        try {$lock=[IO.File]::Open($lockPath,[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)} catch {throw 'Another installer is using this game folder.'}
        if(Test-Path -LiteralPath $jp) {
            $j=Get-Content -LiteralPath $jp -Raw|ConvertFrom-Json
            if($j.schema -ne 2 -or $j.root -ne $Root -or $j.manifest_sha256 -ne $identity -or $j.status -notin @('preparing','patching','installed','restoring','uninstalled','rolled_back') -or ($j.pending -and $j.pending -notin $units.id) -or ($j.dirty -and $j.dirty -notin $units.id)) {throw 'Recovery journal does not match this build or directory'}
        }
        foreach($f in $M.files) {
            $p=Get-CheckedPath $Root $f.path
            if($f.source_sha256 -and -not (Test-Path -LiteralPath $p)) {throw 'Original file mismatch: missing required archive'}
            if((Test-Path -LiteralPath $p) -and ((Get-Item -LiteralPath $p).Attributes -band [IO.FileAttributes]::ReadOnly)) {throw 'Read-only game file'}
            if($f.kind -eq 'ranges') {
                $streams[$f.path]=[IO.File]::Open($p,[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
                if($streams[$f.path].Length -ne $f.size) {throw 'Archive size mismatch'}
            }
        }
        if($Action -ne 'Install') {
            if($null -eq $j) {throw 'No LowSpace backup found. Uninstall the older installer with its own package.'}
            if($j.status -in @('uninstalled','rolled_back')) {Write-Output 'ALREADY_UNINSTALLED';return}
            Restore-InPlace $M $Root $backup $j $jp $streams $units;Write-Output 'UNINSTALLED: original game files restored.';return
        }
        if($null -ne $j -and $j.status -eq 'installed') {
            foreach($f in $M.files) {$actual=if($f.kind -eq 'ranges') {Get-StreamSha $streams[$f.path]} else {Get-Sha (Get-CheckedPath $Root $f.path)};if($actual -ne $f.target_sha256) {throw 'Installed files changed; use Recover or Steam Verify first'}}
            Write-Output 'ALREADY_INSTALLED';return
        }
        if($null -ne $j -and $j.status -notin @('uninstalled','rolled_back')) {throw 'Previous installation was interrupted. Run Recover Thai Mod before trying again.'}
        if((Get-Sha $Payload) -ne $M.payload_sha256) {throw 'mod_data.zip is damaged. Extract the complete download again.'}
        if([IO.DriveInfo]::new([IO.Path]::GetPathRoot($Root)).AvailableFreeSpace -lt $M.temporary_bytes) {throw 'Insufficient free space. Keep at least 1 GB free on the game drive.'}
        foreach($f in $M.files) {
            Write-Output ('Checking original: '+$f.path);$p=Get-CheckedPath $Root $f.path
            if($null -eq $f.source_sha256) {if(Test-Path -LiteralPath $p) {throw 'version.dll already exists. Remove previous mod safely first.'}}
            else {
                $actual=if($f.kind -eq 'ranges') {Get-StreamSha $streams[$f.path]} else {Get-Sha $p}
                if($actual -ne $f.source_sha256) {throw "Original file mismatch: $($f.path). Uninstall earlier mods or Steam Verify first."}
                if($f.kind -eq 'full') {$probe=[IO.File]::Open($p,[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None);$probe.Dispose()}
            }
        }
        $j=[pscustomobject]@{schema=2;root=$Root;manifest_sha256=$identity;status='preparing';pending=$null;dirty=$null;created=[DateTime]::UtcNow.ToString('o')};Save-Journal $j $jp
        $zip=[IO.Compression.ZipFile]::OpenRead($Payload)
        try {
            # Verify payloads and flush ALL originals before the first game mutation.
            foreach($u in $units) {
                $f=$u.file
                if($f.kind -eq 'ranges') {
                    $r=$u.range;$null=Read-ZipBytes $zip $r.payload $r.size $r.target_sha256
                    $b=Read-Range $streams[$f.path] $r.physical_offset $r.size
                    if((Get-BytesSha $b) -ne $r.original_sha256) {throw 'Original texture range mismatch'}
                    Write-Durable (Get-OriginalRange $backup $r) $b
                } else {
                    $b=Read-ZipBytes $zip $f.payload $f.size $f.target_sha256;Write-Durable (Get-CheckedPath $backup ('Staged/'+$f.path)) $b
                    if($f.source_sha256) {Write-Durable (Get-CheckedPath $backup ('Original/'+$f.path)) ([IO.File]::ReadAllBytes((Get-CheckedPath $Root $f.path)))}
                }
            }
            foreach($u in $units) {
                $f=$u.file
                if($f.kind -eq 'ranges') {
                    if((Get-Sha (Get-OriginalRange $backup $u.range)) -ne $u.range.original_sha256) {throw 'Original range backup verification failed'}
                } else {
                    if((Get-Sha (Get-CheckedPath $backup ('Staged/'+$f.path))) -ne $f.target_sha256) {throw 'Staged payload verification failed'}
                    if($f.source_sha256 -and (Get-Sha (Get-CheckedPath $backup ('Original/'+$f.path))) -ne $f.source_sha256) {throw 'Original file backup verification failed'}
                }
            }
            $j.status='patching';Save-Journal $j $jp;Invoke-Checkpoint 'all-backups-ready'
            foreach($u in $units) {
                Assert-GameClosed;$f=$u.file;$p=Get-CheckedPath $Root $f.path
                $j.pending=$u.id;$j.dirty=$u.id;Save-Journal $j $jp;Invoke-Checkpoint 'install-pending'
                if($f.kind -eq 'ranges') {
                    $r=$u.range;$s=$streams[$f.path];$b=Read-ZipBytes $zip $r.payload $r.size $r.target_sha256
                    if((Get-BytesSha (Read-Range $s $r.physical_offset $r.size)) -ne $r.original_sha256) {throw 'Original changed before range write'}
                    Write-Range $s $r.physical_offset $b 'install'
                    if((Get-BytesSha (Read-Range $s $r.physical_offset $r.size)) -ne $r.target_sha256) {throw 'Texture write readback failed'}
                } else {
                    $tmp=Get-CheckedPath $backup ('Staged/'+$f.path)
                    if((Get-Sha $tmp) -ne $f.target_sha256) {throw 'Staged file changed'}
                    if($f.source_sha256) {
                        if((Get-Sha $p) -ne $f.source_sha256) {throw 'Original changed before replacement'}
                        $discard=Get-CheckedPath $backup ('Discard/'+$f.path);$null=[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($discard));[IO.File]::Replace($tmp,$p,$discard);[IO.File]::Delete($discard)
                    } else {if(Test-Path -LiteralPath $p) {throw 'Unexpected DLL appeared'};[IO.File]::Move($tmp,$p)}
                }
                Invoke-Checkpoint 'install-after-unit';$j.pending=$null;$j.dirty=$null;Save-Journal $j $jp
            }
            foreach($f in $M.files) {
                Write-Output ('Verifying mod: '+$f.path)
                $actual=if($f.kind -eq 'ranges') {Get-StreamSha $streams[$f.path]} else {Get-Sha (Get-CheckedPath $Root $f.path)}
                if($actual -ne $f.target_sha256) {throw 'Installed target hash mismatch'}
            }
            $j.status='installed';Save-Journal $j $jp;Write-Output 'INSTALLED: choose Thai text and subtitles in the game.'
        } catch {
            $failure=$_
            try {Restore-InPlace $M $Root $backup $j $jp $streams $units} catch {throw ('Installation stopped. Run Recover Thai Mod. '+$_.Exception.Message+'; original error: '+$failure.Exception.Message)}
            throw $failure
        }
    } finally {if($zip) {$zip.Dispose()};foreach($s in $streams.Values) {$s.Dispose()};if($lock) {$lock.Dispose()}}
}
