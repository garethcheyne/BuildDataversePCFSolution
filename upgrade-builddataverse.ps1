#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Upgrade BuildDataversePCFSolution to the latest version
.DESCRIPTION
    This script checks the GitHub repository for the latest version of BuildDataversePCFSolution
    and upgrades the current installation if a newer version is available.
.PARAMETER Force
    Force upgrade even if the current version is up to date
.PARAMETER CheckOnly
    Only check for updates without upgrading
.EXAMPLE
    .\upgrade-builddataverse.ps1
    .\upgrade-builddataverse.ps1 -Force
    .\upgrade-builddataverse.ps1 -CheckOnly
#>

param(
    [switch]$Force,
    [switch]$CheckOnly
)

# Set error action preference
$ErrorActionPreference = "Stop"

# Repository information
$REPO_OWNER = "garethcheyne"
$REPO_NAME = "BuildDataversePCFSolution"
$GITHUB_API_URL = "https://api.github.com/repos/$REPO_OWNER/$REPO_NAME/releases/latest"
$INSTALL_SCRIPT_URL = "https://raw.githubusercontent.com/$REPO_OWNER/$REPO_NAME/main/install.ps1"

# Color output functions
function Write-Info {
    param([string]$Message)
    Write-Host "[i] INFO: $Message" -ForegroundColor Cyan
}

function Write-Success {
    param([string]$Message)
    Write-Host "[+] SUCCESS: $Message" -ForegroundColor Green
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

# Function to get current installed version
function Get-CurrentVersion {
    $versionFile = "BuildDataversePCFSolution\.version"
    if (Test-Path $versionFile) {
        try {
            $versionData = Get-Content $versionFile -Raw | ConvertFrom-Json
            return $versionData.version
        }
        catch {
            Write-Warning "Could not read current version from .version file"
            return $null
        }
    }
    return $null
}

# Function to get latest version from GitHub
function Get-LatestVersion {
    try {
        Write-Info "Checking for latest version..."
        
        # Use GitHub API to get latest release
        if (Get-Command Invoke-RestMethod -ErrorAction SilentlyContinue) {
            $response = Invoke-RestMethod -Uri $GITHUB_API_URL -ErrorAction Stop
            return $response.tag_name -replace '^v', ''  # Remove 'v' prefix if present
        }
        # Fallback to Invoke-WebRequest
        elseif (Get-Command Invoke-WebRequest -ErrorAction SilentlyContinue) {
            $response = Invoke-WebRequest -Uri $GITHUB_API_URL -UseBasicParsing -ErrorAction Stop
            $json = $response.Content | ConvertFrom-Json
            return $json.tag_name -replace '^v', ''  # Remove 'v' prefix if present
        }
        else {
            throw "Neither Invoke-RestMethod nor Invoke-WebRequest is available"
        }
    }
    catch {
        Write-Warning "Could not fetch latest version from GitHub: $($_.Exception.Message)"
        Write-Info "Falling back to install script approach..."
        return $null
    }
}

# Function to compare versions
function Compare-Versions {
    param(
        [string]$CurrentVersion,
        [string]$LatestVersion
    )
    
    if (-not $CurrentVersion -or -not $LatestVersion) {
        return $true  # Assume update needed if we can't compare
    }
    
    try {
        $current = [Version]$CurrentVersion
        $latest = [Version]$LatestVersion
        return $latest -gt $current
    }
    catch {
        # Fallback to string comparison if version parsing fails
        return $LatestVersion -ne $CurrentVersion
    }
}

# Function to perform upgrade
function Invoke-Upgrade {
    Write-Info "Downloading and running upgrade..."
    
    try {
        # Download the latest install script
        $tempScript = "upgrade-temp.ps1"
        
        if (Get-Command Invoke-WebRequest -ErrorAction SilentlyContinue) {
            Invoke-WebRequest -Uri $INSTALL_SCRIPT_URL -OutFile $tempScript -UseBasicParsing
        }
        else {
            throw "Invoke-WebRequest is not available"
        }
        
        # Run the install script with force and skip setup flags
        Write-Info "Running upgrade installation..."
        & ".\$tempScript" -Force -SkipSetup
        
        if ($LASTEXITCODE -eq 0) {
            Write-Success "Upgrade completed successfully!"
            
            # Clean up temp file
            Remove-Item $tempScript -ErrorAction SilentlyContinue
            
            # Show new version
            $newVersion = Get-CurrentVersion
            if ($newVersion) {
                Write-Success "Updated to version: $newVersion"
            }
            
            return $true
        }
        else {
            Write-Error "Upgrade installation failed"
            Remove-Item $tempScript -ErrorAction SilentlyContinue
            return $false
        }
    }
    catch {
        Write-Error "Upgrade failed: $($_.Exception.Message)"
        if (Test-Path $tempScript) {
            Remove-Item $tempScript -ErrorAction SilentlyContinue
        }
        return $false
    }
}

try {
    Write-Header "BuildDataversePCFSolution Upgrade Utility"
    
    # Check if we're in a valid project directory
    if (-not (Test-Path "BuildDataversePCFSolution")) {
        Write-Error "BuildDataversePCFSolution directory not found."
        Write-Info "Please run this script from your PCF project root directory."
        exit 1
    }
    
    # Get current version
    $currentVersion = Get-CurrentVersion
    if ($currentVersion) {
        Write-Info "Current version: $currentVersion"
    } else {
        Write-Warning "Current version could not be determined"
    }
    
    # Get latest version
    $latestVersion = Get-LatestVersion
    if ($latestVersion) {
        Write-Info "Latest version: $latestVersion"
    } else {
        Write-Warning "Latest version could not be determined from GitHub"
        if (-not $Force) {
            Write-Info "Use -Force to upgrade anyway, or check your internet connection"
            exit 1
        }
    }
    
    # Check if update is needed
    $updateNeeded = $Force -or (Compare-Versions -CurrentVersion $currentVersion -LatestVersion $latestVersion)
    
    if ($CheckOnly) {
        if ($updateNeeded -and -not $Force) {
            Write-Info "🔄 Update available: $currentVersion → $latestVersion"
            Write-Info "Run 'npm run boom-upgrade' to upgrade"
        } elseif ($currentVersion -eq $latestVersion) {
            Write-Success "✅ You have the latest version ($currentVersion)"
        } else {
            Write-Info "Version check completed"
        }
        exit 0
    }
    
    if ($updateNeeded) {
        if ($Force) {
            Write-Info "Force upgrade requested"
        } else {
            Write-Info "🔄 Update available: $currentVersion → $latestVersion"
        }
        
        if (Invoke-Upgrade) {
            Write-Success "🎉 BuildDataversePCFSolution has been upgraded successfully!"
            Write-Info ""
            Write-Info "You can now continue using the latest features:"
            Write-Info "  • npm run boom           - Quick Release build"
            Write-Info "  • npm run boom-debug     - Quick Debug build"
            Write-Info "  • npm run boom-check     - Check environment"
            Write-Info "  • npm run boom-upgrade   - Check for updates"
        } else {
            Write-Error "Upgrade failed. Please try again or install manually."
            exit 1
        }
    } else {
        Write-Success "✅ You already have the latest version ($currentVersion)"
        Write-Info "Use -Force to reinstall anyway"
    }
}
catch {
    Write-Error "Upgrade process failed: $($_.Exception.Message)"
    exit 1
}
