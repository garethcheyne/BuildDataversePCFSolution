#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Create GitHub release from Azure DevOps or any CI environment
.DESCRIPTION
    This script creates a GitHub release using the GitHub CLI, parsing release information
    from solution.yaml configuration. Designed to work in Azure DevOps pipelines.
.PARAMETER ConfigFile
    Path to the solution.yaml configuration file (default: ../solution.yaml)
.PARAMETER TagName
    Git tag name for the release (required)
.PARAMETER ArtifactPath
    Path to the solution package to upload (required)
.PARAMETER GitHubToken
    GitHub personal access token (can also be set via GITHUB_TOKEN environment variable)
.PARAMETER Repository
    GitHub repository in format owner/repo (can be detected from git remote)
.EXAMPLE
    .\create-github-release.ps1 -TagName "v1.0.0" -ArtifactPath "MySolution.zip"
    .\create-github-release.ps1 -TagName "v1.0.0" -ArtifactPath "MySolution.zip" -Repository "myorg/myrepo"
#>

param(
    [string]$ConfigFile = "../solution.yaml",
    [Parameter(Mandatory=$true)]
    [string]$TagName,
    [Parameter(Mandatory=$true)]
    [string]$ArtifactPath,
    [string]$GitHubToken = $env:GITHUB_TOKEN,
    [string]$Repository = ""
)

# Set error action preference
$ErrorActionPreference = "Stop"

# Color functions for output
function Write-Info { param($Message) Write-Host "INFO: $Message" -ForegroundColor Cyan }
function Write-Success { param($Message) Write-Host "SUCCESS: $Message" -ForegroundColor Green }
function Write-Warning { param($Message) Write-Host "WARNING: $Message" -ForegroundColor Yellow }
function Write-Error { param($Message) Write-Host "ERROR: $Message" -ForegroundColor Red }

# Function to parse YAML file (simple parser for basic YAML structure)
function Parse-YamlFile {
    param([string]$FilePath)
    
    if (-not (Test-Path $FilePath)) {
        throw "Configuration file not found: $FilePath"
    }
    
    $yaml = @{}
    $currentSection = $null
    $currentSubSection = $null
    
    Get-Content $FilePath | ForEach-Object {
        $line = $_.Trim()
        
        # Skip comments and empty lines
        if ($line.StartsWith("#") -or [string]::IsNullOrWhiteSpace($line)) {
            return
        }
        
        # Handle top-level sections
        if ($line -match "^([a-zA-Z_][a-zA-Z0-9_]*):$") {
            $currentSection = $matches[1]
            $yaml[$currentSection] = @{}
            $currentSubSection = $null
        }
        # Handle sub-sections with 2 spaces
        elseif ($line -match "^  ([a-zA-Z_][a-zA-Z0-9_]*):(.*)$") {
            $key = $matches[1]
            $value = $matches[2].Trim()
            
            if ([string]::IsNullOrWhiteSpace($value)) {
                $currentSubSection = $key
                $yaml[$currentSection][$key] = @{}
            } else {
                # Remove quotes and parse value
                $value = $value -replace '^["'']|["'']$', ''
                $yaml[$currentSection][$key] = $value
            }
        }
        # Handle sub-sub-sections with 4 spaces
        elseif ($line -match "^    ([a-zA-Z_][a-zA-Z0-9_]*):(.*)$") {
            $key = $matches[1]
            $value = $matches[2].Trim() -replace '^["'']|["'']$', ''
            
            if ($currentSubSection) {
                $yaml[$currentSection][$currentSubSection][$key] = $value
            }
        }
    }
    
    return $yaml
}

# Function to resolve template variables
function Resolve-Template {
    param([string]$Template, [hashtable]$Config)
    
    $resolved = $Template
    
    # Replace {{section.key}} patterns
    $resolved = $resolved -replace '\{\{solution\.name\}\}', $Config.solution.name
    $resolved = $resolved -replace '\{\{solution\.displayName\}\}', $Config.solution.displayName
    $resolved = $resolved -replace '\{\{solution\.version\}\}', $Config.solution.version
    $resolved = $resolved -replace '\{\{publisher\.name\}\}', $Config.publisher.name
    $resolved = $resolved -replace '\{\{publisher\.prefix\}\}', $Config.publisher.prefix
    
    return $resolved
}

