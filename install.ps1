# BuildDataverseSolution Installation Script
# This script downloads and installs BuildDataverseSolution to your PCF project
param(
    [string]$ProjectPath = ".",
    [switch]$Force,
    [switch]$SkipSetup
)

# Version information
$BUILDSOLUTION_VERSION = "1.0.0"
$BUILDSOLUTION_REPO = "https://github.com/garethcheyne/BuildDataverseSolution.git"
$BUILDSOLUTION_RAW_URL = "https://raw.githubusercontent.com/garethcheyne/BuildDataverseSolution/main"

# Color output functions
function Write-Success {
    param([string]$Message)
    Write-Host "[+] SUCCESS: $Message" -ForegroundColor Green
}

function Write-Info {
    param([string]$Message)
    Write-Host "[i] INFO: $Message" -ForegroundColor Cyan
}

function Write-Warning {
    param([string]$Message)
    Write-Host "[!] WARNING: $Message" -ForegroundColor Yellow
}

function Write-Error {
    param([string]$Message)
    Write-Host "[x] ERROR: $Message" -ForegroundColor Red
}

function Write-Header {
    param([string]$Message)
    Write-Host ""
    Write-Host "=== $Message ===" -ForegroundColor Blue
}

function Test-PCFProject {
    param([string]$Path)
    
    $pcfFiles = Get-ChildItem -Path $Path -Filter "*.pcfproj" -ErrorAction SilentlyContinue
    if ($pcfFiles.Count -eq 0) {
        return $false, "No PCF project file (*.pcfproj) found in the current directory."
    }
    
    if (-not (Test-Path (Join-Path $Path "package.json"))) {
        return $false, "No package.json found. This doesn't appear to be a valid PCF project."
    }
    
    return $true, "Valid PCF project structure detected."
}

function Get-InstalledVersion {
    param([string]$ProjectPath)
    
    $versionFile = Join-Path $ProjectPath "BuildDataverseSolution\.version"
    if (Test-Path $versionFile) {
        try {
            return Get-Content $versionFile -Raw | ConvertFrom-Json | Select-Object -ExpandProperty version
        }
        catch {
            return $null
        }
    }
    return $null
}

function Download-File {
    param(
        [string]$Url,
        [string]$OutputPath
    )
    
    try {
        # Ensure directory exists
        $directory = Split-Path $OutputPath -Parent
        if (-not (Test-Path $directory)) {
            New-Item -Path $directory -ItemType Directory -Force | Out-Null
        }
        
        # Try Invoke-WebRequest first (PowerShell 3.0+)
        if (Get-Command Invoke-WebRequest -ErrorAction SilentlyContinue) {
            Invoke-WebRequest -Uri $Url -OutFile $OutputPath -UseBasicParsing
            return $true
        }
        # Fallback to WebClient (.NET)
        elseif ([System.Net.WebClient]) {
            $webClient = New-Object System.Net.WebClient
            $webClient.DownloadFile($Url, $OutputPath)
            $webClient.Dispose()
            return $true
        }
        else {
            Write-Error "Unable to download files. Please install manually."
            return $false
        }
    }
    catch {
        Write-Error "Failed to download $Url`: $($_.Exception.Message)"
        return $false
    }
}

