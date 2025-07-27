# Changelog

All notable changes to the BuildDataverseSolution project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.2.0] - 2025-07-27

### Added
- **Solution Type Selection**: Added support for building Managed, Unmanaged, or Both solution types
  - New `-SolutionType` parameter with validation (`Managed`, `Unmanaged`, `Both`)
  - Configuration support in `solution.yaml` with `build.solutionType` setting
  - Separate packaging for managed and unmanaged solutions
- **Version-based Package Naming**: ZIP files now include version number in filename
  - Format: `{SolutionName}_v{Version}_{Type}.zip`
  - Example: `PCFFluentUiAutoCompleteGooglePlaces_v2025.7.27.01_managed.zip`
- **Releases Directory**: All solution packages are now output to a dedicated `releases/` directory
  - Automatic creation of releases directory if it doesn't exist
  - Cleaner project root with organized build outputs
- **Enhanced Build Output**: Improved logging to show all created packages with sizes
- **Documentation**: Added CHANGELOG.md and BLOG.md for project documentation

### Fixed
- **Post-build Script Handling**: Fixed empty pipe element error in YAML parsing
  - Added proper null/empty checks for post-build script execution
  - Wrapped script execution in try-catch for better error handling
- **YAML Parser Improvements**: Enhanced BOM handling and property extraction
- **Clean Build Process**: Updated to handle new versioned package naming patterns

### Changed
- **Package Naming Convention**: Changed from single ZIP to versioned, type-specific packages
- **Package Output Location**: Solution ZIP files are now created in `releases/` directory instead of root
- **Clean Build Process**: Updated to handle new versioned package naming patterns and releases directory
- **Build Configuration Display**: Added solution type and version information to build output
- **Clean Process**: Enhanced to clean both managed and unmanaged packages

## [1.1.0] - 2025-07-27

### Added
- **Cross-Platform Installation System**: 
  - PowerShell installer (`install.ps1`) for Windows
  - Bash installer (`install.sh`) for Unix/Linux/macOS
  - One-liner installation via curl/wget from GitHub
- **GitHub Repository Integration**: Direct installation from https://github.com/garethcheyne/BuildDataverseSolution.git
- **Version Management**: Automatic version checking and upgrade capabilities
- **Enhanced CLI Setup Script**: Improved interactive setup with auto-detection

### Fixed
- **PowerShell Unicode Issues**: Replaced Unicode characters with ASCII equivalents for better compatibility
- **GitHub URL Structure**: Corrected download URLs to match repository structure
- **Installation Validation**: Added proper PCF project structure validation

### Changed
- **Installation Experience**: Streamlined one-command installation process
- **Documentation**: Updated README.md with installation instructions

## [1.0.0] - 2025-07-27

### Added
- **Initial Release**: Core BuildDataverseSolution functionality
- **YAML Configuration System**: Complete solution.yaml configuration support
- **CI/CD Integration**: Support for GitHub Actions, Azure DevOps, and local builds
- **PCF Build Pipeline**: End-to-end PCF control building and Power Platform solution packaging
- **Interactive Setup Script**: PowerShell-based setup with intelligent auto-detection
- **Multi-Environment Support**: Adaptive output formatting for different CI/CD environments

### Features
- **Automated Dependency Management**: NPM package installation and management
- **Power Platform CLI Integration**: Automatic PAC CLI installation and usage
- **Solution Packaging**: Complete Power Platform solution creation and packaging
- **Build Validation**: Pre and post-build validation with configurable checks
- **Template System**: Variable substitution in configuration files
- **Clean Build Support**: Configurable artifact cleanup

### Configuration
- **Flexible YAML Configuration**: Comprehensive solution.yaml with all build settings
- **Publisher Management**: Configurable publisher information and prefixes
- **Build Customization**: Configurable build commands, validation, and scripts
- **Environment Variables**: Support for environment-specific configurations

### Documentation
- **Comprehensive README**: Complete setup and usage documentation
- **Example Configurations**: Sample solution.yaml files for different scenarios
- **CLI Help**: Built-in help and parameter documentation

---

## Release Notes

### Version 1.2.0 Highlights
This release introduces **flexible solution packaging** with support for both managed and unmanaged solutions. Key improvements include:

- **Choose Your Package Type**: Build exactly what you need - managed for production, unmanaged for development, or both
- **Version-Aware Naming**: Packages now include version numbers for better release management
- **Enhanced Reliability**: Fixed YAML parsing issues and improved error handling

### Version 1.1.0 Highlights
This release focused on **ease of installation** and **cross-platform support**:

- **One-Line Installation**: Install directly from GitHub with a single command
- **Cross-Platform Support**: Works on Windows, macOS, and Linux
- **GitHub Integration**: Direct integration with the BuildDataverseSolution repository

### Version 1.0.0 Highlights
The initial release established the **core framework** for PCF solution building:

- **YAML-Driven Configuration**: Flexible, reusable configuration system
- **CI/CD Ready**: Built-in support for major CI/CD platforms  
- **Complete Pipeline**: From PCF source to deployable Power Platform solution

---

## Migration Guide

### Upgrading to 1.2.0
- **Package Names**: Update any deployment scripts to handle the new naming convention
- **Solution Types**: Review your `solution.yaml` to set the desired `solutionType` (defaults to "Both")
- **Clean Process**: The clean build process now handles multiple package types automatically

### Upgrading to 1.1.0  
- **Installation Method**: Consider using the new one-liner installation for easier setup in CI/CD
- **Repository Structure**: No breaking changes to existing installations

### Upgrading to 1.0.0
- **Initial Setup**: Follow the installation guide in README.md
- **Configuration**: Create your solution.yaml based on the provided examples

---

*For more information, visit the [BuildDataverseSolution GitHub repository](https://github.com/garethcheyne/BuildDataverseSolution).*
