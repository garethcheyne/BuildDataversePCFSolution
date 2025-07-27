# BuildDataversePCFSolution Environment Check and Setup Script
# This script checks and installs all prerequisites for PCF development

param(
    [switch]$AutoInstall,
    [switch]$CheckOnly,
    [string]$LogFile = "environment-check.log"
)

# Set error action preference
$ErrorActionPreference = "Continue"

# Color output functions
function Write-Header { param($Message) Write-Host "`n=== $Message ===" -ForegroundColor Magenta }
function Write-Info { param($Message) Write-Host "INFO: $Message" -ForegroundColor Cyan }
function Write-Success { param($Message) Write-Host "SUCCESS: $Message" -ForegroundColor Green }
function Write-Warning { param($Message) Write-Host "WARNING: $Message" -ForegroundColor Yellow }
function Write-Error { param($Message) Write-Host "ERROR: $Message" -ForegroundColor Red }
function Write-Debug { param($Message) Write-Host "DEBUG: $Message" -ForegroundColor DarkGray }

# Logging function
function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"
    Add-Content -Path $LogFile -Value $logEntry
    
    switch ($Level) {
        "INFO" { Write-Info $Message }
        "SUCCESS" { Write-Success $Message }
        "WARNING" { Write-Warning $Message }
        "ERROR" { Write-Error $Message }
        "DEBUG" { Write-Debug $Message }
    }
}

