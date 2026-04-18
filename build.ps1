[CmdletBinding()]
param(
    [switch]$SkipPbo,
    [switch]$SkipToolsCopy
)

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$buildDir = Join-Path $root "build"
$modFolderName = "@YouTube Player Music"
$stagedModRoot = Join-Path $buildDir "${modFolderName}_staged"
$legacyStagedModRoot = Join-Path $buildDir "@A3YTPlayer_staged"
$srcAddonDir = Join-Path $root "src\\addon\\a3yt_player"
$nativeProject = Join-Path $root "src\\native\\A3YT.Native\\A3YT.Native.csproj"
$modRoot = Join-Path $root ("mod\\" + $modFolderName)
$legacyModRoot = Join-Path $root "mod\\@A3YTPlayer"
$modAddonsDir = Join-Path $modRoot "addons"
$modKeysDir = Join-Path $modRoot "Key"
$toolsDir = Join-Path $root "tools"
$extensionBaseName = "youtube_player_music"
$extensionDllName32 = "${extensionBaseName}.dll"
$extensionDllName64 = "${extensionBaseName}_x64.dll"
$addonPboName = "youtube_player_music.pbo"
$discordInvite = "https://discord.gg/2AftdXY333"
$localDotnet = Join-Path $HOME ".dotnet\\dotnet.exe"
$dotnetCommand = Get-Command dotnet.exe -ErrorAction SilentlyContinue
$dotnet = if (Test-Path $localDotnet) { $localDotnet } elseif ($dotnetCommand) { $dotnetCommand.Source } else { $localDotnet }
$addonBuilder = if ($env:A3YT_ADDONBUILDER_PATH) { $env:A3YT_ADDONBUILDER_PATH } else { "C:\\Program Files (x86)\\Steam\\steamapps\\common\\Arma 3 Tools\\AddonBuilder\\AddonBuilder.exe" }
$dsSignFile = if ($env:A3YT_DSSIGNFILE_PATH) { $env:A3YT_DSSIGNFILE_PATH } else { "C:\\Program Files (x86)\\Steam\\steamapps\\common\\Arma 3 Tools\\DSSignFile\\DSSignFile.exe" }
$keyRoot = Join-Path (Split-Path $root -Parent) "BKey"
$preferredSigningKeyName = if ($env:A3YT_SIGNING_KEY_NAME) { $env:A3YT_SIGNING_KEY_NAME } else { "Alpha" }
$script:CachedVsInstallPath = $null
$script:CachedMsvcRoot = $null

function Ensure-Directory {
    param([string]$Path)

    if (!(Test-Path $Path)) {
        New-Item -ItemType Directory -Path $Path | Out-Null
    }
}

function Remove-PathIfExists {
    param([string]$Path)

    if (Test-Path $Path) {
        Remove-Item $Path -Recurse -Force
    }
}

function Write-Utf8File {
    param(
        [string]$Path,
        [string]$Content
    )

    $utf8Bom = New-Object System.Text.UTF8Encoding($true)
    [System.IO.File]::WriteAllText($Path, $Content, $utf8Bom)
}

function Get-LatestChildDir {
    param([string]$Path)

    $item = Get-ChildItem $Path -Directory | Sort-Object Name -Descending | Select-Object -First 1
    if (-not $item) {
        throw "Directory not found under $Path"
    }

    return $item.FullName
}

function Get-LatestVersionedChildDir {
    param([string]$Path)

    $item = Get-ChildItem $Path -Directory |
        Where-Object { $_.Name -match '^\d+\.\d+\.\d+\.\d+$' } |
        Sort-Object Name -Descending |
        Select-Object -First 1

    if (-not $item) {
        throw "Versioned directory not found under $Path"
    }

    return $item.FullName
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
    if ($script:CachedVsInstallPath) {
        return $script:CachedVsInstallPath
    }

    $candidateRoots = @()
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
            $script:CachedVsInstallPath = $candidateRoot
            return $script:CachedVsInstallPath
        }
    }

    $vswhere = Resolve-VsWherePath
    if ($vswhere) {
        $installationPath = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath 2>$null | Select-Object -First 1
        if ($LASTEXITCODE -eq 0 -and $installationPath -and (Test-Path (Join-Path $installationPath "VC\\Tools\\MSVC"))) {
            $script:CachedVsInstallPath = $installationPath
            return $script:CachedVsInstallPath
        }
    }

    throw @"
