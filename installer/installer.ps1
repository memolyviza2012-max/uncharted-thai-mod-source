param([ValidateSet('Install','Uninstall','Recover')][string]$Action='Install',[string]$GamePath,[switch]$NonInteractive)
$ErrorActionPreference='Stop'
try {
    if(-not $GamePath) {
        Add-Type -AssemblyName System.Windows.Forms
        $pick=[Windows.Forms.FolderBrowserDialog]::new()
        $pick.Description='Select the UNCHARTED game folder containing u4.exe (Steam > Manage > Browse local files)'
        $pick.ShowNewFolderButton=$false
        $steam=Get-ItemProperty -LiteralPath 'HKCU:\Software\Valve\Steam' -ErrorAction SilentlyContinue
        if($steam -and $steam.SteamPath) { $pick.SelectedPath=$steam.SteamPath }
        $installed=Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Steam App 1659420' -ErrorAction SilentlyContinue
        if($installed -and $installed.InstallLocation -and (Test-Path -LiteralPath (Join-Path $installed.InstallLocation 'u4.exe'))) { $pick.SelectedPath=$installed.InstallLocation }
        if($pick.ShowDialog() -ne [Windows.Forms.DialogResult]::OK) { exit 0 }
        $GamePath=$pick.SelectedPath;$pick.Dispose()
    }
    $manifestPath=Join-Path $PSScriptRoot 'manifest.json'
    $expected='e7c92617e2a767d01aaa238f3dd1d0239f204d9fb5b6c5871ae742e7f8e58cdc'
    if((Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash.ToLowerInvariant() -ne $expected) { throw 'Manifest is damaged or changed. Extract the official ZIP again.' }
    $engine=Join-Path $PSScriptRoot 'installer_engine.ps1'
    if((Get-FileHash -LiteralPath $engine -Algorithm SHA256).Hash.ToLowerInvariant() -ne '40eaa5116df6dee1326e21b52181268f2998ec26ae6cfdbb3b81a5d1437ee379') { throw 'Installer engine is damaged or changed.' }
    . $engine
    $manifest=Get-Content -LiteralPath $manifestPath -Raw|ConvertFrom-Json
    Assert-Manifest $manifest $GamePath
    if(-not $NonInteractive) {
        Add-Type -AssemblyName System.Windows.Forms
        $message="Action: $Action`nGame: $GamePath`nSupported: Steam PC 1.4.21058`n`nInstall needs 1 GB free on the game drive. Texture archives are patched directly.`nOnly changed ranges and small originals are backed up (up to 395 MB). Keep _NodNuatThai_v1.0_LowSpace_Backup for recovery/uninstall.`nThe game must be closed. This changes 6 mod files; saves are untouched.`n`nContinue?"
        if([Windows.Forms.MessageBox]::Show($message,'UNCHARTED Thai Mod v1.0',[Windows.Forms.MessageBoxButtons]::YesNo,[Windows.Forms.MessageBoxIcon]::Information) -ne [Windows.Forms.DialogResult]::Yes) { exit 0 }
    }
    Invoke-ThaiPatch $manifest $GamePath (Join-Path $PSScriptRoot 'mod_data.zip') $Action
    if(-not $NonInteractive) { [Windows.Forms.MessageBox]::Show("$Action completed.",'UNCHARTED Thai Mod')|Out-Null }
    exit 0
} catch {
    Write-Host $_.Exception.Message -ForegroundColor Red
    if(-not $NonInteractive) { Add-Type -AssemblyName System.Windows.Forms;[Windows.Forms.MessageBox]::Show($_.Exception.Message,'UNCHARTED Thai Mod - stopped')|Out-Null }
    exit 1
}
