# CI/CD Setup Guide for PCF BuildDataverseSolution

This guide explains how to set up the BuildDataverseSolution system for both GitHub Actions and Azure DevOps pipelines.

## Overview

The BuildDataverseSolution system supports multiple CI/CD platforms:

- **GitHub Actions** - Fully supported with automatic release creation
- **Azure DevOps** - Fully supported with build and artifact publishing
- **Local Development** - Full support for local testing and development

## Platform-Specific Features

### GitHub Actions
- ✅ Automatic environment detection
- ✅ Proper GitHub Actions logging format
- ✅ Automatic release creation on version tags
- ✅ Security scanning with Trivy
- ✅ Artifact retention policies

### Azure DevOps
- ✅ Automatic environment detection
- ✅ Azure DevOps logging format
- ✅ Build artifact publishing
- ✅ Multi-stage pipeline support
- ✅ Security scanning integration
- ⚠️ GitHub release creation requires additional setup

### Local Development
- ✅ Colored console output
- ✅ Full build and packaging functionality
- ✅ YAML configuration validation
- ✅ Custom script execution

## Quick Start

### For GitHub Actions

1. **Copy BuildDataverseSolution to your project:**
   ```bash
   # Copy the entire BuildDataverseSolution directory to your PCF project root
   cp -r BuildDataverseSolution /path/to/your/pcf/project/
   ```

2. **Create solution.yaml configuration:**
   ```bash
   # Copy and customize the solution.yaml template
   cp BuildDataverseSolution/solution-template.yaml solution.yaml
   # Edit solution.yaml with your project details
   ```

3. **Copy GitHub workflow:**
   ```bash
   # Copy the workflow file to your .github/workflows directory
   mkdir -p .github/workflows
   cp .github/workflows/build-and-release.yml /path/to/your/project/.github/workflows/
   ```

4. **Commit and push:**
   ```bash
   git add .
   git commit -m "Add BuildDataverseSolution CI/CD system"
   git push
   ```

### For Azure DevOps

1. **Copy BuildDataverseSolution to your project:**
   ```bash
   # Copy the entire BuildDataverseSolution directory to your PCF project root
   cp -r BuildDataverseSolution /path/to/your/pcf/project/
   ```

2. **Create solution.yaml configuration:**
   ```bash
   # Copy and customize the solution.yaml template
   cp BuildDataverseSolution/solution-template.yaml solution.yaml
   # Edit solution.yaml with your project details
   ```

3. **Copy Azure DevOps pipeline:**
   ```bash
   # Copy the pipeline file to your project root
   cp azure-pipelines.yml /path/to/your/project/
   ```

4. **Set up Azure DevOps project:**
   - Create a new pipeline in Azure DevOps
   - Connect to your repository
   - Select "Existing Azure Pipelines YAML file"
   - Choose `/azure-pipelines.yml`

5. **Configure GitHub release (optional):**
   - Install GitHub CLI in your Azure DevOps environment
   - Set up GitHub authentication
   - Uncomment the GitHub release creation commands in the pipeline

## Configuration

### solution.yaml Structure

The `solution.yaml` file controls all aspects of the build process:

```yaml
# Solution Information
solution:
  name: "YourSolutionName"
  displayName: "Your Solution Display Name"
  description: "Description of your PCF control"
  version: "1.0.0.0"

# Publisher Information
publisher:
  name: "YourName"
  displayName: "Your Display Name"
  prefix: "prefix"
  description: "Your publisher description"

# Project Configuration
project:
  pcfProjectPath: "./YourProject.pcfproj"
  pcfRootPath: "./"
  buildOutputPath: "./out"
  packageJsonPath: "./package.json"

# Build Configuration
build:
  cleanBuild: true
  nodeVersion: "18"
  dotnetVersion: "6.0.x"
  npmCommand: "ci"
  pcfBuildCommand: "build"

# ... additional configuration sections
```

### Platform-Specific Variables

#### GitHub Actions
The system automatically detects GitHub Actions environment and uses:
- `GITHUB_ACTIONS=true` for detection
- GitHub Actions logging format (`::notice::`, `::error::`, etc.)
- Automatic artifact upload and retention
- Tag-based release creation

#### Azure DevOps
The system automatically detects Azure DevOps environment and uses:
- `TF_BUILD=True` for detection
- Azure DevOps logging format (`##[section]`, `##[error]`, etc.)
- Build artifact publishing
- Multi-stage pipeline support

## Advanced Setup

### Custom Scripts in solution.yaml

You can add custom PowerShell scripts that run at different stages:

```yaml
scripts:
  preBuild: |
    Write-Host "Running pre-build validation..."
    # Your custom pre-build logic
  
  postBuild: |
    Write-Host "Running post-build checks..."
    # Your custom post-build logic
  
  prePackage: |
    Write-Host "Preparing package..."
    # Your custom pre-package logic
  
  postPackage: |
    Write-Host "Package created successfully!"
    # Your custom post-package logic
```

### GitHub Release Configuration

For automatic GitHub release creation, configure the `github` section in `solution.yaml`:

```yaml
github:
  repository:
    owner: "your-username"
    name: "your-repo-name"
    branch: "main"
  
  release:
    titleTemplate: "{{solution.displayName}} v{{solution.version}}"
    bodyTemplate: |
      ## {{solution.displayName}} {{solution.version}}
      
      ### 🚀 What's New
      - Your release notes here
      
      ### 💾 Installation
      1. Download the `{{solution.name}}.zip` file
      2. Import it into your Power Platform environment
```

