[CmdletBinding()]
param(
    [string]$AssetRoot = "$env:ProgramData\kmos\assets",
    [string]$RegistryRoot = 'HKCU:',
    [string]$HomePath = $HOME,
    [switch]$SkipBrowserDefault
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$WallpaperPath = Join-Path $AssetRoot 'wallpapers\kmos-wallpaper.png'
$StarshipPreset = Join-Path $AssetRoot 'starship-presets\holow-light.toml'
$StarshipCandidates = @(
    'C:\Program Files\starship\bin\starship.exe',
    'C:\Program Files (x86)\starship\bin\starship.exe',
    (Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links\starship.exe')
)
$FirefoxCandidates = @(
    'C:\Program Files\Firefox Developer Edition\firefox.exe',
    'C:\Program Files (x86)\Firefox Developer Edition\firefox.exe'
)

function Ensure-Directory {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Join-RegistryPath {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$Child
    )

    return ($Root.TrimEnd('\') + '\' + $Child.TrimStart('\'))
}

function Set-RegistryValue {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)]$Value,
        [ValidateSet('String','DWord','QWord','Binary','MultiString','ExpandString')]
        [string]$Type = 'String'
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -Path $Path -Force | Out-Null
    }

    try {
        Set-ItemProperty -Path $Path -Name $Name -Value $Value -Force -ErrorAction Stop | Out-Null
    } catch {
        if ($_.Exception.Message -match 'does not exist' -or $_.FullyQualifiedErrorId -match 'System.Management.Automation.PSArgumentException') {
            New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType $Type -Force | Out-Null
        } else {
            throw
        }
    }
}

function Ensure-PowerShellProfile {
    param([Parameter(Mandatory)][string]$ProfilePath)

    Ensure-Directory -Path (Split-Path -Parent $ProfilePath)

    $marker = '# kmos'
    $content = @(
        $marker
        '$env:STARSHIP_CONFIG = ''C:\ProgramData\kmos\assets\starship-presets\holow-light.toml'''
        '$kmosStarship = @('
        '  ''C:\Program Files\starship\bin\starship.exe'''
        '  ''C:\Program Files (x86)\starship\bin\starship.exe'''
        '  (Join-Path $env:LOCALAPPDATA ''Microsoft\WinGet\Links\starship.exe'')'
        ') | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1'
        'if (-not $kmosStarship) {'
        '  $kmosStarship = (Get-Command starship -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source -First 1)'
        '}'
        'if ($kmosStarship) {'
        '  Invoke-Expression (& $kmosStarship init powershell)'
        '}'
    ) -join [Environment]::NewLine

    if (Test-Path -LiteralPath $ProfilePath) {
        $existing = Get-Content -LiteralPath $ProfilePath -Raw
        if ($existing -match [regex]::Escape($marker)) {
            return
        }
        Add-Content -LiteralPath $ProfilePath -Value ([Environment]::NewLine + $content + [Environment]::NewLine)
    } else {
        Set-Content -LiteralPath $ProfilePath -Value ($content + [Environment]::NewLine) -Encoding UTF8
    }
}

function Get-StarshipCommand {
    $command = Get-Command starship -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }

    return $StarshipCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
}

function Apply-VisualDefaults {
    Set-RegistryValue -Path (Join-RegistryPath $RegistryRoot 'Software\Microsoft\Windows\CurrentVersion\Themes\Personalize') -Name 'AppsUseLightTheme' -Value 0 -Type DWord
    Set-RegistryValue -Path (Join-RegistryPath $RegistryRoot 'Software\Microsoft\Windows\CurrentVersion\Themes\Personalize') -Name 'SystemUsesLightTheme' -Value 0 -Type DWord
    Set-RegistryValue -Path (Join-RegistryPath $RegistryRoot 'Software\Microsoft\Windows\CurrentVersion\Themes\Personalize') -Name 'ColorPrevalence' -Value 0 -Type DWord
    Set-RegistryValue -Path (Join-RegistryPath $RegistryRoot 'Software\Microsoft\Windows\CurrentVersion\Themes\Personalize') -Name 'EnableTransparency' -Value 0 -Type DWord

    Set-RegistryValue -Path (Join-RegistryPath $RegistryRoot 'Control Panel\Colors') -Name 'Background' -Value '0 0 0'
    Set-RegistryValue -Path (Join-RegistryPath $RegistryRoot 'Control Panel\Desktop') -Name 'WallpaperStyle' -Value '6'
    Set-RegistryValue -Path (Join-RegistryPath $RegistryRoot 'Control Panel\Desktop') -Name 'TileWallpaper' -Value '0'
    Set-RegistryValue -Path (Join-RegistryPath $RegistryRoot 'Software\Microsoft\Windows\DWM') -Name 'AccentColor' -Value 4285887861 -Type DWord
    Set-RegistryValue -Path (Join-RegistryPath $RegistryRoot 'Software\Microsoft\Windows\DWM') -Name 'AccentColorInactive' -Value 4282400832 -Type DWord
    Set-RegistryValue -Path (Join-RegistryPath $RegistryRoot 'Software\Microsoft\Windows\CurrentVersion\Explorer\Accent') -Name 'AccentColorMenu' -Value 4285887861 -Type DWord

    if (Test-Path -LiteralPath $WallpaperPath) {
        Set-RegistryValue -Path (Join-RegistryPath $RegistryRoot 'Control Panel\Desktop') -Name 'WallPaper' -Value $WallpaperPath
        if ($RegistryRoot -eq 'HKCU:') {
            Add-Type -TypeDefinition @"
using System.Runtime.InteropServices;
public class KmosWallpaper {
  [DllImport("user32.dll", SetLastError=true, CharSet=CharSet.Auto)]
  public static extern int SystemParametersInfo(int uiAction, int uiParam, string pvParam, int fWinIni);
}
"@ -ErrorAction SilentlyContinue | Out-Null
            [void][KmosWallpaper]::SystemParametersInfo(20, 0, $WallpaperPath, 3)
        }
    }

    Set-RegistryValue -Path (Join-RegistryPath $RegistryRoot 'Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced') -Name 'TaskbarDa' -Value 0 -Type DWord
    Set-RegistryValue -Path (Join-RegistryPath $RegistryRoot 'Software\Microsoft\Windows\CurrentVersion\Dsh') -Name 'IsPrelaunchEnabled' -Value 0 -Type DWord
}

function Set-FirefoxDeveloperEditionDefault {
    $firefox = $FirefoxCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    if (-not $firefox) {
        return
    }

    try {
        Start-Process -FilePath $firefox -ArgumentList '-setDefaultBrowser' -Wait -WindowStyle Hidden
    } catch {
        # Windows 11 can reject fully silent default-browser changes for the current user.
    }
}

Ensure-PowerShellProfile -ProfilePath (Join-Path $HomePath 'Documents\PowerShell\Microsoft.PowerShell_profile.ps1')
Ensure-PowerShellProfile -ProfilePath (Join-Path $HomePath 'Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1')
Apply-VisualDefaults
if (-not $SkipBrowserDefault) {
    Set-FirefoxDeveloperEditionDefault
}
