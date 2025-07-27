# PCF Project Creation Script for BuildDataversePCFSolution
# This script creates a new PCF control project with all necessary setup

param(
    [string]$ProjectPath = ".",
    [string]$Namespace = "",
    [string]$ControlName = "",
    [string]$Template = "field",
    [switch]$NonInteractive,
    [switch]$SkipEnvironmentCheck
)

# Set error action preference
$ErrorActionPreference = "Stop"

# Color output functions
function Write-Header { param($Message) Write-Host "`n=== $Message ===" -ForegroundColor Magenta }
function Write-Info { param($Message) Write-Host "INFO: $Message" -ForegroundColor Cyan }
function Write-Success { param($Message) Write-Host "✅ SUCCESS: $Message" -ForegroundColor Green }
function Write-Warning { param($Message) Write-Host "⚠️  WARNING: $Message" -ForegroundColor Yellow }
function Write-Error { param($Message) Write-Host "❌ ERROR: $Message" -ForegroundColor Red }

# Function to prompt for input with default value
function Get-UserInput {
    param(
        [string]$Prompt,
        [string]$DefaultValue = "",
        [switch]$Required,
        [string[]]$ValidValues = @()
    )
    
    if ($NonInteractive) {
        if ($DefaultValue) {
            return $DefaultValue
        } elseif ($Required) {
            throw "Required parameter missing in non-interactive mode: $Prompt"
        } else {
            return ""
        }
    }
    
    $promptText = $Prompt
    if (-not [string]::IsNullOrEmpty($DefaultValue)) {
        $promptText += " (default: $DefaultValue)"
    }
    if ($Required) {
        $promptText += " *"
    }
    if ($ValidValues.Count -gt 0) {
        $promptText += " [" + ($ValidValues -join "/") + "]"
    }
    $promptText += ": "
    
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
        
        $userInput = $userInput.Trim()
        
        if ($ValidValues.Count -gt 0 -and $userInput -notin $ValidValues) {
            Write-Host "   WARNING: Please enter one of: $($ValidValues -join ', ')" -ForegroundColor Red
            continue
        }
        
        return $userInput
    } while ($Required -or $ValidValues.Count -gt 0)
}

# Function to validate project name
function Test-ProjectName {
    param([string]$Name)
    
    if ([string]::IsNullOrWhiteSpace($Name)) {
        return $false, "Project name cannot be empty"
    }
    
    if ($Name -match '[^a-zA-Z0-9_]') {
        return $false, "Project name can only contain letters, numbers, and underscores"
    }
    
    if ($Name -match '^\d') {
        return $false, "Project name cannot start with a number"
    }
    
    if ($Name.Length -lt 3) {
        return $false, "Project name must be at least 3 characters long"
    }
    
    if ($Name.Length -gt 50) {
        return $false, "Project name must be 50 characters or less"
    }
    
    return $true, "Valid"
}

# Function to create directory structure
function New-ProjectDirectory {
    param([string]$Path, [string]$Name)
    
    $fullPath = Join-Path $Path $Name
    
    if (Test-Path $fullPath) {
        $overwrite = Get-UserInput -Prompt "Directory '$Name' already exists. Overwrite?" -ValidValues @("y", "n") -DefaultValue "n"
        if ($overwrite -eq "n") {
            throw "Project creation cancelled"
        }
        Remove-Item $fullPath -Recurse -Force
    }
    
    New-Item -Path $fullPath -ItemType Directory -Force | Out-Null
    return $fullPath
}

# Function to run environment check
function Invoke-EnvironmentCheck {
    $envCheckScript = Join-Path $PSScriptRoot "environment-check.ps1"
    
    if (Test-Path $envCheckScript) {
        Write-Info "Running environment check..."
        $result = & $envCheckScript -CheckOnly
        return $LASTEXITCODE -eq 0
    } else {
        Write-Warning "Environment check script not found. Proceeding without verification."
        return $true
    }
}

