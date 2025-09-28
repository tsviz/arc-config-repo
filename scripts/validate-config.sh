#!/bin/bash

# Simple validation script for ARC configurations
# Usage: ./validate-config.sh [options]

set -euo pipefail

# Default values
VERBOSE=false
CONFIG_DIR="."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Counters
TOTAL_FILES=0
VALID_FILES=0
INVALID_FILES=0
WARNINGS=0

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
    ((WARNINGS++))
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Print usage
usage() {
    cat << EOF
Usage: $0 [options]

Validate ARC YAML configuration files for syntax and common issues.

Options:
    -h, --help          Show this help message
    -v, --verbose       Verbose output
    -d, --dir DIR       Directory to validate (default: current directory)

Examples:
    $0                  # Validate all YAML files in current directory
    $0 -v              # Verbose validation
    $0 -d runners/     # Validate only files in runners/ directory

EOF
}

# Validate YAML syntax
validate_yaml_syntax() {
    local file=$1
    
    if [[ "$VERBOSE" == "true" ]]; then
        log_info "Validating YAML syntax: $file"
    fi
    
    # Use yq if available
    if command -v yq &> /dev/null; then
        if yq eval '.' "$file" > /dev/null 2>&1; then
            return 0
        else
            log_error "YAML syntax error in $file"
            return 1
        fi
    # Use python as fallback
    elif command -v python3 &> /dev/null; then
        if python3 -c "import yaml; yaml.safe_load(open('$file'))" > /dev/null 2>&1; then
            return 0
        else
            log_error "YAML syntax error in $file"
            return 1
        fi
    else
        log_warning "No YAML validator found (yq or python3). Skipping syntax validation for $file"
        return 0
    fi
}

# Check for common issues
check_common_issues() {
    local file=$1
    local warnings_found=0
    
    # Check for tabs
    if grep -P '\t' "$file" > /dev/null 2>&1; then
        log_warning "$file: Contains tabs, should use spaces for indentation"
        ((warnings_found++))
    fi
    
    # Check for trailing whitespace
    if grep -E ' +$' "$file" > /dev/null 2>&1; then
        log_warning "$file: Contains trailing whitespace"
        ((warnings_found++))
    fi
    
    # Check for template placeholders in non-template files
    if [[ "$file" != *"template"* ]] && grep -q "__.*__" "$file"; then
        log_warning "$file: Contains template placeholders (should be replaced)"
        ((warnings_found++))
    fi
    
    return $warnings_found
}

# Check security best practices
check_security() {
    local file=$1
    local warnings_found=0
    
    # Check for runAsNonRoot: false
    if grep -q "runAsNonRoot: false" "$file"; then
        log_warning "$file: runAsNonRoot is set to false (security risk)"
        ((warnings_found++))
    fi
    
    # For RunnerDeployment files, check for security context
    if grep -q "kind: RunnerDeployment" "$file"; then
        if ! grep -q "securityContext:" "$file"; then
            log_warning "$file: Missing securityContext in RunnerDeployment"
            ((warnings_found++))
        fi
        
        # Check for resource limits
        if grep -q "requests:" "$file" && ! grep -A 10 "resources:" "$file" | grep -q "limits:"; then
            log_warning "$file: Resource requests without limits"
            ((warnings_found++))
        fi
    fi
    
    return $warnings_found
}

# Validate a single file
validate_file() {
    local file=$1
    local file_valid=true
    
    ((TOTAL_FILES++))
    
    if [[ "$VERBOSE" == "true" ]]; then
        log_info "Validating: $file"
    fi
    
    # YAML syntax validation
    if ! validate_yaml_syntax "$file"; then
        file_valid=false
        ((INVALID_FILES++))
        return 1
    fi
    
    # Check for common issues (warnings only)
    check_common_issues "$file" || true
    
    # Check security best practices (warnings only)
    check_security "$file" || true
    
    # File is valid
    ((VALID_FILES++))
    if [[ "$VERBOSE" == "true" ]]; then
        log_success "Valid: $file"
    fi
    
    return 0
}

# Find and validate all YAML files
validate_all_configs() {
    local search_dir=$1
    
    log_info "Searching for YAML files in: $search_dir"
    
    # Find all YAML files
    local yaml_files=()
    while IFS= read -r -d '' file; do
        yaml_files+=("$file")
    done < <(find "$search_dir" -type f \( -name "*.yaml" -o -name "*.yml" \) -print0)
    
    if [[ ${#yaml_files[@]} -eq 0 ]]; then
        log_warning "No YAML files found in $search_dir"
        return 0
    fi
    
    log_info "Found ${#yaml_files[@]} YAML files"
    
    # Validate each file
    for file in "${yaml_files[@]}"; do
        validate_file "$file" || true  # Don't exit on file validation failure
    done
}

# Generate validation report
generate_report() {
    echo
    log_info "Validation Summary:"
    echo "  Total files processed: $TOTAL_FILES"
    echo "  Valid files: $VALID_FILES"
    echo "  Invalid files: $INVALID_FILES"
    echo "  Warnings: $WARNINGS"
    
    if [[ $INVALID_FILES -eq 0 ]]; then
        log_success "All YAML files are syntactically valid!"
        if [[ $WARNINGS -gt 0 ]]; then
            log_info "Consider addressing the warnings above for better configuration."
        fi
        return 0
    else
        log_error "$INVALID_FILES file(s) have validation errors"
        return 1
    fi
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            usage
            exit 0
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -d|--dir)
            CONFIG_DIR="$2"
            shift 2
            ;;
        *)
            log_error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Main execution
main() {
    log_info "Starting ARC configuration validation..."
    
    # Validate directory exists
    if [[ ! -d "$CONFIG_DIR" ]]; then
        log_error "Directory not found: $CONFIG_DIR"
        exit 1
    fi
    
    validate_all_configs "$CONFIG_DIR"
    generate_report
}

# Run main function
main