### Azure DevOps GitHub Release Setup

To enable GitHub release creation from Azure DevOps:

1. **Install GitHub CLI in your pipeline:**
   ```yaml
   - task: PowerShell@2
     displayName: 'Install GitHub CLI'
     inputs:
       targetType: 'inline'
       script: |
         # Install GitHub CLI
         Invoke-WebRequest -Uri "https://github.com/cli/cli/releases/latest/download/gh_windows_amd64.zip" -OutFile "gh.zip"
         Expand-Archive gh.zip -DestinationPath .
         $env:PATH += ";$(Get-Location)\gh_windows_amd64"
   ```

2. **Configure GitHub authentication:**
   ```yaml
   - task: PowerShell@2
     displayName: 'Authenticate GitHub CLI'
     inputs:
       targetType: 'inline'
       script: |
         # Set GitHub token (configure as secret variable)
         $env:GITHUB_TOKEN = "$(GITHUB_TOKEN)"
         gh auth status
   ```

3. **Create release:**
   ```yaml
   - task: PowerShell@2
     displayName: 'Create GitHub Release'
     inputs:
       targetType: 'inline'
       script: |
         gh release create "$(TAG_NAME)" "$(Pipeline.Workspace)/solution-package/$(SOLUTION_NAME).zip" `
           --title "$(SOLUTION_DISPLAY_NAME) $(TAG_NAME)" `
           --notes "Release created from Azure DevOps Pipeline"
   ```

## Testing the Setup

### Local Testing

Test your configuration locally before committing:

```powershell
# Test with Debug configuration
.\BuildDataverseSolution\build-solution.ps1 -BuildConfiguration "Debug"

# Test with specific solution name
.\BuildDataverseSolution\build-solution.ps1 -SolutionName "TestSolution" -BuildConfiguration "Debug"

# Test configuration validation only
.\BuildDataverseSolution\build-solution.ps1 -ConfigFile "solution.yaml" -WhatIf
```

### Validating CI/CD Integration

1. **GitHub Actions:**
   - Push changes to trigger build
   - Check Actions tab for build results
   - Create a version tag (`v1.0.0`) to trigger release

2. **Azure DevOps:**
   - Queue a new build
   - Check build logs and artifacts
   - Verify artifact publishing

## Troubleshooting

### Common Issues

1. **PowerShell execution policy:**
   ```powershell
   Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
   ```

2. **Missing Power Platform CLI:**
   ```powershell
   dotnet tool install --global Microsoft.PowerApps.CLI.Tool
   ```

3. **Node.js version issues:**
   - Ensure Node.js 18+ is installed
   - Clear npm cache: `npm cache clean --force`

4. **Path issues in CI:**
   - Use absolute paths where possible
   - Verify working directory in scripts

**Note:** BOM (Byte Order Mark) issues with `package.json` are automatically handled by the setup script. The setup process includes built-in BOM detection and removal to ensure clean JSON files.

### Platform-Specific Issues

#### GitHub Actions
- Check runner logs for detailed error messages
- Verify artifact upload paths
- Ensure secrets are properly configured

#### Azure DevOps
- Check build logs for specific error details
- Verify agent capabilities (Node.js, .NET, PowerShell)
- Ensure service connections are properly configured

### Debug Mode

Enable verbose logging by adding `-Verbose` to the build script call:

```powershell
# Local debugging
.\BuildDataverseSolution\build-solution.ps1 -BuildConfiguration "Debug" -Verbose

# In GitHub Actions
run: .\BuildDataverseSolution\build-solution.ps1 -BuildConfiguration "Release" -CiMode "GitHub" -Verbose

# In Azure DevOps
script: |
  .\BuildDataverseSolution\build-solution.ps1 -BuildConfiguration "$(BUILD_CONFIGURATION)" -CiMode "DevOps" -Verbose
```

## Migration Guide

### From Existing GitHub Actions

1. Replace your existing build steps with the BuildDataverseSolution system
2. Move your configuration to `solution.yaml`
3. Update your workflow to use the provided template
4. Test the new workflow with a pull request

### From Existing Azure DevOps Pipelines

1. Replace your existing build tasks with the BuildDataverseSolution system
2. Move your configuration to `solution.yaml`
3. Update your pipeline to use the provided template
4. Test the new pipeline with a feature branch

## Best Practices

1. **Version Control:**
   - Keep `solution.yaml` in version control
   - Use semantic versioning for releases
   - Tag releases consistently

2. **Security:**
   - Use secrets for sensitive information
   - Limit permissions on service accounts
   - Regularly update dependencies

3. **Testing:**
   - Test locally before committing
   - Use feature branches for changes
   - Validate configuration changes

4. **Documentation:**
   - Keep your `solution.yaml` well-documented
   - Update release notes regularly
   - Document custom scripts and configurations

## Support

For issues and questions:

1. Check the `BuildDataverseSolution/README.md` for detailed usage instructions
2. Review the example configurations in `BuildDataverseSolution/examples/`
3. Validate your `solution.yaml` against the template
4. Test locally to isolate CI/CD specific issues

## Examples

See the `BuildDataverseSolution/examples/` directory for:
- `basic-pcf.yaml` - Minimal configuration
- `advanced-pcf.yaml` - Full-featured configuration with custom scripts
- Platform-specific workflow examples