MSVC Build Tools were not found.

Expected one of:
- Visual Studio Build Tools / Community / Professional / Enterprise with C++ tools
- a custom install path exposed via A3YT_VS_INSTALL_PATH

Run .\setup_dev_environment.ps1 to install the dependencies, or install Visual Studio Build Tools manually.
"@
}

function Get-MsvcToolsRoot {
    if ($script:CachedMsvcRoot) {
        return $script:CachedMsvcRoot
    }

    $vsInstallPath = Get-VisualStudioInstallPath
    $script:CachedMsvcRoot = Get-LatestChildDir (Join-Path $vsInstallPath "VC\\Tools\\MSVC")
    return $script:CachedMsvcRoot
}

function Resolve-SigningKeyPair {
    param(
        [string]$KeyDirectory,
        [string]$PreferredBaseName = "Alpha"
    )

    if (!(Test-Path $KeyDirectory)) {
        return $null
    }

    $candidateBases = @()
    if (![string]::IsNullOrWhiteSpace($PreferredBaseName)) {
        $candidateBases += $PreferredBaseName
    }

    $candidateBases += Get-ChildItem $KeyDirectory -Filter *.biprivatekey -File -ErrorAction SilentlyContinue |
        ForEach-Object { [System.IO.Path]::GetFileNameWithoutExtension($_.Name) }

    $candidateBases = $candidateBases | Where-Object { $_ } | Select-Object -Unique

    foreach ($baseName in $candidateBases) {
        $privateKey = Join-Path $KeyDirectory "$baseName.biprivatekey"
        $publicKey = Join-Path $KeyDirectory "$baseName.bikey"
        if ((Test-Path $privateKey) -and (Test-Path $publicKey)) {
            return [PSCustomObject]@{
                BaseName   = $baseName
                PrivateKey = $privateKey
                PublicKey  = $publicKey
            }
        }
    }

    return $null
}

