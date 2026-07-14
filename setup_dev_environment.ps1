[CmdletBinding()]
param(
    [string]$BuildToolsPath = "",
    [string]$DevKeyName = "LocalDev",
    [switch]$SkipDotNet,
    [switch]$SkipBuildTools,
    [switch]$SkipArmaToolsCheck,
    [switch]$SkipDevKey
)

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$keyRoot = Join-Path (Split-Path $root -Parent) "BKey"
$localDotnet = Join-Path $HOME ".dotnet\dotnet.exe"

function Resolve-ArmaToolPath {
    param(
        [string]$RelativePath,
        [string]$SpecificEnvName = ""
    )

    $candidates = @()
    if ($SpecificEnvName) {
        $specificPath = [Environment]::GetEnvironmentVariable($SpecificEnvName)
        if ($specificPath) {
            $candidates += $specificPath
        }
    }

    $toolsRoot = [Environment]::GetEnvironmentVariable("A3YT_ARMA_TOOLS_PATH")
    if ($toolsRoot) {
        $candidates += Join-Path $toolsRoot $RelativePath
    }

    $candidates += @(
        (Join-Path "D:\SteamLibrary\steamapps\common\Arma 3 Tools" $RelativePath),
        (Join-Path "C:\Program Files (x86)\Steam\steamapps\common\Arma 3 Tools" $RelativePath)
    )

    foreach ($candidate in $candidates | Where-Object { $_ } | Select-Object -Unique) {
        if (Test-Path -LiteralPath $candidate) {
            return $candidate
        }
    }

    return ($candidates | Where-Object { $_ } | Select-Object -First 1)
}

$addonBuilder = Resolve-ArmaToolPath -RelativePath "AddonBuilder\AddonBuilder.exe" -SpecificEnvName "A3YT_ADDONBUILDER_PATH"
$dsCreateKey = Resolve-ArmaToolPath -RelativePath "DSSignFile\DSCreateKey.exe" -SpecificEnvName "A3YT_DSCREATEKEY_PATH"
$installCleanupExe = "C:\Program Files (x86)\Microsoft Visual Studio\Installer\InstallCleanup.exe"
$setupTempRoot = Join-Path $root ".setup-temp"
$setupRunTempRoot = Join-Path $setupTempRoot ([guid]::NewGuid().ToString("N"))
$requiredVsComponents = @(
    "Microsoft.VisualStudio.Workload.VCTools",
    "Microsoft.VisualStudio.Component.VC.Tools.x86.x64"
)

function Ensure-Directory {
    param([string]$Path)

    if (!(Test-Path $Path)) {
        New-Item -ItemType Directory -Path $Path | Out-Null
    }
}

function New-SetupTempPath {
    param([string]$FileName)

    Ensure-Directory $setupRunTempRoot
    return Join-Path $setupRunTempRoot $FileName
}

function Remove-PathQuietly {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return
    }

    try {
        if (Test-Path -LiteralPath $Path -ErrorAction SilentlyContinue) {
            Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
        }
    } catch {
        Write-Warning "Failed to remove temporary path '${Path}': $($_.Exception.Message)"
    }
}

function Remove-SetupTempFiles {
    Remove-PathQuietly -Path $setupRunTempRoot

    try {
        if ((Test-Path -LiteralPath $setupTempRoot -ErrorAction SilentlyContinue) -and
            -not (Get-ChildItem -LiteralPath $setupTempRoot -Force -ErrorAction SilentlyContinue | Select-Object -First 1)) {
            Remove-Item -LiteralPath $setupTempRoot -Force -ErrorAction Stop
        }
    } catch {
        Write-Warning "Failed to remove temporary setup directory '${setupTempRoot}': $($_.Exception.Message)"
    }
}

function Format-ProcessArgument {
    param([AllowNull()][string]$Argument)

    if ($null -eq $Argument -or $Argument -eq "") {
        return '""'
    }

    if ($Argument -notmatch '[\s"]') {
        return $Argument
    }

    $escaped = $Argument -replace '(\\*)"', '$1$1\"'
    $escaped = $escaped -replace '(\\+)$', '$1$1'
    return '"' + $escaped + '"'
}