# Function to check if running as administrator
function Test-IsAdmin {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Function to get installed version of a command
function Get-CommandVersion {
    param([string]$Command, [string]$VersionArg = "--version")
    
    try {
        $versionOutput = & $Command $VersionArg 2>&1
        if ($LASTEXITCODE -eq 0) {
            # Handle multi-line output by taking the first meaningful line
            $outputString = if ($versionOutput -is [array]) { 
                ($versionOutput | Where-Object { $_.ToString().Trim() -ne "" } | Select-Object -First 1).ToString().Trim()
            }
            else { 
                $versionOutput.ToString().Trim() 
            }
            return $outputString
        }
    }
    catch {
        return $null
    }
    return $null
}

# Function to check Node.js installation
function Test-NodeJs {
    Write-Log "Checking Node.js installation..." "INFO"
    
    $nodeVersion = Get-CommandVersion "node"
    if ($nodeVersion) {
        $npmVersion = Get-CommandVersion "npm"
        Write-Log "Node.js found: $nodeVersion" "SUCCESS"
        Write-Log "npm found: $npmVersion" "SUCCESS"
        
        # Check if version is supported (Node 16+ recommended for PCF)
        if ($nodeVersion -match "v(\d+)\.") {
            $majorVersion = [int]$matches[1]
            if ($majorVersion -ge 16) {
                Write-Log "Node.js version is compatible (v$majorVersion)" "SUCCESS"
                return @{ Installed = $true; Version = $nodeVersion; Compatible = $true }
            }
            else {
                Write-Log "Node.js version is outdated (v$majorVersion). PCF requires Node 16+" "WARNING"
                return @{ Installed = $true; Version = $nodeVersion; Compatible = $false }
            }
        }
        return @{ Installed = $true; Version = $nodeVersion; Compatible = $true }
    }
    else {
        Write-Log "Node.js not found" "ERROR"
        return @{ Installed = $false; Version = $null; Compatible = $false }
    }
}

# Function to install Node.js
function Install-NodeJs {
    Write-Log "Installing Node.js..." "INFO"
    
    if ($IsWindows) {
        # Use winget if available, otherwise download manually
        try {
            $wingetAvailable = Get-Command winget -ErrorAction SilentlyContinue
            if ($wingetAvailable) {
                Write-Log "Installing Node.js via winget..." "INFO"
                winget install OpenJS.NodeJS --accept-package-agreements --accept-source-agreements
                return $LASTEXITCODE -eq 0
            }
        }
        catch {
            Write-Log "winget not available, using manual installation" "WARNING"
        }
        
        # Manual download and install
        $nodeUrl = "https://nodejs.org/dist/v20.10.0/node-v20.10.0-x64.msi"
        $tempFile = Join-Path $env:TEMP "nodejs-installer.msi"
        
        Write-Log "Downloading Node.js installer..." "INFO"
        Invoke-WebRequest -Uri $nodeUrl -OutFile $tempFile
        
        Write-Log "Installing Node.js (requires admin privileges)..." "INFO"
        Start-Process msiexec.exe -Wait -ArgumentList "/i `"$tempFile`" /quiet /norestart"
        
        Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
        
        # Refresh environment variables
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
        
        return $true
    }
    else {
        Write-Log "Please install Node.js manually from https://nodejs.org/" "ERROR"
        return $false
    }
}

# Function to check .NET installation
function Test-DotNet {
    Write-Log "Checking .NET installation..." "INFO"
    
    $dotnetVersion = Get-CommandVersion "dotnet"
    if ($dotnetVersion) {
        Write-Log ".NET found: $dotnetVersion" "SUCCESS"
        
        # Check for .NET 6.0+ (required for PAC CLI)
        try {
            $sdks = & dotnet --list-sdks 2>&1
            $dotnet6PlusAvailable = $sdks | Where-Object { $_ -match "([6-9]|[1-9]\d+)\.\d+\.\d+" }
            if ($dotnet6PlusAvailable) {
                Write-Log ".NET 6.0+ SDK available" "SUCCESS"
                return @{ Installed = $true; Version = $dotnetVersion; Compatible = $true }
            }
            else {
                Write-Log ".NET 6.0+ SDK not found. PAC CLI requires .NET 6.0+" "WARNING"
                return @{ Installed = $true; Version = $dotnetVersion; Compatible = $false }
            }
        }
        catch {
            return @{ Installed = $true; Version = $dotnetVersion; Compatible = $true }
        }
    }
    else {
        Write-Log ".NET not found" "ERROR"
        return @{ Installed = $false; Version = $null; Compatible = $false }
    }
}

# Function to install .NET
function Install-DotNet {
    Write-Log "Installing .NET 6.0 SDK..." "INFO"
    
    if ($IsWindows) {
        try {
            $wingetAvailable = Get-Command winget -ErrorAction SilentlyContinue
            if ($wingetAvailable) {
                Write-Log "Installing .NET 6.0 SDK via winget..." "INFO"
                winget install Microsoft.DotNet.SDK.6 --accept-package-agreements --accept-source-agreements
                return $LASTEXITCODE -eq 0
            }
        }
        catch {
            Write-Log "winget not available, using manual installation" "WARNING"
        }
        
        # Manual download and install
        $dotnetUrl = "https://download.microsoft.com/download/f/c/f/fcf87ccf-6268-4c08-baf0-474e89ad3b6a/dotnet-sdk-6.0.425-win-x64.exe"
        $tempFile = Join-Path $env:TEMP "dotnet-sdk-installer.exe"
        
        Write-Log "Downloading .NET SDK installer..." "INFO"
        Invoke-WebRequest -Uri $dotnetUrl -OutFile $tempFile
        
        Write-Log "Installing .NET SDK..." "INFO"
        Start-Process $tempFile -Wait -ArgumentList "/quiet"
        
        Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
        
        # Refresh environment variables
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
        
        return $true
    }
    else {
        Write-Log "Please install .NET 6.0 SDK manually from https://dotnet.microsoft.com/" "ERROR"
        return $false
    }
}

# Function to check Power Platform CLI
function Test-PowerPlatformCLI {
    Write-Log "Checking Power Platform CLI installation..." "INFO"
    
    try {
        # PAC CLI doesn't support --version flag, so we run it without args and parse the help output
        $pacOutput = & pac 2>&1
        
        # Convert to string if it's an array
        $pacString = if ($pacOutput -is [array]) { $pacOutput -join "`n" } else { $pacOutput.ToString() }
        
        if ($pacString -match "Version: ([\d\.]+\+\w+)") {
            $version = $matches[1]
            Write-Log "Power Platform CLI found: $version" "SUCCESS"
            return @{ Installed = $true; Version = $version; Compatible = $true }
        }
        elseif ($pacString -match "Microsoft PowerPlatform CLI") {
            # Found PAC CLI but couldn't parse version
            Write-Log "Power Platform CLI found (version unknown)" "SUCCESS"
            return @{ Installed = $true; Version = "Unknown"; Compatible = $true }
        }
        else {
            Write-Log "Power Platform CLI not found" "ERROR"
            return @{ Installed = $false; Version = $null; Compatible = $false }
        }
    }
    catch {
        Write-Log "Power Platform CLI not found" "ERROR"
        return @{ Installed = $false; Version = $null; Compatible = $false }
    }
}

# Function to install Power Platform CLI
function Install-PowerPlatformCLI {
    Write-Log "Installing Power Platform CLI..." "INFO"
    
    try {
        # Install via dotnet tool (requires .NET)
        Write-Log "Installing PAC CLI via .NET tool..." "INFO"
        & dotnet tool install --global Microsoft.PowerApps.CLI.Tool
        
        if ($LASTEXITCODE -eq 0) {
            Write-Log "Power Platform CLI installed successfully" "SUCCESS"
            
            # Refresh environment variables
            $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
            
            return $true
        }
        else {
            Write-Log "Failed to install Power Platform CLI via dotnet tool" "ERROR"
            return $false
        }
    }
    catch {
        Write-Log "Error installing Power Platform CLI: $($_.Exception.Message)" "ERROR"
        return $false
    }
}

# Function to check Git installation
function Test-Git {
    Write-Log "Checking Git installation..." "INFO"
    
    $gitVersion = Get-CommandVersion "git"
    if ($gitVersion) {
        Write-Log "Git found: $gitVersion" "SUCCESS"
        return @{ Installed = $true; Version = $gitVersion; Compatible = $true }
    }
    else {
        Write-Log "Git not found" "WARNING"
        return @{ Installed = $false; Version = $null; Compatible = $false }
    }
}

# Function to install Git
function Install-Git {
    Write-Log "Installing Git..." "INFO"
    
    if ($IsWindows) {
        try {
            $wingetAvailable = Get-Command winget -ErrorAction SilentlyContinue
            if ($wingetAvailable) {
                Write-Log "Installing Git via winget..." "INFO"
                winget install Git.Git --accept-package-agreements --accept-source-agreements
                return $LASTEXITCODE -eq 0
            }
        }
        catch {
            Write-Log "winget not available" "WARNING"
        }
        
        Write-Log "Please install Git manually from https://git-scm.com/" "ERROR"
        return $false
    }
    else {
        Write-Log "Please install Git using your package manager" "ERROR"
        return $false
    }
}

# Function to check Visual Studio Code (optional but recommended)
function Test-VSCode {
    Write-Log "Checking Visual Studio Code installation..." "INFO"
    
    $codeVersion = Get-CommandVersion "code"
    if ($codeVersion) {
        Write-Log "Visual Studio Code found: $codeVersion" "SUCCESS"
        return @{ Installed = $true; Version = $codeVersion; Compatible = $true }
    }
    else {
        Write-Log "Visual Studio Code not found (optional)" "WARNING"
        return @{ Installed = $false; Version = $null; Compatible = $false }
    }
}

# Function to check PCF control dependencies
function Test-PCFDependencies {
    Write-Log "Checking PCF-specific dependencies..." "INFO"
    
    $results = @{
        PCFControls = $false
        ReactTypes  = $false
        FluentUI    = $false
    }
    
    # Check if we're in a PCF project directory
    if (Test-Path "package.json") {
        $packageJson = Get-Content "package.json" | ConvertFrom-Json
        
        # Check for PCF controls dependency
        if ($packageJson.dependencies."@microsoft/generator-powerapps" -or 
            $packageJson.devDependencies."@microsoft/generator-powerapps") {
            $results.PCFControls = $true
            Write-Log "PCF Controls generator found in package.json" "SUCCESS"
        }
        
        # Check for React types
        if ($packageJson.dependencies."@types/react" -or 
            $packageJson.devDependencies."@types/react") {
            $results.ReactTypes = $true
            Write-Log "React types found in package.json" "SUCCESS"
        }
        
        # Check for FluentUI
        if ($packageJson.dependencies."@fluentui/react" -or 
            $packageJson.dependencies."@microsoft/sp-office-ui-fabric-core") {
            $results.FluentUI = $true
            Write-Log "FluentUI found in package.json" "SUCCESS"
        }
    }
    else {
        Write-Log "Not in a PCF project directory (package.json not found)" "INFO"
    }
    
    return $results
}

# Function to get latest version information
function Get-LatestVersions {
    Write-Log "Checking latest versions of key dependencies..." "INFO"
    
    $versions = @{}
    
    try {
        # Check latest Node.js LTS
        $nodeResponse = Invoke-RestMethod -Uri "https://nodejs.org/dist/index.json" -TimeoutSec 10
        $latestLTS = $nodeResponse | Where-Object { $_.lts -ne $false } | Select-Object -First 1
        $versions.NodeJS = $latestLTS.version
        
        # Check latest PAC CLI version (from NuGet)
        $pacResponse = Invoke-RestMethod -Uri "https://api.nuget.org/v3-flatcontainer/microsoft.powerapps.cli.tool/index.json" -TimeoutSec 10
        $versions.PowerPlatformCLI = $pacResponse.versions | Select-Object -Last 1
        
        # Check latest React version
        $reactResponse = Invoke-RestMethod -Uri "https://registry.npmjs.org/react/latest" -TimeoutSec 10
        $versions.React = $reactResponse.version
        
        # Check latest FluentUI version
        $fluentResponse = Invoke-RestMethod -Uri "https://registry.npmjs.org/@fluentui/react/latest" -TimeoutSec 10
        $versions.FluentUI = $fluentResponse.version
        
        Write-Log "Latest versions retrieved successfully" "SUCCESS"
    }
    catch {
        Write-Log "Could not retrieve latest version information: $($_.Exception.Message)" "WARNING"
    }
    
    return $versions
}

# Function to display environment report
function Show-EnvironmentReport {
    param($CheckResults, $LatestVersions)
    
    Write-Host ""
    Write-Host "=================================================================" -ForegroundColor Magenta
    Write-Host "             PCF DEVELOPMENT ENVIRONMENT REPORT" -ForegroundColor White -BackgroundColor Black
    Write-Host "=================================================================" -ForegroundColor Magenta
    
    Write-Host ""
    Write-Host "CORE REQUIREMENTS" -ForegroundColor Yellow -BackgroundColor Black
    Write-Host "================================================================" -ForegroundColor Yellow
    
    # Node.js
    if ($CheckResults.NodeJS.Installed) {
        if ($CheckResults.NodeJS.Compatible) {
            Write-Host "[OK] Node.js: " -NoNewline -ForegroundColor Green
            Write-Host "$($CheckResults.NodeJS.Version)" -ForegroundColor White
        }
        else {
            Write-Host "[!] Node.js: " -NoNewline -ForegroundColor Yellow
            Write-Host "$($CheckResults.NodeJS.Version) (upgrade recommended)" -ForegroundColor White
        }
    }
    else {
        Write-Host "[X] Node.js: " -NoNewline -ForegroundColor Red
        Write-Host "Not installed" -ForegroundColor White
    }
    
    if ($LatestVersions.NodeJS) {
        Write-Host "   Latest LTS: $($LatestVersions.NodeJS)" -ForegroundColor DarkGray
    }
    
    # .NET
    if ($CheckResults.DotNet.Installed) {
        if ($CheckResults.DotNet.Compatible) {
            Write-Host "[OK] .NET SDK: " -NoNewline -ForegroundColor Green
            Write-Host "$($CheckResults.DotNet.Version)" -ForegroundColor White
        }
        else {
            Write-Host "[!] .NET SDK: " -NoNewline -ForegroundColor Yellow
            Write-Host "$($CheckResults.DotNet.Version) (.NET 6.0+ required)" -ForegroundColor White
        }
    }
    else {
        Write-Host "[X] .NET SDK: " -NoNewline -ForegroundColor Red
        Write-Host "Not installed" -ForegroundColor White
    }
    
    # Power Platform CLI
    if ($CheckResults.PowerPlatformCLI.Installed) {
        Write-Host "[OK] Power Platform CLI: " -NoNewline -ForegroundColor Green
        Write-Host "$($CheckResults.PowerPlatformCLI.Version)" -ForegroundColor White
    }
    else {
        Write-Host "[X] Power Platform CLI: " -NoNewline -ForegroundColor Red
        Write-Host "Not installed" -ForegroundColor White
    }
    
    if ($LatestVersions.PowerPlatformCLI) {
        Write-Host "   Latest: $($LatestVersions.PowerPlatformCLI)" -ForegroundColor DarkGray
    }
    
    Write-Host ""
    Write-Host "OPTIONAL TOOLS" -ForegroundColor Cyan -BackgroundColor Black
    Write-Host "================================================================" -ForegroundColor Cyan
    
    # Git
    if ($CheckResults.Git.Installed) {
        Write-Host "[OK] Git: " -NoNewline -ForegroundColor Green
        Write-Host "$($CheckResults.Git.Version)" -ForegroundColor White
    }
    else {
        Write-Host "[!] Git: " -NoNewline -ForegroundColor Yellow
        Write-Host "Not installed (recommended for version control)" -ForegroundColor White
    }
    
    # Visual Studio Code
    if ($CheckResults.VSCode.Installed) {
        Write-Host "[OK] Visual Studio Code: " -NoNewline -ForegroundColor Green
        Write-Host "$($CheckResults.VSCode.Version)" -ForegroundColor White
    }
    else {
        Write-Host "[!] Visual Studio Code: " -NoNewline -ForegroundColor Yellow
        Write-Host "Not installed (recommended for development)" -ForegroundColor White
    }
    
    # PCF Dependencies (if in a project)
    $pcfDeps = Test-PCFDependencies
    if (Test-Path "package.json") {
        Write-Host ""
        Write-Host "PCF PROJECT DEPENDENCIES" -ForegroundColor Magenta -BackgroundColor Black
        Write-Host "================================================================" -ForegroundColor Magenta
        
        if ($pcfDeps.PCFControls) {
            Write-Host "[OK] PCF Generator" -ForegroundColor Green
        }
        else {
            Write-Host "[INFO] PCF Generator: Not needed (project already set up)" -ForegroundColor DarkGray
        }
        
        if ($pcfDeps.ReactTypes) {
            Write-Host "[OK] React Types" -ForegroundColor Green
        }
        else {
            Write-Host "[!] React Types: Not found in project" -ForegroundColor Yellow
        }
        
        if ($pcfDeps.FluentUI) {
            Write-Host "[OK] FluentUI React" -ForegroundColor Green
        }
        else {
            Write-Host "[!] FluentUI React: Not found in project" -ForegroundColor Yellow
        }
        
        if ($LatestVersions.React) {
            Write-Host "   Latest React: $($LatestVersions.React)" -ForegroundColor DarkGray
        }
        if ($LatestVersions.FluentUI) {
            Write-Host "   Latest FluentUI: $($LatestVersions.FluentUI)" -ForegroundColor DarkGray
        }
    }
    
    Write-Host ""
}

# Function to prompt for installations
function Prompt-ForInstallations {
    param($CheckResults)
    
    $toInstall = @()
    
    if (-not $CheckResults.NodeJS.Installed -or -not $CheckResults.NodeJS.Compatible) {
        $install = Read-Host "Install/Update Node.js? (Where-Object/N)"
        if ($install.ToLower() -in @("y", "yes")) {
            $toInstall += "NodeJS"
        }
    }
    
    if (-not $CheckResults.DotNet.Installed -or -not $CheckResults.DotNet.Compatible) {
        $install = Read-Host "Install .NET 6.0 SDK? (y/N)"
        if ($install.ToLower() -in @("y", "yes")) {
            $toInstall += "DotNet"
        }
    }
    
    if (-not $CheckResults.PowerPlatformCLI.Installed) {
        $install = Read-Host "Install Power Platform CLI? (y/N)"
        if ($install.ToLower() -in @("y", "yes")) {
            $toInstall += "PowerPlatformCLI"
        }
    }
    
    if (-not $CheckResults.Git.Installed) {
        $install = Read-Host "Install Git? (y/N)"
        if ($install.ToLower() -in @("y", "yes")) {
            $toInstall += "Git"
        }
    }
    
    return $toInstall
}

# Main execution
try {
    Write-Host ""
    Write-Host "=================================================================" -ForegroundColor Cyan
    Write-Host "    BUILD DATAVERSE PCF SOLUTION - ENVIRONMENT CHECK" -ForegroundColor Yellow -BackgroundColor Black
    Write-Host "=================================================================" -ForegroundColor Cyan
    Write-Info "Checking PCF development environment prerequisites..."
    
    # Initialize log file
    "BuildDataversePCFSolution Environment Check - $(Get-Date)" | Out-File $LogFile
    
    # Detect OS
    if ($PSVersionTable.PSVersion.Major -ge 6) {
        # PowerShell Core/7+ has $IsWindows built-in
        $IsWindows = $IsWindows
    }
    else {
        # Windows PowerShell 5.1 and earlier
        $IsWindows = ($env:OS -eq "Windows_NT")
    }
    Write-Log "Operating System: $(if ($IsWindows) { "Windows" } else { "Non-Windows" })" "INFO"
    
    # Check admin privileges on Windows
    if ($IsWindows) {
        $isAdmin = Test-IsAdmin
        Write-Log "Running as Administrator: $isAdmin" "INFO"
        if (-not $isAdmin -and -not $CheckOnly) {
            Write-Warning "Some installations may require administrator privileges"
        }
    }
    
    # Perform environment checks
    Write-Log "Starting environment checks..." "INFO"
    
    $checkResults = @{
        NodeJS           = Test-NodeJs
        DotNet           = Test-DotNet
        PowerPlatformCLI = Test-PowerPlatformCLI
        Git              = Test-Git
        VSCode           = Test-VSCode
    }
    
    # Get latest versions
    $latestVersions = Get-LatestVersions
    
    # Display report
    Show-EnvironmentReport -CheckResults $checkResults -LatestVersions $latestVersions
    
    # Determine overall status
    $coreRequirementsMet = $checkResults.NodeJS.Installed -and $checkResults.NodeJS.Compatible -and
    $checkResults.DotNet.Installed -and $checkResults.DotNet.Compatible -and
    $checkResults.PowerPlatformCLI.Installed
    
    Write-Host ""
    Write-Host "ENVIRONMENT STATUS" -ForegroundColor White -BackgroundColor Black
    Write-Host "================================================================" -ForegroundColor White
    
    if ($coreRequirementsMet) {
        Write-Success "[OK] Your environment is ready for PCF development!"
        Write-Info "You can now create PCF controls and build solutions."
    }
    else {
        Write-Warning "[!] Some core requirements are missing or need updates."
        
        if (-not $CheckOnly) {
            Write-Host ""
            if ($AutoInstall) {
                Write-Info "Auto-install mode enabled. Installing missing components..."
                
                if (-not $checkResults.NodeJS.Installed -or -not $checkResults.NodeJS.Compatible) {
                    Install-NodeJs
                }
                if (-not $checkResults.DotNet.Installed -or -not $checkResults.DotNet.Compatible) {
                    Install-DotNet
                }
                if (-not $checkResults.PowerPlatformCLI.Installed) {
                    Install-PowerPlatformCLI
                }
                if (-not $checkResults.Git.Installed) {
                    Install-Git
                }
            }
            else {
                $toInstall = Prompt-ForInstallations -CheckResults $checkResults
                
                foreach ($component in $toInstall) {
                    switch ($component) {
                        "NodeJS" { Install-NodeJs }
                        "DotNet" { Install-DotNet }
                        "PowerPlatformCLI" { Install-PowerPlatformCLI }
                        "Git" { Install-Git }
                    }
                }
            }
        }
    }
    
    Write-Host ""
    Write-Host "NEXT STEPS" -ForegroundColor Green -BackgroundColor Black
    Write-Host "================================================================" -ForegroundColor Green
    Write-Host ""
    
    if ($coreRequirementsMet) {
        Write-Host "1. " -NoNewline -ForegroundColor Yellow
        Write-Host "Create a new PCF project:" -ForegroundColor Yellow
        Write-Host "   npm run boom-create" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "2. " -NoNewline -ForegroundColor Yellow
        Write-Host "Or build an existing project:" -ForegroundColor Yellow
        Write-Host "   npm run boom" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "3. " -NoNewline -ForegroundColor Yellow
        Write-Host "Run environment check anytime:" -ForegroundColor Yellow
        Write-Host "   npm run boom-check" -ForegroundColor Cyan
    }
    else {
        Write-Host "1. " -NoNewline -ForegroundColor Yellow
        Write-Host "Install missing prerequisites (listed above)" -ForegroundColor Yellow
        Write-Host "2. " -NoNewline -ForegroundColor Yellow
        Write-Host "Re-run this check: " -ForegroundColor Yellow
        Write-Host "npm run boom-check" -ForegroundColor Cyan
        Write-Host "3. " -NoNewline -ForegroundColor Yellow
        Write-Host "Once ready, create your PCF project: " -ForegroundColor Yellow
        Write-Host "npm run boom-create" -ForegroundColor Cyan
    }
    
    Write-Host ""
    Write-Log "Environment check completed" "SUCCESS"
    Write-Info "Log file saved to: $LogFile"
    
    # Return appropriate exit code
    if ($coreRequirementsMet) {
        exit 0
    }
    else {
        exit 1
    }
}
catch {
    Write-Log "Environment check failed: $($_.Exception.Message)" "ERROR"
    Write-Log "Stack trace: $($_.ScriptStackTrace)" "ERROR"
    exit 1
}
