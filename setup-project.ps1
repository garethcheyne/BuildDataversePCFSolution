# Interactive setup script for PCF BuildDataverseSolution CI/CD system

param(
    [string]$ProjectPath = ".",
    [switch]$NonInteractive
)

# Set error action preference
$ErrorActionPreference = "Stop"

# Color functions for output
function Write-Header { param($Message) Write-Host "`n=== $Message ===" -ForegroundColor Magenta }
function Write-Info { param($Message) Write-Host "INFO: $Message" -ForegroundColor Cyan }
function Write-Success { param($Message) Write-Host "[OK] SUCCESS: $Message" -ForegroundColor Green }
function Write-Warning { param($Message) Write-Host "[!] WARNING: $Message" -ForegroundColor Yellow }
function Write-Error { param($Message) Write-Host "[X] ERROR: $Message" -ForegroundColor Red }

# Function to add BuildDataversePCFSolution scripts to package.json
function Add-BoomScriptToPackageJson {
    param(
        [string]$ProjectPath,
        [string]$SolutionName
    )
    
    $packageJsonPath = Join-Path $ProjectPath "package.json"
    
    if (-not (Test-Path $packageJsonPath)) {
        Write-Warning "package.json not found in project directory"
        return $false
    }
    
    try {
        $packageContent = Get-Content $packageJsonPath -Raw | ConvertFrom-Json
        
        # Ensure scripts section exists
        if (-not $packageContent.scripts) {
            $packageContent | Add-Member -Type NoteProperty -Name "scripts" -Value @{}
        }
        
        # Add BuildDataversePCFSolution scripts
        $scriptsToAdd = @{
            "boom" = "powershell.exe -ExecutionPolicy Bypass -Command `"& './BuildDataversePCFSolution/build-solution.ps1' -BuildConfiguration Release`""
            "boom-debug" = "powershell.exe -ExecutionPolicy Bypass -Command `"& './BuildDataversePCFSolution/build-solution.ps1' -BuildConfiguration Debug`""
            "boom-managed" = "powershell.exe -ExecutionPolicy Bypass -Command `"& './BuildDataversePCFSolution/build-solution.ps1' -BuildConfiguration Release -PackageType Managed`""
            "boom-unmanaged" = "powershell.exe -ExecutionPolicy Bypass -Command `"& './BuildDataversePCFSolution/build-solution.ps1' -BuildConfiguration Release -PackageType Unmanaged`""
            "boom-check" = "powershell.exe -ExecutionPolicy Bypass -Command `"& './BuildDataversePCFSolution/environment-check.ps1'`""
            "boom-create" = "powershell.exe -ExecutionPolicy Bypass -Command `"& './BuildDataversePCFSolution/create-pcf-project.ps1'`""
            "boom-upgrade" = "powershell.exe -ExecutionPolicy Bypass -Command `"& './BuildDataversePCFSolution/upgrade.ps1'`""
        }
        
        $scriptsAdded = 0
        foreach ($scriptName in $scriptsToAdd.Keys) {
            if (-not $packageContent.scripts.$scriptName) {
                $packageContent.scripts | Add-Member -Type NoteProperty -Name $scriptName -Value $scriptsToAdd[$scriptName] -Force
                $scriptsAdded++
            }
        }
        
        # Convert back to JSON with proper formatting and tab indentation
        $jsonOutput = $packageContent | ConvertTo-Json -Depth 100
        
        # Create properly beautified JSON with consistent tab indentation
        $lines = $jsonOutput -split "`r?`n"
        $beautifiedLines = @()
        $indentLevel = 0
        
        foreach ($line in $lines) {
            $trimmedLine = $line.Trim()
            
            # Decrease indent for closing braces/brackets
            if ($trimmedLine -match '^[}\]]') {
                $indentLevel = [Math]::Max(0, $indentLevel - 1)
            }
            
            # Add proper tab indentation
            $indent = "`t" * $indentLevel
            $beautifiedLines += "$indent$trimmedLine"
            
            # Increase indent for opening braces/brackets
            if ($trimmedLine -match '[{[]$') {
                $indentLevel++
            }
        }
        
        $jsonOutput = $beautifiedLines -join "`r`n"
        
        # Save without BOM to prevent encoding issues
        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($packageJsonPath, $jsonOutput + "`r`n", $utf8NoBom)
        
        if ($scriptsAdded -gt 0) {
            Write-Success "Added $scriptsAdded BuildDataversePCFSolution scripts to package.json"
            Write-Host "   Available scripts:" -ForegroundColor DarkGray
            Write-Host "   -> npm run boom           - Quick Release build" -ForegroundColor Cyan
            Write-Host "   -> npm run boom-debug     - Quick Debug build" -ForegroundColor Cyan  
            Write-Host "   -> npm run boom-managed   - Build managed solution only" -ForegroundColor Cyan
            Write-Host "   -> npm run boom-unmanaged - Build unmanaged solution only" -ForegroundColor Cyan
            Write-Host "   -> npm run boom-check     - Check development environment" -ForegroundColor Cyan
            Write-Host "   -> npm run boom-create    - Create new PCF project" -ForegroundColor Cyan
            Write-Host "   -> npm run boom-upgrade   - Check for and install updates" -ForegroundColor Cyan
        } else {
            Write-Info "All BuildDataversePCFSolution scripts already exist in package.json"
        }
        
        return $true
    }
    catch {
        Write-Error "Failed to update package.json: $($_.Exception.Message)"
        return $false
    }
}

# Function to prompt for input with default value
function Get-UserInput {
    param(
        [string]$Prompt,
        [string]$DefaultValue = "",
        [switch]$Required
    )
    
    if ($NonInteractive) {
        return $DefaultValue
    }
    
    $promptText = $Prompt
    if (-not [string]::IsNullOrEmpty($DefaultValue)) {
        $promptText += " (default: $DefaultValue)"
    }
    if ($Required) {
        $promptText += " *"
    }
    # Note: Read-Host automatically adds ": " so we don't add it here
    
    do {
        Write-Host "-> " -NoNewline -ForegroundColor Cyan
        $userInput = Read-Host $promptText
        
        if ([string]::IsNullOrWhiteSpace($userInput)) {
            if (-not [string]::IsNullOrEmpty($DefaultValue)) {
                return $DefaultValue
            } elseif ($Required) {
                Write-Host "   WARNING: This field is required. Please provide a value." -ForegroundColor Red
                continue
            } else {
                return ""
            }
        }
        
        return $userInput.Trim()
    } while ($Required)
}

# Function to prompt for yes/no with default
function Get-YesNoInput {
    param(
        [string]$Prompt,
        [bool]$DefaultValue = $true
    )
    
    if ($NonInteractive) {
        return $DefaultValue
    }
    
    $defaultText = if ($DefaultValue) { "Y/n" } else { "y/N" }
    
    do {
        Write-Host "? " -NoNewline -ForegroundColor Yellow
        $response = Read-Host "$Prompt [$defaultText]"
        
        if ([string]::IsNullOrWhiteSpace($response)) {
            return $DefaultValue
        }
        
        $response = $response.Trim().ToLower()
        if ($response -in @("y", "yes", "true", "1")) {
            return $true
        }
        if ($response -in @("n", "no", "false", "0")) {
            return $false
        }
        
        Write-Host "   WARNING: Please enter Y (yes) or N (no)" -ForegroundColor Red
    } while ($true)
}

