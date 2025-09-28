# Frequently Asked Questions

## General Questions

### Q: What is Actions Runner Controller (ARC)?
A: ARC is a Kubernetes operator that orchestrates and scales self-hosted GitHub Actions runners. It automatically provisions runners in your Kubernetes cluster based on workflow demand.

### Q: Why should I use self-hosted runners?
A: Self-hosted runners provide:
- Better control over the execution environment
- Access to internal resources and services  
- Custom hardware configurations
- Compliance with security requirements
- Cost optimization for large workloads

## Setup and Configuration

### Q: What permissions does my GitHub token need?
A: For repository-level runners:
- `repo` (Full control of private repositories)
- `admin:repo_hook` (Read/write repository hooks)

For organization-level runners:
- `admin:org` (Full control of orgs and teams)
- `repo` (Full control of repositories)

### Q: How do I configure runners for a private repository?
A: Update the `repository` field in your runner configuration:
```yaml
spec:
  template:
    spec:
      repository: your-org/your-private-repo
```

### Q: Can I run multiple runner pools?
A: Yes! Create separate RunnerDeployment resources with different names and configurations. This is useful for different workload types (e.g., build vs. test runners).

## Scaling and Performance

### Q: How does auto-scaling work?
A: ARC uses HorizontalRunnerAutoscaler (HRA) which:
- Monitors GitHub webhook events
- Scales up when jobs are queued
- Scales down after a configurable delay
- Respects min/max replica limits

### Q: My runners are scaling too slowly/quickly. How can I adjust this?
A: Modify the HRA configuration:
```yaml
scaleDownDelaySecondsAfterScaleOut: 300  # Adjust delay
minReplicas: 1                           # Minimum runners
maxReplicas: 10                          # Maximum runners
```

### Q: How do I optimize resource usage?
A: 
- Monitor actual resource consumption with `kubectl top pods`
- Adjust requests/limits based on your workflows
- Use nodeSelector to place runners on appropriate nodes
- Consider using spot instances for cost savings

## Security

### Q: How secure are self-hosted runners?
A: Self-hosted runners require careful security consideration:
- Never use them on public repositories (security risk)
- Always run as non-root users
- Use network policies to restrict access
- Regularly update runner images
- Isolate runner nodes from sensitive systems

### Q: Can I restrict network access from runners?
A: Yes, use Kubernetes NetworkPolicies:
```yaml
networkPolicy:
  enabled: true
  egress:
    - to: []
      ports:
      - protocol: TCP
        port: 443  # Allow HTTPS only
```

### Q: How do I handle secrets in workflows?
A: 
- Use Kubernetes secrets for runner configuration
- Use GitHub secrets for workflow secrets
- Never hardcode sensitive values in runner configs
- Consider external secret management solutions

## Troubleshooting

### Q: My runners show as "Offline" in GitHub
A: Check:
- Network connectivity to GitHub (github.com:443)
- GitHub token validity and permissions
- Runner pod logs: `kubectl logs -l app=actions-runner`
- Repository/organization name accuracy

### Q: Workflows are queuing but runners aren't scaling
A: Verify:
- HRA is deployed and configured
- GitHub webhook delivery is working
- Resource availability on your cluster
- Node capacity and scheduling constraints

### Q: Runner pods are stuck in Pending state
A: Common causes:
- Insufficient cluster resources
- Node selector constraints not met
- Taints/tolerations mismatch
- PVC provisioning issues

### Q: How do I debug runner registration issues?
A: 
1. Check runner logs: `kubectl logs <runner-pod> -c runner`
2. Verify GitHub token permissions
3. Check repository/org name in configuration
4. Ensure network connectivity to GitHub API

### Q: Can I use Windows containers?
A: Yes, but requires:
- Windows node pool in your cluster
- Windows-based runner images
- Appropriate nodeSelector configuration

## Best Practices

### Q: How many runners should I deploy?
A: Start small and scale based on demand:
- Begin with 1-3 runners
- Monitor queue times and adjust
- Use auto-scaling to handle peaks
- Consider separate pools for different job types

### Q: Should I use one big runner pool or multiple smaller ones?
A: Multiple smaller pools offer:
- Better isolation between teams/projects
- Specialized configurations for different workloads
- Easier debugging and maintenance
- More granular scaling control

### Q: How do I handle runner maintenance?
A: 
- Use rolling updates for configuration changes
- Regular image updates for security patches
- Monitor resource usage and adjust limits
- Set up alerts for failed runners

### Q: Can I use ARC with GitHub Enterprise Server?
A: Yes, but you'll need to:
- Configure the GitHub API endpoint
- Ensure network connectivity to your GHES instance
- Use appropriate certificates for SSL/TLS

## Integration

### Q: Can I integrate with monitoring tools?
A: Yes! ARC exposes Prometheus metrics. You can monitor:
- Runner pod status
- Queue lengths
- Resource utilization
- Scaling events

### Q: How do I backup runner configurations?
A: Your runner configurations are Kubernetes resources, so:
- Store YAML files in version control (like this repo)
- Use GitOps for configuration management
- Regular cluster backups include runner configs

### Q: Can I use custom runner images?
A: Absolutely! Build your own images with:
- Required tools and dependencies
- Security hardening
- Custom configuration
- Compliance requirements

Reference the custom image in your runner configuration:
```yaml
spec:
  template:
    spec:
      image: your-registry/custom-runner:latest
```