# Function to create PCF control
function New-PCFControl {
    param(
        [string]$ProjectPath,
        [string]$Namespace,
        [string]$ControlName,
        [string]$Template
    )
    
    Write-Info "Creating PCF control..."
    Write-Info "Path: $ProjectPath"
    Write-Info "Namespace: $Namespace"
    Write-Info "Control Name: $ControlName"
    Write-Info "Template: $Template"
    
    # Change to project directory
    Push-Location $ProjectPath
    
    try {
        # Create PCF control
        $pacInitArgs = @(
            "pcf", "init",
            "--namespace", $Namespace,
            "--name", $ControlName,
            "--template", $Template
        )
        
        Write-Info "Running: pac $($pacInitArgs -join ' ')"
        & pac @pacInitArgs
        
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to create PCF control"
        }
        
        Write-Success "PCF control created successfully"
        
        # Install npm dependencies
        Write-Info "Installing npm dependencies..."
        npm install
        
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to install npm dependencies"
        }
        
        Write-Success "Dependencies installed successfully"
        
        # Install additional recommended packages
        Write-Info "Installing additional PCF development packages..."
        
        $additionalPackages = @(
            "@types/react@^18.0.0",
            "@types/react-dom@^18.0.0",
            "@fluentui/react@^8.110.0",
            "@microsoft/sp-office-ui-fabric-core@^1.16.0"
        )
        
        foreach ($package in $additionalPackages) {
            Write-Info "Installing $package..."
            npm install $package --save-dev
        }
        
        Write-Success "Additional packages installed"
        
        return $true
    }
    catch {
        Write-Error "Error creating PCF control: $($_.Exception.Message)"
        return $false
    }
    finally {
        Pop-Location
    }
}

# Function to install BuildDataversePCFSolution
function Install-BuildDataversePCFSolution {
    param([string]$ProjectPath)
    
    Write-Info "Installing BuildDataversePCFSolution build system..."
    
    $installScript = Join-Path $PSScriptRoot "install.ps1"
    
    if (Test-Path $installScript) {
        Push-Location $ProjectPath
        try {
            & $installScript -ProjectPath $ProjectPath
            return $LASTEXITCODE -eq 0
        }
        finally {
            Pop-Location
        }
    } else {
        Write-Warning "BuildDataversePCFSolution installer not found at: $installScript"
        Write-Info "You can install it manually later by running the installer from the project directory"
        return $false
    }
}

# Function to update package.json with additional scripts
function Update-PackageJson {
    param([string]$ProjectPath)
    
    $packageJsonPath = Join-Path $ProjectPath "package.json"
    
    if (-not (Test-Path $packageJsonPath)) {
        Write-Warning "package.json not found at: $packageJsonPath"
        return
    }
    
    try {
        $packageJson = Get-Content $packageJsonPath | ConvertFrom-Json
        
        # Add our custom scripts
        if (-not $packageJson.scripts) {
            $packageJson.scripts = @{}
        }
        
        # Convert to hashtable for easier manipulation
        $scripts = @{}
        $packageJson.scripts.PSObject.Properties | ForEach-Object {
            $scripts[$_.Name] = $_.Value
        }
        
        # Add BuildDataversePCFSolution scripts
        $scripts["boom"] = "powershell -File BuildDataversePCFSolution/build-solution.ps1"
        $scripts["boomcheck"] = "powershell -File BuildDataversePCFSolution/environment-check.ps1"
        $scripts["create-pcf"] = "powershell -File BuildDataversePCFSolution/create-pcf-project.ps1"
        $scripts["build-managed"] = "powershell -File BuildDataversePCFSolution/build-solution.ps1 -SolutionType Managed"
        $scripts["build-unmanaged"] = "powershell -File BuildDataversePCFSolution/build-solution.ps1 -SolutionType Unmanaged"
        $scripts["build-debug"] = "powershell -File BuildDataversePCFSolution/build-solution.ps1 -BuildConfiguration Debug"
        
        # Convert back to object
        $packageJson.scripts = [PSCustomObject]$scripts
        
        # Save updated package.json
        $packageJson | ConvertTo-Json -Depth 10 | Set-Content $packageJsonPath -Encoding UTF8
        
        Write-Success "Updated package.json with BuildDataversePCFSolution scripts"
    }
    catch {
        Write-Warning "Failed to update package.json: $($_.Exception.Message)"
    }
}