# Function to clean up previous CI/CD installations
function Remove-PreviousCicdFiles {
    param([string]$ProjectPath)
    
    Write-Info "Cleaning up any previous CI/CD installations..."
    
    # Remove GitHub Actions
    $githubDir = Join-Path $ProjectPath ".github"
    if (Test-Path $githubDir) {
        Write-Info "Removing existing GitHub Actions directory: $githubDir"
        Remove-Item $githubDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    
    # Remove Azure DevOps pipeline
    $azurePipeline = Join-Path $ProjectPath "azure-pipelines.yml"
    if (Test-Path $azurePipeline) {
        Write-Info "Removing existing Azure DevOps pipeline file: $azurePipeline"
        Remove-Item $azurePipeline -Force -ErrorAction SilentlyContinue
    }
    
    # Remove old summary/documentation files that might exist
    $oldFiles = @(
        "CICD-SYSTEM-SUMMARY.md",
        "CI-CD-SETUP.md"
    )
    
    foreach ($file in $oldFiles) {
        $filePath = Join-Path $ProjectPath $file
        if (Test-Path $filePath) {
            Write-Info "Removing old file: $file"
            Remove-Item $filePath -Force -ErrorAction SilentlyContinue
        }
    }
    
    Write-Success "Previous CI/CD files cleaned up"
}

# Function to validate project structure
function Test-PCFProject {
    param([string]$Path)
    
    $requiredFiles = @(
        "package.json",
        "tsconfig.json"
    )
    
    $pcfFiles = Get-ChildItem -Path $Path -Filter "*.pcfproj" -ErrorAction SilentlyContinue
    if ($pcfFiles.Count -eq 0) {
        return $false, "No .pcfproj file found"
    }
    
    foreach ($file in $requiredFiles) {
        if (-not (Test-Path (Join-Path $Path $file))) {
            return $false, "Required file missing: $file"
        }
    }
    
    return $true, "Valid PCF project structure"
}

# Function to get version from package.json
function Get-PackageJsonVersion {
    param([string]$ProjectPath)
    
    $packageJsonPath = Join-Path $ProjectPath "package.json"
    if (Test-Path $packageJsonPath) {
        try {
            $packageJson = Get-Content $packageJsonPath -Raw | ConvertFrom-Json
            return $packageJson.version
        }
        catch {
            Write-Warning "Could not read version from package.json: $($_.Exception.Message)"
            return "1.0.0"
        }
    }
    return "1.0.0"
}

function Update-PackageJsonVersion {
    param(
        [string]$ProjectPath,
        [string]$NewVersion
    )
    
    $packageJsonPath = Join-Path $ProjectPath "package.json"
    if (-not (Test-Path $packageJsonPath)) {
        Write-Warning "package.json not found at $packageJsonPath"
        return $false
    }
    
    try {
        # Read the current package.json content as text to preserve formatting
        $content = Get-Content $packageJsonPath -Raw
        
        # Use regex to replace the version while preserving formatting
        $pattern = '("version"\s*:\s*")[^"]*(")'
        $replacement = "`${1}$NewVersion`${2}"
        $updatedContent = $content -replace $pattern, $replacement
        
        # Write back to file without BOM to prevent encoding issues
        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($packageJsonPath, $updatedContent, $utf8NoBom)
        
        Write-Success "Updated package.json version to $NewVersion"
        return $true
    }
    catch {
        Write-Error "Failed to update package.json version: $($_.Exception.Message)"
        return $false
    }
}

# Function to remove BOM from a file
function Remove-BomFromFile {
    param(
        [string]$FilePath
    )
    
    if (-not (Test-Path $FilePath)) {
        Write-Warning "File not found: $FilePath"
        return $false
    }
    
    try {
        # Read file content as bytes
        $bytes = [System.IO.File]::ReadAllBytes($FilePath)
        
        # Check if file starts with UTF-8 BOM (EF BB BF)
        if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
            Write-Info "Removing BOM from $([System.IO.Path]::GetFileName($FilePath))"
            
            # Remove BOM by skipping first 3 bytes
            $contentWithoutBom = $bytes[3..($bytes.Length - 1)]
            
            # Write back without BOM
            [System.IO.File]::WriteAllBytes($FilePath, $contentWithoutBom)
            return $true
        }
        
        return $false
    }
    catch {
        Write-Error "Failed to remove BOM from $FilePath`: $($_.Exception.Message)"
        return $false
    }
}

# Function to recreate package.json from scratch without BOM
function New-PackageJsonFromScratch {
    param(
        [string]$ProjectPath,
        [string]$SolutionName
    )
    
    $packageJsonPath = Join-Path $ProjectPath "package.json"
    
    if (-not (Test-Path $packageJsonPath)) {
        Write-Warning "package.json not found at $packageJsonPath"
        return $false
    }
    
    try {
        Write-Info "Recreating package.json from scratch to remove BOM issues..."
        
        # Read current content and parse as JSON
        $currentContent = Get-Content $packageJsonPath -Raw | ConvertFrom-Json
        
        # Create a clean package.json structure
        $cleanPackage = [ordered]@{}
        
        # Copy properties in a specific order for consistency
        $propertyOrder = @('name', 'version', 'description', 'main', 'scripts', 'keywords', 'author', 'license', 'dependencies', 'devDependencies', 'peerDependencies')
        
        foreach ($prop in $propertyOrder) {
            if ($currentContent.PSObject.Properties.Name -contains $prop) {
                $cleanPackage[$prop] = $currentContent.$prop
            }
        }
        
        # Add any remaining properties not in the standard order
        foreach ($prop in $currentContent.PSObject.Properties.Name) {
            if ($prop -notin $propertyOrder) {
                $cleanPackage[$prop] = $currentContent.$prop
            }
        }
        
        # Ensure scripts section exists
        if (-not $cleanPackage.scripts) {
            $cleanPackage.scripts = [ordered]@{}
        }
        
        # Add BuildDataversePCFSolution scripts
        $scriptsToAdd = [ordered]@{
            "boom" = "powershell.exe -ExecutionPolicy Bypass -Command `"& './BuildDataversePCFSolution/build-solution.ps1' -BuildConfiguration Release`""
            "boom-debug" = "powershell.exe -ExecutionPolicy Bypass -Command `"& './BuildDataversePCFSolution/build-solution.ps1' -BuildConfiguration Debug`""
            "boom-managed" = "powershell.exe -ExecutionPolicy Bypass -Command `"& './BuildDataversePCFSolution/build-solution.ps1' -BuildConfiguration Release -PackageType Managed`""
            "boom-unmanaged" = "powershell.exe -ExecutionPolicy Bypass -Command `"& './BuildDataversePCFSolution/build-solution.ps1' -BuildConfiguration Release -PackageType Unmanaged`""
            "boom-check" = "powershell.exe -ExecutionPolicy Bypass -Command `"& './BuildDataversePCFSolution/environment-check.ps1'`""
            "boom-create" = "powershell.exe -ExecutionPolicy Bypass -Command `"& './BuildDataversePCFSolution/create-pcf-project.ps1'`""
            "boom-upgrade" = "powershell.exe -ExecutionPolicy Bypass -Command `"& './BuildDataversePCFSolution/upgrade.ps1'`""
        }
        
        $scriptsAdded = 0
        foreach ($scriptName in $scriptsToAdd.Keys) {
            if (-not $cleanPackage.scripts.$scriptName) {
                $cleanPackage.scripts[$scriptName] = $scriptsToAdd[$scriptName]
                $scriptsAdded++
            }
        }
        
        # Convert to JSON with proper formatting
        $jsonOutput = $cleanPackage | ConvertTo-Json -Depth 100
        
        # Create properly beautified JSON with consistent tab indentation
        $lines = $jsonOutput -split "`r?`n"
        $beautifiedLines = @()
        $indentLevel = 0
        
        foreach ($line in $lines) {
            $trimmedLine = $line.Trim()
            
            # Decrease indent for closing braces/brackets
            if ($trimmedLine -match '^[}\]]') {
                $indentLevel = [Math]::Max(0, $indentLevel - 1)
            }
            
            # Add proper tab indentation
            $indent = "`t" * $indentLevel
            $beautifiedLines += "$indent$trimmedLine"
            
            # Increase indent for opening braces/brackets
            if ($trimmedLine -match '[{[]$') {
                $indentLevel++
            }
        }
        
        $jsonOutput = $beautifiedLines -join "`r`n"
        
        # Delete the old file
        Remove-Item $packageJsonPath -Force
        
        # Create new file without BOM
        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($packageJsonPath, $jsonOutput + "`r`n", $utf8NoBom)
        
        Write-Success "Successfully recreated package.json without BOM"
        if ($scriptsAdded -gt 0) {
            Write-Success "Added $scriptsAdded BuildDataversePCFSolution scripts to package.json"
            Write-Host "   Available scripts:" -ForegroundColor DarkGray
            Write-Host "   -> npm run boom           - Quick Release build" -ForegroundColor Cyan
            Write-Host "   -> npm run boom-debug     - Quick Debug build" -ForegroundColor Cyan  
            Write-Host "   -> npm run boom-managed   - Build managed solution only" -ForegroundColor Cyan
            Write-Host "   -> npm run boom-unmanaged - Build unmanaged solution only" -ForegroundColor Cyan
            Write-Host "   -> npm run boom-check     - Check development environment" -ForegroundColor Cyan
            Write-Host "   -> npm run boom-create    - Create new PCF project" -ForegroundColor Cyan
        }
        
        return $true
    }
    catch {
        Write-Error "Failed to recreate package.json: $($_.Exception.Message)"
        return $false
    }
}