try {
    Write-Info "Starting GitHub release creation process..."
    
    # Validate GitHub token
    if ([string]::IsNullOrEmpty($GitHubToken)) {
        throw "GitHub token not provided. Set GITHUB_TOKEN environment variable or use -GitHubToken parameter."
    }
    
    # Validate artifact path
    if (-not (Test-Path $ArtifactPath)) {
        throw "Artifact file not found: $ArtifactPath"
    }
    
    # Load configuration
    Write-Info "Loading configuration from: $ConfigFile"
    if (Test-Path $ConfigFile) {
        $config = Parse-YamlFile -FilePath $ConfigFile
    } else {
        Write-Warning "Configuration file not found, using minimal release information"
        $config = @{
            solution = @{ 
                name = "PCFSolution"
                displayName = "PCF Solution"
                version = "1.0.0"
            }
        }
    }
    
    # Determine repository if not provided
    if ([string]::IsNullOrEmpty($Repository)) {
        try {
            $gitRemote = git remote get-url origin 2>$null
            if ($gitRemote -match "github\.com[:/]([^/]+/[^/\.]+)") {
                $Repository = $matches[1]
                Write-Info "Detected repository: $Repository"
            } else {
                throw "Could not detect GitHub repository from git remote"
            }
        } catch {
            throw "Repository not specified and could not be detected from git remote. Use -Repository parameter."
        }
    }
    
    # Extract release information from config
    $solutionName = $config.solution.name
    $displayName = $config.solution.displayName
    $version = $config.solution.version
    
    # Build release title and body
    $releaseTitle = if ($config.github.release.titleTemplate) {
        Resolve-Template -Template $config.github.release.titleTemplate -Config $config
    } else {
        "$displayName $TagName"
    }
    
    $releaseBody = if ($config.github.release.bodyTemplate) {
        Resolve-Template -Template $config.github.release.bodyTemplate -Config $config
    } else {
        @"
## $displayName $TagName

### 💾 Installation
1. Download the ``$solutionName.zip`` file
2. Import it into your Power Platform environment

### 📋 Requirements
- Power Platform environment with PCF controls enabled

---

**Built with automated CI/CD pipeline**
"@
    }
    
    # Set GitHub token for gh CLI
    $env:GITHUB_TOKEN = $GitHubToken
    
    # Check if gh CLI is available
    try {
        $ghVersion = gh --version 2>$null
        Write-Info "GitHub CLI detected: $($ghVersion.Split("`n")[0])"
    } catch {
        throw "GitHub CLI (gh) not found. Please install GitHub CLI: https://cli.github.com/"
    }
    
    # Authenticate with GitHub
    Write-Info "Authenticating with GitHub..."
    try {
        gh auth status 2>$null
        Write-Success "GitHub authentication verified"
    } catch {
        Write-Warning "GitHub authentication failed, attempting to authenticate with token..."
        $authResult = echo $GitHubToken | gh auth login --with-token 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "GitHub authentication failed: $authResult"
        }
        Write-Success "GitHub authentication successful"
    }
    
    # Create the release
    Write-Info "Creating GitHub release..."
    Write-Info "Repository: $Repository"
    Write-Info "Tag: $TagName"
    Write-Info "Title: $releaseTitle"
    Write-Info "Artifact: $ArtifactPath"
    
    $createArgs = @(
        "release", "create", $TagName,
        $ArtifactPath,
        "--repo", $Repository,
        "--title", $releaseTitle,
        "--notes", $releaseBody
    )
    
    # Add draft/prerelease flags if configured
    if ($config.github.release.draft -eq "true") {
        $createArgs += "--draft"
    }
    if ($config.github.release.prerelease -eq "true") {
        $createArgs += "--prerelease"
    }
    
    $result = & gh @createArgs 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "GitHub release creation failed: $result"
    }
    
    Write-Success "GitHub release created successfully!"
    Write-Info "Release URL: https://github.com/$Repository/releases/tag/$TagName"
    
    return 0
}
catch {
    Write-Error "GitHub release creation failed: $($_.Exception.Message)"
    return 1
}
