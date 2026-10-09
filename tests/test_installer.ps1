$ErrorActionPreference='Stop'
. "$PSScriptRoot\..\installer\installer_engine.ps1"
$base=Join-Path $PSScriptRoot ('InPlace_Tests_'+[Guid]::NewGuid().ToString('N'))
$root=Join-Path $base 'Game';$null=[IO.Directory]::CreateDirectory($root)
$old=[Text.Encoding]::ASCII.GetBytes('original-text');$new=[Text.Encoding]::ASCII.GetBytes('translated-text')
$exe=Join-Path $root 'u4.exe';[IO.File]::WriteAllText($exe,'test executable fixture')
[IO.File]::WriteAllBytes((Join-Path $root 'text.psarc'),$old)
$texture=New-Object byte[] 8192;for($i=0;$i -lt $texture.Length;$i++) {$texture[$i]=$i%251}
[IO.File]::WriteAllBytes((Join-Path $root 'texture.psarc'),$texture)
$target=$texture.Clone();$patch=[Text.Encoding]::ASCII.GetBytes('THAI_IMAGE_PATCH');[Array]::Copy($patch,0,$target,100,$patch.Length)
$patch2=[Text.Encoding]::ASCII.GetBytes('SECOND_THAI_PATCH');[Array]::Copy($patch2,0,$target,500,$patch2.Length)
[IO.File]::WriteAllText((Join-Path $base 'dll.bin'),'fixture DLL')
$dll=[IO.File]::ReadAllBytes((Join-Path $base 'dll.bin'))
$data=Join-Path $base 'mod_data.zip';$z=[IO.Compression.ZipFile]::Open($data,[IO.Compression.ZipArchiveMode]::Create)
function Add-Payload([string]$Name,[byte[]]$Bytes) {$e=$z.CreateEntry($Name);$s=$e.Open();try{$s.Write($Bytes,0,$Bytes.Length)}finally{$s.Dispose()}}
try {Add-Payload 'FullFiles/text.psarc' $new;Add-Payload 'FullFiles/version.dll' $dll;Add-Payload ('Textures/'+(Get-BytesSha $patch)+'.bin') $patch;Add-Payload ('Textures/'+(Get-BytesSha $patch2)+'.bin') $patch2}finally{$z.Dispose()}
$ranges=@();foreach($r in @(@(100,$patch),@(500,$patch2))) {
 $b=New-Object byte[] $r[1].Length;[Array]::Copy($texture,$r[0],$b,0,$b.Length)
 $ranges+= [pscustomobject]@{archive='texture.psarc';physical_offset=$r[0];size=$b.Length;original_sha256=(Get-BytesSha $b);target_sha256=(Get-BytesSha $r[1]);payload=('Textures/'+(Get-BytesSha $r[1])+'.bin')}
}
$m=[pscustomobject]@{schema=2;backup_directory='_NodNuatThai_v1.0_LowSpace_Backup';payload_sha256=(Get-Sha $data);temporary_bytes=300MB;executables=@([pscustomobject]@{path='u4.exe';sha256=(Get-Sha $exe)});files=@(
 [pscustomobject]@{path='text.psarc';kind='full';source_sha256=(Get-BytesSha $old);source_size=$old.Length;target_sha256=(Get-BytesSha $new);size=$new.Length;payload='FullFiles/text.psarc'},
 [pscustomobject]@{path='texture.psarc';kind='ranges';source_sha256=(Get-BytesSha $texture);target_sha256=(Get-BytesSha $target);size=$texture.Length;ranges=$ranges},
 [pscustomobject]@{path='version.dll';kind='full';source_sha256=$null;source_size=0;target_sha256=(Get-BytesSha $dll);size=$dll.Length;payload='FullFiles/version.dll'})}