function Get-SuggestedVersionBump {
    param([string]$CurrentVersion)
    
    # Parse semantic version (supports formats like 2025.7.27.4 or 1.2.3)
    if ($CurrentVersion -match '^(\d+)\.(\d+)\.(\d+)\.(\d+)$') {
        # Four-part version (e.g., 2025.7.27.4)
        $major = [int]$matches[1]
        $minor = [int]$matches[2] 
        $patch = [int]$matches[3]
        $build = [int]$matches[4]
        
        return @{
            Major = "$($major + 1).0.0.0"
            Minor = "$major.$($minor + 1).0.0"
            Patch = "$major.$minor.$($patch + 1).0"
            Build = "$major.$minor.$patch.$($build + 1)"
        }
    }
    elseif ($CurrentVersion -match '^(\d+)\.(\d+)\.(\d+)$') {
        # Three-part version (e.g., 1.2.3)
        $major = [int]$matches[1]
        $minor = [int]$matches[2]
        $patch = [int]$matches[3]
        
        return @{
            Major = "$($major + 1).0.0"
            Minor = "$major.$($minor + 1).0"
            Patch = "$major.$minor.$($patch + 1)"
            Build = "$major.$minor.$patch.1"
        }
    }
    else {
        # Fallback for non-standard versions
        return @{
            Major = "2.0.0"
            Minor = "1.1.0"
            Patch = "1.0.1"
            Build = "1.0.0.1"
        }
    }
}

# Function to detect Git repository information
function Get-GitRepositoryInfo {
    param([string]$ProjectPath)
    
    $gitInfo = @{
        IsGitRepo = $false
        RemoteUrl = ""
        Owner = ""
        RepoName = ""
        Platform = "Unknown"
    }
    
    try {
        Push-Location $ProjectPath
        
        # Check if this is a git repository
        $gitStatus = git status 2>$null
        if ($LASTEXITCODE -eq 0) {
            $gitInfo.IsGitRepo = $true
            
            # Get remote URL
            $remoteUrl = git remote get-url origin 2>$null
            if ($remoteUrl) {
                $gitInfo.RemoteUrl = $remoteUrl.Trim()
                
                # Parse GitHub URL
                if ($remoteUrl -match "github\.com[:/]([^/]+)/([^/]+?)(\.git)?$") {
                    $gitInfo.Owner = $matches[1]
                    $gitInfo.RepoName = $matches[2] -replace "\.git$", ""
                    $gitInfo.Platform = "GitHub"
                }
                # Parse Azure DevOps URL
                elseif ($remoteUrl -match "dev\.azure\.com/([^/]+)/([^/]+)/_git/([^/]+)" -or $remoteUrl -match "([^.]+)\.visualstudio\.com/([^/]+)/_git/([^/]+)") {
                    $gitInfo.Owner = $matches[1]
                    $gitInfo.RepoName = $matches[3]
                    $gitInfo.Platform = "Azure DevOps"
                }
                # Parse other common Git hosting patterns
                elseif ($remoteUrl -match "([^/]+)/([^/]+?)(\.git)?$") {
                    $parts = $remoteUrl -split "/"
                    if ($parts.Length -ge 2) {
                        $gitInfo.Owner = $parts[-2]
                        $gitInfo.RepoName = $parts[-1] -replace "\.git$", ""
                    }
                }
            }
        }
    }
    catch {
        Write-Verbose "Error detecting git repository: $($_.Exception.Message)"
    }
    finally {
        Pop-Location
    }
    
    return $gitInfo
}