function Invoke-MsvcExtensionBuild {
    param(
        [string]$OutputDll,
        [ValidateSet("x86", "x64")]
        [string]$Arch,
        [string]$SourceFile = "src\\extension\\a3yt_player.cpp",
        [string]$DefinitionFile = "src\\extension\\a3yt_player.def",
        [string]$ResourceFile = "",
        [string[]]$AdditionalLinkArgs = @()
    )

    $msvcRoot = Get-MsvcToolsRoot
    $sdkRoot = Get-LatestChildDir "C:\\Program Files (x86)\\Windows Kits\\10\\Lib"
    $sdkIncludeRoot = Get-LatestChildDir "C:\\Program Files (x86)\\Windows Kits\\10\\Include"

    $binArch = if ($Arch -eq "x86") { "Hostx64\\x86" } else { "Hostx64\\x64" }
    $libArch = if ($Arch -eq "x86") { "x86" } else { "x64" }

    $cl = Join-Path $msvcRoot "bin\\$binArch\\cl.exe"
    if (!(Test-Path $cl)) {
        throw "MSVC compiler not found: $cl"
    }

    $sdkBinRoot = Get-LatestVersionedChildDir "C:\\Program Files (x86)\\Windows Kits\\10\\bin"
    $rc = Join-Path $sdkBinRoot "x64\\rc.exe"
    if (![string]::IsNullOrWhiteSpace($ResourceFile) -and !(Test-Path $rc)) {
        throw "Windows resource compiler not found: $rc"
    }

    $env:PATH = "$(Split-Path $cl -Parent);$env:PATH"
    $env:LIB = "$msvcRoot\\lib\\$libArch;$sdkRoot\\um\\$libArch;$sdkRoot\\ucrt\\$libArch"
    $env:INCLUDE = "$msvcRoot\\include;$sdkIncludeRoot\\ucrt;$sdkIncludeRoot\\um;$sdkIncludeRoot\\shared;$sdkIncludeRoot\\winrt;$sdkIncludeRoot\\cppwinrt"

    $compiledResource = ""
    if (![string]::IsNullOrWhiteSpace($ResourceFile)) {
        $compiledResource = [System.IO.Path]::ChangeExtension($OutputDll, ".res")
        & $rc /nologo /fo $compiledResource $ResourceFile
        if ($LASTEXITCODE -ne 0) {
            throw "Resource compile failed for $ResourceFile"
        }
    }

    $clArgs = @(
        "/nologo",
        "/std:c++17",
        "/GL",
        "/Gw",
        "/Gy",
        "/O2",
        "/Ob2",
        "/Oi",
        "/Ot",
        "/MT",
        "/EHsc",
        "/LD",
        "/DUNICODE",
        "/D_UNICODE",
        $SourceFile
    )

    if (![string]::IsNullOrWhiteSpace($compiledResource)) {
        $clArgs += $compiledResource
    }

    $clArgs += @(
        "/link",
        "/NOLOGO",
        "/LTCG",
        "/OPT:REF",
        "/OPT:ICF",
        "/INCREMENTAL:NO"
    )

    if (![string]::IsNullOrWhiteSpace($DefinitionFile)) {
        $clArgs += "/DEF:$DefinitionFile"
    }

    $clArgs += @(
        "/OUT:$OutputDll",
        "mfplat.lib",
        "mfplay.lib",
        "mfuuid.lib",
        "ole32.lib",
        "shlwapi.lib",
        "propsys.lib"
    )

    if ($AdditionalLinkArgs.Count -gt 0) {
        $clArgs += $AdditionalLinkArgs
    }

    & $cl @clArgs

    if ($LASTEXITCODE -ne 0) {
        throw "MSVC build failed for $OutputDll"
    }
}

