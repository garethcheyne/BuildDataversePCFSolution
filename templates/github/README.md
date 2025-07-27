# GitHub Actions Template

This directory contains the GitHub Actions workflow template for PCF BuildDataversePCFSolution.

## Files

- **`build-and-release.yml`** - Complete GitHub Actions workflow
  - Builds PCF control on push/PR
  - Creates releases automatically on version tags
  - Includes security scanning with Trivy
  - Publishes build artifacts

## Usage

The setup script (`../setup-project.ps1`) automatically copies this file to your project's `.github/workflows/` directory.

Manual setup:
```bash
mkdir -p .github/workflows
cp BuildDataversePCFSolution/templates/github/build-and-release.yml .github/workflows/
```

## Features

- ✅ **Automatic builds** on push to main/master branch
- ✅ **Pull request validation** 
- ✅ **Tag-based releases** (create `v1.0.0` tag to trigger)
- ✅ **Artifact upload** with 30/90 day retention
- ✅ **Security scanning** with Trivy
- ✅ **Cross-platform** (Windows build agents)

## Configuration

The workflow reads from your `solution.yaml` file automatically. No additional configuration needed.

Environment variables used:
- `SOLUTION_NAME` - Automatically set from solution.yaml
- `GITHUB_TOKEN` - Automatically available in GitHub Actions

## Triggering Builds

- **Push to main/master** → Build only
- **Create PR** → Build validation
- **Push version tag** (e.g., `v1.0.0`) → Build + Release

## Release Process

1. Update version in `solution.yaml`
2. Commit changes: `git commit -am "Version 1.0.0"`
3. Create tag: `git tag v1.0.0`
4. Push: `git push origin main --tags`
5. GitHub Actions automatically creates release with solution package

## Artifacts

- **PCF Build Output**: Available for 30 days
- **Solution Package**: Available for 90 days
- **GitHub Release**: Permanent (until manually deleted)

## Troubleshooting

- Check the **Actions** tab in your GitHub repository
- Look for failed steps in the workflow logs
- Verify your `solution.yaml` configuration
- Ensure all required files exist in your PCF project