function Install-BuildDataverseSolution {
    param(
        [string]$ProjectPath,
        [bool]$IsUpgrade = $false
    )
    
    $buildSolutionDir = Join-Path $ProjectPath "BuildDataverseSolution"
    
    # Create BuildDataverseSolution directory
    if (-not (Test-Path $buildSolutionDir)) {
        New-Item -Path $buildSolutionDir -ItemType Directory -Force | Out-Null
    }
    
    # List of files to download
    $filesToDownload = @(
        @{ Source = "setup-project.ps1"; Dest = "setup-project.ps1" },
        @{ Source = "build-solution.ps1"; Dest = "build-solution.ps1" },
        @{ Source = "README.md"; Dest = "README.md" },
        @{ Source = "GETTING-STARTED.md"; Dest = "GETTING-STARTED.md" }
    )
    
    $downloadedFiles = 0
    
    foreach ($file in $filesToDownload) {
        $sourceUrl = "$BUILDSOLUTION_RAW_URL/$($file.Source)"
        $destPath = Join-Path $buildSolutionDir $file.Dest
        
        Write-Info "Downloading $($file.Source)..."
        
        if (Download-File -Url $sourceUrl -OutputPath $destPath) {
            $downloadedFiles++
        }
    }
    
    if ($downloadedFiles -eq $filesToDownload.Count) {
        # Create version file
        $versionInfo = @{
            version = $BUILDSOLUTION_VERSION
            installedDate = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
            repository = $BUILDSOLUTION_REPO
        }
        
        $versionFile = Join-Path $buildSolutionDir ".version"
        $versionInfo | ConvertTo-Json | Set-Content -Path $versionFile
        
        if ($IsUpgrade) {
            Write-Success "BuildDataverseSolution upgraded to version $BUILDSOLUTION_VERSION"
        } else {
            Write-Success "BuildDataverseSolution installed successfully!"
        }
        
        return $true
    } else {
        Write-Error "Failed to download all required files. Installation incomplete."
        return $false
    }
}

try {
    Write-Header "BuildDataverseSolution Installer"
    Write-Info "Installing BuildDataverseSolution v$BUILDSOLUTION_VERSION"
    
    # Resolve project path
    $ProjectPath = Resolve-Path $ProjectPath -ErrorAction Stop
    Write-Info "Project path: $ProjectPath"
    
    # Validate PCF project
    $isValid, $validationMessage = Test-PCFProject -Path $ProjectPath
    if (-not $isValid) {
        Write-Error $validationMessage
        Write-Info "Please run this script from your PCF project root directory"
        exit 1
    }
    Write-Success $validationMessage
    
    # Check for existing installation
    $installedVersion = Get-InstalledVersion -ProjectPath $ProjectPath
    $isUpgrade = $false
    
    if ($installedVersion) {
        Write-Info "BuildDataverseSolution v$installedVersion is already installed"
        
        if ($installedVersion -eq $BUILDSOLUTION_VERSION) {
            if (-not $Force) {
                Write-Info "You already have the latest version installed."
                Write-Info "Use -Force to reinstall or run setup-project.ps1 to reconfigure."
                exit 0
            }
        } else {
            Write-Info "A newer version (v$BUILDSOLUTION_VERSION) is available"
            if (-not $Force) {
                $upgrade = Read-Host "Do you want to upgrade? [Y/n]"
                if ($upgrade.ToLower() -eq "n" -or $upgrade.ToLower() -eq "no") {
                    Write-Info "Installation cancelled"
                    exit 0
                }
            }
            $isUpgrade = $true
        }
    }
    
    # Install/upgrade BuildDataverseSolution
    $installSuccess = Install-BuildDataverseSolution -ProjectPath $ProjectPath -IsUpgrade $isUpgrade
    
    if (-not $installSuccess) {
        exit 1
    }
    
    # Run setup unless skipped
    if (-not $SkipSetup) {
        Write-Header "Running Setup"
        Write-Info "Starting interactive setup..."
        
        $setupScript = Join-Path $ProjectPath "BuildDataverseSolution\setup-project.ps1"
        if (Test-Path $setupScript) {
            & $setupScript -ProjectPath $ProjectPath
        } else {
            Write-Warning "Setup script not found. You can run it manually later:"
            Write-Info ".\BuildDataverseSolution\setup-project.ps1"
        }
    } else {
        Write-Info "Setup skipped. You can run it manually later:"
        Write-Info ".\BuildDataverseSolution\setup-project.ps1"
    }
    
    Write-Header "Installation Complete"
    Write-Success "BuildDataverseSolution is ready to use!"
    Write-Info "Documentation: .\BuildDataverseSolution\GETTING-STARTED.md"
    
} catch {
    Write-Error "Installation failed: $($_.Exception.Message)"
    exit 1
}
