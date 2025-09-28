# Testing ARC Configuration

This guide covers different approaches to test and validate your ARC (Actions Runner Controller) configuration before deploying to production.

## 🚀 Quick Testing

### 1. Local Validation
The fastest way to test your configuration:

```bash
# Basic validation
./scripts/validate-config.sh

# Verbose validation with detailed output
./scripts/validate-config.sh -v

# Validate specific directory
./scripts/validate-config.sh -d runners/
```

**What it checks:**
- ✅ YAML syntax validation
- ✅ Security best practices
- ✅ Common configuration issues
- ✅ Template placeholder detection
- ✅ Resource limit validation

### 2. Dry Run Deployment
Test deployment without actually applying changes:

```bash
# Test all configurations
./scripts/apply-config.sh --dry-run

# Test specific configuration types
./scripts/apply-config.sh --dry-run --type org
./scripts/apply-config.sh --dry-run --type repo
./scripts/apply-config.sh --dry-run --type policy
```

**Requirements:**
- `kubectl` installed and configured
- Access to a Kubernetes cluster (for validation)

## 🔄 Continuous Integration Testing

The repository includes automated testing via GitHub Actions that runs on:
- Every pull request affecting YAML files
- Every push to the main branch

### What CI Tests Include:
- ✅ YAML syntax validation
- ✅ Template placeholder verification
- ✅ Kubernetes resource validation
- ✅ Security checks
- ✅ YAML formatting checks

### Triggering CI Tests:
```bash
# Make changes and push
git add .
git commit -m "Test configuration changes"
git push
```

## 🏗️ Integration Testing

### Prerequisites for Full Testing:

1. **Kubernetes Cluster** (local or cloud):
   ```bash
   # Using kind (local)
   kind create cluster --name arc-test
   
   # Using minikube (local)
   minikube start --profile arc-test
   
   # Or use cloud providers (AKS, EKS, GKE)
   ```

2. **ARC Installation**:
   ```bash
   # Install ARC controller
   kubectl create namespace actions-runner-system
   helm repo add actions-runner-controller https://actions-runner-controller.github.io/actions-runner-controller
   helm upgrade --install --namespace actions-runner-system --create-namespace actions-runner-controller actions-runner-controller/actions-runner-controller
   ```

3. **GitHub Configuration**:
   - Create a GitHub App or Personal Access Token
   - Configure authentication secrets in Kubernetes

### Testing Steps:

1. **Customize Configuration**:
   ```bash
   # Copy example configuration
   cp runners/org-level/arc-org-runners.yaml my-org-runners.yaml
   
   # Edit with your organization/repository details
   sed -i 's/tsviz-demo-org/your-org-name/g' my-org-runners.yaml
   ```

2. **Deploy and Test**:
   ```bash
   # Deploy configuration
   ./scripts/apply-config.sh
   
   # Verify deployment
   kubectl get runnerdeployments -A
   kubectl get pods -l app=actions-runner -A
   ```

3. **Test Runner Functionality**:
   - Create a simple workflow in your GitHub repository
   - Verify runners appear in GitHub Settings > Actions > Runners
   - Run a test workflow and confirm it uses your ARC runners

## 🧪 Testing Scenarios

### Scenario 1: Organization-wide Runners
```bash
# Test org-level configuration
./scripts/apply-config.sh --type org --dry-run

# Verify organization is correctly set
grep -r "organization:" runners/org-level/
```

### Scenario 2: Repository-specific Runners
```bash
# Test repo-level configuration
./scripts/apply-config.sh --type repo --dry-run

# Verify repository references
grep -r "repository:" runners/repo-level/
```

### Scenario 3: Policy Validation
```bash
# Test policy configurations
./scripts/apply-config.sh --type policy --dry-run

# Check security contexts
grep -r "securityContext:" policies/
```

### Scenario 4: Scaling Behavior
```bash
# Deploy and monitor scaling
kubectl apply -f runners/repo-level/my-team/another-repo-runners.yaml
kubectl get pods -l app=actions-runner -w
```

## 🐛 Troubleshooting Tests

### Common Issues:

1. **YAML Syntax Errors**:
   ```bash
   # Debug with yq
   yq eval '.' your-config.yaml
   
   # Check for common issues
   ./scripts/validate-config.sh -v
   ```

2. **Template Placeholders**:
   ```bash
   # Find remaining placeholders
   grep -r "__.*__" runners/ policies/ | grep -v templates/
   ```

3. **Security Warnings**:
   ```bash
   # Check security contexts
   grep -r "runAsNonRoot: false" runners/ policies/
   ```

4. **Deployment Failures**:
   ```bash
   # Check kubectl context
   kubectl config current-context
   
   # Verify cluster connectivity
   kubectl cluster-info
   
   # Check for existing resources
   kubectl get runnerdeployments -A
   ```

## 📊 Testing Checklist

Before deploying to production:

- [ ] ✅ Local validation passes (`./scripts/validate-config.sh -v`)
- [ ] ✅ GitHub Actions CI validation passes
- [ ] ✅ Dry run deployment succeeds
- [ ] ✅ No template placeholders in non-template files
- [ ] ✅ Security contexts properly configured
- [ ] ✅ Resource limits set appropriately
- [ ] ✅ Organization/repository references updated
- [ ] ✅ Integration test on staging cluster successful
- [ ] ✅ Test workflow runs successfully with ARC runners

## 📚 Additional Resources

- [ARC Documentation](https://github.com/actions/actions-runner-controller)
- [Kubernetes Testing Best Practices](https://kubernetes.io/docs/tasks/debug-application-cluster/)
- [GitHub Actions Documentation](https://docs.github.com/en/actions)

## 🔄 Automated Testing Pipeline

Consider setting up a complete testing pipeline:

```yaml
# .github/workflows/full-test.yml
name: Full ARC Testing Pipeline
on:
  pull_request:
    paths: ['runners/**', 'policies/**']

jobs:
  validate:
    runs-on: ubuntu-latest
    steps:
      # Validation steps from existing workflow
      
  integration-test:
    runs-on: ubuntu-latest
    if: github.event.pull_request.head.repo.full_name == github.repository
    steps:
      - uses: actions/checkout@v4
      - name: Create test cluster
        # Set up kind/minikube cluster
      - name: Deploy ARC
        # Install ARC controller
      - name: Test deployment
        # Deploy and verify configurations
```

This comprehensive testing approach ensures your ARC configuration is reliable, secure, and ready for production use.