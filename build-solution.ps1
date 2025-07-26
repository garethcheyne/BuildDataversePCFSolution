#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Build PCF Control and create Power Platform solution package using solution.yaml configuration
.DESCRIPTION
    This script builds the PCF control, creates a Power Platform solution, and packages it for deployment.
    Uses solution.yaml for configuration, making it reusable across different PCF projects.
    Supports both GitHub Actions and Azure DevOps CI/CD environments.
.PARAMETER ConfigFile
    Path to the solution.yaml configuration file (default: ./solution.yaml)
.PARAMETER SolutionName
    Override solution name from config file
.PARAMETER PublisherName
    Override publisher name from config file
.PARAMETER PublisherPrefix
    Override publisher prefix from config file
.PARAMETER CleanBuild
    Override clean build setting from config file
.PARAMETER BuildConfiguration
    Build configuration (Debug, Release) - default: Release
.PARAMETER CiMode
    CI/CD mode (GitHub, DevOps, Local) - auto-detected if not specified
.EXAMPLE
    .\build-solution.ps1
    .\build-solution.ps1 -ConfigFile ".\custom-solution.yaml"
    .\build-solution.ps1 -SolutionName "MyCustomSolution" -BuildConfiguration "Debug"
    .\build-solution.ps1 -CiMode "DevOps" -BuildConfiguration "Release"
#>

param(
    [string]$ConfigFile = "../solution.yaml",
    [string]$SolutionName = "",
    [string]$PublisherName = "", 
    [string]$PublisherPrefix = "",
    [bool]$CleanBuild = $true,
    [string]$BuildConfiguration = "Release",
    [string]$CiMode = ""
)

# Set error action preference
$ErrorActionPreference = "Stop"

# Detect CI/CD environment if not specified
if ([string]::IsNullOrEmpty($CiMode)) {
    if ($env:GITHUB_ACTIONS -eq "true") {
        $CiMode = "GitHub"
    } elseif ($env:TF_BUILD -eq "True") {
        $CiMode = "DevOps"
    } else {
        $CiMode = "Local"
    }
}

# Color functions for output (adapted for different CI environments)
function Write-Info { 
    param($Message) 
    if ($CiMode -eq "DevOps") {
        Write-Host "##[section]INFO: $Message"
    } elseif ($CiMode -eq "GitHub") {
        Write-Host "::notice::$Message"
    } else {
        Write-Host "INFO: $Message" -ForegroundColor Cyan 
    }
}

function Write-Success { 
    param($Message) 
    if ($CiMode -eq "DevOps") {
        Write-Host "##[section]SUCCESS: $Message"
    } elseif ($CiMode -eq "GitHub") {
        Write-Host "::notice::✅ $Message"
    } else {
        Write-Host "SUCCESS: $Message" -ForegroundColor Green 
    }
}

function Write-Warning { 
    param($Message) 
    if ($CiMode -eq "DevOps") {
        Write-Host "##[warning]WARNING: $Message"
    } elseif ($CiMode -eq "GitHub") {
        Write-Host "::warning::$Message"
    } else {
        Write-Host "WARNING: $Message" -ForegroundColor Yellow 
    }
}

