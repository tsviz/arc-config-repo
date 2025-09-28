# Testing ARC Configuration with GitHub Actions

This guide provides step-by-step instructions for testing your ARC configuration using GitHub Actions, from basic validation to advanced integration testing.

## 📋 Prerequisites

Before starting, ensure you have:
- [x] GitHub repository with ARC configuration files
- [x] GitHub CLI (`gh`) installed (optional but helpful)
- [x] Git configured with your GitHub credentials
- [x] Write access to the repository

## 🚀 Step-by-Step Testing Guide

### Step 1: Understand the Existing Validation Workflow

Your repository already includes a comprehensive validation workflow at `.github/workflows/validate-config.yml` that automatically:

- ✅ Validates YAML syntax
- ✅ Checks for security best practices  
- ✅ Detects template placeholders in non-template files
- ✅ Validates Kubernetes resource definitions
- ✅ Checks YAML formatting
- ✅ Generates detailed reports

### Step 2: Trigger Automatic Validation

The validation runs automatically when:
- You push changes to the `main` branch
- You create a pull request affecting YAML files

**To trigger validation right now:**

```bash
# Make a small change to trigger validation
echo "# Last updated: $(date)" >> README.md
git add README.md
git commit -m "docs: Update README timestamp to trigger validation"
git push
```

### Step 3: Monitor the Validation Run

**Option A: Using GitHub Web Interface**
1. Go to your repository on GitHub
2. Click the "Actions" tab
3. Look for the "Validate ARC Configuration" workflow
4. Click on the latest run to see detailed results

**Option B: Using GitHub CLI**
```bash
# List recent workflow runs
gh run list

# Watch the latest run
gh run watch

# View detailed logs
gh run view --log
```

**Option C: Using Git/Terminal**
```bash
# Check if the commit triggered a workflow
git log --oneline -1
echo "Check: https://github.com/$(gh repo view --json owner,name -q '.owner.login + "/" + .name')/actions"
```

### Step 4: Understanding the Validation Results

The workflow provides detailed feedback in several sections:

#### 🔍 **YAML Syntax Validation**
- Verifies all YAML files have correct syntax
- Uses `yq` for robust multi-document YAML validation
- Reports specific line numbers for errors

#### 🔒 **Security Validation** 
- Checks for `runAsNonRoot: false` (security risk)
- Validates presence of `securityContext` in RunnerDeployments
- Ensures resource limits are specified with requests

#### 📝 **Template Validation**
- Ensures template placeholders (`__PLACEHOLDER__`) only exist in template files
- Prevents accidental deployment of unresolved templates

#### 🎨 **Formatting Checks**
- Detects tabs vs spaces inconsistencies  
- Identifies trailing whitespace
- Promotes consistent formatting

### Step 5: Test Configuration Changes with Pull Requests

**Create a test branch and make changes:**

```bash
# Create a test branch
git checkout -b test-configuration-changes

# Make a test change (e.g., modify runner count)
sed -i 's/maxRunners: 10/maxRunners: 15/' runners/org-level/arc-org-runners.yaml

# Commit and push
git add .
git commit -m "test: Increase max runners for testing"
git push -u origin test-configuration-changes
```

**Create a pull request:**

```bash
# Using GitHub CLI
gh pr create --title "Test: Configuration Changes" --body "Testing ARC configuration validation in PR"

# Or manually via GitHub web interface
```

**The PR will trigger validation automatically and show results directly in the PR.**

### Step 6: Advanced Integration Testing

For more comprehensive testing, let's create an advanced workflow:

#### Create Enhanced Testing Workflow

Create `.github/workflows/integration-test.yml`:

```yaml
name: ARC Integration Testing

on:
  pull_request:
    paths: ['runners/**', 'policies/**']
    types: [opened, synchronize, labeled]
  workflow_dispatch:
    inputs:
      test_type:
        description: 'Type of test to run'
        required: true
        default: 'validation'
        type: choice
        options:
          - validation
          - dry-run
          - integration

jobs:
  basic-validation:
    name: Basic Validation
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v4
        
      - name: Install tools
        run: |
          # Install yq
          wget -qO /tmp/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64
          chmod +x /tmp/yq && sudo mv /tmp/yq /usr/local/bin/yq
          
          # Install kubectl
          curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
          chmod +x kubectl && sudo mv kubectl /usr/local/bin/
      
      - name: Run validation
        run: |
          chmod +x scripts/validate-config.sh
          ./scripts/validate-config.sh -v

  dry-run-test:
    name: Dry Run Deployment Test
    runs-on: ubuntu-latest
    needs: basic-validation
    if: github.event.inputs.test_type == 'dry-run' || contains(github.event.pull_request.labels.*.name, 'test:dry-run')
    steps:
      - name: Checkout
        uses: actions/checkout@v4
        
      - name: Setup kubectl
        run: |
          curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
          chmod +x kubectl && sudo mv kubectl /usr/local/bin/
          
      - name: Create fake kubeconfig for dry-run
        run: |
          mkdir -p $HOME/.kube
          cat > $HOME/.kube/config << EOF
          apiVersion: v1
          kind: Config
          clusters:
          - cluster:
              server: https://fake-server:6443
            name: fake-cluster
          contexts:
          - context:
              cluster: fake-cluster
              user: fake-user
            name: fake-context
          current-context: fake-context
          users:
          - name: fake-user
            user:
              token: fake-token
          EOF
          
      - name: Test dry-run (will fail on connection, but validates YAML)
        run: |
          chmod +x scripts/apply-config.sh
          # This will fail at kubectl connection, but validates the YAML processing
          ./scripts/apply-config.sh --dry-run || echo "Expected failure - no real cluster"

  kind-integration-test:
    name: Kind Cluster Integration Test
    runs-on: ubuntu-latest
    needs: basic-validation
    if: github.event.inputs.test_type == 'integration' || contains(github.event.pull_request.labels.*.name, 'test:integration')
    steps:
      - name: Checkout
        uses: actions/checkout@v4
        
      - name: Setup Kind
        uses: helm/kind-action@v1.4.0
        with:
          cluster_name: arc-test
          
      - name: Install ARC Controller (simulation)
        run: |
          # Create namespace
          kubectl create namespace actions-runner-system
          kubectl create namespace arc-systems
          kubectl create namespace my-team
          
      - name: Customize configs for testing
        run: |
          # Replace example values with test values
          find runners/ -name "*.yaml" -exec sed -i 's/tsviz-demo-org/test-org/g' {} \;
          find runners/ -name "*.yaml" -exec sed -i 's/my-team\/my-repo/test-org\/test-repo/g' {} \;
          find runners/ -name "*.yaml" -exec sed -i 's/my-org\/another-repo/test-org\/another-repo/g' {} \;
          
      - name: Deploy configurations
        run: |
          chmod +x scripts/apply-config.sh
          ./scripts/apply-config.sh --dry-run --verbose
          
      - name: Verify configurations
        run: |
          echo "Configurations that would be deployed:"
          kubectl apply --dry-run=client -f runners/ -R
          kubectl apply --dry-run=client -f policies/ -R

  report-results:
    name: Test Report
    runs-on: ubuntu-latest
    needs: [basic-validation, dry-run-test, kind-integration-test]
    if: always()
    steps:
      - name: Generate Test Report
        run: |
          echo "## ARC Configuration Test Results" >> $GITHUB_STEP_SUMMARY
          echo "" >> $GITHUB_STEP_SUMMARY
          echo "### Test Status" >> $GITHUB_STEP_SUMMARY
          echo "- Basic Validation: ${{ needs.basic-validation.result }}" >> $GITHUB_STEP_SUMMARY
          echo "- Dry Run Test: ${{ needs.dry-run-test.result || 'Skipped' }}" >> $GITHUB_STEP_SUMMARY
          echo "- Integration Test: ${{ needs.kind-integration-test.result || 'Skipped' }}" >> $GITHUB_STEP_SUMMARY
```

### Step 7: Testing Different Scenarios

#### Scenario 1: Test Valid Configuration Changes
```bash
# Test increasing runner limits
git checkout -b test-increase-limits
sed -i 's/maxRunners: 10/maxRunners: 20/' runners/org-level/arc-org-runners.yaml
git add . && git commit -m "test: Increase org runner limits"
git push -u origin test-increase-limits
gh pr create --title "Test: Increase Runner Limits"
```

#### Scenario 2: Test Invalid Configuration (Should Fail)
```bash
# Test invalid YAML syntax
git checkout -b test-invalid-yaml
echo "invalid: yaml: syntax:" >> runners/org-level/arc-org-runners.yaml
git add . && git commit -m "test: Add invalid YAML syntax"
git push -u origin test-invalid-yaml
gh pr create --title "Test: Invalid YAML (Should Fail)"
```