# Function to read existing solution.yaml configuration
function Get-ExistingSolutionConfig {
    param([string]$ProjectPath)
    
    $config = @{
        SolutionName = ""
        DisplayName = ""
        Description = ""
        Version = ""
        PublisherName = ""
        PublisherDisplayName = ""
        PublisherPrefix = ""
        PublisherDescription = ""
        NodeVersion = ""
        DotnetVersion = ""
    }
    
    $yamlPath = Join-Path $ProjectPath "solution.yaml"
    if (-not (Test-Path $yamlPath)) {
        return $config
    }
    
    try {
        $yamlContent = Get-Content $yamlPath -Raw
        
        # Simple YAML parsing for our specific structure
        if ($yamlContent -match 'name:\s*["]?([^"\r\n]+)["]?') {
            $config.SolutionName = $matches[1].Trim()
        }
        if ($yamlContent -match 'displayName:\s*["]?([^"\r\n]+)["]?') {
            $config.DisplayName = $matches[1].Trim()
        }
        if ($yamlContent -match 'description:\s*["]?([^"\r\n]+)["]?') {
            $config.Description = $matches[1].Trim()
        }
        if ($yamlContent -match 'version:\s*["]?([^"\r\n]+)["]?') {
            $config.Version = $matches[1].Trim()
        }
        
        # Publisher information
        if ($yamlContent -match 'publisher:[\r\n]+\s+name:\s*["]?([^"\r\n]+)["]?') {
            $config.PublisherName = $matches[1].Trim()
        }
        if ($yamlContent -match 'publisher:[\r\n]+(?:.*[\r\n]+)*?\s+displayName:\s*["]?([^"\r\n]+)["]?') {
            $config.PublisherDisplayName = $matches[1].Trim()
        }
        if ($yamlContent -match 'publisher:[\r\n]+(?:.*[\r\n]+)*?\s+prefix:\s*["]?([^"\r\n]+)["]?') {
            $config.PublisherPrefix = $matches[1].Trim()
        }
        if ($yamlContent -match 'publisher:[\r\n]+(?:.*[\r\n]+)*?\s+description:\s*["]?([^"\r\n]+)["]?') {
            $config.PublisherDescription = $matches[1].Trim()
        }
        
        # Build configuration
        if ($yamlContent -match 'nodeVersion:\s*["]?([^"\r\n]+)["]?') {
            $config.NodeVersion = $matches[1].Trim()
        }
        if ($yamlContent -match 'dotnetVersion:\s*["]?([^"\r\n]+)["]?') {
            $config.DotnetVersion = $matches[1].Trim()
        }
    }
    catch {
        Write-Verbose "Could not parse solution.yaml: $($_.Exception.Message)"
    }
    
    return $config
}

# Function to extract information from ControlManifest.Input.xml
function Get-ControlManifestInfo {
    param([string]$ProjectPath)
    
    $manifestInfo = @{
        Namespace = ""
        Constructor = ""
        Version = ""
        DisplayName = ""
        Description = ""
    }
    
    # Look for ControlManifest.Input.xml in common locations
    $possiblePaths = @(
        (Join-Path $ProjectPath "ControlManifest.Input.xml"),
        (Join-Path $ProjectPath "*\ControlManifest.Input.xml")
    )
    
    $manifestPath = $null
    foreach ($path in $possiblePaths) {
        $found = Get-ChildItem -Path $path -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($found) {
            $manifestPath = $found.FullName
            break
        }
    }
    
    if ($manifestPath -and (Test-Path $manifestPath)) {
        try {
            [xml]$manifest = Get-Content $manifestPath
            $control = $manifest.manifest.control
            
            if ($control) {
                $manifestInfo.Namespace = $control.namespace
                $manifestInfo.Constructor = $control.constructor
                $manifestInfo.Version = $control.version
                $manifestInfo.DisplayName = $control.'display-name-key'
                $manifestInfo.Description = $control.'description-key'
            }
        }
        catch {
            Write-Warning "Could not parse ControlManifest.Input.xml: $($_.Exception.Message)"
        }
    }
    
    return $manifestInfo
}