$results=[Collections.Generic.List[object]]::new()
function Pass([string]$Name) {$results.Add([pscustomobject]@{test=$Name;passed=$true});Write-Host "PASS $Name"}
function Reject([string]$Name,[scriptblock]$Work,[string]$Pattern) {
 $rejected=$false;try {& $Work|Out-Null} catch {if($_.Exception.Message -notmatch $Pattern){throw "Unexpected rejection $Name : $($_.Exception.Message)"};$rejected=$true}
 if(-not $rejected){throw "Did not reject $Name"};Pass $Name
}
function Assert-Originals {
 foreach($f in $m.files) {if($f.source_sha256){if((Get-Sha (Join-Path $root $f.path)) -ne $f.source_sha256){throw 'Original mismatch'}}elseif(Test-Path (Join-Path $root $f.path)){throw 'Unexpected DLL'}}
}
$real=${function:Assert-GameClosed};Set-Item Function:\Assert-GameClosed -Value {throw 'Close UNCHARTED'}
Reject 'game running gate' {Invoke-ThaiPatch $m $root $data} 'Close UNCHARTED';Set-Item Function:\Assert-GameClosed -Value $real
$good=$m.executables[0].sha256;$m.executables[0].sha256='0'*64;Reject 'wrong build' {Invoke-ThaiPatch $m $root $data} 'Unsupported';$m.executables[0].sha256=$good
$path=$m.files[0].path;$m.files[0].path='../escape';Reject 'path traversal' {Invoke-ThaiPatch $m $root $data} 'Unsafe';$m.files[0].path='C:\escape';Reject 'absolute path' {Invoke-ThaiPatch $m $root $data} 'Unsafe';$m.files[0].path=$path
$path2=$m.files[1].path;$m.files[1].path=$path;Reject 'duplicate destination' {Invoke-ThaiPatch $m $root $data} 'Duplicate';$m.files[1].path=$path2
$outside=Join-Path $base 'Outside';$null=[IO.Directory]::CreateDirectory($outside);$null=New-Item -ItemType Junction -Path (Join-Path $root 'Linked') -Target $outside
Reject 'junction destination' {Get-CheckedPath $root 'Linked/test'} 'Linked'
$p=Join-Path $root 'text.psarc';[IO.File]::Move($p,$p+'.missing');Reject 'missing archive' {Invoke-ThaiPatch $m $root $data} 'missing';[IO.File]::Move($p+'.missing',$p)
[IO.File]::WriteAllBytes($p,$new);Reject 'modded original' {Invoke-ThaiPatch $m $root $data} 'Original file mismatch';[IO.File]::WriteAllBytes($p,$old)
$m.temporary_bytes=[long]100000000000000;Reject 'insufficient capacity' {Invoke-ThaiPatch $m $root $data} 'Insufficient';$m.temporary_bytes=300MB
[IO.File]::SetAttributes($p,[IO.FileAttributes]::ReadOnly);Reject 'read-only source' {Invoke-ThaiPatch $m $root $data} 'Read-only';[IO.File]::SetAttributes($p,[IO.FileAttributes]::Normal)
$good=$m.payload_sha256;$m.payload_sha256='0'*64;Reject 'corrupt payload zip' {Invoke-ThaiPatch $m $root $data} 'damaged';$m.payload_sha256=$good
$off=$ranges[0].physical_offset;$ranges[0].physical_offset=8190;Reject 'out of bounds range' {Invoke-ThaiPatch $m $root $data} 'Invalid or overlapping';$ranges[0].physical_offset=$off
$off=$ranges[1].physical_offset;$ranges[1].physical_offset=101;Reject 'overlapping ranges' {Invoke-ThaiPatch $m $root $data} 'Invalid or overlapping';$ranges[1].physical_offset=$off
$backup=Join-Path $root $m.backup_directory;$jp=Join-Path $backup 'journal.json'
$held=[IO.File]::Open((Join-Path $backup 'installer.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
try {Reject 'concurrent installer lock' {Invoke-ThaiPatch $m $root $data} 'Another installer'}finally{$held.Dispose()}
$script:injected=$false;Set-Item Function:\Invoke-Checkpoint -Value {param($Name) if($Name -eq 'install-mid-write' -and -not $script:injected){$script:injected=$true;throw 'Injected partial-write failure'}}
Reject 'automatic rollback of torn range' {Invoke-ThaiPatch $m $root $data} 'Injected partial-write';Assert-Originals
Set-Item Function:\Invoke-Checkpoint -Value {param($Name)}
Invoke-ThaiPatch $m $root $data|Out-Null
foreach($f in $m.files){if((Get-Sha (Join-Path $root $f.path)) -ne $f.target_sha256){throw 'Target hash mismatch'}};Pass 'install target hashes'
if((Invoke-ThaiPatch $m $root $data) -notcontains 'ALREADY_INSTALLED'){throw 'Repeat failure'};Pass 'repeat installation'
# Changed bytes outside the known texture ranges must stop recovery BEFORE any write.
$tp=Join-Path $root 'texture.psarc';$b=[IO.File]::ReadAllBytes($tp);$b[7000]=99;[IO.File]::WriteAllBytes($tp,$b)
$before=Get-Sha $tp;Reject 'unrelated archive mutation blocks restore' {Invoke-ThaiPatch $m $root $data Recover} 'outside mod ranges'
if((Get-Sha $tp) -ne $before -or (Get-Sha $p) -ne (Get-BytesSha $new)){throw 'Recovery wrote before validation'};[IO.File]::WriteAllBytes($tp,$target)
$rp=Get-OriginalRange $backup $ranges[1];$saved=[IO.File]::ReadAllBytes($rp);[IO.File]::WriteAllText($rp,'bad')
Reject 'corrupt backup blocks restore' {Invoke-ThaiPatch $m $root $data Uninstall} 'corrupt original range';Write-Durable $rp $saved
Invoke-ThaiPatch $m $root $data Uninstall|Out-Null;Assert-Originals;Pass 'uninstall exact originals'
# Kill a separate Windows PowerShell process while only HALF a range is written.
$mp=Join-Path $base 'manifest.json';$m|ConvertTo-Json -Depth 16|Set-Content -LiteralPath $mp -Encoding UTF8
$worker=Join-Path $base 'crash_worker.ps1'
$engine="$PSScriptRoot\..\installer\installer_engine.ps1"
$workerCode=@'
param($Engine,$Manifest,$Root,$Data,$Checkpoint,$Action,[int]$Occurrence=1)
$ErrorActionPreference='Stop'
. $Engine
$script:checkpointCount=0
function Invoke-Checkpoint([string]$Name) {if($Name -eq $Checkpoint){$script:checkpointCount++;if($script:checkpointCount -eq $Occurrence){[Diagnostics.Process]::GetCurrentProcess().Kill()}}}
$m=Get-Content -LiteralPath $Manifest -Raw|ConvertFrom-Json
Invoke-ThaiPatch $m $Root $Data $Action
'@
[IO.File]::WriteAllText($worker,$workerCode)
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $worker $engine $mp $root $data 'install-mid-write' Install 2
if($LASTEXITCODE -eq 0){throw 'Child did not crash'}
Reject 'abrupt install requires recovery' {Invoke-ThaiPatch $m $root $data} 'interrupted'
$j=Get-Content $jp -Raw|ConvertFrom-Json;if(-not $j.pending -or $j.pending -ne $j.dirty){throw 'Missing durable pending write marker'}
Pass 'process killed halfway through range write with persisted journal'
# Recovery itself can be interrupted while rewriting a torn range.
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $worker $engine $mp $root $data 'restore-mid-write' Recover
if($LASTEXITCODE -eq 0){throw 'Recovery child did not crash'}
$j=Get-Content $jp -Raw|ConvertFrom-Json
if(-not $j.dirty -or -not $j.pending -or $j.dirty -eq $j.pending){throw 'Dirty installation range marker lost during interrupted recovery'}
$b=[IO.File]::ReadAllBytes($tp);$partial=New-Object byte[] $patch.Length;[Array]::Copy($b,100,$partial,0,$partial.Length)
if((Get-BytesSha $partial) -in @($ranges[0].original_sha256,$ranges[0].target_sha256)){throw 'Expected an actually torn recovery range'}
Pass 'process killed halfway through recovery'
[IO.File]::Move($data,$data+'.missing')
Invoke-ThaiPatch $m $root $data Recover|Out-Null;Assert-Originals;Pass 'recovery after double interruption without mod payload'
[IO.File]::Move($data+'.missing',$data)
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $worker $engine $mp $root $data 'install-after-unit' Install
if($LASTEXITCODE -eq 0){throw 'Post-replacement child did not crash'}
Invoke-ThaiPatch $m $root $data Recover|Out-Null;Assert-Originals;Pass 'kill after atomic small-file replacement before journal clear'
Invoke-ThaiPatch $m $root $data|Out-Null
$j=Get-Content $jp -Raw|ConvertFrom-Json;$correct=$j.manifest_sha256;$j.manifest_sha256='0'*64;Save-Journal $j $jp
Reject 'mismatched recovery journal' {Invoke-ThaiPatch $m $root $data Recover} 'journal does not match';$j.manifest_sha256=$correct;Save-Journal $j $jp
Invoke-ThaiPatch $m $root $data Uninstall|Out-Null;Assert-Originals
$results|ConvertTo-Json -Depth 6|Set-Content -LiteralPath "$PSScriptRoot\InPlace_Installer_Safety_Tests.json" -Encoding UTF8
Write-Host ('ALL PASSED '+$results.Count)