function Write-BuildError { 
    param($Message) 
    if ($CiMode -eq "DevOps") {
        Write-Host "##[error]ERROR: $Message"
    } elseif ($CiMode -eq "GitHub") {
        Write-Host "::error::$Message"
    } else {
        Write-Host "ERROR: $Message" -ForegroundColor Red 
    }
}

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
                $value = $value -replace '^["\']|["\']$', ''
                $yaml[$currentSection][$key] = $value
            }
        }
        # Handle sub-sub-sections with 4 spaces
        elseif ($line -match "^    ([a-zA-Z_][a-zA-Z0-9_]*):(.*)$") {
            $key = $matches[1]
            $value = $matches[2].Trim() -replace '^["\']|["\']$', ''
            
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
    # Change to project root directory (parent of BuildDataverseSolution)
    $projectRoot = Split-Path -Parent $PSScriptRoot
    Set-Location $projectRoot
    Write-Info "Working directory: $projectRoot"
    Write-Info "CI/CD Mode: $CiMode"
    
    # Display environment information for debugging
    if ($CiMode -eq "DevOps") {
        Write-Info "Azure DevOps Build detected (TF_BUILD: $env:TF_BUILD)"
        Write-Info "Build ID: $env:BUILD_BUILDID"
        Write-Info "Build Number: $env:BUILD_BUILDNUMBER"
    } elseif ($CiMode -eq "GitHub") {
        Write-Info "GitHub Actions detected (GITHUB_ACTIONS: $env:GITHUB_ACTIONS)"
        Write-Info "Workflow: $env:GITHUB_WORKFLOW"
        Write-Info "Run ID: $env:GITHUB_RUN_ID"
    } else {
        Write-Info "Local build environment"
    }
    
    Write-Info "Loading configuration from: $ConfigFile"
    $config = Parse-YamlFile -FilePath $ConfigFile
    
    # Override config values with command line parameters
    $finalSolutionName = if ($SolutionName) { $SolutionName } else { $config.solution.name }
    $finalPublisherName = if ($PublisherName) { $PublisherName } else { $config.publisher.name }
    $finalPublisherPrefix = if ($PublisherPrefix) { $PublisherPrefix } else { $config.publisher.prefix }
    $finalCleanBuild = if ($PSBoundParameters.ContainsKey('CleanBuild')) { $CleanBuild } else { $config.build.cleanBuild -eq "true" }
    
    Write-Info "Starting PCF Control Build Process..."
    Write-Info "Solution Name: $finalSolutionName"
    Write-Info "Publisher: $finalPublisherName ($finalPublisherPrefix)"
    Write-Info "Build Configuration: $BuildConfiguration"
    Write-Info "Clean Build: $finalCleanBuild"
    
    # Step 1: Validate required files
    Write-Info "Validating project structure..."
    if ($config.validation.requiredFiles) {
        foreach ($file in $config.validation.requiredFiles) {
            if (-not (Test-Path $file)) {
                throw "Required file missing: $file"
            }
        }
    }
    Write-Success "Project structure validation passed"
    
    # Step 2: Clean previous build artifacts
    if ($finalCleanBuild) {
        Write-Info "Cleaning previous build artifacts..."
        $cleanPaths = @("out", $config.solutionStructure.tempDirectory, "$finalSolutionName.zip")
        foreach ($path in $cleanPaths) {
            if (Test-Path $path) { 
                Remove-Item $path -Recurse -Force 
                Write-Info "Cleaned: $path"
            }
        }
        Write-Success "Clean completed"
    }
    
    # Step 3: Install npm dependencies
    Write-Info "Installing npm dependencies..."
    $npmCmd = if ($config.build.npmCommand) { $config.build.npmCommand } else { "ci" }
    if (Test-Path "package-lock.json") {
        & npm $npmCmd
    } else {
        & npm install
    }
    if ($LASTEXITCODE -ne 0) { throw "npm install failed" }
    Write-Success "Dependencies installed"
    
    # Step 4: Build PCF control
    Write-Info "Building PCF control..."
    $buildCmd = if ($config.build.pcfBuildCommand) { $config.build.pcfBuildCommand } else { "build" }
    & npm run $buildCmd
    if ($LASTEXITCODE -ne 0) { throw "PCF build failed" }
    Write-Success "PCF control built successfully"
    
    # Step 5: Validate post-build files
    if ($config.validation.postBuildFiles) {
        Write-Info "Validating build output..."
        foreach ($file in $config.validation.postBuildFiles) {
            if (-not (Test-Path $file)) {
                Write-Warning "Expected build output missing: $file"
            }
        }
        Write-Success "Build output validation completed"
    }
    
    # Step 6: Verify PAC CLI is available
    Write-Info "Checking Power Platform CLI..."
    try {
        $pacVersion = & pac --version 2>&1
        Write-Success "PAC CLI available: $($pacVersion -join ' ')"
    }
    catch {
        Write-Error "Power Platform CLI not found. Installing..."
        & dotnet tool install --global Microsoft.PowerApps.CLI.Tool
        if ($LASTEXITCODE -ne 0) { throw "Failed to install PAC CLI" }
        Write-Success "PAC CLI installed"
    }
    
    # Step 7: Create solution folder
    $tempDir = if ($config.solutionStructure.tempDirectory) { $config.solutionStructure.tempDirectory } else { "solution" }
    Write-Info "Creating solution structure in: $tempDir"
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
    Set-Location $tempDir
    
    # Step 8: Initialize solution
    Write-Info "Initializing Power Platform solution..."
    & pac solution init --publisher-name $finalPublisherName --publisher-prefix $finalPublisherPrefix
    if ($LASTEXITCODE -ne 0) { throw "Solution initialization failed" }
    Write-Success "Solution initialized"
    
    # Step 9: List solution contents for debugging
    Write-Info "Solution contents:"
    Get-ChildItem | ForEach-Object { Write-Host "  - $($_.Name)" }
    
    # Step 10: Add PCF control reference to solution
    Write-Info "Adding PCF control to solution..."
    $pcfPath = if ($config.project.pcfRootPath) { $config.project.pcfRootPath } else { "../" }
    & pac solution add-reference --path $pcfPath
    if ($LASTEXITCODE -ne 0) { throw "Failed to add PCF reference" }
    Write-Success "PCF control added to solution"
    
    # Step 11: Build solution
    Write-Info "Building solution (Configuration: $BuildConfiguration)..."
    & dotnet build --configuration $BuildConfiguration
    if ($LASTEXITCODE -ne 0) { throw "Solution build failed" }
    Write-Success "Solution built successfully"
    
    # Step 12: Pack solution
    Write-Info "Packaging solution..."
    $buildConfig = $BuildConfiguration.ToLower()
    $solutionFiles = Get-ChildItem -Path "bin/$BuildConfiguration" -Filter "*.zip" -ErrorAction SilentlyContinue
    if ($solutionFiles.Count -gt 0) {
        $sourceSolution = $solutionFiles[0].FullName
        Copy-Item $sourceSolution "../$finalSolutionName.zip" -Force
        Write-Success "Solution packaged from build output: $finalSolutionName.zip"
    } else {
        # Fallback to manual packing
        & pac solution pack --zipfile "../$finalSolutionName.zip"
        if ($LASTEXITCODE -ne 0) { throw "Solution packaging failed" }
        Write-Success "Solution packaged: $finalSolutionName.zip"
    }
    
    # Step 13: Return to root directory
    Set-Location ..
    
    # Step 14: Verify final output and validate
    if (Test-Path "$finalSolutionName.zip") {
        $zipSize = (Get-Item "$finalSolutionName.zip").Length
        $sizeKB = [math]::Round($zipSize/1KB, 2)
        
        # Validate minimum package size
        $minSize = if ($config.validation.solutionValidation.minPackageSize) { 
            [int]$config.validation.solutionValidation.minPackageSize 
        } else { 1024 }
        
        if ($zipSize -lt $minSize) {
            Write-Warning "Solution package size ($sizeKB KB) is smaller than expected minimum ($([math]::Round($minSize/1KB, 2)) KB)"
        }
        
        Write-Success "Build completed successfully!"
        Write-Info "Solution package: $finalSolutionName.zip ($sizeKB KB)"
        
        # List all build outputs
        Write-Info "Build outputs:"
        if (Test-Path "out") {
            Write-Host "  PCF Build Output (out/):"
            Get-ChildItem "out" -Recurse | ForEach-Object { Write-Host "    - $($_.FullName.Replace($PWD, '.'))" }
        }
        Write-Host "  Solution Package: $finalSolutionName.zip"
        
        # Run post-build script if defined
        if ($config.scripts.postBuild) {
            Write-Info "Running post-build script..."
            Invoke-Expression $config.scripts.postBuild
        }
        
    } else {
        throw "Solution package was not created"
    }
    
    Write-Success "Build process completed successfully!"
    
    # Set CI-specific success indicators
    if ($CiMode -eq "DevOps") {
        Write-Host "##vso[task.complete result=Succeeded;]Build completed successfully"
    } elseif ($CiMode -eq "GitHub") {
        Write-Host "::notice::✅ Build completed successfully"
    }
    
    return 0
}
catch {
    $errorMessage = $_.Exception.Message
    $stackTrace = $_.ScriptStackTrace
    
    Write-BuildError "Build failed: $errorMessage"
    
    # Set CI-specific error indicators
    if ($CiMode -eq "DevOps") {
        Write-Host "##vso[task.logissue type=error]Build failed: $errorMessage"
        Write-Host "##vso[task.complete result=Failed;]Build failed"
        if ($stackTrace) {
            Write-Host "##[debug]Stack trace: $stackTrace"
        }
    } elseif ($CiMode -eq "GitHub") {
        Write-Host "::error::Build failed: $errorMessage"
        if ($stackTrace) {
            Write-Host "::debug::Stack trace: $stackTrace"
        }
    } else {
        Write-Host "Stack trace: $stackTrace" -ForegroundColor Red
    }
    
    # Cleanup on failure
    Set-Location $PSScriptRoot
    $tempDir = if ($config.solutionStructure.tempDirectory) { $config.solutionStructure.tempDirectory } else { "solution" }
    if (Test-Path $tempDir) {
        Write-Warning "Cleaning up failed build artifacts..."
        Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    
    return 1
}
finally {
    # Ensure we're back in the root directory
    Set-Location $PSScriptRoot
}
