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
$addonBuilder = "C:\Program Files (x86)\Steam\steamapps\common\Arma 3 Tools\AddonBuilder\AddonBuilder.exe"
$dsCreateKey = "C:\Program Files (x86)\Steam\steamapps\common\Arma 3 Tools\DSSignFile\DSCreateKey.exe"
$installCleanupExe = "C:\Program Files (x86)\Microsoft Visual Studio\Installer\InstallCleanup.exe"
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

    & $winget @args
    if ($LASTEXITCODE -ne 0) {
        throw "winget install failed for $Id"
    }

    return $true
}

function Install-DotNetSdkFallback {
    $scriptUrl = "https://dot.net/v1/dotnet-install.ps1"
    $tempScript = Join-Path $env:TEMP "dotnet-install.ps1"
    $installDir = Split-Path $localDotnet -Parent

    Write-Host "winget not found. Downloading official dotnet-install.ps1..."
    try {
        Invoke-WebRequest -Uri $scriptUrl -OutFile $tempScript
        Unblock-File -Path $tempScript -ErrorAction SilentlyContinue

        & $tempScript -Channel "8.0" -InstallDir $installDir
        if ($LASTEXITCODE -ne 0) {
            throw "dotnet-install.ps1 failed."
        }
    } finally {
        if (Test-Path -LiteralPath $tempScript) {
            Remove-Item -LiteralPath $tempScript -Force -ErrorAction SilentlyContinue
        }
    }
}

function Install-BuildToolsFallback {
    $installerUrl = "https://aka.ms/vs/17/release/vs_BuildTools.exe"
    $tempInstaller = Join-Path $env:TEMP "vs_BuildTools.exe"
    $existingInstance = Get-VisualStudioInstanceInfo
    $targetInstallPath = if ($BuildToolsPath) { $BuildToolsPath } elseif ($existingInstance) { $existingInstance.installationPath } else { "C:\BuildTools" }

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

        & $tempInstaller @args
        if ($LASTEXITCODE -notin @(0, 3010)) {
            throw "Visual Studio Build Tools bootstrapper failed with exit code $LASTEXITCODE."
        }
    }

    function Invoke-InstallCleanupFallback {
        if (-not (Test-Path $installCleanupExe)) {
            throw "InstallCleanup.exe not found at $installCleanupExe"
        }

        Write-Warning "Running InstallCleanup.exe -i 17 to remove the broken Visual Studio Build Tools instance."
        & $installCleanupExe -i 17
        if ($LASTEXITCODE -notin @(0, 3010)) {
            throw "InstallCleanup.exe failed with exit code $LASTEXITCODE."
        }

        Start-Sleep -Seconds 5
    }

    Write-Host "winget not found. Downloading official Visual Studio Build Tools bootstrapper..."
    try {
        Invoke-WebRequest -Uri $installerUrl -OutFile $tempInstaller

        if ($existingInstance) {
            $setupExe = $existingInstance.properties.setupEngineFilePath
            if (-not $setupExe -or -not (Test-Path $setupExe)) {
                $setupExe = "C:\Program Files (x86)\Microsoft Visual Studio\Installer\setup.exe"
            }

            Ensure-Directory $existingInstance.installationPath

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
            & $setupExe @modifyArgs
            if ($LASTEXITCODE -notin @(0, 3010)) {
                throw "Visual Studio Installer modify failed with exit code $LASTEXITCODE."
            }

            Start-Sleep -Seconds 5
            if (Get-VisualStudioInstallPath) {
                return
            }

            Invoke-InstallCleanupFallback
            Invoke-BuildToolsBootstrapperInstall -InstallPath $targetInstallPath
            return
        }

        Invoke-BuildToolsBootstrapperInstall -InstallPath $targetInstallPath
    } finally {
        if (Test-Path -LiteralPath $tempInstaller) {
            Remove-Item -LiteralPath $tempInstaller -Force -ErrorAction SilentlyContinue
        }
    }
}

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

        $existingVsPath = Get-VisualStudioInstallPath
        if (-not $existingVsPath) {
            throw "Visual Studio Build Tools installation completed, but MSVC tools were still not detected."
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
