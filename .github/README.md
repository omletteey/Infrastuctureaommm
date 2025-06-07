# Terraform GitHub Actions Pipeline

This repository contains a comprehensive GitHub Actions pipeline for managing Terraform infrastructure across multiple cloud providers (AWS, Azure, GCP) following industry best practices.

## 🚀 Features

### Core Workflows

1. **`terraform.yml`** - Main CI/CD pipeline with:
   - ✅ Code validation and formatting checks
   - 🔐 Security scanning with Checkov and tfsec
   - 📋 Plan generation and PR comments
   - 🚀 Automated deployment to production
   - 🔍 Infrastructure drift detection

2. **`terraform-drift-detection.yml`** - Scheduled drift monitoring:
   - 📅 Daily automated drift detection
   - 🎯 Automatic issue creation/updates
   - ✅ Auto-resolution when drift is fixed

3. **`terraform-cost-estimation.yml`** - Cost analysis:
   - 💰 Infrastructure cost estimation using Infracost
   - 📊 Cost change analysis in PRs
   - ⚠️ Cost threshold alerts
   - 💡 Cost optimization recommendations

## 🏗️ Architecture

The pipeline supports multi-cloud deployment with the following structure:
```
Terrafrom/Terrafrom/
├── AWS/
│   ├── main.tf
│   └── outputs.tf
├── AZURE/
│   └── main.tf
└── GCP/
    └── main.tf
```

## ⚙️ Setup Instructions

### 1. Repository Secrets Configuration

#### For AWS:
```bash
AWS_ROLE_ARN=arn:aws:iam::123456789012:role/TerraformGitHubActionsRole
AWS_REGION=us-east-1
```

#### For Azure:
```bash
AZURE_CREDENTIALS={
  "clientId": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
  "clientSecret": "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx",
  "subscriptionId": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
  "tenantId": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
}
```

#### For GCP:
```bash
GCP_SA_KEY={
  "type": "service_account",
  "project_id": "your-project-id",
  ...
}
```

#### For Cost Analysis:
```bash
INFRACOST_API_KEY=ico-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

### 2. Cloud Provider OIDC Setup (Recommended)

#### AWS OIDC Setup:
```bash
# Create OIDC identity provider
aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --client-id-list sts.amazonaws.com \
  --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1

# Create trust policy for GitHub Actions
cat > trust-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::ACCOUNT-ID:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRole",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com",
          "token.actions.githubusercontent.com:sub": "repo:YOUR-ORG/YOUR-REPO:ref:refs/heads/main"
        }
      }
    }
  ]
}
EOF

# Create IAM role
aws iam create-role \
  --role-name TerraformGitHubActionsRole \
  --assume-role-policy-document file://trust-policy.json
```

### 3. Environment Protection Rules

Set up environment protection rules in GitHub:
1. Go to Settings > Environments
2. Create "production" environment
3. Add required reviewers
4. Set deployment branches to "main" only

## 🔄 Workflow Triggers

### Main Pipeline (`terraform.yml`)
- **Push to main/develop**: Full validation, security scan, and deployment
- **Pull Request**: Validation, security scan, and plan generation
- **Manual Dispatch**: Choose environment and cloud provider

### Drift Detection (`terraform-drift-detection.yml`)
- **Scheduled**: Daily at 6 AM UTC
- **Manual Dispatch**: On-demand drift checking

### Cost Estimation (`terraform-cost-estimation.yml`)
- **Pull Request**: Automatic cost analysis
- **Manual Dispatch**: On-demand cost estimation

## 📋 Best Practices Implemented

### 🔐 Security
- **OIDC Authentication**: Eliminates long-lived credentials
- **Secret Management**: Secure handling of sensitive data
- **Security Scanning**: Automated vulnerability detection
- **Least Privilege**: Minimal required permissions

### 🏗️ Infrastructure as Code
- **State Management**: Remote state with locking
- **Plan Before Apply**: No surprises in production
- **Immutable Deployments**: Artifact-based deployments
- **Multi-Environment**: Separate environments with protection

### 🔍 Monitoring & Observability
- **Drift Detection**: Automated infrastructure monitoring
- **Cost Tracking**: Proactive cost management
- **Audit Trail**: Complete deployment history
- **Automated Reporting**: Issue creation and updates

### 👥 Collaboration
- **PR Comments**: Detailed plan and validation results
- **Code Review**: Required approvals for production
- **Documentation**: Automated artifact generation
- **Notifications**: Slack/email integration ready

## 🎯 Usage Examples

### Triggering Manual Deployment
```yaml
# Trigger via GitHub CLI
gh workflow run terraform.yml \
  -f environment=prod \
  -f cloud_provider=AWS
```

### Reviewing Plan in PR
1. Create pull request with Terraform changes
2. Review automated comments with:
   - Validation results
   - Security scan results
   - Infrastructure plan
   - Cost estimation
3. Approve and merge when ready

### Monitoring Drift
- Check Issues tab for drift detection alerts
- Review daily drift reports
- Investigate and resolve any unexpected changes

## 🔧 Customization

### Modifying Cost Thresholds
Edit `.github/workflows/terraform-cost-estimation.yml`:
```bash
THRESHOLD=1000  # Change to your preferred monthly limit
```

### Adding New Cloud Providers
1. Add provider directory under `Terrafrom/Terrafrom/`
2. Update matrix strategy in workflow files
3. Add authentication configuration

### Custom Security Policies
Edit Checkov and tfsec configurations:
```yaml
# Add custom Checkov checks
- name: Run Checkov
  with:
    check: CKV_AWS_1,CKV_AWS_2  # Specific checks
    skip_check: CKV_AWS_3       # Skip certain checks
```

## 🐛 Troubleshooting

### Common Issues

1. **Authentication Failures**
   - Verify OIDC setup
   - Check IAM permissions
   - Validate service account keys

2. **Plan Failures**
   - Check Terraform syntax
   - Verify provider configuration
   - Review backend settings

3. **Cost Estimation Issues**
   - Validate Infracost API key
   - Check supported resources
   - Review pricing data

### Debug Mode
Enable debug logging by setting:
```yaml
env:
  TF_LOG: DEBUG
  ACTIONS_STEP_DEBUG: true
```

## 📚 Additional Resources

- [Terraform Best Practices](https://www.terraform-best-practices.com/)
- [GitHub Actions Documentation](https://docs.github.com/en/actions)
- [Infracost Documentation](https://www.infracost.io/docs/)
- [Checkov Security Policies](https://www.checkov.io/4.Integrations/GitHub%20Actions.html)

## 🤝 Contributing

1. Fork the repository
2. Create feature branch
3. Update workflows as needed
4. Test thoroughly
5. Submit pull request

## 📄 License

This project is licensed under the MIT License - see the LICENSE file for details. 