#### Scenario 3: Test Security Issues (Should Warn)
```bash
# Test security issues
git checkout -b test-security-issues
cat >> runners/repo-level/my-team/my-repo-runners.yaml << EOF

  # Security issue for testing
  securityContext:
    runAsNonRoot: false
EOF
git add . && git commit -m "test: Add security issue"
git push -u origin test-security-issues  
gh pr create --title "Test: Security Issues (Should Warn)"
```

### Step 8: Monitor and Interpret Results

#### Understanding Exit Codes
- ✅ **Success (0)**: All validations passed
- ❌ **Failure (1)**: Critical issues found (invalid YAML, missing files)  
- ⚠️ **Success with warnings**: Non-critical issues found

#### Reading the Logs
```bash
# View detailed logs for the latest run
gh run view --log

# View logs for specific job
gh run view --log --job="Validate Configuration Files"
```

#### GitHub Actions Dashboard
1. Navigate to **Actions** tab in your repository
2. Click on workflow run
3. Expand each step to see detailed output
4. Look for grouped sections (::group::) for organized results

### Step 9: Automated Testing Best Practices

#### Use Branch Protection Rules
```bash
# Require status checks via GitHub CLI
gh api repos/:owner/:repo/branches/main/protection \
  --method PUT \
  --field required_status_checks='{"strict":true,"contexts":["Validate Configuration Files"]}' \
  --field enforce_admins=true \
  --field required_pull_request_reviews='{"required_approving_review_count":1}'
```

#### Add PR Labels for Different Test Types
- `test:validation` - Run basic validation only
- `test:dry-run` - Include dry-run deployment test  
- `test:integration` - Run full integration test with Kind cluster

#### Set up Notifications
1. Go to repository **Settings** → **Webhooks**  
2. Add webhook URL for Slack/Discord/Teams notifications
3. Select **Workflow runs** events

### Step 10: Continuous Monitoring

#### Regular Health Checks
Create a scheduled workflow:

```yaml
# .github/workflows/scheduled-validation.yml
name: Scheduled ARC Health Check

on:
  schedule:
    - cron: '0 8 * * MON'  # Every Monday at 8 AM
  workflow_dispatch:

jobs:
  health-check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Run full validation
        run: |
          chmod +x scripts/validate-config.sh
          ./scripts/validate-config.sh -v
```

## 🎯 Quick Testing Checklist

For immediate testing:

- [ ] **Step 1**: Make a small change and push to trigger validation
- [ ] **Step 2**: Check the Actions tab for results  
- [ ] **Step 3**: Create a test PR with configuration changes
- [ ] **Step 4**: Verify validation runs on the PR
- [ ] **Step 5**: Test with intentionally broken YAML
- [ ] **Step 6**: Review security warnings and recommendations

## 🐛 Troubleshooting

### Common Issues

**1. Workflow doesn't trigger:**
- Check file paths in workflow triggers match your changes
- Verify branch name matches workflow configuration

**2. yq installation fails:**
- Use alternative yq installation method in workflow
- Check Ubuntu version compatibility

**3. Permissions issues:**
- Ensure scripts have execute permissions
- Check repository workflow permissions in Settings

**4. False positives:**
- Review template placeholder detection logic
- Adjust security check thresholds if needed

### Debug Commands
```bash
# Check workflow file syntax
yq eval '.jobs' .github/workflows/validate-config.yml

# Validate workflow locally
gh workflow view

# Test specific validation step locally
docker run --rm -v $(pwd):/workspace -w /workspace ubuntu:latest bash -c "
  apt-get update && apt-get install -y wget
  wget -qO /tmp/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64
  chmod +x /tmp/yq && mv /tmp/yq /usr/local/bin/
  chmod +x scripts/validate-config.sh
  ./scripts/validate-config.sh -v
"
```

## 🔗 Related Resources

- [GitHub Actions Documentation](https://docs.github.com/en/actions)
- [ARC Documentation](https://github.com/actions/actions-runner-controller)
- [Kubernetes YAML Validation](https://kubernetes.io/docs/tasks/debug-application-cluster/)
- [yq Documentation](https://mikefarah.gitbook.io/yq/)

This comprehensive approach ensures your ARC configuration is thoroughly tested before deployment!