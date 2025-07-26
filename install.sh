#!/bin/bash
# BuildDataverseSolution Installation Script for Unix/Linux/macOS
# This script downloads and installs BuildDataverseSolution to your PCF project

set -e

# Version information
BUILDSOLUTION_VERSION="1.0.0"
BUILDSOLUTION_REPO="https://github.com/garethcheyne/BuildDataverseSolution.git"
BUILDSOLUTION_RAW_URL="https://raw.githubusercontent.com/garethcheyne/BuildDataverseSolution/main"

# Color output functions
print_success() {
    echo -e "\033[32m✅ SUCCESS: $1\033[0m"
}

print_info() {
    echo -e "\033[36mℹ️  INFO: $1\033[0m"
}

print_warning() {
    echo -e "\033[33m⚠️  WARNING: $1\033[0m"
}

print_error() {
    echo -e "\033[31m❌ ERROR: $1\033[0m"
}

print_header() {
    echo ""
    echo -e "\033[34m=== $1 ===\033[0m"
}

# Check if this is a PCF project
test_pcf_project() {
    if [ ! -f "package.json" ]; then
        print_error "No package.json found. This doesn't appear to be a valid PCF project."
        return 1
    fi
    
    if ! ls *.pcfproj >/dev/null 2>&1; then
        print_error "No PCF project file (*.pcfproj) found in the current directory."
        return 1
    fi
    
    print_success "Valid PCF project structure detected."
    return 0
}

# Get installed version
get_installed_version() {
    if [ -f "BuildDataverseSolution/.version" ]; then
        # Try to extract version using various tools
        if command -v jq >/dev/null 2>&1; then
            jq -r '.version' BuildDataverseSolution/.version 2>/dev/null || echo ""
        elif command -v python3 >/dev/null 2>&1; then
            python3 -c "import json; print(json.load(open('BuildDataverseSolution/.version'))['version'])" 2>/dev/null || echo ""
        elif command -v python >/dev/null 2>&1; then
            python -c "import json; print(json.load(open('BuildDataverseSolution/.version'))['version'])" 2>/dev/null || echo ""
        else
            echo ""
        fi
    else
        echo ""
    fi
}

# Download file function
download_file() {
    local url="$1"
    local output="$2"
    local dir=$(dirname "$output")
    
    # Create directory if it doesn't exist
    mkdir -p "$dir"
    
    # Try different download tools
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "$url" -o "$output"
    elif command -v wget >/dev/null 2>&1; then
        wget -q "$url" -O "$output"
    else
        print_error "Neither curl nor wget is available. Please install one of them."
        return 1
    fi
}

# Install BuildDataverseSolution
install_builddataversesolution() {
    local is_upgrade="$1"
    
    # Create BuildDataverseSolution directory
    mkdir -p BuildDataverseSolution
    
    # List of files to download
    local files=(
        "setup-project.ps1"
        "build-solution.ps1"
        "README.md"
        "GETTING-STARTED.md"
    )
    
    local downloaded_files=0
    
    for file in "${files[@]}"; do
        local source_url="$BUILDSOLUTION_RAW_URL/$file"
        local dest_path="BuildDataverseSolution/$file"
        
        print_info "Downloading $file..."
        
        if download_file "$source_url" "$dest_path"; then
            ((downloaded_files++))
        else
            print_error "Failed to download $file"
        fi
    done
    
    if [ $downloaded_files -eq ${#files[@]} ]; then
        # Create version file
        local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
        cat > BuildDataverseSolution/.version << EOF
{
    "version": "$BUILDSOLUTION_VERSION",
    "installedDate": "$timestamp",
    "repository": "$BUILDSOLUTION_REPO"
}
EOF
        
        if [ "$is_upgrade" = "true" ]; then
            print_success "BuildDataverseSolution upgraded to version $BUILDSOLUTION_VERSION"
        else
            print_success "BuildDataverseSolution installed successfully!"
        fi
        return 0
    else
        print_error "Failed to download all required files. Installation incomplete."
        return 1
    fi
}

# Parse command line arguments
FORCE=false
SKIP_SETUP=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --force)
            FORCE=true
            shift
            ;;
        --skip-setup)
            SKIP_SETUP=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [--force] [--skip-setup]"
            echo "  --force      Force reinstallation even if already installed"
            echo "  --skip-setup Skip the interactive setup after installation"
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Main installation process
main() {
    print_header "BuildDataverseSolution Installer"
    print_info "Installing BuildDataverseSolution v$BUILDSOLUTION_VERSION"
    
    # Validate PCF project
    if ! test_pcf_project; then
        print_info "Please run this script from your PCF project root directory"
        exit 1
    fi
    
    # Check for existing installation
    local installed_version=$(get_installed_version)
    local is_upgrade=false
    
    if [ -n "$installed_version" ]; then
        print_info "BuildDataverseSolution v$installed_version is already installed"
        
        if [ "$installed_version" = "$BUILDSOLUTION_VERSION" ]; then
            if [ "$FORCE" != "true" ]; then
                print_info "You already have the latest version installed."
                print_info "Use --force to reinstall or run PowerShell to reconfigure:"
                print_info "pwsh BuildDataverseSolution/setup-project.ps1"
                exit 0
            fi
        else
            print_info "A newer version (v$BUILDSOLUTION_VERSION) is available"
            if [ "$FORCE" != "true" ]; then
                read -p "Do you want to upgrade? [Y/n]: " -r upgrade
                if [[ $upgrade =~ ^[Nn]$ ]]; then
                    print_info "Installation cancelled"
                    exit 0
                fi
            fi
            is_upgrade=true
        fi
    fi
    
    # Install/upgrade BuildDataverseSolution
    if ! install_builddataversesolution "$is_upgrade"; then
        exit 1
    fi
    
    # Run setup unless skipped
    if [ "$SKIP_SETUP" != "true" ]; then
        print_header "Running Setup"
        
        # Check if PowerShell is available
        if command -v pwsh >/dev/null 2>&1; then
            print_info "Starting interactive setup with PowerShell Core..."
            pwsh BuildDataverseSolution/setup-project.ps1
        elif command -v powershell >/dev/null 2>&1; then
            print_info "Starting interactive setup with Windows PowerShell..."
            powershell -File BuildDataverseSolution/setup-project.ps1
        else
            print_warning "PowerShell not found. Please install PowerShell Core to run setup:"
            print_info "https://docs.microsoft.com/en-us/powershell/scripting/install/installing-powershell"
            print_info "Or run setup manually: pwsh BuildDataverseSolution/setup-project.ps1"
        fi
    else
        print_info "Setup skipped. You can run it manually later:"
        print_info "pwsh BuildDataverseSolution/setup-project.ps1"
    fi
    
    print_header "Installation Complete"
    print_success "BuildDataverseSolution is ready to use!"
    print_info "Documentation: BuildDataverseSolution/GETTING-STARTED.md"
}

main "$@"
