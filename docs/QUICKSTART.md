# ARC Configuration Repository - Quick Start Guide

This guide will help you get started with GitHub Actions Runner Controller (ARC) using the configuration examples in this repository.

## Prerequisites

- Kubernetes cluster (v1.19+)
- kubectl configured to access your cluster
- GitHub App or Personal Access Token with appropriate permissions
- Helm 3.x

## Step 1: Install ARC

First, install the Actions Runner Controller:

```bash
# Add the ARC Helm repository
helm repo add actions-runner-controller https://actions-runner-controller.github.io/actions-runner-controller

# Create namespace for ARC
kubectl create namespace actions-runner-system

# Install ARC with Helm
helm install arc actions-runner-controller/actions-runner-controller \
  --namespace actions-runner-system \
  --set=authSecret.github_token="YOUR_GITHUB_TOKEN"
```

## Step 2: Configure Your Environment

1. **Update runner configurations**: Edit the YAML files in `runners/` to match your repositories/organization
2. **Customize policies**: Modify files in `policies/` according to your security and resource requirements
3. **Set up secrets**: Create Kubernetes secrets for GitHub authentication

## Step 3: Deploy Runners

### Organization-level Runners

```bash
# Apply the organization runner configuration
kubectl apply -f runners/org-level/arc-org-runners.yaml

# Apply organization policy
kubectl apply -f policies/org-level-policy.yaml
```

### Repository-specific Runners

```bash
# Create namespace for your team
kubectl create namespace my-team

# Apply repository runner configuration
kubectl apply -f runners/repo-level/my-team/my-repo-runners.yaml

# Apply repository-specific policy
kubectl apply -f policies/repo-level/my-team/my-repo-policy.yaml
```

## Step 4: Verify Deployment

Check that your runners are running:

```bash
# Check runner deployments
kubectl get runnerdeployments -A

# Check runner pods
kubectl get pods -l app=actions-runner -A

# View runner logs
kubectl logs -l app=actions-runner -n YOUR_NAMESPACE
```

## Step 5: Test Your Setup

1. Go to your GitHub repository settings
2. Navigate to Actions → Runners
3. You should see your self-hosted runners listed
4. Create a workflow that uses `runs-on: self-hosted` to test

## Configuration Tips

### Resource Planning
- Start with modest resource requests and adjust based on your workload
- Monitor CPU and memory usage to optimize settings
- Consider using HorizontalRunnerAutoscaler for dynamic scaling

### Security Best Practices
- Always run runners as non-root users
- Use network policies to restrict egress traffic
- Regularly update runner images
- Use secrets management for sensitive configuration

### Scaling Considerations
- Use `minReplicas` and `maxReplicas` to control costs
- Configure appropriate scale-down delays
- Monitor queue times to optimize scaling parameters

## Troubleshooting

### Common Issues

1. **Runners not appearing in GitHub**
   - Check GitHub token permissions
   - Verify repository/organization names in configuration
   - Check runner pod logs for authentication errors

2. **Resource constraints**
   - Check node resources: `kubectl top nodes`
   - Adjust resource requests/limits
   - Verify node selectors and tolerations

3. **Network connectivity**
   - Ensure outbound HTTPS (443) access to GitHub
   - Check DNS resolution within the cluster
   - Verify network policies aren't blocking required traffic

For more detailed troubleshooting, check the [official ARC documentation](https://github.com/actions/actions-runner-controller).

## Next Steps

- Explore auto-scaling configurations
- Set up monitoring and alerting
- Implement CI/CD for runner configuration updates
- Consider multiple runner pools for different workload types