try {
    Write-Header "PCF BuildDataverseSolution Setup"
    Write-Info "This script will help you set up CI/CD for your PCF project"
    
    # Validate project path
    $ProjectPath = Resolve-Path $ProjectPath
    Write-Info "Project path: $ProjectPath"
    
    $isValid, $validationMessage = Test-PCFProject -Path $ProjectPath
    if (-not $isValid) {
        Write-Error $validationMessage
        Write-Info "Please run this script from your PCF project root directory"
        exit 1
    }
    Write-Success $validationMessage
    
    # Clean up any previous CI/CD installations
    Remove-PreviousCicdFiles -ProjectPath $ProjectPath
    
    # Find PCF project file
    $pcfFiles = Get-ChildItem -Path $ProjectPath -Filter "*.pcfproj"
    $pcfProjectFile = $pcfFiles[0].Name
    Write-Info "Detected PCF project file: $pcfProjectFile"
    
    # Detect repository information
    Write-Info "Detecting repository information..."
    $gitInfo = Get-GitRepositoryInfo -ProjectPath $ProjectPath
    if ($gitInfo.IsGitRepo) {
        Write-Success "Git repository detected: $($gitInfo.Platform)"
        Write-Info "Repository: $($gitInfo.Owner)/$($gitInfo.RepoName)"
    } else {
        Write-Info "No git repository detected"
    }
    
    # Extract information from ControlManifest.Input.xml
    Write-Info "Reading control manifest information..."
    $manifestInfo = Get-ControlManifestInfo -ProjectPath $ProjectPath
    if ($manifestInfo.DisplayName) {
        Write-Success "Control manifest found: $($manifestInfo.DisplayName)"
    }
    
    # Get project information
    Write-Header "Project Configuration"
    
    # Get version from package.json and offer to bump it
    $packageVersion = Get-PackageJsonVersion -ProjectPath $ProjectPath
    Write-Info "Current version in package.json: $packageVersion"
    
    $bumpVersion = $false
    $newVersion = $packageVersion
    
    if (-not $NonInteractive) {
        Write-Host ""
        Write-Host "VERSION MANAGEMENT" -ForegroundColor Cyan -BackgroundColor Black
        Write-Host "===============================================================" -ForegroundColor Cyan
        Write-Host ""
        
        $bumpVersion = Get-YesNoInput -Prompt "Do you want to bump the version?" -DefaultValue $false
        
        if ($bumpVersion) {
            $suggestedVersions = Get-SuggestedVersionBump -CurrentVersion $packageVersion
            
            Write-Host ""
            Write-Host "VERSION BUMP OPTIONS:" -ForegroundColor Yellow
            Write-Host "+-------------------------------------------------------------+" -ForegroundColor Gray
            Write-Host "| 1. Build:  " -NoNewline -ForegroundColor Gray
            Write-Host "$($suggestedVersions.Build)" -NoNewline -ForegroundColor Green
            Write-Host " (increment build number)".PadRight(25) + " |" -ForegroundColor Gray
            Write-Host "| 2. Patch:  " -NoNewline -ForegroundColor Gray
            Write-Host "$($suggestedVersions.Patch)" -NoNewline -ForegroundColor Green
            Write-Host " (bug fixes)".PadRight(35) + " |" -ForegroundColor Gray
            Write-Host "| 3. Minor:  " -NoNewline -ForegroundColor Gray
            Write-Host "$($suggestedVersions.Minor)" -NoNewline -ForegroundColor Green
            Write-Host " (new features)".PadRight(31) + " |" -ForegroundColor Gray
            Write-Host "| 4. Major:  " -NoNewline -ForegroundColor Gray
            Write-Host "$($suggestedVersions.Major)" -NoNewline -ForegroundColor Green
            Write-Host " (breaking changes)".PadRight(27) + " |" -ForegroundColor Gray
            Write-Host "| 5. Custom: " -NoNewline -ForegroundColor Gray
            Write-Host "Enter your own version".PadRight(32) + " |" -ForegroundColor Gray
            Write-Host "+-------------------------------------------------------------+" -ForegroundColor Gray
            Write-Host ""
            
            do {
                Write-Host "-> " -NoNewline -ForegroundColor Yellow
                $versionChoice = Read-Host "Select version bump type (1-5) or press [Enter] to keep current version"
                if ([string]::IsNullOrWhiteSpace($versionChoice)) {
                    $bumpVersion = $false
                    Write-Host "SUCCESS: Keeping current version: $packageVersion" -ForegroundColor Green
                    break
                }
            } while ($versionChoice -notin @("1", "2", "3", "4", "5"))
            
            if ($bumpVersion) {
                switch ($versionChoice) {
                    "1" { $newVersion = $suggestedVersions.Build }
                    "2" { $newVersion = $suggestedVersions.Patch }
                    "3" { $newVersion = $suggestedVersions.Minor }
                    "4" { $newVersion = $suggestedVersions.Major }
                    "5" { 
                        Write-Host ""
                        Write-Host "CUSTOM VERSION" -ForegroundColor Magenta
                        Write-Host "--------------------------------------------------------------" -ForegroundColor Magenta
                        do {
                            Write-Host "-> " -NoNewline -ForegroundColor Magenta
                            $customVersion = Read-Host "Enter custom version (e.g., 1.2.3 or 1.2.3.4)"
                            if ($customVersion -match '^\d+\.\d+\.\d+(\.\d+)?$') {
                                $newVersion = $customVersion
                                break
                            }
                            Write-Host "WARNING: Please enter a valid version format (e.g., 1.2.3 or 1.2.3.4)" -ForegroundColor Red
                        } while ($true)
                    }
                }
                
                Write-Host ""
                Write-Host "Updating package.json..." -ForegroundColor Cyan
                
                # Update package.json with new version
                $updateSuccess = Update-PackageJsonVersion -ProjectPath $ProjectPath -NewVersion $newVersion
                if ($updateSuccess) {
                    Write-Success "Version updated from $packageVersion to $newVersion"
                } else {
                    Write-Warning "Failed to update package.json, using original version"
                    $newVersion = $packageVersion
                }
            }
        } else {
            Write-Host "SUCCESS: Using current version: $packageVersion" -ForegroundColor Green
        }
        Write-Host ""
    }
    
    # Get existing solution configuration
    $existingConfig = Get-ExistingSolutionConfig -ProjectPath $ProjectPath
    
    # Use manifest info and existing solution.yaml for better defaults
    $defaultSolutionName = if ($existingConfig.SolutionName) { $existingConfig.SolutionName } elseif ($manifestInfo.Constructor) { $manifestInfo.Constructor } else { "PCFSolution" }
    $defaultDisplayName = if ($existingConfig.DisplayName) { $existingConfig.DisplayName } elseif ($manifestInfo.DisplayName) { $manifestInfo.DisplayName } else { $defaultSolutionName }
    $defaultDescription = if ($existingConfig.Description) { $existingConfig.Description } elseif ($manifestInfo.Description) { $manifestInfo.Description } else { "A Power Apps Component Framework control" }
    $defaultPublisherPrefix = if ($existingConfig.PublisherPrefix) { $existingConfig.PublisherPrefix } elseif ($manifestInfo.Namespace) { $manifestInfo.Namespace.ToLower() } else { "pcf" }
    
    # Publisher defaults from existing solution.yaml
    $defaultPublisherName = if ($existingConfig.PublisherName) { $existingConfig.PublisherName } else { "DefaultPublisher" }
    $defaultPublisherDisplayName = if ($existingConfig.PublisherDisplayName) { $existingConfig.PublisherDisplayName } else { $defaultPublisherName }
    $defaultPublisherDescription = if ($existingConfig.PublisherDescription) { $existingConfig.PublisherDescription } else { "Custom PCF controls and Power Platform solutions" }
    
    # Build configuration defaults
    $defaultNodeVersion = if ($existingConfig.NodeVersion) { $existingConfig.NodeVersion } else { "18" }
    $defaultDotnetVersion = if ($existingConfig.DotnetVersion) { $existingConfig.DotnetVersion } else { "6.0.x" }
    
    Write-Host ""
    Write-Host "SOLUTION CONFIGURATION" -ForegroundColor Blue -BackgroundColor Black
    Write-Host "===============================================================" -ForegroundColor Blue
    Write-Host ""
    
    Write-Host "Solution Details:" -ForegroundColor Yellow
    $solutionName = Get-UserInput -Prompt "   Name (no spaces, alphanumeric)" -DefaultValue $defaultSolutionName -Required
    $displayName = Get-UserInput -Prompt "   Display name" -DefaultValue $defaultDisplayName -Required
    $description = Get-UserInput -Prompt "   Description" -DefaultValue $defaultDescription
    $version = Get-UserInput -Prompt "   Version" -DefaultValue $newVersion
    
    Write-Host ""
    Write-Host "Publisher Information:" -ForegroundColor Yellow
    
    $publisherName = Get-UserInput -Prompt "   Publisher name (your name or company)" -DefaultValue $defaultPublisherName -Required
    $publisherDisplayName = Get-UserInput -Prompt "   Publisher display name" -DefaultValue $defaultPublisherDisplayName
    $publisherPrefix = Get-UserInput -Prompt "   Publisher prefix (2-8 characters)" -DefaultValue $defaultPublisherPrefix -Required
    $publisherDescription = Get-UserInput -Prompt "   Publisher description" -DefaultValue $defaultPublisherDescription
    
    # CI/CD Platform Selection with intelligent defaults
    Write-Host ""
    Write-Host "CI/CD PLATFORM SELECTION" -ForegroundColor Magenta -BackgroundColor Black
    Write-Host "===============================================================" -ForegroundColor Magenta
    Write-Host ""
    
    # Default to detected platform if available
    $defaultCicdChoice = "1"  # Default to GitHub
    if ($gitInfo.IsGitRepo -and $gitInfo.Platform -eq "Azure DevOps") {
        $defaultCicdChoice = "2"
    }
    
    $platformDetectedText = if ($gitInfo.IsGitRepo) { " [detected: $($gitInfo.Platform)]" } else { "" }
    
    Write-Host "Choose your CI/CD platform:$platformDetectedText" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "+-------------------------------------------------------------+" -ForegroundColor Gray
    Write-Host "| 1. GitHub Actions    - For GitHub repositories             |" -ForegroundColor Gray
    Write-Host "|    " -NoNewline -ForegroundColor Gray
    Write-Host "Creates .github/workflows/ directory" -NoNewline -ForegroundColor DarkGray
    Write-Host "              |" -ForegroundColor Gray
    Write-Host "|                                                             |" -ForegroundColor Gray
    Write-Host "| 2. Azure DevOps      - For Azure DevOps repositories       |" -ForegroundColor Gray
    Write-Host "|    " -NoNewline -ForegroundColor Gray
    Write-Host "Creates azure-pipelines.yml file" -NoNewline -ForegroundColor DarkGray
    Write-Host "                  |" -ForegroundColor Gray
    Write-Host "|                                                             |" -ForegroundColor Gray
    Write-Host "| 3. Both Platforms    - Set up templates for both           |" -ForegroundColor Gray
    Write-Host "|                                                             |" -ForegroundColor Gray
    Write-Host "| 4. None              - Just create build system only       |" -ForegroundColor Gray
    Write-Host "+-------------------------------------------------------------+" -ForegroundColor Gray
    Write-Host ""
    
    $cicdChoice = $defaultCicdChoice
    if (-not $NonInteractive) {
        do {
            Write-Host "-> " -NoNewline -ForegroundColor Magenta
            $userChoice = Read-Host "Select option (1-4) [default: $defaultCicdChoice]"
            if ([string]::IsNullOrWhiteSpace($userChoice)) {
                $cicdChoice = $defaultCicdChoice
                break
            } else {
                $cicdChoice = $userChoice
            }
        } while ($cicdChoice -notin @("1", "2", "3", "4"))
    }
    
    $setupGitHub = $cicdChoice -in @("1", "3")
    $setupDevOps = $cicdChoice -in @("2", "3")
    
    Write-Host ""
    if ($cicdChoice -eq "4") {
        Write-Host "SUCCESS: Build system only - No CI/CD will be configured" -ForegroundColor Green
    } else {
        $selectedPlatforms = @()
        if ($setupGitHub) { $selectedPlatforms += "GitHub Actions" }
        if ($setupDevOps) { $selectedPlatforms += "Azure DevOps" }
        Write-Host "SUCCESS: Selected: $($selectedPlatforms -join ' and ')" -ForegroundColor Green
    }
    Write-Host ""
    
    # GitHub-specific configuration with detected defaults
    $githubOwner = ""
    $githubRepo = ""
    if ($setupGitHub) {
        Write-Host "GITHUB CONFIGURATION" -ForegroundColor Green -BackgroundColor Black
        Write-Host "===============================================================" -ForegroundColor Green
        Write-Host ""
        
        $defaultGitHubOwner = if ($gitInfo.Platform -eq "GitHub" -and $gitInfo.Owner) { $gitInfo.Owner } else { "myuser" }
        $defaultGitHubRepo = if ($gitInfo.Platform -eq "GitHub" -and $gitInfo.RepoName) { $gitInfo.RepoName } else { "myrepo" }
        
        Write-Host "Repository Details:" -ForegroundColor Yellow
        $githubOwner = Get-UserInput -Prompt "   Username/Organization" -DefaultValue $defaultGitHubOwner -Required
        $githubRepo = Get-UserInput -Prompt "   Repository name" -DefaultValue $defaultGitHubRepo -Required
        
        Write-Host ""
        Write-Host "SUCCESS: Will create: " -NoNewline -ForegroundColor Green
        Write-Host ".github/workflows/build-and-release.yml" -ForegroundColor Cyan
        Write-Host ""
    }
    
    # Azure DevOps configuration with detected defaults
    $devOpsOrg = ""
    $devOpsProject = ""
    $devOpsRepo = ""
    if ($setupDevOps) {
        Write-Host "AZURE DEVOPS CONFIGURATION" -ForegroundColor Blue -BackgroundColor Black
        Write-Host "===============================================================" -ForegroundColor Blue
        Write-Host ""
        
        $defaultDevOpsOrg = if ($gitInfo.Platform -eq "Azure DevOps" -and $gitInfo.Owner) { $gitInfo.Owner } else { "myorg" }
        $defaultDevOpsProject = if ($gitInfo.Platform -eq "Azure DevOps" -and $gitInfo.RepoName) { $gitInfo.RepoName } else { "myproject" }
        $defaultDevOpsRepo = if ($gitInfo.Platform -eq "Azure DevOps" -and $gitInfo.RepoName) { $gitInfo.RepoName } else { "myrepo" }
        
        Write-Host "Organization Details:" -ForegroundColor Yellow
        $devOpsOrg = Get-UserInput -Prompt "   Organization name" -DefaultValue $defaultDevOpsOrg -Required
        $devOpsProject = Get-UserInput -Prompt "   Project name" -DefaultValue $defaultDevOpsProject -Required  
        $devOpsRepo = Get-UserInput -Prompt "   Repository name" -DefaultValue $defaultDevOpsRepo -Required
        
        Write-Host ""
        Write-Host "SUCCESS: Will create: " -NoNewline -ForegroundColor Green
        Write-Host "azure-pipelines.yml" -ForegroundColor Cyan
        Write-Host "INFO: You'll need to create the pipeline manually in Azure DevOps after setup" -ForegroundColor DarkGray
        Write-Host ""
    }
    
    # Build configuration
    Write-Host "BUILD CONFIGURATION" -ForegroundColor DarkYellow -BackgroundColor Black
    Write-Host "===============================================================" -ForegroundColor DarkYellow
    Write-Host ""
    
    Write-Host "Runtime Versions:" -ForegroundColor Yellow
    $nodeVersion = Get-UserInput -Prompt "   Node.js version" -DefaultValue $defaultNodeVersion
    $dotnetVersion = Get-UserInput -Prompt "   .NET version" -DefaultValue $defaultDotnetVersion
    
    Write-Host ""
    Write-Host "Build Options:" -ForegroundColor Yellow
    $cleanBuild = Get-YesNoInput -Prompt "   Enable clean build by default?" -DefaultValue $true
    
    Write-Host ""
    
    # Create solution.yaml configuration
    Write-Header "Generating Configuration"
    
    $yamlContent = @"
# PCF Solution Build Configuration
# This file defines the configuration for building and packaging PCF controls into Power Platform solutions

# Solution Information
solution:
  name: "$solutionName"
  displayName: "$displayName"
  description: "$description"
  version: "$version"

# Publisher Information
publisher:
  name: "$publisherName"
  displayName: "$publisherDisplayName"
  prefix: "$publisherPrefix"
  description: "$publisherDescription"

# Build Configuration
build:
  # Node.js version to use
  nodeVersion: "$nodeVersion"
  
  # .NET version for Power Platform CLI
  dotnetVersion: "$dotnetVersion"
  
  # Build configuration (Release or Debug)
  configuration: "Release"
  
  # Whether to run npm ci (clean install) vs npm install
  cleanInstall: $($cleanBuild.ToString().ToLower())
  
  # Output directory for build artifacts
  outputDirectory: "out"

# Package Configuration
package:
  # Whether to create a managed solution package
  createManaged: true
  
  # Whether to create an unmanaged solution package
  createUnmanaged: true
  
  # Package naming convention
  namingConvention: "{solution.name}_{version}"
"@

    if ($setupGitHub) {
        $yamlContent += @"

# GitHub-specific configuration
github:
  # Repository information
  owner: "$githubOwner"
  repository: "$githubRepo"
  
  # Release configuration
  releases:
    # Whether to create GitHub releases automatically
    createReleases: true
    
    # Release naming pattern
    namePattern: "v{version}"
    
    # Whether to mark releases as pre-release
    preRelease: false
    
    # Release notes configuration
    generateReleaseNotes: true
"@
    }
    
    $yamlContent += @"

# Environment Variables (can be overridden)
environment:
  SOLUTION_NAME: "$solutionName"
  PUBLISHER_NAME: "$publisherName"
  PUBLISHER_PREFIX: "$publisherPrefix"
  BUILD_CONFIGURATION: "Release"

# Custom Scripts (optional)
scripts:
  # Pre-build script (PowerShell)
  preBuild: "Write-Host 'Starting pre-build validation for $displayName...'"
  
  # Post-build script (PowerShell)
  postBuild: "Write-Host 'Running post-build validation...'"
  
  # Pre-package script (PowerShell)
  prePackage: "Write-Host 'Preparing $displayName package...'"
  
  # Post-package script (PowerShell)
  postPackage: "Write-Host '$displayName package created successfully!'"

# Logging Configuration
logging:
  # Log level (Verbose, Info, Warning, Error)
  level: "Info"
  
  # Whether to show timestamps
  showTimestamps: true
  
  # Whether to use colors in output
  useColors: true
"@

    # Write solution.yaml
    $solutionYamlPath = Join-Path $ProjectPath "solution.yaml"
    $yamlContent | Set-Content -Path $solutionYamlPath -Encoding UTF8
    Write-Success "Created solution.yaml configuration"
    
    # Add boom script to package.json
    Write-Host ""
    Write-Host "ADDING NPM SCRIPT" -ForegroundColor DarkCyan -BackgroundColor Black
    Write-Host "===============================================================" -ForegroundColor DarkCyan
    Write-Host ""
    
    # First, try to remove any existing BOM from package.json
    $packageJsonPath = Join-Path $ProjectPath "package.json"
    if (Test-Path $packageJsonPath) {
        $bomRemoved = Remove-BomFromFile -FilePath $packageJsonPath
        if ($bomRemoved) {
            Write-Info "Removed BOM from existing package.json"
        }
    }
    
    $boomScriptAdded = Add-BoomScriptToPackageJson -ProjectPath $ProjectPath -SolutionName $solutionName
    
    # If the normal function failed (possibly due to BOM issues), try recreating from scratch
    if (-not $boomScriptAdded) {
        Write-Info "Standard update failed, attempting to recreate package.json from scratch..."
        $boomScriptAdded = New-PackageJsonFromScratch -ProjectPath $ProjectPath -SolutionName $solutionName
    }
    
    if ($boomScriptAdded) {
        Write-Host "SUCCESS: " -NoNewline -ForegroundColor Green
        Write-Host "Added 'boom' script for quick building!" -ForegroundColor Green
        Write-Host "   -> Run: " -NoNewline -ForegroundColor DarkGray
        Write-Host "npm run boom" -ForegroundColor Cyan
        Write-Host "   -> This will build and package your solution in Release mode" -ForegroundColor DarkGray
    }
    
    # Copy BuildDataversePCFSolution scripts
    Write-Host ""
    Write-Host "COPYING BUILDDATAVERSEPCFSOLUTION SCRIPTS" -ForegroundColor DarkCyan -BackgroundColor Black
    Write-Host "===============================================================" -ForegroundColor DarkCyan
    Write-Host ""
    
    $buildDir = Join-Path $ProjectPath "BuildDataversePCFSolution"
    if (-not (Test-Path $buildDir)) {
        New-Item -Path $buildDir -ItemType Directory -Force | Out-Null
    }
    
    # Copy all BuildDataversePCFSolution scripts
    $scriptsToCopy = @(
        "build-solution.ps1",
        "environment-check.ps1", 
        "create-pcf-project.ps1",
        "install.ps1"
    )
    
    $copiedScripts = 0
    foreach ($scriptName in $scriptsToCopy) {
        $scriptSource = Join-Path $PSScriptRoot $scriptName
        $scriptDest = Join-Path $buildDir $scriptName
        
        if (Test-Path $scriptSource) {
            # Only copy if source and destination are different
            if ($scriptSource -ne $scriptDest) {
                Copy-Item $scriptSource $scriptDest -Force
                Write-Success "Copied $scriptName to project"
                $copiedScripts++
            } else {
                Write-Info "$scriptName already in correct location"
            }
        } else {
            Write-Warning "Could not find $scriptName in BuildDataversePCFSolution directory"
        }
    }
    
    if ($copiedScripts -gt 0) {
        Write-Host ""
        Write-Host "SUCCESS: " -NoNewline -ForegroundColor Green
        Write-Host "Copied $copiedScripts BuildDataversePCFSolution scripts!" -ForegroundColor Green
        Write-Host "   -> Available commands:" -ForegroundColor DarkGray
        Write-Host "      npm run boom-check - Check development environment" -ForegroundColor Cyan
        Write-Host "      npm run boom-create - Create new PCF project" -ForegroundColor Cyan
        Write-Host "      npm run boom - Quick Release build" -ForegroundColor Cyan
    }
    
    # Set up CI/CD files based on selection
    if ($setupGitHub) {
        # Create GitHub Actions workflow
        $githubDir = Join-Path $ProjectPath ".github\workflows"
        if (-not (Test-Path $githubDir)) {
            New-Item -Path $githubDir -ItemType Directory -Force | Out-Null
        }
        
        $workflowSource = Join-Path $PSScriptRoot "templates\github\build-and-release.yml"
        $workflowDest = Join-Path $githubDir "build-and-release.yml"
        
        if (Test-Path $workflowSource) {
            # Read and customize the workflow template
            $workflowContent = Get-Content $workflowSource -Raw
            $workflowContent = $workflowContent -replace '{{SOLUTION_NAME}}', $solutionName
            $workflowContent = $workflowContent -replace '{{NODE_VERSION}}', $nodeVersion
            $workflowContent = $workflowContent -replace '{{DOTNET_VERSION}}', $dotnetVersion
            
            $workflowContent | Set-Content -Path $workflowDest -Encoding UTF8
            Write-Success "Created GitHub Actions workflow"
        } else {
            Write-Warning "Could not find GitHub Actions template"
        }
        
        # Copy GitHub Actions README
        $githubReadmeSource = Join-Path $PSScriptRoot "templates\github\README.md"
        $githubReadmeDest = Join-Path $ProjectPath ".github\README.md"
        if (Test-Path $githubReadmeSource) {
            Copy-Item $githubReadmeSource $githubReadmeDest -Force
            Write-Success "Created GitHub Actions documentation"
        }
    }
    
    if ($setupDevOps) {
        # Create Azure DevOps pipeline
        $pipelineSource = Join-Path $PSScriptRoot "templates\devops\azure-pipelines.yml"
        $pipelineDest = Join-Path $ProjectPath "azure-pipelines.yml"
        
        if (Test-Path $pipelineSource) {
            # Read and customize the pipeline template
            $pipelineContent = Get-Content $pipelineSource -Raw
            $pipelineContent = $pipelineContent -replace '{{SOLUTION_NAME}}', $solutionName
            $pipelineContent = $pipelineContent -replace '{{NODE_VERSION}}', $nodeVersion
            $pipelineContent = $pipelineContent -replace '{{DOTNET_VERSION}}', $dotnetVersion
            
            $pipelineContent | Set-Content -Path $pipelineDest -Encoding UTF8
            Write-Success "Created Azure DevOps pipeline"
        } else {
            Write-Warning "Could not find Azure DevOps pipeline template"
        }
    }
    
    # Copy documentation files
    $docFiles = @(
        @{ Source = "GETTING-STARTED.md"; Dest = "BuildDataversePCFSolution\GETTING-STARTED.md" },
        @{ Source = "TROUBLESHOOTING.md"; Dest = "BuildDataversePCFSolution\TROUBLESHOOTING.md" },
        @{ Source = "README.md"; Dest = "BuildDataversePCFSolution\README.md" }
    )
    
    foreach ($docFile in $docFiles) {
        $sourceFile = Join-Path $PSScriptRoot $docFile.Source
        $destFile = Join-Path $ProjectPath $docFile.Dest
        
        if (Test-Path $sourceFile) {
            # Only copy if source and destination are different
            if ($sourceFile -ne $destFile) {
                Copy-Item $sourceFile $destFile -Force
                Write-Success "Copied $($docFile.Source)"
            } else {
                Write-Info "$($docFile.Source) already in correct location"
            }
        } else {
            Write-Info "Documentation file $($docFile.Source) not found (will be created later)"
        }
    }
    
    # Final summary
    Write-Host ""
    Write-Host "SETUP COMPLETE!" -ForegroundColor Green -BackgroundColor Black
    Write-Host "===============================================================" -ForegroundColor Green
    Write-Host ""
    
    Write-Success "BuildDataverseSolution system configured successfully!"
    
    Write-Host ""
    Write-Host "FILES CREATED:" -ForegroundColor Yellow
    Write-Host "   -> solution.yaml configuration file" -ForegroundColor White
    Write-Host "   -> BuildDataversePCFSolution/build-solution.ps1 build engine" -ForegroundColor White
    Write-Host "   -> BuildDataversePCFSolution/environment-check.ps1 environment validator" -ForegroundColor White
    Write-Host "   -> BuildDataversePCFSolution/create-pcf-project.ps1 project creator" -ForegroundColor White
    Write-Host "   -> BuildDataversePCFSolution/install.ps1 system installer" -ForegroundColor White
    Write-Host "   -> BuildDataversePCFSolution/ documentation and guides" -ForegroundColor White
    Write-Host "   -> package.json updated with BuildDataversePCFSolution scripts" -ForegroundColor White
    
    if ($setupGitHub) {
        Write-Host "   -> .github/workflows/build-and-release.yml GitHub Actions" -ForegroundColor White
        Write-Host "   -> .github/README.md GitHub documentation" -ForegroundColor White
    }
    
    if ($setupDevOps) {
        Write-Host "   -> azure-pipelines.yml Azure DevOps pipeline" -ForegroundColor White
    }
    
    if (-not $setupGitHub -and -not $setupDevOps) {
        Write-Host "   -> Local build system only (no CI/CD configured)" -ForegroundColor White
        Write-Success "Build system ready for local development!"
    }
    
    Write-Host ""
    Write-Host "NEXT STEPS" -ForegroundColor Cyan -BackgroundColor Black
    Write-Host "===============================================================" -ForegroundColor Cyan
    Write-Host ""
    
    Write-Host "1. " -NoNewline -ForegroundColor Yellow
    Write-Host "Check your development environment:" -ForegroundColor Yellow
    Write-Host "   Environment check: " -NoNewline -ForegroundColor DarkGray
    Write-Host "npm run boom-check" -ForegroundColor Cyan
    Write-Host "   -> Validates Node.js, .NET, PAC CLI, Git installations" -ForegroundColor DarkGray
    Write-Host "   -> Automatically installs missing dependencies (Windows)" -ForegroundColor DarkGray
    
    Write-Host ""
    Write-Host "2. " -NoNewline -ForegroundColor Yellow
    Write-Host "Test build locally (ALWAYS do this!):" -ForegroundColor Yellow
    Write-Host "   Quick Release build: " -NoNewline -ForegroundColor DarkGray
    Write-Host "npm run boom" -ForegroundColor Cyan
    Write-Host "   Quick Debug build: " -NoNewline -ForegroundColor DarkGray
    Write-Host "npm run boom-debug" -ForegroundColor Cyan
    Write-Host "   Managed solution only: " -NoNewline -ForegroundColor DarkGray
    Write-Host "npm run boom-managed" -ForegroundColor Cyan
    Write-Host "   Unmanaged solution only: " -NoNewline -ForegroundColor DarkGray
    Write-Host "npm run boom-unmanaged" -ForegroundColor Cyan
    Write-Host "   -> Creates versioned ZIP files in " -NoNewline -ForegroundColor DarkGray
    Write-Host "releases/" -NoNewline -ForegroundColor Cyan
    Write-Host " directory" -ForegroundColor DarkGray
    
    Write-Host ""
    Write-Host "3. " -NoNewline -ForegroundColor Yellow
    Write-Host "Create additional PCF projects:" -ForegroundColor Yellow
    Write-Host "   Project creator: " -NoNewline -ForegroundColor DarkGray
    Write-Host "npm run boom-create" -ForegroundColor Cyan
    Write-Host "   -> Interactive PCF project creation with templates" -ForegroundColor DarkGray
    Write-Host "   -> Automatic BuildDataversePCFSolution integration" -ForegroundColor DarkGray
    
    if ($setupGitHub) {
        Write-Host ""
        Write-Host "4. " -NoNewline -ForegroundColor Yellow
        Write-Host "GitHub Actions workflow:" -ForegroundColor Yellow
        Write-Host "   -> Commit and push: " -NoNewline -ForegroundColor DarkGray
        Write-Host "git add . && git commit -m `"Add BuildDataversePCFSolution`" && git push" -ForegroundColor White
        Write-Host "   -> Check Actions tab in GitHub to see build progress" -ForegroundColor DarkGray
        Write-Host "   -> Create release: " -NoNewline -ForegroundColor DarkGray
        Write-Host "git tag v1.0.0 && git push origin v1.0.0" -ForegroundColor White
        Write-Host "   -> GitHub will automatically create release with solution packages" -ForegroundColor DarkGray
    }
    
    if ($setupDevOps) {
        Write-Host ""
        Write-Host "4. " -NoNewline -ForegroundColor Yellow
        Write-Host "Azure DevOps setup:" -ForegroundColor Yellow
        Write-Host "   -> Go to Azure DevOps -> Pipelines -> New Pipeline" -ForegroundColor DarkGray
        Write-Host "   -> Choose your repo -> Existing Azure Pipelines YAML -> /azure-pipelines.yml" -ForegroundColor DarkGray
        Write-Host "   -> Save and run to test the pipeline" -ForegroundColor DarkGray
    }
    
    Write-Host ""
    Write-Host "5. " -NoNewline -ForegroundColor Yellow
    Write-Host "Configuration and advanced usage:" -ForegroundColor Yellow
    Write-Host "   -> Edit " -NoNewline -ForegroundColor DarkGray
    Write-Host "solution.yaml" -NoNewline -ForegroundColor Cyan
    Write-Host " to customize build behavior" -ForegroundColor DarkGray
    Write-Host "   -> See " -NoNewline -ForegroundColor DarkGray
    Write-Host "BuildDataversePCFSolution/GETTING-STARTED.md" -NoNewline -ForegroundColor Cyan
    Write-Host " for detailed documentation" -ForegroundColor DarkGray
    Write-Host "   -> Use " -NoNewline -ForegroundColor DarkGray
    Write-Host "BuildDataversePCFSolution/TROUBLESHOOTING.md" -NoNewline -ForegroundColor Cyan
    Write-Host " for common issues" -ForegroundColor DarkGray
    
    Write-Host ""
    Write-Host "SUCCESS: " -NoNewline -ForegroundColor Green
    Write-Host "BuildDataversePCFSolution system ready! Your comprehensive PCF development environment is configured." -ForegroundColor Green
    Write-Host ""
    Write-Host "[*] " -NoNewline -ForegroundColor Yellow
    Write-Host "Features available: Environment checking, automated builds, project creation, CI/CD integration" -ForegroundColor Yellow
    Write-Host ""
    
    return 0
}
catch {
    Write-Error "Setup failed: $($_.Exception.Message)"
    Write-Error "Stack trace: $($_.ScriptStackTrace)"
    return 1
}
