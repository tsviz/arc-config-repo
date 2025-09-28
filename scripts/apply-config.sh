#!/bin/bash

# apply-config.sh - Apply ARC configurations to Kubernetes cluster
# Usage: ./apply-config.sh [options]

set -euo pipefail

# Default values
DRY_RUN=false
NAMESPACE=""
CONFIG_TYPE=""
VERBOSE=false

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Print usage information
usage() {
    cat << EOF
Usage: $0 [options]

Apply ARC configurations to your Kubernetes cluster.

Options:
    -h, --help              Show this help message
    -d, --dry-run          Show what would be applied without actually applying
    -n, --namespace NAME   Target namespace (default: auto-detect from manifests)
    -t, --type TYPE        Configuration type: org, repo, policy, or all (default: all)
    -v, --verbose          Verbose output
    
Examples:
    $0                      # Apply all configurations
    $0 -t org              # Apply only org-level runners
    $0 -t repo             # Apply only repo-level runners  
    $0 -t policy           # Apply only policies
    $0 -d                  # Dry run - show what would be applied
    $0 -n my-team -t repo  # Apply repo configs to specific namespace

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
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if kubectl is available and connected
check_kubectl() {
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl not found. Please install kubectl."
        exit 1
    fi

    if ! kubectl cluster-info &> /dev/null; then
        log_error "Cannot connect to Kubernetes cluster. Please check your kubeconfig."
        exit 1
    fi

    log_info "Connected to cluster: $(kubectl config current-context)"
}

# Apply configurations based on type
apply_configs() {
    local config_type=$1
    local dry_run_flag=""
    
    if [[ "$DRY_RUN" == "true" ]]; then
        dry_run_flag="--dry-run=client"
        log_info "DRY RUN MODE - No changes will be applied"
    fi

    case $config_type in
        "org")
            log_info "Applying organization-level configurations..."
            if [[ -f "runners/org-level/arc-org-runners.yaml" ]]; then
                log_info "Applying org runners..."
                kubectl apply -f runners/org-level/arc-org-runners.yaml $dry_run_flag
                log_success "Org runners configuration applied"
            fi
            ;;
        "repo")
            log_info "Applying repository-level configurations..."
            if [[ -d "runners/repo-level" ]]; then
                find runners/repo-level -name "*.yaml" -o -name "*.yml" | while read -r file; do
                    log_info "Applying $file..."
                    if [[ -n "$NAMESPACE" ]]; then
                        # Create namespace if it doesn't exist
                        kubectl create namespace "$NAMESPACE" $dry_run_flag --dry-run=client -o yaml | kubectl apply $dry_run_flag -f - || true
                        # Apply with namespace override
                        sed "s/namespace: .*/namespace: $NAMESPACE/" "$file" | kubectl apply $dry_run_flag -f -
                    else
                        kubectl apply -f "$file" $dry_run_flag
                    fi
                done
                log_success "Repository runners configurations applied"
            fi
            ;;
        "policy")
            log_info "Applying policy configurations..."
            if [[ -d "policies" ]]; then
                find policies -name "*.yaml" -o -name "*.yml" | while read -r file; do
                    log_info "Applying policy: $file..."
                    if [[ -n "$NAMESPACE" ]]; then
                        # Create namespace if it doesn't exist
                        kubectl create namespace "$NAMESPACE" $dry_run_flag --dry-run=client -o yaml | kubectl apply $dry_run_flag -f - || true
                        # Apply with namespace override
                        sed "s/namespace: .*/namespace: $NAMESPACE/" "$file" | kubectl apply $dry_run_flag -f -
                    else
                        kubectl apply -f "$file" $dry_run_flag
                    fi
                done
                log_success "Policy configurations applied"
            fi
            ;;
        "all")
            apply_configs "policy"
            apply_configs "org"
            apply_configs "repo"
            ;;
        *)
            log_error "Unknown configuration type: $config_type"
            usage
            exit 1
            ;;
    esac
}

# Verify deployments
verify_deployments() {
    if [[ "$DRY_RUN" == "true" ]]; then
        return 0
    fi

    log_info "Verifying deployments..."
    
    # Wait a bit for resources to be created
    sleep 5
    
    # Check RunnerDeployments
    if kubectl get runnerdeployments -A &> /dev/null; then
        log_info "Runner deployments status:"
        kubectl get runnerdeployments -A -o wide
    fi
    
    # Check runner pods
    log_info "Runner pods status:"
    kubectl get pods -l app=actions-runner -A -o wide || log_warning "No runner pods found yet"
    
    # Check for any failed pods
    failed_pods=$(kubectl get pods -l app=actions-runner -A --field-selector=status.phase=Failed -o name 2>/dev/null || echo "")
    if [[ -n "$failed_pods" ]]; then
        log_warning "Found failed runner pods:"
        echo "$failed_pods"
    fi
    
    log_success "Deployment verification complete"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            usage
            exit 0
            ;;
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -n|--namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        -t|--type)
            CONFIG_TYPE="$2"
            shift 2
            ;;
        -v|--verbose)
            VERBOSE=true
            set -x
            shift
            ;;
        *)
            log_error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Set default config type if not specified
if [[ -z "$CONFIG_TYPE" ]]; then
    CONFIG_TYPE="all"
fi

# Main execution
main() {
    log_info "Starting ARC configuration deployment..."
    
    check_kubectl
    
    # Change to script directory to find config files
    cd "$(dirname "$0")/.."
    
    apply_configs "$CONFIG_TYPE"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        verify_deployments
        log_success "ARC configuration deployment completed successfully!"
        log_info "Check your GitHub repository settings to see the runners."
    else
        log_info "Dry run completed. Use without --dry-run to apply changes."
    fi
}

# Run main function
main