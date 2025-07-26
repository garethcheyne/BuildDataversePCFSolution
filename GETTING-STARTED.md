# Getting Started with BuildDataverseSolution

This is your complete step-by-step guide to setting up CI/CD for any PCF project.

## 📋 Prerequisites Checklist

Before you start, make sure you have:
- ✅ A PCF project with `.pcfproj` file
- ✅ Node.js 18+ installed
- ✅ .NET 6.0+ SDK installed
- ✅ PowerShell 5.1+ or PowerShell Core
- ✅ Git repository (GitHub or Azure DevOps)

## 🚀 Step 1: Copy BuildDataverseSolution

Copy this entire `BuildDataverseSolution` directory to your PCF project root:

```
YourPCFProject/
├── YourControl.pcfproj
├── package.json
├── tsconfig.json
├── BuildDataverseSolution/    ← Copy this entire directory here
└── ... other project files
```

## 🎯 Step 2: Run Setup Script

From your PCF project root directory, run:

```powershell
.\BuildDataverseSolution\setup-project.ps1
```

The script will ask you:
- **Solution name** (no spaces, e.g., "MyPCFControl")
- **Display name** (human-readable, e.g., "My PCF Control")
- **Publisher info** (your name, company prefix)
- **CI/CD platform** (GitHub Actions, Azure DevOps, or both)
- **Repository details** (if using GitHub Actions)

## 🔧 Step 3: Test Locally

Always test before pushing to CI/CD:

```powershell
# Test debug build
.\BuildDataverseSolution\build-solution.ps1 -BuildConfiguration "Debug"

# Should create: YourSolutionName.zip in your project root
```

If this works, you're ready for CI/CD!

## 📤 Step 4A: GitHub Actions Setup

If you chose GitHub Actions:

1. **Commit and push** your changes:
   ```bash
   git add .
   git commit -m "Add BuildDataverseSolution CI/CD"
   git push
   ```

2. **Check the Actions tab** in your GitHub repository
   - Should see a build running automatically
   - Build creates artifacts but no release yet

3. **Create your first release**:
   ```bash
   # Update version in solution.yaml if needed
   git tag v1.0.0
   git push origin v1.0.0
   ```

4. **Check releases** - GitHub should automatically create a release with your solution package

## 📤 Step 4B: Azure DevOps Setup

If you chose Azure DevOps:

1. **Commit and push** your changes to your Azure DevOps repository

2. **Create the pipeline**:
   - Go to Azure DevOps → Pipelines → New pipeline
   - Choose your repository
   - Select "Existing Azure Pipelines YAML file"
   - Choose `/azure-pipelines.yml`
   - Save and run

3. **Optional: Enable GitHub releases**:
   - Generate GitHub Personal Access Token (repo scope)
   - Add `GITHUB_TOKEN` variable to your pipeline (mark as secret)

4. **Create your first release**:
   ```bash
   git tag v1.0.0
   git push origin v1.0.0
   ```

## ✅ Verification Checklist

You know everything is working when:

### Local Build Success:
- ✅ `.\BuildDataverseSolution\build-solution.ps1` completes without errors
- ✅ `YourSolutionName.zip` file is created
- ✅ File size is reasonable (not 0 bytes, not too large)

### GitHub Actions Success:
- ✅ Green checkmark on your commits in GitHub
- ✅ Build artifacts appear in the Actions tab
- ✅ Release is created when you push a version tag
- ✅ Solution package is attached to the release

### Azure DevOps Success:
- ✅ Build shows "Succeeded" status
- ✅ Artifacts are published (pcf-control-build, solution-package)
- ✅ Security scan completes (may show warnings, that's normal)
- ✅ GitHub release created (if configured)

## 🔄 Ongoing Usage

Once set up, your workflow becomes:

### For Regular Development:
1. Make code changes
2. Test locally: `.\BuildDataverseSolution\build-solution.ps1 -BuildConfiguration "Debug"`
3. Commit and push
4. CI/CD automatically builds and validates

### For Releases:
1. Update version in `solution.yaml`
2. Commit: `git commit -am "Version X.Y.Z"`
3. Tag: `git tag vX.Y.Z`
4. Push: `git push origin main --tags`
5. CI/CD automatically creates release

## 🎨 Customization

### Custom Build Scripts
Edit `solution.yaml` to add custom logic:

```yaml
scripts:
  preBuild: |
    Write-Host "Custom pre-build validation"
    # Your PowerShell code here
  
  postBuild: |
    Write-Host "Custom post-build checks"
    # Your PowerShell code here
```

### Custom Validation
Add your own validation rules:

```yaml
validation:
  requiredFiles:
    - "src/MyComponent.tsx"
    - "css/MyStyles.css"
  
  postBuildFiles:
    - "out/MyComponent.js"
```

## 🆘 Common Issues & Solutions

### Issue: "No .pcfproj file found"
**Solution:** Run the setup script from your PCF project root directory (same level as your .pcfproj file)

### Issue: "Power Platform CLI not found"
**Solution:** The script will auto-install it, or manually run: `dotnet tool install --global Microsoft.PowerApps.CLI.Tool`

### Issue: "Build failed" with Node.js errors
**Solution:** Ensure Node.js 18+ is installed: `node --version`

### Issue: "Solution package not created"
**Solution:** Check for errors in the build output, verify your PCF control builds successfully first

### Issue: GitHub Actions not triggering
**Solution:** Make sure you have `.github/workflows/build-and-release.yml` and you've pushed to main/master branch

### Issue: Azure DevOps pipeline not found
**Solution:** Make sure `azure-pipelines.yml` is in your repository root and you've created the pipeline correctly

## 📚 Advanced Configuration

For advanced scenarios, see:
- `templates/github/README.md` - GitHub Actions details
- `templates/devops/README.md` - Azure DevOps details  
- `templates/TROUBLESHOOTING.md` - Detailed troubleshooting
- `examples/` - Configuration examples

## 🎉 You're Done!

Once everything is green and working:
- Your PCF control builds automatically on every push
- Releases are created automatically when you tag versions
- Solution packages are ready for deployment to Power Platform
- You can copy this entire `BuildDataverseSolution` directory to any other PCF project and repeat the process

**Pro tip:** Bookmark this file - you'll refer back to it when setting up future PCF projects!