function Invoke-NativeBackendPublish {
    param(
        [string]$RuntimeIdentifier,
        [string]$Arch
    )

    if (!(Test-Path $dotnet)) {
        throw ".NET SDK not found at $dotnet"
    }

    $msvcRoot = Get-MsvcToolsRoot
    $sdkRoot = Get-LatestChildDir "C:\\Program Files (x86)\\Windows Kits\\10\\Lib"
    $sdkIncludeRoot = Get-LatestChildDir "C:\\Program Files (x86)\\Windows Kits\\10\\Include"

    $binArch = if ($Arch -eq "x86") { "Hostx64\\x86" } else { "Hostx64\\x64" }
    $libArch = if ($Arch -eq "x86") { "x86" } else { "x64" }

    $env:PATH = "$($dotnet | Split-Path -Parent);$msvcRoot\\bin\\$binArch;$env:PATH"
    $env:LIB = "$msvcRoot\\lib\\$libArch;$sdkRoot\\ucrt\\$libArch;$sdkRoot\\um\\$libArch"
    $env:INCLUDE = "$msvcRoot\\include;$sdkIncludeRoot\\ucrt;$sdkIncludeRoot\\um;$sdkIncludeRoot\\shared"

    & $dotnet publish $nativeProject `
        -c Release `
        -r $RuntimeIdentifier `
        -p:IlcUseEnvironmentalTools=true `
        -p:CppLinker="$msvcRoot\\bin\\$binArch\\link.exe" `
        -p:CppLibCreator="$msvcRoot\\bin\\$binArch\\lib.exe"

    if ($LASTEXITCODE -ne 0) {
        throw "dotnet publish failed for $RuntimeIdentifier"
    }
}

function Get-NativeBackendLinkArgs {
    param([string]$RuntimeIdentifier)

    $nativeProjectDir = Split-Path $nativeProject -Parent
    $linkRsp = Join-Path $nativeProjectDir ("obj\\Release\\net8.0-windows\\{0}\\native\\link.rsp" -f $RuntimeIdentifier)
    if (!(Test-Path $linkRsp)) {
        throw "Native backend link.rsp not found: $linkRsp"
    }

    $resolvedArgs = @()
    foreach ($line in Get-Content $linkRsp) {
        $trimmed = $line.Trim()
        if ([string]::IsNullOrWhiteSpace($trimmed)) {
            continue
        }

        if (
            $trimmed -like "/OUT:*" -or
            $trimmed -like "/DEF:*" -or
            $trimmed -eq "/DLL" -or
            $trimmed -like "/NOLOGO*" -or
            $trimmed -like "/MANIFEST:*" -or
            $trimmed -like "/DEBUG*" -or
            $trimmed -like "/INCREMENTAL:*" -or
            $trimmed -like "/NATVIS:*"
        ) {
            continue
        }

        if ($trimmed.StartsWith('"') -and $trimmed.EndsWith('"')) {
            $value = $trimmed.Trim('"')
            if (-not [System.IO.Path]::IsPathRooted($value)) {
                $candidate = Join-Path $nativeProjectDir $value
                if (Test-Path $candidate) {
                    $value = $candidate
                }
            }

            $resolvedArgs += $value
            continue
        }

        $resolvedArgs += $trimmed
    }

    return ,$resolvedArgs
}

Ensure-Directory $buildDir

if ((Test-Path $legacyModRoot) -and !(Test-Path $modRoot)) {
    Move-Item $legacyModRoot $modRoot
}

if ((Test-Path $legacyStagedModRoot) -and !(Test-Path $stagedModRoot)) {
    Move-Item $legacyStagedModRoot $stagedModRoot
}

Ensure-Directory $modRoot
Ensure-Directory $modAddonsDir
Ensure-Directory $modKeysDir

Remove-PathIfExists (Join-Path $root "src\\native\\A3YT.Native\\bin\\Release")
Remove-PathIfExists (Join-Path $root "src\\native\\A3YT.Native\\obj\\Release")

Invoke-NativeBackendPublish -RuntimeIdentifier "win-x64" -Arch "x64"
Invoke-MsvcExtensionBuild `
    -OutputDll (Join-Path $buildDir $extensionDllName64) `
    -Arch "x64" `
    -AdditionalLinkArgs (Get-NativeBackendLinkArgs -RuntimeIdentifier "win-x64")
Invoke-MsvcExtensionBuild `
    -OutputDll (Join-Path $buildDir $extensionDllName32) `
    -Arch "x86" `
    -SourceFile "src\\extension\\a3yt_player_x86_stub.cpp" `
    -DefinitionFile $null `
    -ResourceFile "src\\extension\\youtube_player_music_x86.rc"

Copy-Item (Join-Path $buildDir $extensionDllName64) (Join-Path $modRoot $extensionDllName64) -Force
Copy-Item (Join-Path $buildDir $extensionDllName32) (Join-Path $modRoot $extensionDllName32) -Force

if (!$SkipPbo) {
    if (!(Test-Path $addonBuilder)) {
        throw "AddonBuilder.exe not found: $addonBuilder"
    }

    if (!(Test-Path $dsSignFile)) {
        throw "DSSignFile.exe not found: $dsSignFile"
    }

    & $addonBuilder $srcAddonDir $modAddonsDir -packonly
    if ($LASTEXITCODE -ne 0) {
        throw "AddonBuilder failed."
    }

    $sourcePbo = Join-Path $modAddonsDir "a3yt_player.pbo"
    if (Test-Path $sourcePbo) {
        Move-Item $sourcePbo (Join-Path $modAddonsDir $addonPboName) -Force
    }

    $signedPbo = Join-Path $modAddonsDir $addonPboName
    Remove-Item "$signedPbo.*.bisign" -Force -ErrorAction SilentlyContinue
    Get-ChildItem $modKeysDir -Filter *.bikey -File -ErrorAction SilentlyContinue | Remove-Item -Force

    $signingKeyPair = Resolve-SigningKeyPair -KeyDirectory $keyRoot -PreferredBaseName $preferredSigningKeyName
    if ($signingKeyPair) {
        & $dsSignFile $signingKeyPair.PrivateKey $signedPbo
        if ($LASTEXITCODE -ne 0) {
            throw "DSSignFile failed for $signedPbo"
        }

        Copy-Item $signingKeyPair.PublicKey (Join-Path $modKeysDir "$($signingKeyPair.BaseName).bikey") -Force
    } else {
        Write-Warning "No signing key pair found under $keyRoot. Built unsigned PBO for local development."
    }
}

foreach ($obsolete in @("a3yt_player.pbo", "a3yt_player.txt")) {
    Remove-Item (Join-Path $modAddonsDir $obsolete) -Force -ErrorAction SilentlyContinue
}
Remove-Item (Join-Path $modAddonsDir "a3yt_player") -Recurse -Force -ErrorAction SilentlyContinue

$modDescriptionRu = "Музыкальный YouTube-плеер для Zeus."
$modOverviewRu = "Этот мод должен использоваться только в оригинальном, неизменённом виде и в пресете должен стоять отдельным модом. Связь и разрешения: Discord $discordInvite."
$modDescriptionEn = "YouTube music audio player for Zeus and curator. Global playlist, radio, song player, sound and audio queue."
$modKeywordsRu = "Ключевые слова: youtube музыка аудио плеер плейлист зевс radio песни звук глобальный."
$modSearchRu = "Поиск: youtube музыка аудио плеер плейлист зевс радио песни звук."
$modOverviewEn = "This mod must remain in its original, unmodified form. If used in a preset or modpack, it must stay as a separate standalone mod and must not be repacked, merged, or bundled into another package. Contact, support, and permissions: Discord $discordInvite."

$modCpp = @"
name = "YouTube Player Music";
picture = "";
actionName = "Discord";
action = "$discordInvite";
description = "EN: $modDescriptionEn Keywords: youtube music audio player playlist zeus curator radio song sound global. RU: $modDescriptionRu $modKeywordsRu";
logo = "";
logoOver = "";
tooltip = "YouTube Player Music | youtube music audio player playlist zeus";
tooltipOwned = "YouTube Player Music | youtube music audio player playlist zeus";
overview = "EN: $modOverviewEn Search: youtube music audio player playlist zeus curator radio song sound.  RU: $modOverviewRu $modSearchRu";
author = "Alpha";
hideName = 0;
hidePicture = 0;
"@
Write-Utf8File -Path (Join-Path $modRoot "mod.cpp") -Content $modCpp

foreach ($obsolete in @("yt-dlp.exe", "ffplay.exe")) {
    Remove-Item (Join-Path $modRoot $obsolete) -Force -ErrorAction SilentlyContinue
    Remove-Item (Join-Path $toolsDir $obsolete) -Force -ErrorAction SilentlyContinue
}

foreach ($obsoleteDll in @(
    "a3yt_player.dll",
    "a3yt_backend.dll",
    "a3yt_player_x64.dll",
    "a3yt_backend_x64.dll",
    "youtube_player_music_backend.dll",
    "youtube_player_music_backend_x64.dll"
)) {
    Remove-Item (Join-Path $modRoot $obsoleteDll) -Force -ErrorAction SilentlyContinue
    Remove-Item (Join-Path $toolsDir $obsoleteDll) -Force -ErrorAction SilentlyContinue
}

Remove-Item (Join-Path $modRoot "vlc") -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item (Join-Path $toolsDir "vlc") -Recurse -Force -ErrorAction SilentlyContinue

if (!$SkipToolsCopy) {
    Copy-Item (Join-Path $buildDir $extensionDllName64) (Join-Path $toolsDir $extensionDllName64) -Force
    Copy-Item (Join-Path $buildDir $extensionDllName32) (Join-Path $toolsDir $extensionDllName32) -Force
}

if (Test-Path $stagedModRoot) {
    Remove-Item $stagedModRoot -Recurse -Force
}

Copy-Item $modRoot $stagedModRoot -Recurse -Force

Write-Host "Build complete."
Write-Host "Mod root: $modRoot"