# Function to create README.md for the project
function New-ProjectReadme {
    param(
        [string]$ProjectPath,
        [string]$ControlName,
        [string]$Namespace,
        [string]$Template
    )
    
    $readmePath = Join-Path $ProjectPath "README.md"
    
    $readmeContent = @"
# $ControlName PCF Control

A Power Apps Component Framework (PCF) control built with BuildDataversePCFSolution.

## Overview

- **Control Name**: $ControlName
- **Namespace**: $Namespace
- **Template**: $Template
- **Created**: $(Get-Date -Format "yyyy-MM-dd")

## Development

This project uses BuildDataversePCFSolution for streamlined development and deployment.

### Quick Start

```bash
# Check environment and dependencies
npm run boomcheck

# Build the solution (both managed and unmanaged)
npm run boom

# Build specific types
npm run build-managed    # Managed solution only
npm run build-unmanaged  # Unmanaged solution only
npm run build-debug      # Debug build
```

### Available Scripts

- `npm run boom` - Build complete solution packages
- `npm run boomcheck` - Check development environment
- `npm run build` - Standard PCF build
- `npm run start` - Start PCF test harness
- `npm run build-managed` - Build managed solution
- `npm run build-unmanaged` - Build unmanaged solution
- `npm run build-debug` - Build in debug mode

### Project Structure

```
$ControlName/
├── $ControlName/           # PCF control source
│   ├── index.ts           # Main control logic
│   ├── ControlManifest.Input.xml
│   └── css/               # Stylesheets
├── BuildDataversePCFSolution/  # Build system
│   ├── build-solution.ps1
│   ├── environment-check.ps1
│   └── setup-project.ps1
├── releases/              # Generated solution packages
├── solution.yaml          # Build configuration
└── package.json
```

### Configuration

Edit `solution.yaml` to customize:
- Solution metadata (name, version, description)
- Publisher information
- Build settings
- Custom scripts and validation rules

### Dependencies

This project includes:
- React and TypeScript types
- FluentUI React components
- Microsoft Office UI Fabric
- Power Apps Component Framework SDK

### Deployment

Solution packages are automatically created in the `releases/` directory:
- `{ControlName}_v{version}_managed.zip` - For production deployment
- `{ControlName}_v{version}_unmanaged.zip` - For development/customization

Import these files into your Power Platform environment.

## Documentation

- [BuildDataversePCFSolution Documentation](./BuildDataversePCFSolution/README.md)
- [PCF Documentation](https://docs.microsoft.com/powerapps/developer/component-framework/)
- [FluentUI React](https://developer.microsoft.com/fluentui#/controls/web)

## Support

For issues with the build system, visit the [BuildDataversePCFSolution repository](https://github.com/garethcheyne/BuildDataversePCFSolution).

---

*Generated by BuildDataversePCFSolution*
"@

    Set-Content -Path $readmePath -Value $readmeContent -Encoding UTF8
    Write-Success "Created project README.md"
}

# Main execution
try {
    Write-Header "BuildDataversePCFSolution PCF Project Creator"
    
    # Environment check (unless skipped)
    if (-not $SkipEnvironmentCheck) {
        Write-Info "Checking development environment..."
        $envReady = Invoke-EnvironmentCheck
        
        if (-not $envReady) {
            Write-Warning "Environment check failed. Some prerequisites may be missing."
            $continue = Get-UserInput -Prompt "Continue anyway?" -ValidValues @("y", "n") -DefaultValue "n"
            if ($continue -eq "n") {
                Write-Info "Project creation cancelled. Run 'npm run boomcheck' to fix environment issues."
                exit 1
            }
        } else {
            Write-Success "Environment is ready for PCF development"
        }
    }
    
    # Get project information
    Write-Header "Project Configuration"
    
    # Project name/namespace
    if ([string]::IsNullOrWhiteSpace($Namespace)) {
        do {
            $Namespace = Get-UserInput -Prompt "Namespace (e.g., 'MyCompany')" -Required
            $isValid, $message = Test-ProjectName -Name $Namespace
            if (-not $isValid) {
                Write-Warning $message
                $Namespace = ""
            }
        } while ([string]::IsNullOrWhiteSpace($Namespace))
    }
    
    # Control name
    if ([string]::IsNullOrWhiteSpace($ControlName)) {
        do {
            $ControlName = Get-UserInput -Prompt "Control name (e.g., 'MyAwesomeControl')" -Required
            $isValid, $message = Test-ProjectName -Name $ControlName
            if (-not $isValid) {
                Write-Warning $message
                $ControlName = ""
            }
        } while ([string]::IsNullOrWhiteSpace($ControlName))
    }
    
    # Template selection
    if ([string]::IsNullOrWhiteSpace($Template)) {
        Write-Host ""
        Write-Host "TEMPLATE OPTIONS:" -ForegroundColor Yellow
        Write-Host "  field    - Field component (most common)" -ForegroundColor DarkGray
        Write-Host "  dataset  - Dataset component (grids, lists)" -ForegroundColor DarkGray
        Write-Host ""
        
        $Template = Get-UserInput -Prompt "Template type" -DefaultValue "field" -ValidValues @("field", "dataset")
    }
    
    # Project directory
    $projectName = "$Namespace$ControlName"
    Write-Info "Creating project: $projectName"
    
    # Create project directory
    $fullProjectPath = New-ProjectDirectory -Path $ProjectPath -Name $projectName
    Write-Success "Created project directory: $fullProjectPath"
    
    # Create PCF control
    $pcfSuccess = New-PCFControl -ProjectPath $fullProjectPath -Namespace $Namespace -ControlName $ControlName -Template $Template
    
    if (-not $pcfSuccess) {
        throw "Failed to create PCF control"
    }
    
    # Install BuildDataversePCFSolution
    Write-Header "Installing Build System"
    $buildSystemInstalled = Install-BuildDataversePCFSolution -ProjectPath $fullProjectPath
    
    if ($buildSystemInstalled) {
        Write-Success "BuildDataversePCFSolution installed successfully"
    } else {
        Write-Warning "BuildDataversePCFSolution installation failed, but PCF control was created"
    }
    
    # Update package.json with our scripts
    Update-PackageJson -ProjectPath $fullProjectPath
    
    # Create project README
    New-ProjectReadme -ProjectPath $fullProjectPath -ControlName $ControlName -Namespace $Namespace -Template $Template
    
    # Final summary
    Write-Header "Project Created Successfully!"
    
    Write-Host ""
    Write-Host "PROJECT SUMMARY" -ForegroundColor Green -BackgroundColor Black
    Write-Host "================================================================" -ForegroundColor Green
    Write-Host "  Project Name: " -NoNewline -ForegroundColor White
    Write-Host $projectName -ForegroundColor Cyan
    Write-Host "  Location: " -NoNewline -ForegroundColor White
    Write-Host $fullProjectPath -ForegroundColor Cyan
    Write-Host "  Namespace: " -NoNewline -ForegroundColor White
    Write-Host $Namespace -ForegroundColor Cyan
    Write-Host "  Control Name: " -NoNewline -ForegroundColor White
    Write-Host $ControlName -ForegroundColor Cyan
    Write-Host "  Template: " -NoNewline -ForegroundColor White
    Write-Host $Template -ForegroundColor Cyan
    Write-Host ""
    
    Write-Host "NEXT STEPS" -ForegroundColor Yellow -BackgroundColor Black
    Write-Host "================================================================" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "1. " -NoNewline -ForegroundColor Yellow
    Write-Host "Navigate to your project:" -ForegroundColor Yellow
    Write-Host "   cd `"$fullProjectPath`"" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "2. " -NoNewline -ForegroundColor Yellow
    Write-Host "Start developing:" -ForegroundColor Yellow
    Write-Host "   code .                    # Open in VS Code" -ForegroundColor DarkGray
    Write-Host "   npm start                 # Start test harness" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "3. " -NoNewline -ForegroundColor Yellow
    Write-Host "Build and package:" -ForegroundColor Yellow
    Write-Host "   npm run boom              # Build solution packages" -ForegroundColor Cyan
    Write-Host "   npm run build-debug       # Debug build" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "4. " -NoNewline -ForegroundColor Yellow
    Write-Host "Check environment anytime:" -ForegroundColor Yellow
    Write-Host "   npm run boomcheck         # Verify dependencies" -ForegroundColor Cyan
    Write-Host ""
    
    Write-Success "Your PCF project is ready for development!"
    Write-Info "Documentation available in: README.md"
    
    if ($buildSystemInstalled) {
        Write-Info "Build system documentation: BuildDataversePCFSolution/README.md"
    }
    
    exit 0
}
catch {
    Write-Error "Project creation failed: $($_.Exception.Message)"
    Write-Error "Stack trace: $($_.ScriptStackTrace)"
    exit 1
}