function Invoke-ProcessAndWait {
    param(
        [string]$FilePath,
        [string[]]$Arguments = @()
    )

    $argumentText = ($Arguments | ForEach-Object { Format-ProcessArgument $_ }) -join " "
    $startArgs = @{
        FilePath = $FilePath
        Wait = $true
        PassThru = $true
    }

    if ($argumentText) {
        $startArgs.ArgumentList = $argumentText
    }

    $process = Start-Process @startArgs
    if ($null -eq $process.ExitCode) {
        return 0
    }

    return $process.ExitCode
}

function Test-IsAdministrator {
    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal -ArgumentList $identity
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch {
        return $false
    }
}

function Get-WingetPath {
    $winget = Get-Command winget.exe -ErrorAction SilentlyContinue
    if (-not $winget) {
        return $null
    }

    return $winget.Source
}

function Resolve-VsWherePath {
    $candidates = @()

    if ($env:A3YT_VSWHERE_PATH) {
        $candidates += $env:A3YT_VSWHERE_PATH
    }

    $candidates += @(
        (Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\\Installer\\vswhere.exe"),
        (Join-Path $env:ProgramFiles "Microsoft Visual Studio\\Installer\\vswhere.exe")
    )

    $command = Get-Command vswhere.exe -ErrorAction SilentlyContinue
    if ($command) {
        $candidates += $command.Source
    }

    foreach ($candidate in $candidates | Where-Object { $_ } | Select-Object -Unique) {
        if (Test-Path $candidate) {
            return $candidate
        }
    }

    return $null
}

function Get-VisualStudioInstallPath {
    $candidateRoots = @()
    if ($BuildToolsPath) {
        $candidateRoots += $BuildToolsPath
    }

    if ($env:A3YT_VS_INSTALL_PATH) {
        $candidateRoots += $env:A3YT_VS_INSTALL_PATH
    }

    $candidateRoots += @(
        "C:\\BuildTools",
        "C:\\Program Files\\Microsoft Visual Studio\\2022\\BuildTools",
        "C:\\Program Files\\Microsoft Visual Studio\\2022\\Community",
        "C:\\Program Files\\Microsoft Visual Studio\\2022\\Professional",
        "C:\\Program Files\\Microsoft Visual Studio\\2022\\Enterprise",
        "C:\\Program Files\\Microsoft Visual Studio\\2022\\Preview"
    )

    foreach ($candidateRoot in $candidateRoots | Where-Object { $_ } | Select-Object -Unique) {
        if (Test-Path (Join-Path $candidateRoot "VC\\Tools\\MSVC")) {
            return $candidateRoot
        }
    }

    $vswhere = Resolve-VsWherePath
    if ($vswhere) {
        $installationPath = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath 2>$null | Select-Object -First 1
        if ($LASTEXITCODE -eq 0 -and $installationPath -and (Test-Path (Join-Path $installationPath "VC\\Tools\\MSVC"))) {
            return $installationPath
        }
    }

    return $null
}

function Wait-VisualStudioInstallPath {
    param([int]$TimeoutSeconds = 180)

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        $installPath = Get-VisualStudioInstallPath
        if ($installPath) {
            return $installPath
        }

        Start-Sleep -Seconds 5
    } while ((Get-Date) -lt $deadline)

    return $null
}

function Get-VisualStudioInstanceInfo {
    $vswhere = Resolve-VsWherePath
    if (-not $vswhere) {
        return $null
    }

    $json = & $vswhere -all -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -format json 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($json)) {
        return $null
    }

    $instances = $json | ConvertFrom-Json
    if ($instances -isnot [System.Array]) {
        $instances = @($instances)
    }

    $instance = $instances |
        Sort-Object updateDate -Descending |
        Select-Object -First 1

    return $instance
}

function Test-VisualStudioInstanceBroken {
    param($Instance)

    if (-not $Instance) {
        return $false
    }

    if (-not $Instance.installationPath -or -not (Test-Path -LiteralPath $Instance.installationPath)) {
        return $true
    }

    if ($Instance.isComplete -eq $false -or $Instance.isLaunchable -eq $false) {
        return $true
    }

    return $false
}

