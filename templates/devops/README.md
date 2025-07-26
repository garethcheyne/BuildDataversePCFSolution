# Azure DevOps Template

This directory contains the Azure DevOps pipeline template for PCF BuildDataverseSolution.

## Files

- **`azure-pipelines.yml`** - Complete Azure DevOps pipeline
  - Multi-stage pipeline (Build → Release → Security)
  - Builds PCF control on push/PR
  - Publishes build artifacts
  - Optional GitHub release creation
  - Security scanning with Trivy

## Usage

The setup script (`../setup-project.ps1`) automatically copies this file to your project root.

Manual setup:
```bash
cp BuildDataverseSolution/templates/devops/azure-pipelines.yml .
```

Then in Azure DevOps:
1. Create new pipeline
2. Select "Existing Azure Pipelines YAML file"
3. Choose `/azure-pipelines.yml`

## Features

- ✅ **Multi-stage pipeline** with proper dependency management
- ✅ **Build artifact publishing** 
- ✅ **GitHub release creation** (optional, requires setup)
- ✅ **Security scanning** with Trivy
- ✅ **Windows build agents**
- ✅ **Automatic environment detection**

## Configuration

The pipeline reads from your `solution.yaml` file automatically.

Required variables (set in Azure DevOps):
- `GITHUB_TOKEN` - Only needed if you want automatic GitHub releases

## Pipeline Stages

### 1. Build Stage
- Installs Node.js, .NET, and Power Platform CLI
- Runs the build script with DevOps-specific logging
- Validates build outputs
- Publishes build artifacts

### 2. Release Stage (only on version tags)
- Downloads build artifacts
- Extracts release information from solution.yaml
- Creates GitHub release (if configured)

### 3. Security Stage
- Runs Trivy security scanner
- Publishes security scan results
- Creates readable security report

## Triggering Builds

- **Push to main/master** → Full pipeline
- **Create PR** → Build stage only
- **Push version tag** (e.g., `v1.0.0`) → Build + Release + Security

## GitHub Release Setup (Optional)

To enable automatic GitHub releases from Azure DevOps:

1. **Generate GitHub Personal Access Token**:
   - Go to GitHub Settings → Developer settings → Personal access tokens
   - Create token with `repo` scope
   - Copy the token

2. **Add to Azure DevOps**:
   - Go to your pipeline → Edit → Variables
   - Add variable named `GITHUB_TOKEN`
   - Paste your GitHub token
   - Mark as secret

3. **Pipeline will automatically**:
   - Install GitHub CLI
   - Authenticate using your token
   - Create releases when you push version tags

## Artifacts

- **PCF Build Output**: Published as `pcf-control-build`
- **Solution Package**: Published as `solution-package`
- **Security Scan Results**: Published as `security-scan-results`

## Independent from GitHub

This pipeline works completely independently of GitHub:
- Uses Azure Repos or any Git repository
- Publishes to Azure DevOps artifacts
- GitHub integration is optional for releases only
- Can run in corporate environments without GitHub access

## Troubleshooting

- Check **Build logs** in Azure DevOps for detailed error messages
- Verify **Agent capabilities** (Node.js, .NET, PowerShell)
- For GitHub releases, verify `GITHUB_TOKEN` variable is set correctly
- Test locally first: `.\BuildDataverseSolution\build-solution.ps1 -CiMode DevOps`
