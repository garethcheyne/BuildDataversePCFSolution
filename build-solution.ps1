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
.PARAMETER PublisherEmail
    Override publisher email from config file
.PARAMETER CleanBuild
    Override clean build setting from config file
.PARAMETER BuildConfiguration
    Build configuration (Debug, Release) - default: Release
.PARAMETER SolutionType
    Solution type to build (Managed, Unmanaged, Both) - default: Both
.PARAMETER CiMode
    CI/CD mode (GitHub, DevOps, Local) - auto-detected if not specified
.EXAMPLE
    .\build-solution.ps1
    .\build-solution.ps1 -ConfigFile ".\custom-solution.yaml"
    .\build-solution.ps1 -SolutionName "MyCustomSolution" -BuildConfiguration "Debug"
    .\build-solution.ps1 -CiMode "DevOps" -BuildConfiguration "Release"
    .\build-solution.ps1 -SolutionType "Managed" -BuildConfiguration "Release"
    .\build-solution.ps1 -SolutionType "Both"
#>

param(
    [string]$ConfigFile = "./solution.yaml",
    [string]$SolutionName = "",
    [string]$PublisherName = "", 
    [string]$PublisherPrefix = "",
    [string]$PublisherEmail = "",
    [bool]$CleanBuild = $true,
    [string]$BuildConfiguration = "Release",
    [ValidateSet("Managed", "Unmanaged", "Both")]
    [string]$SolutionType = "Both",
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
    
    # Read content and handle BOM properly
    $content = Get-Content $FilePath -Encoding UTF8 -Raw
    $content = $content -replace "^\xEF\xBB\xBF", ""  # Remove BOM if present
    $lines = $content -split "`r?`n"
    
    foreach ($rawLine in $lines) {
        $line = $rawLine.Trim()
        
        # Skip comments and empty lines
        if ($line.StartsWith("#") -or [string]::IsNullOrWhiteSpace($line)) {
            continue
        }
        
        # Handle top-level sections (no indentation, ends with colon)
        if ($line -match "^([a-zA-Z_][a-zA-Z0-9_]*):$") {
            $currentSection = $matches[1]
            $yaml[$currentSection] = @{}
        }
        # Handle properties with 2 spaces indentation
        elseif ($rawLine -match "^  ([a-zA-Z_][a-zA-Z0-9_]*): ?(.+)$") {
            $key = $matches[1]
            $value = $matches[2].Trim()
            
            # Remove surrounding quotes
            $value = $value -replace '^"(.*)"$', '$1' -replace "^'(.*)'$", '$1'
            
            if ($currentSection) {
                $yaml[$currentSection][$key] = $value
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
    $resolved = $resolved -replace '\{\{publisher\.email\}\}', $Config.publisher.email
    
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
    $baseSolutionName = if ($SolutionName) { $SolutionName } else { $config.solution.name }
    $solutionVersion = $config.solution.version
    $finalSolutionName = "${baseSolutionName}_v${solutionVersion}"
    $finalPublisherName = if ($PublisherName) { $PublisherName } else { $config.publisher.name }
    $finalPublisherPrefix = if ($PublisherPrefix) { $PublisherPrefix } else { $config.publisher.prefix }
    $finalPublisherEmail = if ($PublisherEmail) { $PublisherEmail } else { $config.publisher.email }
    $finalCleanBuild = if ($PSBoundParameters.ContainsKey('CleanBuild')) { $CleanBuild } else { $config.build.cleanBuild -eq "true" }
    $finalSolutionType = if ($PSBoundParameters.ContainsKey('SolutionType')) { $SolutionType } else { 
        if ($config.build.solutionType) { $config.build.solutionType } else { "Both" }
    }
    
    Write-Info "Starting PCF Control Build Process..."
    Write-Info "Solution Name: $baseSolutionName"
    Write-Info "Solution Version: $solutionVersion"
    Write-Info "Final Package Name: releases/$finalSolutionName.zip"
    Write-Info "Publisher: $finalPublisherName ($finalPublisherPrefix)"
    if ($finalPublisherEmail) {
        Write-Info "Publisher Email: $finalPublisherEmail"
    }
    Write-Info "Build Configuration: $BuildConfiguration"
    Write-Info "Solution Type: $finalSolutionType"
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
    
    # Step 2: Create releases directory and clean previous build artifacts
    $releasesDir = "releases"
    if (-not (Test-Path $releasesDir)) {
        New-Item -ItemType Directory -Path $releasesDir -Force | Out-Null
        Write-Info "Created releases directory: $releasesDir"
    }
    
    if ($finalCleanBuild) {
        Write-Info "Cleaning previous build artifacts..."
        $cleanPaths = @("out", $config.solutionStructure.tempDirectory)
        
        # Clean solution packages based on naming pattern in releases directory
        $packagePatterns = @(
            "$releasesDir/${finalSolutionName}_managed.zip",
            "$releasesDir/${finalSolutionName}_unmanaged.zip",
            "$releasesDir/$finalSolutionName.zip",  # Legacy single package
            "${finalSolutionName}_managed.zip",      # Legacy root location
            "${finalSolutionName}_unmanaged.zip",   # Legacy root location
            "$finalSolutionName.zip"                 # Legacy root location
        )
        
        foreach ($pattern in $packagePatterns) {
            $cleanPaths += $pattern
        }
        
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
    
    # Clean up existing solution directory if it exists
    if (Test-Path $tempDir) {
        Write-Info "Removing existing solution directory: $tempDir"
        Remove-Item $tempDir -Recurse -Force
    }
    
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
    Set-Location $tempDir

    # Step 8: Initialize solution
    Write-Info "Initializing Power Platform solution..."
    & pac solution init --publisher-name $finalPublisherName --publisher-prefix $finalPublisherPrefix
    if ($LASTEXITCODE -ne 0) { throw "Solution initialization failed" }
    Write-Success "Solution initialized"
    
    # Step 8.1: Update solution.xml with correct solution name and display name
    Write-Info "Updating solution.xml with correct solution information..."
    $solutionXmlPath = "src/Other/Solution.xml"    
    
    if (Test-Path $solutionXmlPath) {
        try {
            # Read the solution.xml file
            [xml]$solutionXml = Get-Content $solutionXmlPath
            
            # Update UniqueName
            $uniqueNameNode = $solutionXml.SelectSingleNode("//UniqueName")
            if ($uniqueNameNode) {
                $uniqueNameNode.InnerText = $finalSolutionName
                Write-Info "Updated UniqueName to: $finalSolutionName"
            }
            
            # Update LocalizedName description
            $localizedNameNode = $solutionXml.SelectSingleNode("//LocalizedName[@languagecode='1033']")
            if ($localizedNameNode) {
                $displayName = if ($config.solution.displayName) { $config.solution.displayName } else { $finalSolutionName }
                $localizedNameNode.SetAttribute("description", $displayName)
                Write-Info "Updated LocalizedName to: $displayName"
            }
            
            # Update solution description if it exists
            $descriptionNode = $solutionXml.SelectSingleNode("//Description[@languagecode='1033']")
            if ($descriptionNode -and $config.solution.description) {
                $descriptionNode.SetAttribute("description", $config.solution.description)
                Write-Info "Updated Description to: $($config.solution.description)"
            }
            
            # Update Publisher information
            $publisherNode = $solutionXml.SelectSingleNode("//Publisher")
            if ($publisherNode) {
                $publisherUniqueNameNode = $publisherNode.SelectSingleNode("UniqueName")
                if ($publisherUniqueNameNode) {
                    $publisherUniqueNameNode.InnerText = $finalPublisherPrefix
                    Write-Info "Updated Publisher UniqueName to: $finalPublisherPrefix"
                }
                
                $publisherLocalizedNameNode = $publisherNode.SelectSingleNode("LocalizedNames/LocalizedName[@languagecode='1033']")
                if ($publisherLocalizedNameNode) {
                    $publisherDisplayName = if ($config.publisher.displayName) { $config.publisher.displayName } else { $finalPublisherName }
                    $publisherLocalizedNameNode.SetAttribute("description", $publisherDisplayName)
                    Write-Info "Updated Publisher LocalizedName to: $publisherDisplayName"
                }
                
                # Update Publisher email if available and node exists
                if ($finalPublisherEmail) {
                    $publisherEmailNode = $publisherNode.SelectSingleNode("EMailAddress")
                    if ($publisherEmailNode) {
                        $publisherEmailNode.InnerText = $finalPublisherEmail
                        Write-Info "Updated Publisher Email to: $finalPublisherEmail"
                    } else {
                        # Create email node if it doesn't exist
                        $emailElement = $solutionXml.CreateElement("EMailAddress")
                        $emailElement.InnerText = $finalPublisherEmail
                        $publisherNode.AppendChild($emailElement) | Out-Null
                        Write-Info "Added Publisher Email: $finalPublisherEmail"
                    }
                }
                
                # Update Publisher Address information if provided
                if ($config.publisher.address) {
                    $addressNode = $publisherNode.SelectSingleNode("Addresses/Address")
                    if (-not $addressNode) {
                        # Create Addresses node if it doesn't exist
                        $addressesNode = $publisherNode.SelectSingleNode("Addresses")
                        if (-not $addressesNode) {
                            $addressesNode = $solutionXml.CreateElement("Addresses")
                            $publisherNode.AppendChild($addressesNode) | Out-Null
                        }
                        # Create Address node
                        $addressNode = $solutionXml.CreateElement("Address")
                        $addressesNode.AppendChild($addressNode) | Out-Null
                        
                        # Add required Address attributes/elements
                        $addressNumberElement = $solutionXml.CreateElement("AddressNumber")
                        $addressNumberElement.InnerText = "1"
                        $addressNode.AppendChild($addressNumberElement) | Out-Null
                        
                        $addressTypeCodeElement = $solutionXml.CreateElement("AddressTypeCode")
                        $addressTypeCodeElement.InnerText = "1"
                        $addressNode.AppendChild($addressTypeCodeElement) | Out-Null
                        
                        $shippingMethodCodeElement = $solutionXml.CreateElement("ShippingMethodCode")
                        $shippingMethodCodeElement.InnerText = "1"
                        $addressNode.AppendChild($shippingMethodCodeElement) | Out-Null
                    }
                    
                    # Define address field mappings
                    $addressFields = @{
                        "Line1" = $config.publisher.address.line1
                        "Line2" = $config.publisher.address.line2
                        "Line3" = $config.publisher.address.line3
                        "City" = $config.publisher.address.city
                        "StateOrProvince" = $config.publisher.address.stateOrProvince
                        "PostalCode" = $config.publisher.address.postalCode
                        "Country" = $config.publisher.address.country
                        "County" = $config.publisher.address.county
                        "Telephone1" = $config.publisher.address.telephone1
                        "Telephone2" = $config.publisher.address.telephone2
                        "Telephone3" = $config.publisher.address.telephone3
                        "Fax" = $config.publisher.address.fax
                        "Name" = $config.publisher.address.name
                        "PrimaryContactName" = $config.publisher.address.primaryContactName
                        "PostOfficeBox" = $config.publisher.address.postOfficeBox
                    }
                    
                    # Update address fields if they have values
                    $updatedFields = 0
                    foreach ($fieldName in $addressFields.Keys) {
                        $fieldValue = $addressFields[$fieldName]
                        if ($fieldValue -and $fieldValue.Trim() -ne "") {
                            $fieldNode = $addressNode.SelectSingleNode($fieldName)
                            if (-not $fieldNode) {
                                # Create the field node if it doesn't exist
                                $fieldNode = $solutionXml.CreateElement($fieldName)
                                $addressNode.AppendChild($fieldNode) | Out-Null
                            }
                            
                            # Remove xsi:nil attribute if it exists and set the value
                            $fieldNode.RemoveAttribute("nil", "http://www.w3.org/2001/XMLSchema-instance")
                            $fieldNode.InnerText = $fieldValue.Trim()
                            $updatedFields++
                        }
                    }
                    
                    if ($updatedFields -gt 0) {
                        Write-Info "Updated $updatedFields publisher address field(s)"
                    }
                }
            }
            
            # Save the updated XML file
            $solutionXml.Save((Resolve-Path $solutionXmlPath).Path)
            Write-Success "Solution.xml updated successfully"
        }
        catch {
            Write-Warning "Failed to update solution.xml: $($_.Exception.Message)"
            Write-Warning "Continuing with build, but solution may have generic names"
        }
    } else {
        Write-Warning "Solution.xml file not found at expected path: $solutionXmlPath"
        Write-Warning "Solution may use default names"
    }
    
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
    
    # Step 12: Pack solution(s) based on SolutionType
    Write-Info "Packaging solution(s) - Type: $finalSolutionType..."
    $buildConfig = $BuildConfiguration.ToLower()
    $createdPackages = @()
    
    if ($finalSolutionType -eq "Unmanaged" -or $finalSolutionType -eq "Both") {
        Write-Info "Creating unmanaged solution package..."
        $unmanagedName = "${finalSolutionName}_unmanaged"
        $unmanagedPath = "../releases/$unmanagedName.zip"
        
        # Try to find built solution first
        $solutionFiles = Get-ChildItem -Path "bin/$BuildConfiguration" -Filter "*.zip" -ErrorAction SilentlyContinue
        if ($solutionFiles.Count -gt 0) {
            $sourceSolution = $solutionFiles[0].FullName
            Copy-Item $sourceSolution $unmanagedPath -Force
            Write-Success "Unmanaged solution packaged from build output: releases/$unmanagedName.zip"
        } else {
            # Fallback to manual packing
            & pac solution pack --zipfile $unmanagedPath --folder src
            if ($LASTEXITCODE -ne 0) { throw "Unmanaged solution packaging failed" }
            Write-Success "Unmanaged solution packaged: releases/$unmanagedName.zip"
        }
        $createdPackages += "releases/$unmanagedName.zip"
    }
    
    if ($finalSolutionType -eq "Managed" -or $finalSolutionType -eq "Both") {
        Write-Info "Creating managed solution package..."
        $managedName = "${finalSolutionName}_managed"
        $managedPath = "../releases/$managedName.zip"
        
        # For managed solutions, we create an unmanaged solution first, then import and export as managed
        # This is the proper way to create managed solutions with PAC CLI
        Write-Info "Creating managed solution by first creating unmanaged, then converting..."
        
        # First create unmanaged solution in temp location
        $tempUnmanagedPath = "../releases/temp_unmanaged.zip"
        & pac solution pack --zipfile $tempUnmanagedPath --folder src
        if ($LASTEXITCODE -ne 0) { 
            Write-Error "Failed to create temporary unmanaged solution for managed conversion"
            throw "Managed solution packaging failed - unable to create base unmanaged solution" 
        }
        
        # Now try to create managed solution using the --packagetype parameter
        Write-Info "Converting to managed solution package..."
        & pac solution pack --zipfile $managedPath --folder src --packagetype Managed
        
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "Direct managed packaging failed, attempting alternative approach..."
            
            # Alternative: Copy the unmanaged solution as managed (this is a fallback)
            # In practice, managed solutions are typically created during solution import/export in an environment
            Write-Info "Using unmanaged solution as managed solution template..."
            Copy-Item $tempUnmanagedPath $managedPath -Force
            Write-Warning "Managed solution created as copy of unmanaged. For true managed solution, import this into an environment and export as managed."
        }
        
        # Clean up temp file
        if (Test-Path $tempUnmanagedPath) {
            Remove-Item $tempUnmanagedPath -Force
        }
        
        # Verify the managed solution was created and has content
        if (Test-Path $managedPath) {
            $managedFileSize = (Get-Item $managedPath).Length
            if ($managedFileSize -gt 1000) {  # Should be at least 1KB
                Write-Success "Managed solution packaged: releases/$managedName.zip (${managedFileSize} bytes)"
                $createdPackages += "releases/$managedName.zip"
            } else {
                Write-Error "Managed solution appears to be empty or corrupted (${managedFileSize} bytes)"
                throw "Managed solution packaging failed - file too small"
            }
        } else {
            Write-Error "Managed solution file was not created"
            throw "Managed solution packaging failed - file not found"
        }
    }
    
    # Step 13: Return to root directory
    Set-Location ..
    
    # Step 14: Verify final output and validate
    if ($createdPackages.Count -gt 0) {
        Write-Success "Build completed successfully!"
        Write-Info "Created solution packages:"
        
        $totalSize = 0
        foreach ($package in $createdPackages) {
            if (Test-Path $package) {
                $zipSize = (Get-Item $package).Length
                $sizeKB = [math]::Round($zipSize/1KB, 2)
                $totalSize += $zipSize
                
                # Validate minimum package size
                $minSize = if ($config.validation.solutionValidation.minPackageSize) { 
                    [int]$config.validation.solutionValidation.minPackageSize 
                } else { 1024 }
                
                if ($zipSize -lt $minSize) {
                    Write-Warning "Solution package size ($sizeKB KB) is smaller than expected minimum ($([math]::Round($minSize/1KB, 2)) KB) for $package"
                }
                
                Write-Host "  - $package ($sizeKB KB)"
            } else {
                Write-Warning "Expected package not found: $package"
            }
        }
        
        $totalSizeKB = [math]::Round($totalSize/1KB, 2)
        Write-Info "Total package size: $totalSizeKB KB"
        
        # List all build outputs
        Write-Info "Build outputs:"
        if (Test-Path "out") {
            Write-Host "  PCF Build Output (out/):"
            Get-ChildItem "out" -Recurse | ForEach-Object { Write-Host "    - $($_.FullName.Replace($PWD, '.'))" }
        }
        Write-Host "  Solution Packages:"
        foreach ($package in $createdPackages) {
            Write-Host "    - $package"
        }
        
        # Run post-build script if defined
        if ($config.scripts.postBuild -and $config.scripts.postBuild.Trim()) {
            Write-Info "Running post-build script..."
            try {
                Invoke-Expression $config.scripts.postBuild
            }
            catch {
                Write-Warning "Post-build script failed: $($_.Exception.Message)"
            }
        }
        
    } else {
        throw "No solution packages were created"
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