function Install-WingetPackage {
    param(
        [string]$Id,
        [string]$OverrideArgs = ""
    )

    $winget = Get-WingetPath
    if (-not $winget) {
        return $false
    }

    $args = @(
        "install",
        "--id", $Id,
        "--exact",
        "--accept-package-agreements",
        "--accept-source-agreements",
        "--silent",
        "--disable-interactivity"
    )

    if ($OverrideArgs -ne "") {
        $args += @("--override", $OverrideArgs)
    }

    $wingetOutput = @()
    try {
        $wingetOutput = & $winget @args 2>&1
        $exitCode = $LASTEXITCODE
    } catch {
        $exitCode = if ($null -ne $LASTEXITCODE) { $LASTEXITCODE } else { 1 }
        Write-Warning "winget install failed for ${Id}: $($_.Exception.Message)"
        return $false
    }

    if ($exitCode -ne 0) {
        Write-Warning "winget install failed for ${Id} with exit code $exitCode. Falling back to the official installer."
        $wingetOutput |
            ForEach-Object { $_.ToString().Trim() } |
            Where-Object { $_ -and $_ -notmatch '^[\\|/\-]+$' } |
            Select-Object -Last 8 |
            ForEach-Object { Write-Warning "winget: $_" }
        return $false
    }

    return $true
}

function Install-DotNetSdkFallback {
    $scriptUrl = "https://dot.net/v1/dotnet-install.ps1"
    $tempScript = New-SetupTempPath -FileName "dotnet-install.ps1"
    $installDir = Split-Path $localDotnet -Parent

    Write-Host "Downloading official dotnet-install.ps1..."
    try {
        Invoke-WebRequest -Uri $scriptUrl -OutFile $tempScript
        Unblock-File -Path $tempScript -ErrorAction SilentlyContinue

        & $tempScript -Channel "8.0" -InstallDir $installDir
        if ($LASTEXITCODE -ne 0) {
            throw "dotnet-install.ps1 failed."
        }
    } finally {
        Remove-PathQuietly -Path $tempScript
    }
}

function Install-BuildToolsFallback {
    $installerUrl = "https://aka.ms/vs/17/release/vs_BuildTools.exe"
    $tempInstaller = New-SetupTempPath -FileName "vs_BuildTools.exe"
    $existingInstance = Get-VisualStudioInstanceInfo
    $targetInstallPath = if ($BuildToolsPath) { $BuildToolsPath } elseif ($existingInstance -and $existingInstance.installationPath) { $existingInstance.installationPath } else { "C:\BuildTools" }

    function Invoke-BuildToolsBootstrapperInstall {
        param([string]$InstallPath)

        $args = @(
            "--wait",
            "--passive",
            "--norestart"
        )

        foreach ($component in $requiredVsComponents) {
            $args += @("--add", $component)
        }

        if ($InstallPath) {
            Ensure-Directory $InstallPath
            $args += @("--installPath", $InstallPath)
        }

        $exitCode = Invoke-ProcessAndWait -FilePath $tempInstaller -Arguments $args
        if ($exitCode -notin @(0, 3010)) {
            throw "Visual Studio Build Tools bootstrapper failed with exit code $exitCode."
        }
    }

    function Invoke-InstallCleanupFallback {
        if (-not (Test-Path $installCleanupExe)) {
            throw "InstallCleanup.exe not found at $installCleanupExe"
        }

        Write-Warning "Running InstallCleanup.exe -i 17 to remove the broken Visual Studio Build Tools instance."
        $exitCode = Invoke-ProcessAndWait -FilePath $installCleanupExe -Arguments @("-i", "17")
        if ($exitCode -notin @(0, 3010)) {
            throw "InstallCleanup.exe failed with exit code $exitCode."
        }

        Start-Sleep -Seconds 5
    }

    Write-Host "Downloading official Visual Studio Build Tools bootstrapper..."
    try {
        Invoke-WebRequest -Uri $installerUrl -OutFile $tempInstaller

        if ($existingInstance) {
            if (Test-VisualStudioInstanceBroken -Instance $existingInstance) {
                Write-Warning "Broken Visual Studio Build Tools instance detected at $($existingInstance.installationPath). Running cleanup before reinstall."
                Invoke-InstallCleanupFallback
                Invoke-BuildToolsBootstrapperInstall -InstallPath $targetInstallPath
                $null = Wait-VisualStudioInstallPath -TimeoutSeconds 180
                return
            }

            $setupExe = $existingInstance.properties.setupEngineFilePath
            if (-not $setupExe -or -not (Test-Path $setupExe)) {
                $setupExe = "C:\Program Files (x86)\Microsoft Visual Studio\Installer\setup.exe"
            }

            $modifyArgs = @(
                "modify",
                "--installPath", $existingInstance.installationPath,
                "--channelId", $existingInstance.channelId,
                "--productId", $existingInstance.productId,
                "--passive",
                "--norestart"
            )

            foreach ($component in $requiredVsComponents) {
                $modifyArgs += @("--add", $component)
            }

            Write-Host "Existing Visual Studio Build Tools instance detected at $($existingInstance.installationPath). Running modify..."
            $exitCode = Invoke-ProcessAndWait -FilePath $setupExe -Arguments $modifyArgs
            if ($exitCode -notin @(0, 3010)) {
                throw "Visual Studio Installer modify failed with exit code $exitCode."
            }

            if (Wait-VisualStudioInstallPath -TimeoutSeconds 180) {
                return
            }

            Invoke-InstallCleanupFallback
            Invoke-BuildToolsBootstrapperInstall -InstallPath $targetInstallPath
            $null = Wait-VisualStudioInstallPath -TimeoutSeconds 180
            return
        }

        Invoke-BuildToolsBootstrapperInstall -InstallPath $targetInstallPath
        $null = Wait-VisualStudioInstallPath -TimeoutSeconds 180
    } finally {
        Remove-PathQuietly -Path $tempInstaller
    }
}

