# ARC Runner Operational Maintenance with k8s-mcp Server

## Overview
This guide complements `ARC_Troubleshooting_with_MCP.md` by focusing on **ongoing operations**: security hardening, efficiency tuning, observability, policy compliance, and automated maintenance of GitHub Actions runners (ARC) using the **k8s-mcp server + GitHub Copilot**.

Rather than one-off troubleshooting, this document establishes **repeatable playbooks** you can execute conversationally through MCP-integrated AI.

---
## Table of Contents
- [Foundations & Assumptions](#foundations--assumptions)
- [Operational Objectives](#operational-objectives)
- [Profile Recap (Configuration Reuse)](#profile-recap-configuration-reuse)
- [Security Hardening Lifecycle](#security-hardening-lifecycle)
- [Efficiency & Scaling Optimization](#efficiency--scaling-optimization)
- [Observability & Telemetry](#observability--telemetry)
- [Policy & Compliance Framework](#policy--compliance-framework)
- [Runner Job Tracking & Correlation](#runner-job-tracking--correlation)
- [Caching & Performance Patterns](#caching--performance-patterns)
- [Cost Control Strategies](#cost-control-strategies)
- [Automation Playbooks (AI-Driven)](#automation-playbooks-ai-driven)
- [Maintenance Schedule (Daily / Weekly / Monthly)](#maintenance-schedule-daily--weekly--monthly)
- [Helm Overrides Reference](#helm-overrides-reference)
- [Policy JSON Scaffold](#policy-json-scaffold)
- [Risk Matrix (Pre vs Post Hardening)](#risk-matrix-pre-vs-post-hardening)
- [KPIs & ROI Tracking](#kpis--roi-tracking)
- [Appendix: Sample AI Prompts](#appendix-sample-ai-prompts)

---
## Foundations & Assumptions
| Aspect | Current Baseline |
|--------|------------------|
| Controller Version | 0.12.1 |
| Scale Set | `arc-repo-runners` (min=1, max=5) |
| Deployment Method | Helm (controller + scale set) |
| SecurityContext | In-progress (target: non-root, labels) |
| Policy Mode | Read-only → transitioning to write-enabled for fixes |
| AI Stack | GitHub Copilot + k8s-mcp server |

---
## Operational Objectives
1. **Security**: Enforce non-root, limit capabilities, rotate tokens, validate image provenance.
2. **Reliability**: Ensure runners scale predictably under workflow spikes.
3. **Efficiency**: Minimize cold start & redundant dependency fetches.
4. **Compliance**: Maintain ≥90% policy adherence (image registry, labels, non-root, resource specs).
5. **Traceability**: Every change is auditable (Git commits + AI transcript + policy logs).
6. **Cost Awareness**: Right-size min/max runners, purge idle capacity, leverage caching.

---
## Profile Recap (Configuration Reuse)
Instead of duplicating container definitions, reuse **MCP Configuration Profiles** from `ARC_Troubleshooting_with_MCP.md`:
- Profile 1: Discovery (read-only) – inventory & baseline metrics
- Profile 2: Policy-Enforced (read-only) – compliance checking
- Profile 3: Write-Enabled – controlled remediation & rollout

> TIP: Begin each maintenance session in Profile 2. Switch to Profile 3 only for approved patches.

---
## Security Hardening Lifecycle
| Phase | Goal | Example MCP/AI Action | Validation |
|-------|------|------------------------|-----------|
| Baseline Capture | Record current posture | "List runner pods + describe scale set" | Git diff stored |
| Harden Runtime | Enforce non-root + drop caps | Helm override (securityContext) | Pod spec reflect runAsNonRoot |
| Image Governance | Registry / digest pinning | Add allowed registries list in policy | Policy eval passes comp-001 |
| Secret Hygiene | PAT rotation | AI prompts: "When was token last rotated?" | Secret creationTimestamp delta < policy threshold |
| Least Privilege | Narrow kubeconfig permissions | Use SA + RBAC role | kubectl auth can-i audit |
| Supply Chain | SBOM / signature check | Integrate cosign policy gate | Policy denies unverified image |

### Recommended SecurityContext (Runner Pod)
```yaml
securityContext:
  runAsNonRoot: true
  runAsUser: 1001
  allowPrivilegeEscalation: false
  capabilities:
    drop: ["ALL"]
  readOnlyRootFilesystem: true
```

### PAT Token Rotation Playbook
1. Generate new PAT (scopes: repo + actions:read or least-required fine-grained).
2. Create/update Kubernetes secret: `kubectl create secret generic github-token --from-literal=github_token=**** -n arc-systems --dry-run=client -o yaml | kubectl apply -f -`
3. Helm upgrade runner scale set (forces listener to re-auth). 
4. Verify: controller logs show successful registration using new token.
5. Revoke old PAT.

---
## Efficiency & Scaling Optimization
| Lever | Description | Action | Metric |
|-------|-------------|--------|--------|
| Min/Max Runners | Prevent over/under provisioning | Tune based on p95 concurrent jobs | Idle minutes / hour |
| Ephemeral vs Persistent | Ephemeral avoids drift; persistent caches dependencies | Choose hybrid for heavy build repos | Avg job duration delta |
| Horizontal Scaling Lag | Time to spawn new runner | Pre-warm via min > 1 during peak windows | Queue wait time |
| Warm Image Layers | Use custom base image with toolchains | Build & pin internal runner image | Avg setup time |
| Workflow Matrix Explosion | Parallel job bursts | Stagger with `max-parallel` | Peak concurrency |

### Scaling Review Prompt
"List last 24h runner pods, summarize churn rate, and recommend min/max adjustments if average concurrent > 80% of max for >30% of intervals."

---
## Observability & Telemetry
| Signal | Source | Use |
|--------|--------|-----|
| Controller Logs | Deployment logs | Reconciliation latency, errors |
| Runner Lifecycle Logs | Runner pods | Job start/finish timing |
| Autoscaling Metrics | (Planned exporter) | Scale decision tuning |
| GitHub API (runs/jobs) | Actions API | Backlog / throughput |
| Policy Evaluation Results | MCP policy engine | Drift detection |

Add a Prometheus scrape (if enabled):
```yaml
controllerManager:
  metrics:
    enabled: true
    serviceMonitor:
      enabled: true
```

---
## Policy & Compliance Framework
| Rule Category | Examples | Enforcement Mode | AI Usage |
|---------------|----------|------------------|----------|
| Security | Non-root, registry allowlist, digest pinning | strict | "Show failing high severity rules" |
| Operations | Label standards, resource specs | advisory → strict | "Suggest labels missing" |
| Governance | Namespace access boundaries | strict | "List non-conforming namespaces" |

### Drift Detection Prompt
"Re-run compliance and compare against last stored snapshot; list new failures only."

---
## Runner Job Tracking & Correlation
Use combined GitHub + Kubernetes view.

Script concept (see potential future `scripts/track-jobs.sh`):
- List busy runners via GitHub API.
- Map `runner_name` to pod via env or annotation.
- Collect active job IDs + durations.

### AI Prompt
"Correlate currently busy runners with pod names and flag any pod older than 6h still idle."

---
## Caching & Performance Patterns
| Layer | Technique | Notes |
|-------|----------|-------|
| Language Toolchains | Pre-bake images with Java/Node/Rust | Reduce setup minutes |
| Dependency Cache | Use `actions/cache` with explicit keys | Avoid broad wildcards |
| Docker Layer Cache | Self-hosted + privileged? (caution) | Consider rootless buildkit |
| Artifact Reuse | Promote build job artifacts → test/deploy | Cuts rebuild duplication |

---
## Cost Control Strategies
| Strategy | Mechanism | AI Prompt |
|----------|-----------|----------|
| Right-Size Min | Adjust minRunners by hour-of-day | "Recommend off-peak minRunners" |
| Scale Cap | Keep max conservative until evidence | "Show peak concurrency vs max" |
| Idle Reclaim | Detect stale persistent pods | "List pods idle > 30m" |
| Heavy Job Isolation | Route large builds to dedicated set | Multiple scale sets |

---
## Automation Playbooks (AI-Driven)
| Playbook | Natural Language Trigger | Underlying Actions |
|----------|--------------------------|--------------------|
| Weekly Compliance Snapshot | "Capture weekly runner compliance baseline" | Policy eval + markdown summary |
| SecurityContext Audit | "List runner pods missing runAsNonRoot" | Describe → filter → table |
| Token Rotation | "Generate rotation checklist for PAT" | Steps + secret patch command |
| Scale Tuning | "Analyze past 7d concurrency vs capacity" | Aggregate job → propose new min/max |
| Non-Root Enforcement | "Apply non-root patch now" | Helm override (write mode) |

---
## Maintenance Schedule (Daily / Weekly / Monthly)
| Cadence | Tasks | Tooling |
|---------|-------|---------|
| Daily | Check failing policies; scan logs for auth errors | Profile 2 + AI summarization |
| Weekly | Compliance snapshot; scale efficiency review | Profile 2 + stored report |
| Monthly | PAT rotation validation; image digest audit; resource limit review | Profile 2/3 depending on changes |
| Quarterly | Policy set refinement; cost benchmarking | Profile 2 |

---
## Helm Overrides Reference
```yaml
# values.sec-hardening.yaml
controllerDeployment:
  podTemplate:
    securityContext:
      runAsNonRoot: true
      runAsUser: 1001
      allowPrivilegeEscalation: false
      readOnlyRootFilesystem: true
    labels:
      app: arc-controller
      owner: devops
      env: dev

template:
  spec:
    securityContext:
      runAsNonRoot: true
      runAsUser: 1001
      allowPrivilegeEscalation: false
      readOnlyRootFilesystem: true
    metadata:
      labels:
        app: arc-repo-runners
        owner: devops
        env: dev
```
Apply (dry-run first):
```
helm upgrade arc-repo-runners oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set \
  -n arc-systems -f values.sec-hardening.yaml --dry-run
```

---
## Policy JSON Scaffold
```jsonc
{
  "rules": {
    "comp-001": { "enforcement": "strict", "allowedRegistries": ["ghcr.io"], "requireDigest": true },
    "sec-003": { "enforcement": "strict", "requireNonRoot": true },
    "ops-002": { "enforcement": "advisory", "requiredLabels": ["app","owner","env"] },
    "ops-004": { "enforcement": "advisory", "requireResourceLimits": true }
  },
  "metadata": {
    "version": "1.0.0",
    "generated": "<DATE>"
  }
}
```

---
## Risk Matrix (Pre vs Post Hardening)
| Risk | Before | After | Residual Action |
|------|--------|-------|-----------------|
| Privileged Execution | Medium | Low | Enforce PSP/Admission control |
| Registry Trust | Medium | Low | Add signature verification |
| Secret Exposure | Medium | Low | Automate rotation audit |
| Drift (Config) | High | Medium | Add periodic diff & lock files |
| Scale Exhaustion | Medium | Low | Alert on queued > X for Y minutes |

---
## KPIs & ROI Tracking
| KPI | Definition | Target | Collection |
|-----|------------|--------|------------|
| Compliance Score | Passed / Total Rules | ≥ 90% | Policy eval output |
| Mean Job Start Latency | Queue to job start | < 20s | GitHub API delta |
| Avg Job Duration | Duration vs baseline | -10% vs month 0 | Job timeline aggregation |
| Idle Runner Minutes | Sum idle per hour | < 15% capacity | Pod + API busy flag |
| Security Drifts / Month | New policy failures | 0 High severity | Diff of eval snapshots |

---
## Appendix: Sample AI Prompts
| Goal | Prompt |
|------|--------|
| Snapshot Compliance | "Run compliance and summarize only new failures since last run." |
| Scale Recommendation | "Analyze runner usage last 48h; propose new min/max with justification." |
| Security Audit | "List runner pods without readOnlyRootFilesystem enabled." |
| Token Hygiene | "When was the GitHub PAT secret last updated? Recommend rotation if older than 30d." |
| Image Governance | "List all running runner images and flag any not pinned by digest." |
| Cost Awareness | "Estimate idle runner-minutes over last 4 hours and suggest cost reduction steps." |

---
## Closing Summary
By pairing **GitHub Copilot** with the **k8s-mcp server**, operational maintenance shifts from ad hoc manual scripts to **guided, policy-aware conversations**. This accelerates: 
- Hardening enforcement
- Scaling right-sizing
- Compliance continuity
- Executive reporting

Adopt an iterative loop: **Baseline → Evaluate → Remediate → Verify → Document**—all within your IDE.

---
*Guide Version: 1.0.0*  
*Last Updated: <REPLACE_DATE>*
