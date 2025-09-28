#!/bin/bash

# validate-config.sh - Validate ARC YAML configurations
# Usage: ./validate-config.sh [options]

set -euo pipefail

# Default values
FIX_ISSUES=false
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

# Print usage information
usage() {
    cat << EOF
Usage: $0 [options]

Validate ARC YAML configuration files for syntax and common issues.

Options:
    -h, --help          Show this help message
    -f, --fix           Attempt to fix common issues automatically
    -v, --verbose       Verbose output
    -d, --dir DIR       Directory to validate (default: current directory)

Examples:
    $0                  # Validate all YAML files in current directory
    $0 -v              # Verbose validation
    $0 -f              # Validate and fix issues where possible
    $0 -d runners/     # Validate only files in runners/ directory

EOF
}

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

# Check if required tools are available
check_dependencies() {
    local missing_tools=()
    
    if ! command -v kubectl &> /dev/null; then
        missing_tools+=("kubectl")
    fi
    
    if ! command -v yq &> /dev/null; then
        log_warning "yq not found. Some advanced validations will be skipped."
        log_info "Install yq with: sudo snap install yq or brew install yq"
    fi
    
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        exit 1
    fi
}

# Validate YAML syntax
validate_yaml_syntax() {
    local file=$1
    local temp_output
    
    if [[ "$VERBOSE" == "true" ]]; then
        log_info "Validating YAML syntax: $file"
    fi
    
    # Use kubectl to validate YAML syntax
    if temp_output=$(kubectl apply --dry-run=client --validate=true -f "$file" 2>&1); then
        return 0
    else
        log_error "YAML syntax error in $file:"
        echo "$temp_output" | sed 's/^/  /'
        return 1
    fi
}

# Validate Runner Deployment specific fields
validate_runner_deployment() {
    local file=$1
    local issues=0
    
    if [[ "$VERBOSE" == "true" ]]; then
        log_info "Validating RunnerDeployment: $file"
    fi
    
    # Check if it's a RunnerDeployment
    if ! grep -q "kind: RunnerDeployment" "$file"; then
        return 0
    fi
    
    # Check required fields
    if ! grep -q "repository\|organization" "$file"; then
        log_error "$file: Missing repository or organization field"
        ((issues++))
    fi
    
    # Check for placeholder values
    if grep -q "__.*__" "$file"; then
        log_warning "$file: Contains template placeholders (e.g., __PLACEHOLDER__)"
        local placeholders
        placeholders=$(grep -o "__[^_]*__" "$file" | sort | uniq)
        echo "  Placeholders found: $placeholders"
    fi
    
    # Check resource limits
    if grep -q "resources:" "$file"; then
        if ! grep -A 10 "resources:" "$file" | grep -q "limits:"; then
            log_warning "$file: Resource requests defined but no limits"
        fi
    fi
    
    # Check for security context
    if ! grep -q "securityContext:" "$file"; then
        log_warning "$file: No securityContext defined (security best practice)"
    fi
    
    return $issues
}

# Validate ConfigMap policies
validate_policy_config() {
    local file=$1
    local issues=0
    
    if [[ "$VERBOSE" == "true" ]]; then
        log_info "Validating Policy ConfigMap: $file"
    fi
    
    # Check if it's a ConfigMap
    if ! grep -q "kind: ConfigMap" "$file"; then
        return 0
    fi
    
    # Check for policy data
    if ! grep -q "policy.yaml:" "$file"; then
        log_warning "$file: ConfigMap doesn't contain policy.yaml data"
    fi
    
    # Check for security context in policy
    if grep -q "policy.yaml:" "$file"; then
        if ! grep -A 50 "policy.yaml:" "$file" | grep -q "securityContext:"; then
            log_warning "$file: Policy doesn't define securityContext"
        fi
        
        # Check for runAsNonRoot
        if grep -A 50 "policy.yaml:" "$file" | grep -q "runAsNonRoot:"; then
            if grep -A 50 "policy.yaml:" "$file" | grep "runAsNonRoot:" | grep -q "false"; then
                log_error "$file: runAsNonRoot is set to false (security risk)"
                ((issues++))
            fi
        fi
    fi
    
    return $issues
}

# Check for common issues across all files
validate_common_issues() {
    local file=$1
    local issues=0
    
    # Check for tabs (should use spaces)
    if grep -P '\t' "$file" &> /dev/null; then
        log_warning "$file: Contains tabs, should use spaces for indentation"
    fi
    
    # Check for trailing whitespace
    if grep -E ' +$' "$file" &> /dev/null; then
        log_warning "$file: Contains trailing whitespace"
        
        if [[ "$FIX_ISSUES" == "true" ]]; then
            sed -i 's/[[:space:]]*$//' "$file"
            log_info "Fixed trailing whitespace in $file"
        fi
    fi
    
    # Check for very long lines (might indicate formatting issues)
    if awk 'length($0) > 200' "$file" | grep -q .; then
        log_warning "$file: Contains very long lines (>200 chars)"
    fi
    
    return $issues
}

# Validate namespace consistency
validate_namespace_consistency() {
    local file=$1
    
    # Extract namespace from metadata
    local namespace
    namespace=$(grep -A 5 "metadata:" "$file" | grep "namespace:" | head -1 | sed 's/.*namespace: *//; s/ *#.*//')
    
    if [[ -n "$namespace" && "$namespace" != "null" ]]; then
        # Check if namespace makes sense for file location
        local dir_path
        dir_path=$(dirname "$file")
        
        if [[ "$dir_path" == *"org-level"* ]] && [[ "$namespace" != *"arc"* && "$namespace" != *"org"* ]]; then
            log_warning "$file: Org-level config in namespace '$namespace' (consider arc-systems or similar)"
        fi
        
        if [[ "$dir_path" == *"repo-level"* ]] && [[ "$namespace" == *"arc"* || "$namespace" == *"system"* ]]; then
            log_warning "$file: Repo-level config in system namespace '$namespace'"
        fi
    fi
}

# Validate a single file
validate_file() {
    local file=$1
    local file_valid=true
    
    ((TOTAL_FILES++))
    
    if [[ "$VERBOSE" == "true" ]]; then
        log_info "Validating: $file"
    fi
    
    # Basic YAML syntax validation
    if ! validate_yaml_syntax "$file"; then
        file_valid=false
    fi
    
    # Skip further validation if YAML is invalid
    if [[ "$file_valid" == "false" ]]; then
        ((INVALID_FILES++))
        return 1
    fi
    
    # Specific validations based on content
    validate_runner_deployment "$file"
    validate_policy_config "$file"
    validate_common_issues "$file"
    validate_namespace_consistency "$file"
    
    if [[ "$file_valid" == "true" ]]; then
        ((VALID_FILES++))
        if [[ "$VERBOSE" == "true" ]]; then
            log_success "Valid: $file"
        fi
    else
        ((INVALID_FILES++))
    fi
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
        validate_file "$file"
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
        log_success "All YAML files are valid!"
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
        -f|--fix)
            FIX_ISSUES=true
            shift
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
    
    if [[ "$FIX_ISSUES" == "true" ]]; then
        log_info "Fix mode enabled - will attempt to fix common issues"
    fi
    
    check_dependencies
    
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