try {
Write-Host "== YouTube Player Music dev setup =="

if (!$SkipDotNet) {
    $dotnetCmd = Get-Command dotnet.exe -ErrorAction SilentlyContinue
    if ($dotnetCmd) {
        Write-Host "dotnet found in PATH: $($dotnetCmd.Source)"
    } elseif (Test-Path $localDotnet) {
        Write-Host "dotnet found in local install: $localDotnet"
    } else {
        Write-Host "Installing .NET 8 SDK..."
        if (-not (Install-WingetPackage -Id "Microsoft.DotNet.SDK.8")) {
            Install-DotNetSdkFallback
        }
    }
}

if (!$SkipBuildTools) {
    $existingVsPath = Get-VisualStudioInstallPath
    if (-not $existingVsPath) {
        Write-Host "Installing Visual Studio Build Tools 2022..."
        if (-not (Test-IsAdministrator)) {
            Write-Warning "Visual Studio Build Tools may require administrator rights. Accept the UAC prompt, or rerun this PowerShell window as Administrator if installation does not start."
        }

        $overrideArgs = "--wait --passive --norestart"
        foreach ($component in $requiredVsComponents) {
            $overrideArgs += " --add $component"
        }
        if ($BuildToolsPath) {
            $overrideArgs += " --installPath `"$BuildToolsPath`""
        }

        if (-not (Install-WingetPackage -Id "Microsoft.VisualStudio.2022.BuildTools" -OverrideArgs $overrideArgs)) {
            Install-BuildToolsFallback
        }

        $existingVsPath = Wait-VisualStudioInstallPath -TimeoutSeconds 180
        if (-not $existingVsPath) {
            throw "Visual Studio Build Tools installer returned, but MSVC tools were still not detected. Rerun this script from an elevated PowerShell window or open Visual Studio Installer and add 'MSVC v143 - VS 2022 C++ x64/x86 build tools'."
        }
    } else {
        Write-Host "MSVC Build Tools found: $existingVsPath"
    }
}

if (!$SkipArmaToolsCheck) {
    if (Test-Path $addonBuilder) {
        Write-Host "Arma 3 Tools found: $addonBuilder"
    } else {
        Write-Warning "Arma 3 Tools not found. Install 'Arma 3 Tools' from Steam before running build.ps1."
        Write-Host "Steam app page: steam://install/233800"
    }
}

if (!$SkipDevKey) {
    Ensure-Directory $keyRoot
    $existingKeys = Get-ChildItem $keyRoot -Filter *.biprivatekey -File -ErrorAction SilentlyContinue

    if (-not $existingKeys) {
        if (Test-Path $dsCreateKey) {
            Write-Host "Creating local development key pair '$DevKeyName'..."
            Push-Location $keyRoot
            try {
                & $dsCreateKey $DevKeyName
                if ($LASTEXITCODE -ne 0) {
                    throw "DSCreateKey failed for $DevKeyName"
                }
            } finally {
                Pop-Location
            }
        } else {
            Write-Warning "DSCreateKey.exe not found. Development signing key was not created."
        }
    } else {
        Write-Host "Signing key already present in: $keyRoot"
    }
}

Write-Host ""
Write-Host "Setup complete."
Write-Host "Next step: run .\\build.ps1"
} finally {
    Remove-SetupTempFiles
}
