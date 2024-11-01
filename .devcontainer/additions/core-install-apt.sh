#!/bin/bash
# file: .devcontainer/additions/core-install-apt.sh
#
# Core functionality for managing system packages via apt
# To be sourced by installation scripts, not executed directly.

set -e

# Debug function
debug() {
    if [ "${DEBUG_MODE:-0}" -eq 1 ]; then
        echo "DEBUG: $*" >&2
    fi
}

# Simple logging function
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

# Error logging function
error() {
    echo "ERROR: $*" >&2
}

# Function to check if a package is installed
is_package_installed() {
    local package=$1
    debug "Checking if package '$package' is installed..."
    dpkg -l "$package" 2>/dev/null | grep -q "^ii"
}

# Function to get installed package version
get_package_version() {
    local package=$1
    dpkg -l "$package" 2>/dev/null | grep "^ii" | awk '{print $3}'
}

# Function to install apt packages
process_system_packages() {
    debug "=== Starting package installation ==="
    
    # Get array reference
    declare -n arr=$1
    
    log "Installing ${#arr[@]} system packages..."
    echo
    printf "%-25s %-20s %s\n" "Package" "Status" "Version"
    printf "%s\n" "----------------------------------------------------"
    
    local installed=0
    local updated=0
    local failed=0
    declare -A successful_ops
    
    # First update package lists with error handling
    debug "Running apt update..."
    local update_output
    update_output=$(sudo DEBIAN_FRONTEND=noninteractive apt-get update 2>&1)
    if [ $? -ne 0 ]; then
        error "Failed to update package lists:"
        error "$update_output"
        return 1
    fi
    
    for package in "${arr[@]}"; do
        printf "%-25s " "$package"
        
        if is_package_installed "$package"; then
            local old_version
            old_version=$(get_package_version "$package")
            debug "Package '$package' is already installed (v$old_version)"
            
            # Try to upgrade the package
            local upgrade_output
            upgrade_output=$(sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --only-upgrade "$package" 2>&1)
            if [ $? -eq 0 ]; then
                local new_version
                new_version=$(get_package_version "$package")
                if [ "$old_version" != "$new_version" ]; then
                    printf "%-20s %s\n" "Updated" "v$new_version"
                    updated=$((updated + 1))
                else
                    printf "%-20s %s\n" "Up to date" "v$new_version"
                    installed=$((installed + 1))
                fi
                successful_ops["$package"]=$new_version
            else
                printf "%-20s\n" "Update failed"
                error "Failed to update $package:"
                error "$upgrade_output"
                failed=$((failed + 1))
            fi
        else
            debug "Installing package '$package'..."
            local install_output
            install_output=$(sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "$package" 2>&1)
            if [ $? -eq 0 ] && is_package_installed "$package"; then
                local version
                version=$(get_package_version "$package")
                printf "%-20s %s\n" "Installed" "v$version"
                installed=$((installed + 1))
                successful_ops["$package"]=$version
            else
                printf "%-20s\n" "Installation failed"
                error "Failed to install $package:"
                error "$install_output"
                failed=$((failed + 1))
            fi
        fi
    done
    
    echo
    echo "Current Status:"
    if [ ${#successful_ops[@]} -gt 0 ]; then
        while IFS= read -r package; do
            printf "* ✅ %s (v%s)\n" "$package" "${successful_ops[$package]}"
        done < <(printf '%s\n' "${!successful_ops[@]}" | sort)
    else
        echo "No packages were successfully installed or updated"
    fi
    
    echo
    echo "----------------------------------------"
    log "Package Installation Summary"
    echo "Total packages: ${#arr[@]}"
    echo "  Installed/Up to date: $installed"
    echo "  Updated: $updated"
    echo "  Failed: $failed"
    
    # Return failure if any package failed to install
    [ $failed -eq 0 ] || return 1
}

# Function to uninstall apt packages
process_system_packages_uninstall() {
    debug "=== Starting package uninstallation ==="
    
    # Get array reference
    declare -n arr=$1
    
    log "Uninstalling ${#arr[@]} system packages..."
    echo
    printf "%-25s %-20s %s\n" "Package" "Status" "Previous Version"
    printf "%s\n" "----------------------------------------------------"
    
    local uninstalled=0
    local skipped=0
    local failed=0
    declare -A successful_ops
    
    for package in "${arr[@]}"; do
        printf "%-25s " "$package"
        
        if is_package_installed "$package"; then
            local version
            version=$(get_package_version "$package")
            debug "Uninstalling package '$package' (v$version)..."
            
            local uninstall_output
            uninstall_output=$(sudo DEBIAN_FRONTEND=noninteractive apt-get remove -y "$package" 2>&1)
            if [ $? -eq 0 ] && ! is_package_installed "$package"; then
                printf "%-20s %s\n" "Uninstalled" "was v$version"
                uninstalled=$((uninstalled + 1))
                successful_ops["$package"]=$version
            else
                printf "%-20s %s\n" "Failed" "v$version"
                error "Failed to uninstall $package:"
                error "$uninstall_output"
                failed=$((failed + 1))
            fi
        else
            printf "%-20s\n" "Not installed"
            skipped=$((skipped + 1))
        fi
    done
    
    echo
    echo "Current Status:"
    if [ ${#successful_ops[@]} -gt 0 ]; then
        while IFS= read -r package; do
            printf "* 🗑️  %s (was v%s)\n" "$package" "${successful_ops[$package]}"
        done < <(printf '%s\n' "${!successful_ops[@]}" | sort)
    else
        echo "No packages were successfully uninstalled"
    fi
    
    echo
    echo "----------------------------------------"
    log "Package Uninstallation Summary"
    echo "Total packages: ${#arr[@]}"
    echo "  Successfully uninstalled: $uninstalled"
    echo "  Skipped/Not installed: $skipped"
    echo "  Failed: $failed"
    
    # Return failure if any package failed to uninstall
    [ $failed -eq 0 ] || return 1
}

# Handle install or uninstall based on mode
if [ "${UNINSTALL_MODE:-0}" -eq 1 ]; then
    process_system_packages=process_system_packages_uninstall
fi