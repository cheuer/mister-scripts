[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$LocalFile,
    [string]$YamlPath,
    [string]$MisterHost,
    [string]$MisterSnesBase,
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptDirectory = if ($PSScriptRoot) {
    $PSScriptRoot
} elseif ($MyInvocation.MyCommand.Path) {
    Split-Path -Parent $MyInvocation.MyCommand.Path
} else {
    $PWD.Path
}

if ([string]::IsNullOrWhiteSpace($YamlPath)) {
    $YamlPath = Join-Path $scriptDirectory 'romloader.yaml'
} elseif (-not [System.IO.Path]::IsPathRooted($YamlPath)) {
    $YamlPath = Join-Path $scriptDirectory $YamlPath
}

$yamlModuleName = 'powershell-yaml'
$yamlModule = Get-Module -ListAvailable -Name $yamlModuleName | Select-Object -First 1
if (-not $yamlModule) {
    $installChoice = Read-Host "The PowerShell module '$yamlModuleName' is required to parse romloader.yaml. Install it now? [Y/n]"
    if ($installChoice -match '^(y|yes|)$') {
        try {
            Install-Module -Name $yamlModuleName -Scope CurrentUser -Force -ErrorAction Stop
            $yamlModule = Get-Module -ListAvailable -Name $yamlModuleName | Select-Object -First 1
        } catch {
            throw "Failed to install '$yamlModuleName'. Please run: Install-Module $yamlModuleName -Scope CurrentUser -Force"
        }
    } else {
        throw "Missing required module '$yamlModuleName'. Please install it with: Install-Module $yamlModuleName -Scope CurrentUser -Force"
    }
}

Import-Module $yamlModuleName -ErrorAction Stop

if (-not (Test-Path -LiteralPath $LocalFile -PathType Leaf)) {
    throw "File not found: $LocalFile"
}

if (-not (Test-Path -LiteralPath $YamlPath -PathType Leaf)) {
    throw "YAML file not found: $YamlPath"
}

function Get-RomLoaderYamlData {
    param([Parameter(Mandatory = $true)][string]$Path)

    $yamlContent = Get-Content -LiteralPath $Path -Raw
    return ConvertFrom-Yaml -Yaml $yamlContent
}

function Get-RomLoaderDestinations {
    param(
        [Parameter(Mandatory = $true)]$YamlData,
        [Parameter(Mandatory = $true)][string]$LocalFile
    )

    $candidates = New-Object System.Collections.Generic.List[object]
    $rules = Get-YamlValue -InputObject $YamlData -Name 'rules'
    if (-not $rules) {
        return $candidates
    }

    foreach ($ruleName in $rules.Keys) {
        $rule = $rules[$ruleName]
        $namePatterns = Get-YamlValue -InputObject $rule -Name 'name_pattern'
        $destinations = Get-YamlValue -InputObject $rule -Name 'destinations'

        $matchesPattern = $false
        if (-not $namePatterns) {
            $matchesPattern = $true
        } else {
            foreach ($pattern in @($namePatterns)) {
                if ([string]::IsNullOrWhiteSpace($pattern)) {
                    continue
                }

                if ($LocalFile -like [string]$pattern) {
                    $matchesPattern = $true
                    break
                }
            }
        }

        Write-Host "Rule '$ruleName': matchesPattern=$matchesPattern, destinations=$($destinations.Count)" -ForegroundColor Yellow

        if (-not $matchesPattern) {
            continue
        }

        if (-not $destinations) {
            continue
        }

        foreach ($destination in @($destinations)) {
            $name = Get-YamlValue -InputObject $destination -Name 'name'
            $path = Get-YamlValue -InputObject $destination -Name 'path'
            $romName = Get-YamlValue -InputObject $destination -Name 'romname'
            if ($name -and $path) {
                $candidates.Add([pscustomobject]@{
                    Name = [string]$name
                    Path = [string]$path
                    RomName = if ($romName) { [string]$romName } else { $null }
                })
            }
        }
    }

    return $candidates
}

function Get-YamlValue {
    param(
        $InputObject,
        [Parameter(Mandatory = $true)][string]$Name
    )

    if ($null -eq $InputObject) {
        return $null
    }

    if ($InputObject.PSObject.Properties.Name -contains $Name) {
        return $InputObject.$Name
    }

    if ($InputObject -is [System.Collections.IDictionary]) {
        if ($InputObject.Contains($Name)) {
            return $InputObject[$Name]
        }
    }

    return $null
}

function Join-RemotePath {
    param([string]$BasePath, [string]$TargetName)

    $sanitizedBase = $BasePath.TrimEnd('/', '\')
    $sanitizedTarget = $TargetName.TrimStart('/', '\')
    return '{0}/{1}' -f $sanitizedBase, $sanitizedTarget
}

function Write-TitleOutput {
    param([string]$FilePath, [string]$Value)

    if ([string]::IsNullOrWhiteSpace($FilePath)) {
        return
    }

    $parentPath = Split-Path -Path $FilePath -Parent
    if ($parentPath) {
        New-Item -ItemType Directory -Path $parentPath -Force | Out-Null
    }

    [System.IO.File]::WriteAllText($FilePath, $Value)
}

$localBasename = Split-Path -Path $LocalFile -Leaf
$yamlData = Get-RomLoaderYamlData -Path $YamlPath

$yamlHost = Get-YamlValue -InputObject $yamlData -Name 'mister_host'
$yamlBase = Get-YamlValue -InputObject $yamlData -Name 'mister_snes_base'
$yamlTitleOutputFile = Get-YamlValue -InputObject $yamlData -Name 'title_output_file'
$yamlDefaultTitle = Get-YamlValue -InputObject $yamlData -Name 'default_title'

$resolvedHost = if ($MisterHost) {
    $MisterHost
} elseif ($yamlHost) {
    [string]$yamlHost
} else {
    'mister.local'
}

$resolvedBase = if ($MisterSnesBase) {
    $MisterSnesBase
} elseif ($yamlBase) {
    [string]$yamlBase
} else {
    '/media/fat/games/SNES'
}

$titleOutputFile = if ($yamlTitleOutputFile) { [string]$yamlTitleOutputFile } else { $null }
$defaultTitle = if ($yamlDefaultTitle) { [string]$yamlDefaultTitle } else { 'Not an MSU pack' }

$candidates = @(Get-RomLoaderDestinations -YamlData $yamlData -LocalFile $localBasename)

if ($candidates.Count -eq 0) {
    throw "No matching destinations found for '$localBasename'."
}

Write-Host "Loaded $($candidates.Count) destination(s) from $YamlPath" -ForegroundColor Cyan

$menuItems = @()

foreach ($candidate in $candidates) {
    $menuItems += [pscustomobject]@{
        Label = $candidate.Name
        Type = 'pack'
        Name = $candidate.Name
        Path = $candidate.Path
        RomName = $candidate.RomName
    }
}

Write-Host "`nSelect a destination:"
for ($i = 0; $i -lt $menuItems.Count; $i++) {
    Write-Host ("{0}. {1}" -f ($i + 1), $menuItems[$i].Label)
}

$choice = Read-Host 'Enter choice number'
if ($choice -notmatch '^\d+$') {
    throw 'Invalid selection.'
}

$choiceNumber = [int]$choice
if ($choiceNumber -lt 1 -or $choiceNumber -gt $menuItems.Count) {
    throw 'Selection out of range.'
}

$selected = $menuItems[$choiceNumber - 1]
$targetName = if ($selected.RomName) { $selected.RomName } else { $localBasename }
$remotePath = Join-RemotePath -BasePath ($resolvedBase + $selected.Path) -TargetName $targetName

if ($selected.Name -eq 'default') {
    $titleText = $defaultTitle
} else {
    $titleText = $selected.Name
}

if ($titleOutputFile) {
    Write-TitleOutput -FilePath $titleOutputFile -Value $titleText
}

Write-Host "`nAbout to run:"
Write-Host ("scp -- {0} {1}:{2}" -f $LocalFile, $resolvedHost, $remotePath)

if ($DryRun) {
    Write-Host 'Dry run only; no copy or launch performed.'
    return
}

Write-Host 'Copying…'
$copyExitCode = 0
try {
    & scp -- $LocalFile ("{0}:{1}" -f $resolvedHost, $remotePath)
    $copyExitCode = $LASTEXITCODE
} catch {
    $copyExitCode = 1
}

if ($copyExitCode -eq 0) {
    Write-Host 'Copy succeeded.'

    Write-Host 'Launching ROM on MiSTer…'
    try {
        $launchBody = @{ path = $remotePath } | ConvertTo-Json -Compress
        $null = curl.exe -s -X POST ("http://{0}:8182/api/launch" -f $resolvedHost) -H 'Content-Type: application/json' --data $launchBody
        Write-Host 'Launch POST succeeded.'
    } catch {
        Write-Warning 'Launch POST failed.'
    }

    Write-Host 'Done.'
} else {
    throw "Copy failed with exit code $copyExitCode."
}
